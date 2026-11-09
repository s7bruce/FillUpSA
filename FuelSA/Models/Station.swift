import Foundation
import CoreLocation

struct StationHours: Codable {
    let opens: String
    let closes: String
}

struct Station: Identifiable, Codable {
    let id: String
    let name: String
    let brand: String
    let address: String
    let postcode: String
    let weeklyHours: [Int: StationHours]
    let lat: Double
    let lon: Double
    let fuels: [FuelPrice]
    let lastUpdated: Date
}

extension Station {
    static let mock: [Station] = [
        Station(
            id: "A1",
            name: "BP Port Road",
            brand: "BP",
            address: "Port Road",
            postcode: "5007",
            weeklyHours: [:],
            lat: -34.907, lon: 138.571,
            fuels: [
                FuelPrice(type: "E10",     priceCents: 149.5),
                FuelPrice(type: "91", priceCents: 152.9),
                FuelPrice(type: "95",      priceCents: 168.9),
                FuelPrice(type: "98",      priceCents: 172.9),
                FuelPrice(type: "Diesel",  priceCents: 184.9)
            ],
            lastUpdated: Date().addingTimeInterval(-25*60)
        ),
        Station(
            id: "A2",
            name: "Caltex Anzac Hwy",
            brand: "Caltex",
            address: "Anzac Highway",
            postcode: "5035",
            weeklyHours: [:],
            lat: -34.955, lon: 138.554,
            fuels: [
                FuelPrice(type: "91", priceCents: 189.5),
                FuelPrice(type: "95",     priceCents: 207.9),
                FuelPrice(type: "98",     priceCents: 217.9),
                FuelPrice(type: "Diesel", priceCents: 201.9)
            ],
            lastUpdated: Date().addingTimeInterval(-50*60)
        )
    ]
}

extension Station {
    static let brandFilterOptions = [
        "OTR",
        "Ampol",
        "BP",
        "Shell",
        "Caltex",
        "United",
        "Mobil",
        "X Convenience",
        "Leroy's",
        "Solo",
        "U-Go",
        "LMCT",
        "Independents"
    ]

    var brandFilterCategory: String {
        let identity = "\(brand) \(name)".lowercased()

        if identity.contains("on the run")
            || identity.contains("otr")
            || identity.contains("peregrine") {
            return "OTR"
        } else if identity.contains("ampol") || identity.contains("eg fuel") {
            return "Ampol"
        } else if identity.contains("bp ")
                    || identity.hasPrefix("bp")
                    || identity.contains("british petroleum")
                    || identity.contains("ampm")
                    || identity.contains("am/pm")
                    || identity.contains("am pm") {
            return "BP"
        } else if identity.contains("shell")
                    || identity.contains("coles express")
                    || identity.contains("reddy express") {
            return "Shell"
        } else if identity.contains("caltex")
                    || identity.contains("woolworths fuel") {
            return "Caltex"
        } else if identity.contains("united petroleum")
                    || identity.contains("united fuel")
                    || identity.contains("united ") {
            return "United"
        } else if identity.contains("mobil") {
            return "Mobil"
        } else if identity.contains("x convenience")
                    || identity.contains("x-convenience")
                    || identity.contains("xconvenience") {
            return "X Convenience"
        } else if identity.contains("leroy's")
                    || identity.contains("leroys")
                    || identity.contains("leroy’s") {
            return "Leroy's"
        } else if identity.contains("solo") {
            return "Solo"
        } else if identity.contains("u-go")
                    || identity.contains("u go")
                    || identity.contains("ugo") {
            return "U-Go"
        } else if identity.contains("lmct") {
            return "LMCT"
        }

        return "Independents"
    }

    func price(for fuelName: String) -> Double? {
        fuels.first(where: { $0.type == fuelName })?.priceCents
    }

    func priceForSelection(_ fuelName: String) -> Double? {
        if let regularPrice = price(for: fuelName) {
            return regularPrice
        }

        guard fuelName == "Diesel" else {
            return nil
        }

        return price(for: "Premium Diesel")
    }

    func usesPremiumDiesel(for fuelName: String) -> Bool {
        fuelName == "Diesel"
            && price(for: "Diesel") == nil
            && price(for: "Premium Diesel") != nil
    }
}
