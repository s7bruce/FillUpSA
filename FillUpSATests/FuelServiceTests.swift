import CoreLocation
import Foundation
import Testing
@testable import FillUpSA

@Suite("Fuel API with fixed HTTP responses")
@MainActor
struct FuelAPITests {
    private let origin = CLLocationCoordinate2D(latitude: -34.9285, longitude: 138.6007)

    @Test func joinsResponsesConvertsPricesAndPreservesUpdateTime() async throws {
        let stations = try await fetch()
        let nearest = try #require(stations.first)
        #expect(nearest.id == "1")
        #expect(nearest.name == "BP Adelaide")
        #expect(nearest.brand == "BP")
        #expect(nearest.address == "1 Test Road")
        #expect(nearest.postcode == "5000")
        #expect(nearest.priceForSelection("91") == 159.9)
        let expectedDate = try #require(
            ISO8601DateFormatter().date(from: "2026-10-01T02:03:04Z")
        )
        #expect(nearest.fuels.first?.updatedAt == expectedDate)
        #expect(nearest.weeklyHours[1]?.opens == "08:00")
        #expect(nearest.weeklyHours[2]?.closes == "22:00")
        #expect(nearest.weeklyHours[3] == nil, "Incomplete opening hours must be omitted")
    }

    @Test func skipsMissingCoordinatesAndStationsWithoutPrices() async throws {
        let stations = try await fetch()
        #expect(stations.map(\.id) == ["1", "2", "3"])
        #expect(stations.last?.name == "Unknown")
        #expect(stations.last?.brand == "Independent")
        #expect(stations.last?.address == "")
    }

    @Test(arguments: [(-1, 0), (0, 0), (1, 1), (2, 2), (100, 3)])
    func stationLimitIsAppliedAfterDistanceSorting(limit: Int, count: Int) async throws {
        let stations = try await fetch(limit: limit)
        #expect(stations.count == count)
        #expect(stations.map(\.id) == Array(["1", "2", "3"].prefix(count)))
    }

    @Test func fuelFilterIncludesPremiumDieselFallback() async throws {
        let stations = try await fetch(fuels: ["Diesel"])
        #expect(stations.map(\.id) == ["2"])
        #expect(stations.first?.priceForSelection("Diesel") == 189.9)
    }

    @Test func multipleFuelFiltersMatchAnySelectedFuel() async throws {
        let stations = try await fetch(fuels: ["91", "Diesel"])
        #expect(stations.map(\.id) == ["1", "2", "3"])
    }

    @Test func unavailableFuelReturnsEmptyResults() async throws {
        #expect(try await fetch(fuels: ["LPG"]).isEmpty)
    }

    @Test func excludedBrandsAreRemovedBeforeTakingNearestStations() async throws {
        let stations = try await fetch(limit: 1, excluding: ["BP"])
        #expect(stations.map(\.id) == ["2"])
    }

    @Test func allBrandsExcludedReturnsEmptyResults() async throws {
        #expect(try await fetch(excluding: ["BP", "OTR", "Independents"]).isEmpty)
    }

    @Test(arguments: [
        "/Price/GetSitesPrices", "/Subscriber/GetFullSiteDetails", "/Subscriber/GetCountryBrands"
    ])
    func endpointFailuresFailTheWholeFetch(path: String) async {
        let api = FuelAPI { request in
            if request.url?.path == path {
                return try HTTPFixture.response(request, body: "Service unavailable", status: 503)
            }
            return try HTTPFixture.fuelResponse(request)
        }
        let error = await #expect(throws: NSError.self) {
            try await api.fetchStations(around: origin, maximumStations: 10, fuelTypes: [])
        }
        #expect(error?.code == 503)
    }

    @Test func malformedResponseThrowsDecodingError() async {
        let api = FuelAPI { request in
            try HTTPFixture.response(request, body: "{malformed")
        }
        await #expect(throws: DecodingError.self) {
            try await api.fetchStations(around: origin, maximumStations: 10, fuelTypes: [])
        }
    }

    @Test func offlineErrorIsPropagated() async {
        let api = FuelAPI { _ in throw URLError(.notConnectedToInternet) }
        let error = await #expect(throws: URLError.self) {
            try await api.fetchStations(around: origin, maximumStations: 10, fuelTypes: [])
        }
        #expect(error?.code == .notConnectedToInternet)
    }

    @Test func cancellationIsPropagated() async {
        let api = FuelAPI { _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) {
            try await api.fetchStations(around: origin, maximumStations: 10, fuelTypes: [])
        }
    }

    private func fetch(
        limit: Int = 100, fuels: [String] = [], excluding: Set<String> = []
    ) async throws -> [Station] {
        let api = FuelAPI { request in try HTTPFixture.fuelResponse(request) }
        return try await api.fetchStations(
            around: origin, maximumStations: limit, fuelTypes: fuels,
            excludingBrands: excluding
        )
    }
}

@Suite("Server price history")
@MainActor
struct FuelHistoryServiceTests {
    @Test(arguments: ["2026-10-01T02:03:04Z", "2026-10-01T02:03:04.000Z", "2026-10-01T11:33:04+09:30"])
    func decodesTimestampFormatsAndMarksServerSource(timestamp: String) async throws {
        let service = FuelHistoryService { request in
            try HTTPFixture.response(request, body: """
            [{"captured_at":"\(timestamp)","fuel_type":"Diesel","low":170.5,"high":210.9,"average":190.7}]
            """)
        }
        let history = try await service.fetchHistory()
        let point = try #require(history.first)
        #expect(history.count == 1)
        #expect(point.fuelType == "Diesel")
        #expect(point.low == 170.5)
        #expect(point.high == 210.9)
        #expect(point.average == 190.7)
        #expect(point.source == .server)
        #expect(point.date == ISO8601DateFormatter().date(from: "2026-10-01T02:03:04Z"))
    }

