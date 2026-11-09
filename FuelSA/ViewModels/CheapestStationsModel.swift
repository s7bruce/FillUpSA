import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class CheapestStationsModel {
    private(set) var stations: [Station] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let api: FuelAPI
    private var activeRequest = UUID()

    init(api: FuelAPI? = nil) {
        self.api = api ?? .shared
    }

    func load(
        around coordinate: CLLocationCoordinate2D?,
        fuel: String,
        excludingBrands: Set<String>
    ) async {
        let request = UUID()
        activeRequest = request
        stations = []
        errorMessage = nil
        guard let coordinate else {
            isLoading = false
            errorMessage = "Your current location is not available."
            return
        }
        isLoading = true
        defer {
            if activeRequest == request { isLoading = false }
        }
        do {
            let fetched = try await api.fetchStations(
                around: coordinate, maximumStations: .max,
                fuelTypes: [fuel], excludingBrands: excludingBrands
            )
            guard activeRequest == request, !Task.isCancelled else { return }
            stations = Self.cheapest(fetched, around: coordinate, fuel: fuel)
        } catch is CancellationError {
            return
        } catch {
            guard activeRequest == request, !Task.isCancelled else { return }
            errorMessage = "Fuel prices could not be loaded. Please try again."
        }
    }

    static func cheapest(
        _ stations: [Station], around coordinate: CLLocationCoordinate2D, fuel: String
    ) -> [Station] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let candidates = stations.compactMap { station -> (station: Station, price: Double, distance: Double)? in
            guard let price = station.priceForSelection(fuel), price.isFinite, price > 0 else {
                return nil
            }
            let distance = origin.distance(from: CLLocation(latitude: station.lat, longitude: station.lon))
            guard distance <= 25_000 else { return nil }
            return (station, price, distance)
        }
        return candidates.sorted {
            if $0.price != $1.price { return $0.price < $1.price }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.station.id < $1.station.id
        }.prefix(5).map(\.station)
    }
}
