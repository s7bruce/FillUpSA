import WidgetKit
import SwiftUI
import CoreLocation

// MARK: - Entry
struct FuelEntry: TimelineEntry {
    let date: Date
    let title: String
    let price: String
    let subtitle: String
}

// MARK: - Provider
struct Provider: TimelineProvider {

    // Placeholder (for widget gallery)
    func placeholder(in context: Context) -> FuelEntry {
        FuelEntry(date: Date(), title: "ULP 91", price: "187.9¢", subtitle: "BP Port Road")
    }

    // Snapshot (for quick previews)
    func getSnapshot(in context: Context, completion: @escaping (FuelEntry) -> Void) {
        completion(FuelEntry(date: Date(), title: "ULP 91", price: "187.9¢", subtitle: "BP Port Road"))
    }

    // MARK: Timeline (live data)
    func getTimeline(in context: Context, completion: @escaping (Timeline<FuelEntry>) -> Void) {
        Task {
            let defaultCoord = CLLocationCoordinate2D(latitude: -34.9285, longitude: 138.6007)
            let coord = CLLocationManager().location?.coordinate ?? defaultCoord

            let stations = (try? await FuelAPI.shared.fetchStations(
                around: coord,
                radiusKm: 15,
                fuelTypes: ["ULP 91"]
            )) ?? Station.mock

            // Find the cheapest
            let best = stations.min {
                ($0.price(for: "ULP 91") ?? .infinity) < ($1.price(for: "ULP 91") ?? .infinity)
            }

            let cents = best?.price(for: "ULP 91") ?? 0
            let entry = FuelEntry(
                date: Date(),
                title: "ULP 91",
                price: centsString(cents),
                subtitle: best?.name ?? "—"
            )

            // Refresh every 15 min
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

// MARK: - Helper
fileprivate func centsString(_ cents: Double) -> String {
    // Already in cents per litre (e.g. 187.9)
    return String(format: "%.1f¢", cents)
}

// Optional alternative (for dollars)
// fileprivate func dollarsString(from cents: Double) -> String {
//     let dollars = cents / 100.0
//     return String(format: "$%.3f/L", dollars)
// }

// MARK: - Widget
struct FuelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FuelWidget", provider: Provider()) { entry in
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(entry.price)
                        .font(.system(.title2, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text(entry.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            // ✅ Fixes the container background warnings
            .containerBackground(for: .widget) {
                Color.black
            }
        }
        .configurationDisplayName("Cheapest Nearby Fuel")
        .description("Shows the cheapest ULP 91 fuel price nearby.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    FuelWidget()
} timeline: {
    FuelEntry(date: .now,
              title: "ULP 91",
              price: "187.9¢",
              subtitle: "BP Port Road")
    // You can add more entries to simulate updates:
    FuelEntry(date: .now.addingTimeInterval(15 * 60),
              title: "ULP 91",
              price: "186.5¢",
              subtitle: "Caltex Anzac Hwy")
}
#Preview(as: .systemMedium) {
    FuelWidget()
} timeline: {
    FuelEntry(date: .now, title: "ULP 91", price: "187.9¢", subtitle: "BP Port Road")
}
