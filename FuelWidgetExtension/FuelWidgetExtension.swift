import AppIntents
import CoreLocation
import SwiftUI
import WidgetKit

enum WidgetFuelType: String, AppEnum {
    case e10 = "E10"
    case unleaded91 = "91"
    case premium95 = "95"
    case premium98 = "98"
    case diesel = "Diesel"
    case lpg = "LPG"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Fuel Type"

    static var caseDisplayRepresentations: [WidgetFuelType: DisplayRepresentation] = [
        .e10: "E10",
        .unleaded91: "Unleaded 91",
        .premium95: "Premium 95",
        .premium98: "Premium 98",
        .diesel: "Diesel",
        .lpg: "LPG"
    ]
}

struct FuelWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Fuel Type"
    static var description = IntentDescription("Choose the fuel shown by the widget.")

    @Parameter(title: "Fuel Type", default: .unleaded91)
    var fuelType: WidgetFuelType

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$fuelType
        }
    }
}

struct FuelEntry: TimelineEntry {
    let date: Date
    let fuelName: String
    let price: String
    let stationName: String
    let stationAddress: String?
    let distance: CLLocationDistance?
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FuelEntry {
        FuelEntry(
            date: .now,
            fuelName: "91",
            price: "187.9¢",
            stationName: "BP Port Road",
            stationAddress: "123 Port Road, Hindmarsh 5007",
            distance: 2_400
        )
    }

    func snapshot(
        for configuration: FuelWidgetConfiguration,
        in context: Context
    ) async -> FuelEntry {
        if context.isPreview {
            return previewEntry(for: configuration.fuelType)
        }

        return await loadEntry(for: configuration.fuelType)
    }

    func timeline(
        for configuration: FuelWidgetConfiguration,
        in context: Context
    ) async -> Timeline<FuelEntry> {
        let entry = await loadEntry(for: configuration.fuelType)
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadEntry(for fuelType: WidgetFuelType) async -> FuelEntry {
        let locationManager = CLLocationManager()
        guard locationManager.isAuthorizedForWidgetUpdates,
              let coordinate = locationManager.location?.coordinate else {
            return FuelEntry(
                date: .now,
                fuelName: fuelType.rawValue,
                price: "—",
                stationName: "Open Fill Up SA for location",
                stationAddress: nil,
                distance: nil
            )
        }

        do {
            let stations = try await FuelAPI.shared.fetchStations(
                around: coordinate,
                maximumStations: 1,
                fuelTypes: requestedFuelTypes(for: fuelType)
            )
            let origin = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let closestStation = stations.min { first, second in
                distance(from: origin, to: first) < distance(from: origin, to: second)
            }

            guard let closestStation,
                  let fuelPrice = fuelPrice(for: fuelType, at: closestStation) else {
                return FuelEntry(
                    date: .now,
                    fuelName: fuelType.rawValue,
                    price: "—",
                    stationName: "No nearby stations",
                    stationAddress: nil,
                    distance: nil
                )
            }

            return FuelEntry(
                date: .now,
                fuelName: fuelType.rawValue,
                price: centsString(fuelPrice.priceCents),
                stationName: closestStation.name,
                stationAddress: stationAddress(for: closestStation),
                distance: distance(from: origin, to: closestStation)
            )
        } catch {
            return FuelEntry(
                date: .now,
                fuelName: fuelType.rawValue,
                price: "—",
                stationName: "Price unavailable",
                stationAddress: nil,
                distance: nil
            )
        }
    }

    private func requestedFuelTypes(for fuelType: WidgetFuelType) -> [String] {
        fuelType == .diesel ? ["Diesel", "Premium Diesel"] : [fuelType.rawValue]
    }

    private func fuelPrice(for fuelType: WidgetFuelType, at station: Station) -> FuelPrice? {
        if let fuelPrice = station.fuels.first(where: { $0.type == fuelType.rawValue }) {
            return fuelPrice
        }

        guard fuelType == .diesel else { return nil }
        return station.fuels.first(where: { $0.type == "Premium Diesel" })
    }

    private func stationAddress(for station: Station) -> String? {
        let components = [station.address, station.postcode].filter { !$0.isEmpty }
        return components.isEmpty ? nil : components.joined(separator: " ")
    }

    private func distance(from origin: CLLocation, to station: Station) -> CLLocationDistance {
        origin.distance(
            from: CLLocation(latitude: station.lat, longitude: station.lon)
        )
    }

    private func previewEntry(for fuelType: WidgetFuelType) -> FuelEntry {
        FuelEntry(
            date: .now,
            fuelName: fuelType.rawValue,
            price: "187.9¢",
            stationName: "BP Port Road",
            stationAddress: "123 Port Road, Hindmarsh 5007",
            distance: 2_400
        )
    }
}

private func centsString(_ cents: Double) -> String {
    String(format: "%.1f¢", cents)
}

private func distanceString(_ distance: CLLocationDistance) -> String {
    if distance < 1_000 {
        return "\(Int(distance.rounded())) m"
    }

    return String(format: "%.1f km", distance / 1_000)
}

private struct FuelWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: FuelEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                FuelWidgetMediumView(entry: entry)
            } else {
                FuelWidgetSmallView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

private struct FuelWidgetSmallView: View {
    let entry: FuelEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(entry.fuelName, systemImage: "fuelpump.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .lineLimit(1)

            Text(entry.price)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(entry.stationName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if let distance = entry.distance {
                Label(distanceString(distance), systemImage: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

private struct FuelWidgetMediumView: View {
    let entry: FuelEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label(entry.fuelName, systemImage: "fuelpump.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)

                Text(entry.stationName)
                    .font(.headline)
                    .lineLimit(2)

                if let stationAddress = entry.stationAddress {
                    Text(stationAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if let distance = entry.distance {
                    Label(distanceString(distance), systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .trailing, spacing: 5) {
                Text(entry.price)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("per litre")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
    }
}

struct FuelWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "FuelWidget",
            intent: FuelWidgetConfiguration.self,
            provider: Provider()
        ) { entry in
            FuelWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Closest Fuel Price")
        .description("Shows the selected fuel price at your closest station.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable()
    }
}

#Preview(as: .systemSmall) {
    FuelWidget()
} timeline: {
    FuelEntry(
        date: .now,
        fuelName: "91",
        price: "187.9¢",
        stationName: "BP Port Road",
        stationAddress: "123 Port Road, Hindmarsh 5007",
        distance: 2_400
    )
}

#Preview(as: .systemMedium) {
    FuelWidget()
} timeline: {
    FuelEntry(
        date: .now,
        fuelName: "Diesel",
        price: "198.5¢",
        stationName: "Caltex Anzac Highway",
        stationAddress: "456 Anzac Highway, Everard Park 5035",
        distance: 4_700
    )
}