    @Test func requestsSelectedRangeInAscendingOrder() async throws {
        let service = FuelHistoryService { request in
            let url = try #require(request.url)
            #expect(url.path == "/rest/v1/fuel_price_history")
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let items = Dictionary((components.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }, uniquingKeysWith: { first, _ in first })
            #expect(items["fuel_type"] == "eq.91")
            #expect(components.queryItems?.contains { $0.name == "captured_at" && ($0.value?.hasPrefix("lte.") ?? false) } == true)
            #expect(items["order"] == "captured_at.asc,fuel_type.asc")
            #expect(items["select"] == "captured_at,fuel_type,low,high,average")
            let cutoff = try #require(items["captured_at"])
            #expect(cutoff.hasPrefix("gte."))
            let date = try #require(ISO8601DateFormatter().date(from: String(cutoff.dropFirst(4))))
            let expected = try #require(Calendar.current.date(byAdding: .day, value: -7, to: .now))
            #expect(abs(date.timeIntervalSince(expected)) < 5)
            #expect(request.value(forHTTPHeaderField: "apikey")?.isEmpty == false)
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            return try HTTPFixture.response(request, body: "[]")
        }
        #expect(try await service.fetchHistory(days: 7).isEmpty)
    }

    @Test func invalidTimestampDoesNotDiscardOtherRows() async throws {
        let service = FuelHistoryService { request in
            try HTTPFixture.response(request, body: """
            [
              {"captured_at":"invalid","fuel_type":"91","low":150,"high":190,"average":170},
              {"captured_at":"2026-10-01T00:00:00Z","fuel_type":"91","low":150,"high":190,"average":170}
            ]
            """)
        }
        #expect(try await service.fetchHistory().count == 1)
    }

    @Test(arguments: [401, 429, 500])
    func rejectsHTTPFailures(status: Int) async {
        let service = FuelHistoryService { request in
            try HTTPFixture.response(request, body: "[]", status: status)
        }
        let error = await #expect(throws: URLError.self) {
            try await service.fetchHistory()
        }
        #expect(error?.code == .badServerResponse)
    }

    @Test func rejectsMalformedRows() async {
        let service = FuelHistoryService { request in
            try HTTPFixture.response(request, body: #"[{"fuel_type":"91"}]"#)
        }
        await #expect(throws: DecodingError.self) { try await service.fetchHistory() }
    }

    @Test func propagatesTransportFailure() async {
        let service = FuelHistoryService { _ in throw URLError(.timedOut) }
        let error = await #expect(throws: URLError.self) { try await service.fetchHistory() }
        #expect(error?.code == .timedOut)
    }
}

// Fixed, intentionally unordered responses exercise the complete service pipeline.
// No test in this file sends network traffic or replaces a global URLSession.
@MainActor
enum HTTPFixture {
    static func response(
        _ request: URLRequest, body: String, status: Int = 200
    ) throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: nil
        ))
        return (Data(body.utf8), response)
    }

    static func fuelResponse(_ request: URLRequest) throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("FPDAPI SubscriberToken=") == true)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
        #expect(query["countryId"] == "21")
        if url.path != "/Subscriber/GetCountryBrands" {
            #expect(query["geoRegionLevel"] == "3")
            #expect(query["geoRegionId"] == "4")
        }

        let body: String
        switch url.path {
        case "/Subscriber/GetFullSiteDetails":
            body = """
            {"S":[
              {"S":3,"Lat":-35.1,"Lng":138.6},
              {"S":2,"N":"OTR North","B":20,"Lat":-34.95,"Lng":138.6},
              {"S":1,"N":"BP Adelaide","B":10,"A":"1 Test Road","P":"5000",
               "Lat":-34.9285,"Lng":138.6007,"MO":"06:00","MC":"22:00",
               "TO":"06:00","SUO":"08:00","SUC":"20:00"},
              {"S":4,"N":"Missing latitude","Lng":138.6},
              {"S":5,"N":"No prices","Lat":-34.9285,"Lng":138.6007},
              {"S":6,"N":"Missing longitude","Lat":-34.9285}
            ]}
            """
        case "/Subscriber/GetCountryBrands":
            body = #"{"Brands":[{"BrandId":10,"Name":"BP"},{"BrandId":20,"Name":"OTR"}]}"#
        case "/Price/GetSitesPrices":
            body = """
            {"SitePrices":[
              {"SiteId":3,"FuelId":2,"CollectionMethod":"T","TransactionDateUtc":"2026-10-01T02:03:04.000","Price":1799},
              {"SiteId":2,"FuelId":14,"CollectionMethod":"T","TransactionDateUtc":"2026-10-01T02:03:04.000","Price":1899},
              {"SiteId":1,"FuelId":2,"CollectionMethod":"T","TransactionDateUtc":"2026-10-01T02:03:04.000","Price":1599},
              {"SiteId":4,"FuelId":2,"CollectionMethod":"T","TransactionDateUtc":"2026-10-01T02:03:04.000","Price":1500},
              {"SiteId":6,"FuelId":2,"CollectionMethod":"T","TransactionDateUtc":"2026-10-01T02:03:04.000","Price":1500}
            ]}
            """
        default:
            Issue.record("Unexpected fuel endpoint: \(url.path)")
            throw URLError(.unsupportedURL)
        }
        return try response(request, body: body)
    }
}
