import CoreLocation
import Foundation
import Testing
@testable import FillUpSA

// Continuations make the overlapping-refresh regression deterministic, without sleeps.
@MainActor
private final class FirstFetchGate {
    private var requests = 0
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var ready: CheckedContinuation<Void, Never>?

    func pauseFirstFetch() async {
        requests += 1
        guard requests <= 3 else { return }
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            if pending.count == 3 {
                ready?.resume()
                ready = nil
            }
        }
    }

    func waitUntilPaused() async {
        guard pending.count < 3 else { return }
        await withCheckedContinuation { ready = $0 }
    }

    func resume() {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

@Suite("Refresh and offline state")
@MainActor
struct AppRefreshTests {
    private func withDefaults(
        _ body: (UserDefaults) async throws -> Void
    ) async throws {
        let name = "FillUpSARefreshTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    @Test func successfulRefreshUpdatesStationsAndPersistsFetchDate() async throws {
        try await withDefaults { defaults in
            let api = FuelAPI { request in try HTTPFixture.fuelResponse(request) }
            let app = AppState(defaults: defaults, fuelAPI: api)
            app.preferredFuel = "Diesel"
            app.maximumVisibleStations = 1
            await app.refresh(around: remoteCoordinate(for: app))
            #expect(app.stations.map(\.id) == ["2"])
            #expect(!app.isLoading)
            let fetchDate = try #require(app.lastStationFetchDate)
            #expect(defaults.object(forKey: "lastStationFetchDate") as? Date == fetchDate)
        }
    }

    @Test func refreshPassesBrandExclusionsToService() async throws {
        try await withDefaults { defaults in
            let api = FuelAPI { request in try HTTPFixture.fuelResponse(request) }
            let app = AppState(defaults: defaults, fuelAPI: api)
            app.excludedBrands = ["BP"]
            await app.refresh(around: remoteCoordinate(for: app))
            #expect(app.stations.map(\.id) == ["3"])
            #expect(!app.isLoading)
        }
    }

    @Test(arguments: [false, true])
    func failedOrCancelledRefreshKeepsPreviousData(cancelled: Bool) async throws {
        try await withDefaults { defaults in
            let previousFetch = Date(timeIntervalSince1970: 1_700_000_000)
            defaults.set(previousFetch, forKey: "lastStationFetchDate")
            let api = FuelAPI { _ in
                if cancelled { throw CancellationError() }
                throw URLError(.notConnectedToInternet)
            }
            let app = AppState(defaults: defaults, fuelAPI: api)
            app.stations = Station.mock
            let previousIDs = app.stations.map(\.id)
            await app.refresh(around: remoteCoordinate(for: app))
            #expect(app.stations.map(\.id) == previousIDs)
            #expect(app.lastStationFetchDate == previousFetch)
            #expect(!app.isLoading)
        }
    }

    @Test func serverSyncReplacesServerRowsAndKeepsDeviceObservations() async throws {
        try await withDefaults { defaults in
            let device = point(date: 100, source: .device)
            let oldServer = point(date: 1790812800, source: .server)
            defaults.set(try JSONEncoder().encode([device, oldServer]), forKey: "fuelPriceHistory")
            let service = FuelHistoryService { request in
                try HTTPFixture.response(request, body: """
                [{"captured_at":"2026-10-01T00:00:00Z","fuel_type":"91","low":155,"high":195,"average":175}]
                """)
            }
            let app = AppState(defaults: defaults, historyService: service,
                               now: { Date(timeIntervalSince1970: 1790899200) })
            await app.syncServerHistory()
            await app.syncServerHistory()
            #expect(app.priceHistory.count == 2, "Repeated sync must not duplicate server rows")
            #expect(app.priceHistory.first?.id == device.id)
            #expect(!app.priceHistory.contains { $0.id == oldServer.id })
            #expect(app.priceHistory.last?.average == 175)
            #expect(app.priceHistory.last?.source == .server)
            let restored = AppState(defaults: defaults)
            #expect(restored.priceHistory.map(\.id) == app.priceHistory.map(\.id))
        }
    }

    @Test(arguments: [false, true])
    func emptyOrFailedSyncRetainsOfflineHistory(fails: Bool) async throws {
        try await withDefaults { defaults in
            let saved = point(date: 100, source: .server)
            defaults.set(try JSONEncoder().encode([saved]), forKey: "fuelPriceHistory")
            let service = FuelHistoryService { request in
                if fails { throw URLError(.notConnectedToInternet) }
                return try HTTPFixture.response(request, body: "[]")
            }
            let app = AppState(defaults: defaults, historyService: service,
                               now: { Date(timeIntervalSince1970: 1790899200) })
            await app.syncServerHistory()
            #expect(app.priceHistory.map(\.id) == [saved.id])
            #expect(AppState(defaults: defaults).priceHistory.map(\.id) == [saved.id])
        }
    }

    @Test func olderRefreshCannotOverwriteNewerFuelSelection() async throws {
        try await withDefaults { defaults in
            let gate = FirstFetchGate()
            let api = FuelAPI { request in
                await gate.pauseFirstFetch()
                return try HTTPFixture.fuelResponse(request)
            }
            let app = AppState(defaults: defaults, fuelAPI: api)
            let coordinate = remoteCoordinate(for: app)
            let firstRefresh = Task { await app.refresh(around: coordinate) }
            await gate.waitUntilPaused()
            #expect(app.isLoading)

            app.preferredFuel = "Diesel"
            await app.refresh(around: coordinate)
            #expect(app.stations.map(\.id) == ["2"])
            #expect(!app.isLoading)
            let latestFetchDate = app.lastStationFetchDate

            gate.resume()
            await firstRefresh.value
            #expect(app.stations.map(\.id) == ["2"])
            #expect(app.lastStationFetchDate == latestFetchDate)
            #expect(!app.isLoading)
        }
    }

    private func point(date: TimeInterval, source: FuelPriceHistoryPoint.Source) -> FuelPriceHistoryPoint {
        FuelPriceHistoryPoint(
            date: Date(timeIntervalSince1970: date), fuelType: "91",
            low: 150, high: 190, average: 170, source: source
        )
    }

    // Refreshing far from the device avoids geofence and local-history side effects.
    private func remoteCoordinate(for app: AppState) -> CLLocationCoordinate2D {
        let latitude = (app.location.current?.latitude ?? -34) > 0 ? -80.0 : 80.0
        return CLLocationCoordinate2D(latitude: latitude, longitude: 0)
    }
}
