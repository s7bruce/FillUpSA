import CoreLocation
import Foundation
import Testing
@testable import FillUpSA

@Suite("Device collection and server fallback")
@MainActor
struct HistoryCollectionTests {
    private let origin = CLLocationCoordinate2D(latitude: -34.9285, longitude: 138.6007)
    private let date = Date(timeIntervalSince1970: 1_793_232_000)

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let name = "HistoryCollectionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    @Test func nearbyRefreshCollectsAndPersistsLocalStatistics() async throws {
        try await withDefaults { defaults in
            let app = makeApp(defaults)
            await app.refresh(around: origin)
            let point = try #require(app.priceHistory.first { $0.fuelType == "91" })
            #expect(point.source == .device)
            #expect(point.low == 159.9)
            #expect(point.high == 179.9)
            #expect(abs(point.average - 169.9) < 0.001)
            #expect(point.date == date)
            #expect(AppState(defaults: defaults).priceHistory.first?.id == point.id)
        }
    }

    @Test(arguments: [false, true])
    func noLocalCollectionWithoutLocationOrForRemoteSearch(remote: Bool) async throws {
        try await withDefaults { defaults in
            let app = AppState(
                defaults: defaults, fuelAPI: FuelAPI { try HTTPFixture.fuelResponse($0) },
                currentCoordinate: { remote ? origin : nil }, now: { date },
                monitorStations: { _, _ in Issue.record("Must not register remote geofences") }
            )
            await app.refresh(around: remote ? CLLocationCoordinate2D(latitude: -35.5, longitude: 138.6) : origin)
            #expect(app.priceHistory.isEmpty)
        }
    }

    @Test func serverSampleDoesNotSuppressDeviceCollectionAndHourlyThrottlePersists() async throws {
        try await withDefaults { defaults in
            let server = point(at: date, source: .server)
            defaults.set(try JSONEncoder().encode([server]), forKey: "fuelPriceHistory")
            var clock = date
            let app = AppState(
                defaults: defaults, fuelAPI: FuelAPI { try HTTPFixture.fuelResponse($0) },
                currentCoordinate: { origin }, now: { clock }, monitorStations: { _, _ in }
            )
            await app.refresh(around: origin)
            #expect(app.priceHistory.filter { $0.source == .device }.count == 1)
            clock = date.addingTimeInterval(3599)
            await app.refresh(around: origin)
            #expect(app.priceHistory.filter { $0.source == .device }.count == 1)
            clock = date.addingTimeInterval(3600)
            await app.refresh(around: origin)
            #expect(app.priceHistory.filter { $0.source == .device }.count == 2)
            #expect(app.priceHistory.contains { $0.id == server.id })
            #expect(AppState(defaults: defaults).priceHistory.count == 3)
        }
    }

    @Test func collectionRemovesHistoryOlderThanNinetyDays() async throws {
        try await withDefaults { defaults in
            let expired = point(at: date.addingTimeInterval(-91 * 86400))
            defaults.set(try JSONEncoder().encode([expired]), forKey: "fuelPriceHistory")
            let app = makeApp(defaults)
            await app.refresh(around: origin)
            #expect(!app.priceHistory.contains { $0.id == expired.id })
            #expect(app.priceHistory.count == 1)
        }
    }

    @Test(arguments: [7, 30, 90])
    func adequateLocalCoverageAvoidsNetworkAndWinsOverServer(days: Int) async throws {
        try await withDefaults { defaults in
            let local = (0..<days).map { point(at: date.addingTimeInterval(-Double($0) * 86400)) }
            defaults.set(try JSONEncoder().encode(local + [point(at: date, source: .server)]),
                         forKey: "fuelPriceHistory")
            let app = AppState(defaults: defaults, historyService: FuelHistoryService { _ in
                Issue.record("Sufficient local history should avoid a server request")
                throw URLError(.badURL)
            }, now: { date })
            await app.ensureHistory(days: days)
            #expect(app.historyPoints(days: days).count == days)
            #expect(app.historyPoints(days: days).allSatisfy { $0.source == .device })
        }
    }

    @Test func insufficientLocalHistoryFetchesServerAndPersistsFallback() async throws {
        try await withDefaults { defaults in
            let local = point(at: date)
            defaults.set(try JSONEncoder().encode([local]), forKey: "fuelPriceHistory")
            var requests = 0
            let service = FuelHistoryService { request in
                requests += 1
                return try HTTPFixture.response(request, body: serverJSON())
            }
            let app = AppState(defaults: defaults, historyService: service, now: { date })
            await app.ensureHistory(days: 7)
            #expect(requests == 1)
            #expect(app.historyPoints(days: 7).count == 1)
            #expect(app.historyPoints(days: 7).first?.source == .server)
            #expect(app.priceHistory.contains { $0.id == local.id })
            #expect(AppState(defaults: defaults, now: { date }).historyPoints(days: 7).first?.source == .server)
            await app.ensureHistory(days: 7)
            #expect(requests == 1, "The same fresh range is reused")
            let restored = AppState(defaults: defaults, historyService: service, now: { date })
            await restored.ensureHistory(days: 7)
            #expect(requests == 1, "Coverage survives relaunch")
            await app.ensureHistory(days: 30)
            #expect(requests == 2, "A larger range needs a new scoped download")
        }
    }

    @Test func unavailableServerKeepsLocalDataAndAllowsRetry() async throws {
        try await withDefaults { defaults in
            let local = point(at: date)
            defaults.set(try JSONEncoder().encode([local]), forKey: "fuelPriceHistory")
            var requests = 0
            let service = FuelHistoryService { request in
                requests += 1
                if requests == 1 { throw URLError(.notConnectedToInternet) }
                return try HTTPFixture.response(request, body: serverJSON())
            }
            let app = AppState(defaults: defaults, historyService: service, now: { date })
            await app.ensureHistory(days: 7)
            #expect(app.historyPoints(days: 7).map(\.id) == [local.id])
            await app.ensureHistory(days: 7)
            #expect(requests == 2)
            #expect(app.historyPoints(days: 7).first?.source == .server)
        }
    }

    @Test func burstOfSamplesStaleSamplesAndOtherFuelsDoNotCountAsCoverage() {
        let burst = (0..<100).map { point(at: date.addingTimeInterval(-Double($0) * 60)) }
        #expect(!FuelHistorySelection.hasSufficientLocalHistory(burst, fuel: "91", days: 7, now: date))
        let stale = (2..<9).map { point(at: date.addingTimeInterval(-Double($0) * 86400)) }
        #expect(!FuelHistorySelection.hasSufficientLocalHistory(stale, fuel: "91", days: 7, now: date))
        let daily = (0..<7).map { point(at: date.addingTimeInterval(-Double($0) * 86400)) }
        #expect(!FuelHistorySelection.hasSufficientLocalHistory(daily, fuel: "Diesel", days: 7, now: date))
    }

    @Test func selectionFiltersRangeFuelAndFutureThenSorts() {
        let earlier = point(at: date.addingTimeInterval(-86400))
        let latest = point(at: date)
        let excluded = [point(at: date.addingTimeInterval(86400)), point(at: date.addingTimeInterval(-8 * 86400))]
        let result = FuelHistorySelection.points([latest, earlier] + excluded, fuel: "91", days: 7, now: date)
        #expect(result.map(\.id) == [earlier.id, latest.id])
    }

    @Test func scopedDownloadsPreserveOtherFuelsAndRefreshExpiredCoverage() async throws {
        try await withDefaults { defaults in
            var clock = date
            var requestedFuels: [String] = []
            let service = FuelHistoryService { request in
                let url = try #require(request.url)
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let filter = try #require(query.first { $0.name == "fuel_type" }?.value)
                requestedFuels.append(filter)
                let fuel = String(filter.dropFirst(3))
                let lower = try #require(query.first { $0.name == "captured_at" && ($0.value?.hasPrefix("gte.") ?? false) }?.value)
                let start = try #require(ISO8601DateFormatter().date(from: String(lower.dropFirst(4))))
                #expect(abs(clock.timeIntervalSince(start) - 7 * 86400) < 2)
                return try HTTPFixture.response(request, body: serverJSON().replacingOccurrences(of: "\"91\"", with: "\"\(fuel)\""))
            }
            let app = AppState(defaults: defaults, historyService: service, now: { clock })
            await app.ensureHistory(days: 7)
            let originalID = try #require(app.historyPoints(days: 7).first?.id)
            app.preferredFuel = "Diesel"
            await app.ensureHistory(days: 7)
            #expect(requestedFuels == ["eq.91", "eq.Diesel"])
            #expect(app.priceHistory.contains { $0.id == originalID })
            #expect(app.historyPoints(days: 7).first?.fuelType == "Diesel")
            app.preferredFuel = "91"
            await app.ensureHistory(days: 7)
            #expect(requestedFuels.count == 2)
            clock = date.addingTimeInterval(1801)
            await app.ensureHistory(days: 7)
            #expect(requestedFuels == ["eq.91", "eq.Diesel", "eq.91"])
            #expect(app.priceHistory.filter { $0.fuelType == "91" }.count == 1)
            #expect(app.priceHistory.filter { $0.fuelType == "Diesel" }.count == 1)
        }
    }

    private func makeApp(_ defaults: UserDefaults) -> AppState {
        AppState(defaults: defaults, fuelAPI: FuelAPI { try HTTPFixture.fuelResponse($0) },
                 currentCoordinate: { origin }, now: { date }, monitorStations: { _, _ in })
    }

    private func point(at date: Date, source: FuelPriceHistoryPoint.Source = .device) -> FuelPriceHistoryPoint {
        FuelPriceHistoryPoint(date: date, fuelType: "91", low: 150, high: 190, average: 170, source: source)
    }

    private func serverJSON() -> String {
        """
        [{"captured_at":"\(ISO8601DateFormatter().string(from: date))","fuel_type":"91","low":160,"high":200,"average":180}]
        """
    }
}

