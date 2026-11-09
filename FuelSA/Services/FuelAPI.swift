//
//  FuelAPI.swift
//  FillUpSA
//

import Foundation
import CoreLocation

final class FuelAPI {
    static let shared = FuelAPI()
    private let loadData: (URLRequest) async throws -> (Data, URLResponse)

    init(loadData: @escaping (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }) {
        self.loadData = loadData
    }

    private let baseURL = URL(string: "https://fppdirectapi-prod.safuelpricinginformation.com.au")!
    private let token = "99003d57-f553-4ea8-b883-fece5edb6afa"

    private func authHeader(for request: inout URLRequest) {
        request.setValue("FPDAPI SubscriberToken=\(token)", forHTTPHeaderField: "Authorization")
    }

    // -----------------------------
    // MAIN FUNCTION — USED BY APP
    // -----------------------------

    func fetchStations(
        around coord: CLLocationCoordinate2D,
        maximumStations: Int,
        fuelTypes: [String],
        excludingBrands: Set<String> = []
    ) async throws -> [Station] {

        let countryId = 21
        let geoRegionLevel = 3
        let geoRegionId = 4   // South Australia

        async let prices = getSitePrices(countryId: countryId,
                                         level: geoRegionLevel,
                                         id: geoRegionId)
        async let sites = getSiteDetails(countryId: countryId,
                                         level: geoRegionLevel,
                                         id: geoRegionId)
        async let brands = getBrands(countryId: countryId)

        let (priceRes, siteRes, brandRes) = try await (prices, sites, brands)

        let pricesBySite = Dictionary(grouping: priceRes.SitePrices, by: { $0.SiteId })
        let brandsByID = Dictionary(
            uniqueKeysWithValues: brandRes.Brands.map { ($0.BrandId, $0.Name) }
        )

        let stations: [Station] = siteRes.S.compactMap { apiSite in
            guard let fuelEntries = pricesBySite[apiSite.S],
                  let latitude = apiSite.Lat,
                  let longitude = apiSite.Lng else {
                return nil
            }

            let fuelModels: [FuelPrice] = fuelEntries.map { p in
                let cents = p.Price / 10.0       // convert tenths of cents → cents
                return FuelPrice(
                    type: fuelName(for: p.FuelId),
                    priceCents: cents,
                    updatedAt: parseAPIDate(p.TransactionDateUtc) ?? Date()
                )
            }

            return Station(
                id: String(apiSite.S),
                name: apiSite.N ?? "Unknown",
                brand: apiSite.B.flatMap { brandsByID[$0] } ?? "Independent",
                address: apiSite.A ?? "",
                postcode: apiSite.P ?? "",
                weeklyHours: weeklyHours(for: apiSite),
                lat: latitude,
                lon: longitude,
                fuels: fuelModels,
                lastUpdated: Date()
            )
        }

        let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

        return Array(
            stations
                .filter { station in
                    !excludingBrands.contains(station.brandFilterCategory)
                        && (fuelTypes.isEmpty || fuelTypes.contains { fuelType in
                            station.priceForSelection(fuelType) != nil
                        })
                }
                .sorted { first, second in
                    distance(from: origin, to: first) < distance(from: origin, to: second)
                }
                .prefix(max(maximumStations, 0))
        )
    }

    private func parseAPIDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return formatter.date(from: value)
    }

    private func weeklyHours(for site: ApiSite) -> [Int: StationHours] {
        let values: [(Int, String?, String?)] = [
            (1, site.SUO, site.SUC),
            (2, site.MO, site.MC),
            (3, site.TO, site.TC),
            (4, site.WO, site.WC),
            (5, site.THO, site.THC),
            (6, site.FO, site.FC),
            (7, site.SO, site.SC)
        ]

        return Dictionary(
            uniqueKeysWithValues: values.compactMap { weekday, opens, closes in
                guard let opens, let closes else {
                    return nil
                }
                return (weekday, StationHours(opens: opens, closes: closes))
            }
        )
    }

    private func distance(from origin: CLLocation, to station: Station) -> CLLocationDistance {
        origin.distance(
            from: CLLocation(latitude: station.lat, longitude: station.lon)
        )
    }

    private func getBrands(countryId: Int) async throws -> ApiBrandsResponse {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("/Subscriber/GetCountryBrands")
                .appending(queryItems: [
                    URLQueryItem(name: "countryId", value: String(countryId))
                ])
        )
        authHeader(for: &request)

        let (data, response) = try await loadData(request)
        try validate(response, data: data)

        return try JSONDecoder().decode(ApiBrandsResponse.self, from: data)
    }

    // -----------------------------
    // GET /Price/GetSitesPrices
    // -----------------------------

    private func getSitePrices(countryId: Int, level: Int, id: Int) async throws -> ApiSitePricesResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/Price/GetSitesPrices"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "countryId", value: "\(countryId)"),
            URLQueryItem(name: "geoRegionLevel", value: "\(level)"),
            URLQueryItem(name: "geoRegionId", value: "\(id)")
        ]

        var req = URLRequest(url: components.url!)
        authHeader(for: &req)

        let (data, response) = try await loadData(req)
        try validate(response, data: data)

        return try JSONDecoder().decode(ApiSitePricesResponse.self, from: data)
    }

    // -----------------------------
    // GET /Subscriber/GetFullSiteDetails
    // -----------------------------

    private func getSiteDetails(countryId: Int, level: Int, id: Int) async throws -> ApiSiteDetailsResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/Subscriber/GetFullSiteDetails"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "countryId", value: "\(countryId)"),
            URLQueryItem(name: "geoRegionLevel", value: "\(level)"),
            URLQueryItem(name: "geoRegionId", value: "\(id)")
        ]

        var req = URLRequest(url: components.url!)
        authHeader(for: &req)

        let (data, response) = try await loadData(req)
        try validate(response, data: data)

        return try JSONDecoder().decode(ApiSiteDetailsResponse.self, from: data)
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
