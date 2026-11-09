import Foundation

struct FuelHistoryService {
    static let shared = FuelHistoryService()

    private let loadData: (URLRequest) async throws -> (Data, URLResponse)

    init(loadData: @escaping (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }) {
        self.loadData = loadData
    }

    private let projectURL = URL(string: "https://febmlfvosczhcbcccjxm.supabase.co")!
    private let publishableKey = "sb_publishable_twrstyGVk7ZufVs6xBljzg_r0CJ2_dv"

    func fetchHistory(
        days: Int = 30, fuel: String = "91", endingAt date: Date = .now
    ) async throws -> [FuelPriceHistoryPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: date) ?? date
        let cutoffString = ISO8601DateFormatter().string(from: cutoff)
        var components = URLComponents(
            url: projectURL.appendingPathComponent("rest/v1/fuel_price_history"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "captured_at,fuel_type,low,high,average"),
            URLQueryItem(name: "captured_at", value: "gte.\(cutoffString)"),
            URLQueryItem(name: "captured_at", value: "lte.\(ISO8601DateFormatter().string(from: date))"),
            URLQueryItem(name: "fuel_type", value: "eq.\(fuel)"),
            URLQueryItem(name: "order", value: "captured_at.asc,fuel_type.asc")
        ]
        // Fetch every page; the REST API otherwise truncates the oldest-first result.
        let pageSize = 500
        var offset = 0
        var points: [FuelPriceHistoryPoint] = []
        while true {
            try Task.checkCancellation()
            var page = components
            page?.queryItems?.append(contentsOf: [
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ])
            guard let url = page?.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await loadData(request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let rows = try JSONDecoder().decode([ServerHistoryRow].self, from: data)
            points.append(contentsOf: rows.compactMap(\.historyPoint))
            guard rows.count == pageSize else { break }
            offset += rows.count
        }
        return points
    }
}

private struct ServerHistoryRow: Decodable {
    let capturedAt: String
    let fuelType: String
    let low: Double
    let high: Double
    let average: Double

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case fuelType = "fuel_type"
        case low
        case high
        case average
    }

    var historyPoint: FuelPriceHistoryPoint? {
        guard let date = Self.fractionalDateFormatter.date(from: capturedAt)
                ?? Self.dateFormatter.date(from: capturedAt) else {
            return nil
        }
        return FuelPriceHistoryPoint(
            date: date,
            fuelType: fuelType,
            low: low,
            high: high,
            average: average,
            source: .server
        )
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatter = ISO8601DateFormatter()
}
