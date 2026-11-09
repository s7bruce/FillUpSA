import Foundation
import CoreLocation
import Combine   // <- keep this

enum NavigationApp: String, CaseIterable, Identifiable {
    case appleMaps
    case googleMaps
    case waze

    var id: Self { self }

    var displayName: String {
        switch self {
        case .appleMaps: "Apple Maps"
        case .googleMaps: "Google Maps"
        case .waze: "Waze"
        }
    }
}

struct FuelPriceHistoryPoint: Codable, Identifiable {
    enum Source: String, Codable {
        case device
        case server
    }

    let id: UUID
    let date: Date
    let fuelType: String
    let low: Double
    let high: Double
    let average: Double
    let source: Source?

    init(
        date: Date,
        fuelType: String,
        low: Double,
        high: Double,
        average: Double,
        source: Source = .device
    ) {
        id = UUID()
        self.date = date
        self.fuelType = fuelType
        self.low = low
        self.high = high
        self.average = average
        self.source = source
    }
}

@MainActor
final class AppState: ObservableObject {
    private static let preferredFuelKey = "preferredFuel"
    private static let excludedBrandsKey = "excludedStationBrands"
    private static let maximumVisibleStationsKey = "maximumVisibleStations"
    private static let navigationAppKey = "navigationApp"
    private static let priceHistoryKey = "fuelPriceHistory"
    private static let lastStationFetchDateKey = "lastStationFetchDate"
    private static let supportedFuelTypes = ["E10", "91", "95", "98", "Diesel", "LPG"]
    private static let defaultMaximumVisibleStations = 60
    static let maximumAllowedVisibleStations = 100

    @Published var stations: [Station] = []
    @Published var preferredFuel: String {
        didSet {
            guard Self.supportedFuelTypes.contains(preferredFuel) else {
                return
            }
            defaults.set(preferredFuel, forKey: Self.preferredFuelKey)
        }
    }
    @Published var excludedBrands: Set<String> {
        didSet {
            defaults.set(
                excludedBrands.sorted(),
                forKey: Self.excludedBrandsKey
            )
        }
    }
    @Published var maximumVisibleStations: Int {
        didSet {
            defaults.set(
                maximumVisibleStations,
                forKey: Self.maximumVisibleStationsKey
            )
        }
    }
    @Published var navigationApp: NavigationApp {
        didSet {
            defaults.set(navigationApp.rawValue, forKey: Self.navigationAppKey)
        }
    }
    @Published var isLoading: Bool = false
    @Published private(set) var priceHistory: [FuelPriceHistoryPoint]
    @Published private(set) var lastStationFetchDate: Date?

    let location = LocationManager.shared

    private let defaults: UserDefaults
    private let fuelAPI: FuelAPI
    private let historyService: FuelHistoryService
    private let currentCoordinate: @MainActor () -> CLLocationCoordinate2D?
    private let now: () -> Date
    private let monitorStations: @MainActor ([Station], String) -> Void
    private struct HistoryDownload: Codable {
        let from: Date
        let through: Date
    }
    private static let historyDownloadsKey = "fuelHistoryDownloads"
    private var historyDownloads: [String: HistoryDownload] = [:]
    private var activeHistoryDownloads: Set<String> = []

    init(
        defaults: UserDefaults = .standard,
        fuelAPI: FuelAPI? = nil,
        historyService: FuelHistoryService? = nil,
        currentCoordinate: @escaping @MainActor () -> CLLocationCoordinate2D? = { LocationManager.shared.current },
        now: @escaping () -> Date = { .now },
        monitorStations: @escaping @MainActor ([Station], String) -> Void = {
            GeofenceManager.shared.updateMonitoredStations($0, preferredFuel: $1)
        }
    ) {
        self.defaults = defaults
        self.fuelAPI = fuelAPI ?? .shared
        self.historyService = historyService ?? .shared
        self.currentCoordinate = currentCoordinate
        self.now = now
        self.monitorStations = monitorStations
        if let data = defaults.data(forKey: Self.historyDownloadsKey),
           let downloads = try? JSONDecoder().decode([String: HistoryDownload].self, from: data) {
            historyDownloads = downloads
        }
        lastStationFetchDate = defaults.object(
            forKey: Self.lastStationFetchDateKey
        ) as? Date

        if let historyData = defaults.data(forKey: Self.priceHistoryKey),
           let savedHistory = try? JSONDecoder().decode([FuelPriceHistoryPoint].self, from: historyData) {
            priceHistory = savedHistory
        } else {
            priceHistory = []
        }

        let savedFuel = defaults.string(forKey: Self.preferredFuelKey)
        preferredFuel = savedFuel.flatMap { Self.supportedFuelTypes.contains($0) ? $0 : nil } ?? "91"
        let savedExcludedBrands = Set(
            defaults.stringArray(forKey: Self.excludedBrandsKey) ?? []
        )
        excludedBrands = savedExcludedBrands.intersection(Station.brandFilterOptions)
        navigationApp = defaults.string(forKey: Self.navigationAppKey)
            .flatMap(NavigationApp.init(rawValue:)) ?? .appleMaps

        if defaults.object(forKey: Self.maximumVisibleStationsKey) == nil {
            maximumVisibleStations = Self.defaultMaximumVisibleStations
        } else {
            maximumVisibleStations = min(
                max(defaults.integer(forKey: Self.maximumVisibleStationsKey), 1),
                Self.maximumAllowedVisibleStations
            )
        }
    }

