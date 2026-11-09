import { createClient } from "npm:@supabase/supabase-js@2";

const fuelNames: Record<number, string> = {
  2: "91",
  3: "Diesel",
  4: "LPG",
  5: "95",
  8: "98",
  12: "E10",
  14: "Premium Diesel",
};

type SitePrice = {
  SiteId: number;
  FuelId: number;
  Price: number;
};

type PriceResponse = {
  SitePrices: SitePrice[];
};

Deno.serve(async () => {
  const fuelToken = Deno.env.get("SA_FUEL_API_TOKEN");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!fuelToken || !supabaseURL || !serviceRoleKey) {
    return Response.json({ error: "Missing server configuration" }, { status: 500 });
  }

  const priceURL = new URL(
    "/Price/GetSitesPrices",
    "https://fppdirectapi-prod.safuelpricinginformation.com.au",
  );
  priceURL.searchParams.set("countryId", "21");
  priceURL.searchParams.set("geoRegionLevel", "3");
  priceURL.searchParams.set("geoRegionId", "4");

  const response = await fetch(priceURL, {
    headers: { Authorization: `FPDAPI SubscriberToken=${fuelToken}` },
  });
  if (!response.ok) {
    return Response.json(
      { error: "Fuel provider request failed", status: response.status },
      { status: 502 },
    );
  }

  const payload = await response.json() as PriceResponse;
  const grouped = new Map<string, Map<number, { price: number; priority: number }>>();
  for (const entry of payload.SitePrices) {
    const fuelType = entry.FuelId === 14 ? "Diesel" : fuelNames[entry.FuelId];
    if (!fuelType) continue;
    const price = entry.Price / 10;
    if (price < 50 || price > 500) continue;

    const stationPrices = grouped.get(fuelType) ?? new Map();
    const priority = entry.FuelId === 14 ? 0 : 1;
    const existing = stationPrices.get(entry.SiteId);
    if (!existing || priority > existing.priority) {
      stationPrices.set(entry.SiteId, { price, priority });
    }
    grouped.set(fuelType, stationPrices);
  }

  const capturedAt = new Date();
  capturedAt.setUTCMinutes(capturedAt.getUTCMinutes() < 30 ? 0 : 30, 0, 0);

  const rows = [...grouped.entries()].map(([fuelType, stationPrices]) => {
    const prices = [...stationPrices.values()].map((value) => value.price);
    return {
      captured_at: capturedAt.toISOString(),
      fuel_type: fuelType,
      low: Math.min(...prices),
      high: Math.max(...prices),
      average: prices.reduce((total, price) => total + price, 0) / prices.length,
      station_count: prices.length,
    };
  });

  const supabase = createClient(supabaseURL, serviceRoleKey);
  const { error: upsertError } = await supabase
    .from("fuel_price_history")
    .upsert(rows, { onConflict: "captured_at,fuel_type" });
  if (upsertError) {
    return Response.json({ error: upsertError.message }, { status: 500 });
  }

  const retentionDate = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
  const { error: cleanupError } = await supabase
    .from("fuel_price_history")
    .delete()
    .lt("captured_at", retentionDate.toISOString());
  if (cleanupError) {
    return Response.json({ error: cleanupError.message }, { status: 500 });
  }

  return Response.json({ capturedAt, fuels: rows.length });
});
