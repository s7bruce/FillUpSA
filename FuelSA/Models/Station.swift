import Foundation
import CoreLocation

struct Station: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let brand: String
    let lat: Double
    let lon: Double
    let fuels: [FuelPrice]
    let lastUpdated: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func price(for fuel: String) -> Double? {
        fuels.first(where: { $0.type == fuel })?.priceCents
    }
}

extension Station {
    static let mock: [Station] = [
        Station(
            id: "A1",
            name: "BP Port Road",
            brand: "BP",
            lat: -34.907, lon: 138.571,
            fuels: [
                FuelPrice(type: "ULP 91", priceCents: 187.9),
                FuelPrice(type: "E10",     priceCents: 185.5),
                FuelPrice(type: "95",      priceCents: 205.9),
                FuelPrice(type: "98",      priceCents: 215.9),
                FuelPrice(type: "Diesel",  priceCents: 199.9)
            ],
            lastUpdated: Date().addingTimeInterval(-25*60)
        ),
        Station(
            id: "A2",
            name: "Caltex Anzac Hwy",
            brand: "Caltex",
            lat: -34.955, lon: 138.554,
            fuels: [
                FuelPrice(type: "ULP 91", priceCents: 189.5),
                FuelPrice(type: "95",     priceCents: 207.9),
                FuelPrice(type: "98",     priceCents: 217.9),
                FuelPrice(type: "Diesel", priceCents: 201.9)
            ],
            lastUpdated: Date().addingTimeInterval(-50*60)
        )
    ]
}
