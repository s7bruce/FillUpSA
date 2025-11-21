// CurrentLocation.swift
import CoreLocation

actor CurrentLocation {
    static let shared = CurrentLocation()
    private let manager = CLLocationManager()
    private(set) var coordinate: CLLocationCoordinate2D?

    init() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func set(_ c: CLLocationCoordinate2D) { coordinate = c }
}
