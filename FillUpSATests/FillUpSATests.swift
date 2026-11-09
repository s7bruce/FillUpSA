import CoreLocation
import Foundation
import Testing
@testable import FillUpSA

@Suite("Station fuel selection and brands")
@MainActor
struct StationTests {
    @Test(arguments: [
        (2, "91"), (3, "Diesel"), (4, "LPG"), (5, "95"),
        (8, "98"), (12, "E10"), (14, "Premium Diesel"), (19, "E85"),
        (-1, "Unknown"), (999, "Unknown")
    ])
    func fuelIdentifiers(id: Int, expected: String) {
        #expect(fuelName(for: id) == expected)
    }

    @Test(arguments: [
        ("On The Run", "OTR"), ("Peregrine", "OTR"), ("EG Fuel", "Ampol"),
        ("AM/PM", "BP"), ("British Petroleum", "BP"), ("Reddy Express", "Shell"),
        ("Woolworths Fuel", "Caltex"), ("United Petroleum", "United"),
        ("Mobil", "Mobil"), ("X-Convenience", "X Convenience"),
        ("Leroy’s", "Leroy's"), ("Solo", "Solo"), ("U Go", "U-Go"),
        ("LMCT", "LMCT"), ("Local Roadhouse", "Independents")
    ])
    func brandAliases(name: String, expected: String) {
        #expect(station(name: name).brandFilterCategory == expected)
    }

    @Test func operatorBrandTakesPrecedence() {
        #expect(station(name: "OTR Adelaide", brand: "BP").brandFilterCategory == "OTR")
    }

    @Test func dieselPrefersRegularEvenWhenPremiumIsCheaper() {
        let value = station(fuels: [
            FuelPrice(type: "Premium Diesel", priceCents: 180),
            FuelPrice(type: "Diesel", priceCents: 190)
        ])
        #expect(value.priceForSelection("Diesel") == 190)
        #expect(!value.usesPremiumDiesel(for: "Diesel"))
    }

    @Test func dieselFallsBackToPremium() {
        let value = station(fuels: [FuelPrice(type: "Premium Diesel", priceCents: 189.9)])
        #expect(value.price(for: "Diesel") == nil)
        #expect(value.priceForSelection("Diesel") == 189.9)
        #expect(value.usesPremiumDiesel(for: "Diesel"))
        #expect(value.priceForSelection("91") == nil)
        #expect(!value.usesPremiumDiesel(for: "91"))
    }

    @Test func missingFuelDoesNotInventAPrice() {
        #expect(station().priceForSelection("Diesel") == nil)
        #expect(!station().usesPremiumDiesel(for: "Diesel"))
    }

    @Test func stationCanBeSavedAndRestored() throws {
        let original = station(fuels: [FuelPrice(type: "91", priceCents: 159.9)])
        let restored = try JSONDecoder().decode(
            Station.self, from: JSONEncoder().encode(original)
        )
        #expect(restored.id == original.id)
        #expect(restored.priceForSelection("91") == 159.9)
        #expect(restored.fuels.first?.id == original.fuels.first?.id)
        #expect(restored.lastUpdated == original.lastUpdated)
    }

    private func station(
        name: String = "Test Station", brand: String = "",
        fuels: [FuelPrice] = []
    ) -> Station {
        Station(
            id: "test", name: name, brand: brand, address: "1 Test Road",
            postcode: "5000", weeklyHours: [:], lat: -34.9285, lon: 138.6007,
            fuels: fuels, lastUpdated: Date(timeIntervalSince1970: 0)
        )
    }
}

@Suite("Saved preferences and history")
@MainActor
struct AppStateTests {
    // Every test case owns a separate defaults domain, including parameterized cases.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "FillUpSATests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func firstLaunchDefaults() throws {
        try withDefaults { defaults in
            let app = AppState(defaults: defaults)
            #expect(app.preferredFuel == "91")
            #expect(app.excludedBrands.isEmpty)
            #expect(app.maximumVisibleStations == 60)
            #expect(app.navigationApp == .appleMaps)
            #expect(app.priceHistory.isEmpty)
            #expect(app.lastStationFetchDate == nil)
            #expect(app.stations.isEmpty)
            #expect(!app.isLoading)
        }
    }

    @Test(arguments: ["E10", "91", "95", "98", "Diesel", "LPG"])
    func fuelPreferenceSurvivesRelaunch(fuel: String) throws {
        try withDefaults { defaults in
            let app = AppState(defaults: defaults)
            app.preferredFuel = fuel
            #expect(AppState(defaults: defaults).preferredFuel == fuel)
        }
    }

    @Test func settingsSurviveRelaunch() throws {
        try withDefaults { defaults in
            let app = AppState(defaults: defaults)
            app.excludedBrands = ["BP", "OTR"]
            app.maximumVisibleStations = 25
            app.navigationApp = .waze
            let restored = AppState(defaults: defaults)
            #expect(restored.excludedBrands == ["BP", "OTR"])
            #expect(restored.maximumVisibleStations == 25)
            #expect(restored.navigationApp == .waze)
        }
    }

    @Test func invalidSavedValuesUseSafeDefaults() throws {
        try withDefaults { defaults in
            defaults.set("E85", forKey: "preferredFuel")
            defaults.set("missing-app", forKey: "navigationApp")
            defaults.set(["BP", "Unknown Brand"], forKey: "excludedStationBrands")
            defaults.set(Data("invalid JSON".utf8), forKey: "fuelPriceHistory")
            let app = AppState(defaults: defaults)
            #expect(app.preferredFuel == "91")
            #expect(app.navigationApp == .appleMaps)
            #expect(app.excludedBrands == ["BP"])
            #expect(app.priceHistory.isEmpty)
        }
    }

    @Test(arguments: [(-10, 1), (0, 1), (1, 1), (60, 60), (100, 100), (101, 100)])
    func savedStationLimitIsClamped(saved: Int, expected: Int) throws {
        try withDefaults { defaults in
            defaults.set(saved, forKey: "maximumVisibleStations")
            #expect(AppState(defaults: defaults).maximumVisibleStations == expected)
        }
    }

    @Test func restoresHistoryAndLastFetchDate() throws {
        try withDefaults { defaults in
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let point = FuelPriceHistoryPoint(
                date: date, fuelType: "91", low: 150, high: 190, average: 170,
                source: .server
            )
            defaults.set(try JSONEncoder().encode([point]), forKey: "fuelPriceHistory")
            defaults.set(date, forKey: "lastStationFetchDate")
            let app = AppState(defaults: defaults)
            #expect(app.priceHistory.count == 1)
            #expect(app.priceHistory.first?.id == point.id)
            #expect(app.priceHistory.first?.source == .server)
            #expect(app.lastStationFetchDate == date)
        }
    }

    @Test func legacyHistoryWithoutSourceStillDecodes() throws {
        let data = Data("""
        [{"id":"00000000-0000-0000-0000-000000000001","date":0,
        "fuelType":"91","low":150,"high":190,"average":170}]
        """.utf8)
        let points = try JSONDecoder().decode([FuelPriceHistoryPoint].self, from: data)
        #expect(points.count == 1)
        #expect(points.first?.source == nil)
        #expect(points.first?.average == 170)
    }
}
