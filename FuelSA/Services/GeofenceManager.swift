import Foundation
import CoreLocation

@MainActor
final class GeofenceManager: NSObject, CLLocationManagerDelegate {
    static let shared = GeofenceManager()

    private struct AlertStation: Codable {
        let name: String
        let fuel: String
        let priceCents: Double
    }

    private static let metadataKey = "monitoredFuelStations"
    private static let alertHistoryKey = "fuelStationAlertHistory"
    private static let alertCooldown: TimeInterval = 12 * 60 * 60

    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard

    private override init() {
        super.init()
        manager.delegate = self
    }

    func updateMonitoredStations(_ stations: [Station], preferredFuel: String, limit: Int = 10) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return
        }

        manager.requestAlwaysAuthorization()

        let selected = stations
            .compactMap { station -> (Station, Double)? in
                guard let price = station.priceForSelection(preferredFuel) else {
                    return nil
                }
                return (station, price)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(min(limit, 20))

        let metadata = Dictionary(
            uniqueKeysWithValues: selected.map { station, price in
                (
                    station.id,
                    AlertStation(
                        name: station.name,
                        fuel: station.usesPremiumDiesel(for: preferredFuel)
                            ? "Premium Diesel"
                            : preferredFuel,
                        priceCents: price
                    )
                )
            }
        )
        save(metadata, forKey: Self.metadataKey)

        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }

        for (station, _) in selected {
            let center = CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon)
            let radius = min(250, manager.maximumRegionMonitoringDistance)
            guard radius > 0 else {
                continue
            }

            let region = CLCircularRegion(center: center, radius: radius, identifier: station.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let metadata: [String: AlertStation] = load(forKey: Self.metadataKey) ?? [:]
        guard let station = metadata[region.identifier], shouldSendAlert(for: region.identifier) else {
            return
        }

        recordAlert(for: region.identifier)
        let price = String(format: "%.1f", station.priceCents)
        Notifier.send(
            identifier: "nearby-fuel-\(region.identifier)",
            title: "Low-price fuel nearby",
            body: "\(station.fuel) is \(price)¢/L at \(station.name)."
        )
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        print("Geofence monitoring failed:", region?.identifier ?? "unknown", error.localizedDescription)
    }

    private func shouldSendAlert(for stationID: String) -> Bool {
        let history: [String: Date] = load(forKey: Self.alertHistoryKey) ?? [:]
        guard let lastAlert = history[stationID] else {
            return true
        }
        return Date().timeIntervalSince(lastAlert) >= Self.alertCooldown
    }

    private func recordAlert(for stationID: String) {
        var history: [String: Date] = load(forKey: Self.alertHistoryKey) ?? [:]
        history[stationID] = Date()

        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        history = history.filter { $0.value >= cutoff }
        save(history, forKey: Self.alertHistoryKey)
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func load<Value: Decodable>(forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
