import Foundation
import CoreLocation

@MainActor
final class GeofenceManager: NSObject, CLLocationManagerDelegate {
    static let shared = GeofenceManager()
    private let manager = CLLocationManager()
    private override init() { super.init(); manager.delegate = self }

    func updateMonitoredStations(_ stations: [Station], preferredFuel: String, limit: Int = 10) {
        manager.requestAlwaysAuthorization()

        // clear previous
        for r in manager.monitoredRegions { manager.stopMonitoring(for: r) }

        // pick cheapest N with a valid price
        let selected = stations
            .filter { $0.price(for: preferredFuel) != nil }
            .sorted { ($0.price(for: preferredFuel)!) < ($1.price(for: preferredFuel)!) }
            .prefix(limit)

        for s in selected {
            let region = CLCircularRegion(center: s.coordinate, radius: 250, identifier: s.id) // 250m
            region.notifyOnEntry = true; region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Notifier.send(title: "Cheaper fuel nearby", body: "You’re near \(region.identifier). Check today’s price.")
    }
}
