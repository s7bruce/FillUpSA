//
//  FuelAPI.swift
//  
//
//  Created by Samuel Bruce on 9/10/2025.
//

import Foundation
import CoreLocation

final class FuelAPI {
    static let shared = FuelAPI()
    private init() {}

    // Later: add your baseURL and an injected token or signed header.
    func fetchStations(around coordinate: CLLocationCoordinate2D?,
                       radiusKm: Double,
                       fuelTypes: [String]) async throws -> [Station] {
        // TODO: Replace with real network call to your proxy or SA feed.
        // For now return mock so the app works end-to-end.
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        return Station.mock
    }
}