@Suite("History pagination")
@MainActor
struct HistoryPaginationTests {
    @Test func loadsLaterPagesIncludingNewestRecords() async throws {
        var offsets: [Int] = []
        let service = FuelHistoryService { request in
            let url = try #require(request.url)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let offset = Int(items.first { $0.name == "offset" }?.value ?? "") ?? -1
            offsets.append(offset)
            let row = #"{"captured_at":"2026-11-09T00:00:00Z","fuel_type":"91","low":150,"high":190,"average":170}"#
            return try HTTPFixture.response(request, body: "[" + Array(repeating: row, count: offset == 0 ? 500 : 1).joined(separator: ",") + "]")
        }
        #expect(try await service.fetchHistory().count == 501)
        #expect(offsets == [0, 500])
    }

    @Test func laterPageFailureDoesNotReturnPartialHistory() async {
        let service = FuelHistoryService { request in
            if request.url?.absoluteString.contains("offset=500") == true {
                throw URLError(.timedOut)
            }
            let row = #"{"captured_at":"2026-11-09T00:00:00Z","fuel_type":"91","low":150,"high":190,"average":170}"#
            return try HTTPFixture.response(request, body: "[" + Array(repeating: row, count: 500).joined(separator: ",") + "]")
        }
        await #expect(throws: URLError.self) { try await service.fetchHistory() }
    }
}
