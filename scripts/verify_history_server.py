#!/usr/bin/env python3
"""Read-only production history health check; uses the app's public read key."""
import datetime as dt
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request


def verify():
    root = Path(__file__).resolve().parents[1]
    source = (root / "FuelSA/Services/FuelHistoryService.swift").read_text()
    base = re.search(r'projectURL = URL\(string: "([^"]+)', source)[1]
    key = re.search(r'publishableKey = "([^"]+)', source)[1]
    now = dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(hours=24)
    rows = []
    offset = 0
    while True:
        query = urllib.parse.urlencode({
            "select": "captured_at,fuel_type,low,high,average,station_count",
            "captured_at": "gte." + cutoff.isoformat(),
            "order": "captured_at.asc,fuel_type.asc",
            "limit": 500, "offset": offset,
        })
        request = urllib.request.Request(
            base + "/rest/v1/fuel_price_history?" + query,
            headers={"apikey": key, "Authorization": "Bearer " + key},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            page = json.load(response)
        rows.extend(page)
        if len(page) < 500:
            break
        offset += len(page)

    assert rows, "No server history in the last 24 hours"
    fuels = {"91", "95", "98", "Diesel", "E10", "LPG"}
    batches = {}
    identities = set()
    for row in rows:
        date = dt.datetime.fromisoformat(row["captured_at"].replace("Z", "+00:00"))
        identity = (date, row["fuel_type"])
        assert identity not in identities, "Duplicate capture/fuel record"
        identities.add(identity)
        assert row["fuel_type"] in fuels, "Unexpected fuel type"
        assert row["station_count"] > 0, "Empty aggregation"
        assert 50 <= row["low"] <= row["average"] <= row["high"] <= 500, "Invalid aggregate"
        assert date.minute in (0, 30) and date.second == 0, "Capture outside half-hour slot"
        batches.setdefault(date, set()).add(row["fuel_type"])
    times = sorted(batches)
    for date, present in batches.items():
        assert present == fuels, f"Missing fuels at {date.isoformat()}: {fuels - present}"
    gaps = [
        {"from": first.isoformat(), "to": second.isoformat()}
        for first, second in zip(times, times[1:])
        if (second - first).total_seconds() != 1800
    ]
    age = (now - times[-1]).total_seconds() / 60
    healthy = not gaps and 0 <= age <= 60 and len(times) >= 47
    print(json.dumps({
        "checked_at_utc": now.isoformat(), "status": "PASS" if healthy else "FAIL",
        "records_last_24_hours": len(rows), "complete_batches": len(times),
        "first_capture": times[0].isoformat(), "latest_capture": times[-1].isoformat(),
        "latest_age_minutes": round(age, 1), "fuels_per_batch": sorted(fuels),
        "collection_interval_minutes": 30,
        "gaps": gaps,
    }, indent=2))
    return healthy


if __name__ == "__main__":
    raise SystemExit(0 if verify() else 1)
