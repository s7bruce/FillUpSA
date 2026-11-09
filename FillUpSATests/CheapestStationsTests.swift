import CoreLocation
import Foundation
import Testing
@testable import FillUpSA

@Suite("Cheapest menu")
@MainActor
struct CheapestStationsTests {
    private let origin = CLLocationCoordinate2D(latitude: -34.9285, longitude: 138.6007)

    @Test func ranksByPriceThenDistanceAndLimitsToFive() {
        let stations = (0..<8).map { station(String($0), price: Double(180 - $0), offset: Double($0) * 0.001) }
        let result = CheapestStationsModel.cheapest(stations, around: origin, fuel: "91")
        #expect(result.map(\.id) == ["7", "6", "5", "4", "3"])
        let tied = [station("far", price: 150, offset: 0.1), station("near", price: 150)]
        #expect(CheapestStationsModel.cheapest(tied, around: origin, fuel: "91").map(\.id) == ["near", "far"])
    }

    @Test func excludesDistantMissingAndInvalidPrices() {
        let values = [
            station("near", price: 160), station("outside", price: 100, offset: 0.3),
            station("wrongFuel", price: 90, fuel: "LPG"),
            station("zero", price: 0), station("nan", price: .nan)
        ]
        #expect(CheapestStationsModel.cheapest(values, around: origin, fuel: "91").map(\.id) == ["near"])
    }

    @Test func premiumDieselParticipatesInCheapestSelection() {
        let values = [station("premium", price: 170, fuel: "Premium Diesel"), station("regular", price: 180, fuel: "Diesel")]
        #expect(CheapestStationsModel.cheapest(values, around: origin, fuel: "Diesel").map(\.id) == ["premium", "regular"])
    }

    @Test func missingLocationDoesNotFetch() async {
        let model = CheapestStationsModel(api: FuelAPI { _ in
            Issue.record("No request should occur without location")
            throw URLError(.badURL)
        })
        await model.load(around: nil, fuel: "91", excludingBrands: [])
        #expect(model.errorMessage == "Your current location is not available.")
        #expect(model.stations.isEmpty)
        #expect(!model.isLoading)
    }

    @Test func loadsAndAppliesFuelAndBrandFilters() async {
        let model = CheapestStationsModel(api: FuelAPI { try HTTPFixture.fuelResponse($0) })
        await model.load(around: origin, fuel: "Diesel", excludingBrands: [])
        #expect(model.stations.map(\.id) == ["2"])
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
        await model.load(around: origin, fuel: "Diesel", excludingBrands: ["OTR"])
        #expect(model.stations.isEmpty)
        #expect(model.errorMessage == nil, "No matches is an empty state, not a request error")
    }

    @Test func failedLoadShowsErrorAndClearsPreviousResults() async {
        var fail = false
        let model = CheapestStationsModel(api: FuelAPI { request in
            if fail { throw URLError(.notConnectedToInternet) }
            return try HTTPFixture.fuelResponse(request)
        })
        await model.load(around: origin, fuel: "91", excludingBrands: [])
        #expect(!model.stations.isEmpty)
        fail = true
        await model.load(around: origin, fuel: "91", excludingBrands: [])
        #expect(model.stations.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }

    @Test func cancellationDoesNotShowNetworkError() async {
        let model = CheapestStationsModel(api: FuelAPI { _ in throw CancellationError() })
        await model.load(around: origin, fuel: "91", excludingBrands: [])
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
    }

    private func station(_ id: String, price: Double, fuel: String = "91", offset: Double = 0) -> Station {
        Station(id: id, name: id, brand: "", address: "", postcode: "", weeklyHours: [:],
                lat: origin.latitude + offset, lon: origin.longitude,
                fuels: [FuelPrice(type: fuel, priceCents: price)], lastUpdated: .now)
    }
}
