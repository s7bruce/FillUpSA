import Foundation

enum FuelHistorySelection {
    static func matching(
        _ history: [FuelPriceHistoryPoint], fuel: String, days: Int, now: Date
    ) -> [FuelPriceHistoryPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return history.filter {
            $0.fuelType == fuel && $0.date >= cutoff && $0.date <= now
        }.sorted { $0.date < $1.date }
    }

    // Daily coverage prevents a burst of observations on one day from being
    // mistaken for a usable week/month trend. Legacy source-less rows are local.
    static func hasSufficientLocalHistory(
        _ history: [FuelPriceHistoryPoint], fuel: String, days: Int, now: Date
    ) -> Bool {
        let local = matching(history, fuel: fuel, days: days, now: now)
            .filter { $0.source != .server }
        guard let latest = local.last, now.timeIntervalSince(latest.date) <= 24 * 60 * 60 else {
            return false
        }
        let observedDays = Set(local.map { Calendar.current.startOfDay(for: $0.date) })
        return observedDays.count >= max(2, Int(ceil(Double(days) * 0.75)))
    }

    static func points(
        _ history: [FuelPriceHistoryPoint], fuel: String, days: Int, now: Date
    ) -> [FuelPriceHistoryPoint] {
        let matching = matching(history, fuel: fuel, days: days, now: now)
        let local = matching.filter { $0.source != .server }
        if hasSufficientLocalHistory(history, fuel: fuel, days: days, now: now) {
            return local
        }
        let server = matching.filter { $0.source == .server }
        // Keep local observations visible when the server is unavailable.
        return server.isEmpty ? local : server
    }
}
