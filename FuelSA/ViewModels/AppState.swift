import Foundation
import CoreLocation
import Combine   // <- keep this

@MainActor
final class AppState: ObservableObject {
    @Published var stations: [Station] = []
    @Published var preferredFuel: String = "ULP 91"
    @Published var isLoading: Bool = false

    let location = LocationManager()

    func bootstrap() async {
        location.request()
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let coord = location.current
        do {
            let data = try await FuelAPI.shared.fetchStations(
                around: coord, radiusKm: 15, fuelTypes: [preferredFuel]
            )
            stations = data.sorted {
                ($0.price(for: preferredFuel) ?? .infinity) < ($1.price(for: preferredFuel) ?? .infinity)
            }
        } catch {
            print("Fetch error:", error)
        }
    }
}