    private var visibleCenter: CLLocationCoordinate2D?
    private var activeRefreshID = UUID()

    func bootstrap() async {
        location.request()
        // Wait briefly for initial location (up to ~2 seconds), then proceed
        let start = Date()
        while location.current == nil && Date().timeIntervalSince(start) < 2.0 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        let coordinate = location.current ?? CLLocationCoordinate2D(
            latitude: -34.9285,
            longitude: 138.6007
        )
        await refresh(around: coordinate)
        // History is loaded when Trends is opened.
    }

    func refresh() async {
        let coordinate = visibleCenter ?? location.current ?? CLLocationCoordinate2D(
            latitude: -34.9285,
            longitude: 138.6007
        )
        await refresh(around: coordinate)
    }

    func refresh(around coordinate: CLLocationCoordinate2D) async {
        visibleCenter = coordinate

        let refreshID = UUID()
        activeRefreshID = refreshID
        isLoading = true

        defer {
            if activeRefreshID == refreshID {
                isLoading = false
            }
        }

        do {
            let data = try await fuelAPI.fetchStations(
                around: coordinate,
                maximumStations: maximumVisibleStations,
                fuelTypes: [preferredFuel],
                excludingBrands: excludedBrands
            )
            guard activeRefreshID == refreshID, !Task.isCancelled else {
                return
            }

            stations = data
            lastStationFetchDate = now()
            defaults.set(lastStationFetchDate, forKey: Self.lastStationFetchDateKey)

            if let currentLocation = currentCoordinate() {
                let userLocation = CLLocation(
                    latitude: currentLocation.latitude,
                    longitude: currentLocation.longitude
                )
                let fetchedLocation = CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )

                if userLocation.distance(from: fetchedLocation) <= 5_000 {
                    recordPriceHistory(from: stations, around: userLocation)
                    monitorStations(stations, preferredFuel)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            print("Fetch error:", error)
        }
    }

    func historyPoints(days: Int) -> [FuelPriceHistoryPoint] {
        FuelHistorySelection.points(priceHistory, fuel: preferredFuel, days: days, now: now())
    }

    func ensureHistory(days: Int) async {
        guard !FuelHistorySelection.hasSufficientLocalHistory(
            priceHistory, fuel: preferredFuel, days: days, now: now()
        ) else { return }
        let date = now()
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: date) ?? date
        if let download = historyDownloads[preferredFuel],
           download.from <= cutoff,
           (0..<30 * 60).contains(date.timeIntervalSince(download.through)) {
            return
        }
        await syncServerHistory(days: days)
    }

    func syncServerHistory(days: Int = 30) async {
        let fuel = preferredFuel
        let requestKey = "\(fuel)-\(days)"
        guard activeHistoryDownloads.insert(requestKey).inserted else { return }
        defer { activeHistoryDownloads.remove(requestKey) }
        let date = now()
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: date) ?? date
        do {
            let serverHistory = try await historyService.fetchHistory(days: days, fuel: fuel, endingAt: date)
            guard !serverHistory.isEmpty, !Task.isCancelled else { return }

            // Preserve other fuels and older cached ranges when downloading a subset.
            priceHistory.removeAll {
                $0.source == .server && $0.fuelType == fuel
                    && $0.date >= cutoff && $0.date <= date
            }
            priceHistory.append(contentsOf: serverHistory)
            priceHistory.sort { $0.date < $1.date }
            savePriceHistory()
            // A narrower refresh must not certify an older, wider range as fresh.
            historyDownloads[fuel] = HistoryDownload(from: cutoff, through: date)
            if let data = try? JSONEncoder().encode(historyDownloads) {
                defaults.set(data, forKey: Self.historyDownloadsKey)
            }
        } catch {
            // Keep the last downloaded server history and local observations available offline.
        }
    }

    private func recordPriceHistory(from stations: [Station], around location: CLLocation) {
        let nearbyStations = stations.filter { station in
            location.distance(
                from: CLLocation(latitude: station.lat, longitude: station.lon)
            ) <= 25_000
        }
        let now = now()

        for fuelType in Self.supportedFuelTypes {
            let prices = nearbyStations.compactMap { $0.priceForSelection(fuelType) }
            guard let low = prices.min(), let high = prices.max(), !prices.isEmpty else {
                continue
            }
            let mostRecent = priceHistory.filter {
                $0.fuelType == fuelType && $0.source != .server
            }.max { $0.date < $1.date }
            guard mostRecent.map({ now.timeIntervalSince($0.date) >= 60 * 60 }) ?? true else {
                continue
            }

            priceHistory.append(
                FuelPriceHistoryPoint(
                    date: now,
                    fuelType: fuelType,
                    low: low,
                    high: high,
                    average: prices.reduce(0, +) / Double(prices.count)
                )
            )
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        priceHistory.removeAll { $0.date < cutoff }
        savePriceHistory()
    }

    private func savePriceHistory() {
        if let data = try? JSONEncoder().encode(priceHistory) {
            defaults.set(data, forKey: Self.priceHistoryKey)
        }
    }
}
