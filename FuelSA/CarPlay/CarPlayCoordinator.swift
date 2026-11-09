// FuelSA/CarPlay/CarPlayCoordinator.swift

import Foundation
import CarPlay
import MapKit

@MainActor
final class CarPlayCoordinator: NSObject {

    private weak var interfaceController: CPInterfaceController?

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        super.init()
    }

    // MARK: - Entry Point

    func start() {
        Task { @MainActor in
            await loadAndPresent()
        }
    }

    // MARK: - Async loading & presentation (SDK-compatible: no `since:`)

    private func loadAndPresent() async {
        let defaultCoord = CLLocationCoordinate2D(latitude: -34.9285, longitude: 138.6007)

        // Use your own manager if you like; fallback to Adelaide CBD
        let coord = LocationManager.shared.current ?? defaultCoord

        // Fetch stations (same as phone UI)
        let stations: [Station]
        do {
            stations = try await FuelAPI.shared.fetchStations(
                around: coord,
                maximumStations: 75,
                fuelTypes: ["ULP 91"]
            )
        } catch {
            stations = Station.mock
        }

        // Build POIs (limit for performance)
        let pois: [CPPointOfInterest] = stations.prefix(12).map { station in
            let coord = CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon)
            let item: MKMapItem
            if #available(iOS 26.0, *) {
                let loc = CLLocation(latitude: coord.latitude,
                                     longitude: coord.longitude)
                item = MKMapItem(location: loc, address: nil)   // iOS 26 initializer
            } else {
                let placemark = MKPlacemark(coordinate: coord)
                item = MKMapItem(placemark: placemark)
            }
            item.name = station.name

            let summary = priceSummary(for: station, preferredFuel: "ULP 91")

            // Use the initializer that exists on older SDKs (detailSummary: String, no `since:`)
            return CPPointOfInterest(
                location: item,
                title: station.name,
                subtitle: station.brand,
                summary: summary,
                detailTitle: "Details",
                detailSubtitle: "Updated \(relativeMins(station.lastUpdated))",
                detailSummary: summary,
                pinImage: nil
            )
        }

        // List template
        let template = CPPointOfInterestTemplate(
            title: "Nearby Fuel",
            pointsOfInterest: pois,
            selectedIndex: NSNotFound
        )
        template.pointOfInterestDelegate = self

        // Present template (handles both API shapes)
        if let controller = interfaceController,
           controller.responds(to: #selector(CPInterfaceController.setRootTemplate(_:animated:completion:))) {
            // Newer API with completion; bridge completion to async
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                controller.setRootTemplate(template, animated: true, completion: { _, _ in
                    continuation.resume()
                })
            }
        } else {
            // Older API may be throwing on newer SDKs; call with try? to ignore failures gracefully
            _ = try? await interfaceController?.setRootTemplate(template, animated: true)
        }
    }

    // MARK: - Helpers

    private func priceSummary(for s: Station, preferredFuel: String) -> String {
        if let p = s.price(for: preferredFuel) {
            return String(format: "A$ %.1fc", p)
        }
        return "Prices unavailable"
    }

    private func relativeMins(_ date: Date) -> String {
        let mins = max(1, Int(Date().timeIntervalSince(date) / 60))
        return "\(mins)m ago"
    }
}

@MainActor
extension CarPlayCoordinator: CPPointOfInterestTemplateDelegate {
    func pointOfInterestTemplate(_ pointOfInterestTemplate: CPPointOfInterestTemplate,
                                 didSelectPointOfInterest pointOfInterest: CPPointOfInterest) {
        _ = pointOfInterest.location

        _ = CPRouteChoice(
            summaryVariants: ["Route"],
            additionalInformationVariants: [],
            selectionSummaryVariants: ["Go"]
        )

        let mapT = CPMapTemplate()

        if let controller = interfaceController,
           controller.responds(to: #selector(CPInterfaceController.pushTemplate(_:animated:completion:))) {
            controller.pushTemplate(mapT, animated: true, completion: nil)
        } else if let controller = interfaceController {
            Task { @MainActor in
                _ = try? await controller.pushTemplate(mapT, animated: true)
            }
        }
    }

    // Optional delegate method present in some SDKs; include a no-op to avoid warnings if exposed.
    func pointOfInterestTemplate(_ pointOfInterestTemplate: CPPointOfInterestTemplate,
                                 didChangeMapRegion region: MKCoordinateRegion) {
        // No-op
    }
}
