//
//  StationMapView.swift
//
//
//  Created by Samuel Bruce on 9/10/2025.
//

import SwiftUI
import MapKit
import Combine

struct StationMapView: View {
    @EnvironmentObject var app: AppState
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    let locationSearchRequestID: UUID?
    let onSettings: () -> Void

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -34.9285, longitude: 138.6007),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    @Namespace private var mapScope
    @State private var position = MapCameraPosition.region(initialRegion)
    @State private var visibleRegion = initialRegion
    @State private var hasCenteredOnUser = false
    @State private var viewportRefreshTask: Task<Void, Never>?
    @State private var idleRefreshTask: Task<Void, Never>?
    @State private var lastRequestedCenter: CLLocationCoordinate2D?
    @State private var locationSearchTask: Task<Void, Never>?
    @State private var phoneLookupTask: Task<Void, Never>?
    @State private var selectedStationID: Station.ID?
    @State private var selectedPhoneNumber: String?
    @State private var isPhoneLookupComplete = false

    var body: some View {
        Map(position: $position, scope: mapScope) {
            UserAnnotation()

            ForEach(displayedStations) { station in
                Annotation(
                    station.name,
                    coordinate: CLLocationCoordinate2D(
                        latitude: station.lat,
                        longitude: station.lon
                    ),
                    anchor: .bottom
                ) {
                    VStack(spacing: 8) {
                        if selectedStationID == station.id {
                            StationCalloutView(
                                station: station,
                                preferredFuel: app.preferredFuel,
                                currentLocation: app.location.current,
                                navigationApp: app.navigationApp,
                                lastUpdated: app.lastStationFetchDate,
                                phoneNumber: selectedPhoneNumber,
                                isPhoneLookupComplete: isPhoneLookupComplete,
                                onClose: {
                                    withAnimation(.snappy) {
                                        selectedStationID = nil
                                    }
                                    phoneLookupTask?.cancel()
                                }
                            )
                            .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                        }

                        Button {
                            select(station)
                        } label: {
                            StationAnnotationView(
                                brand: station.brand,
                                stationName: station.name,
                                priceCents: station.priceForSelection(app.preferredFuel),
                                showsPremiumLabel: station.usesPremiumDiesel(for: app.preferredFuel)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapControls {
            MapScaleView()
            MapCompass()
            MapPitchToggle()
        }
        .overlay(alignment: .bottom) {
            HStack {
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .modifier(MapLocationControlGlassModifier())
                .accessibilityLabel("Settings")

                Spacer()

                MapUserLocationButton(scope: mapScope)
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .modifier(MapLocationControlGlassModifier())
            }
            .safeAreaPadding(.horizontal, 16)
            .safeAreaPadding(.bottom, 16)
        }
        .mapScope(mapScope)
        .onMapCameraChange(frequency: .continuous) { context in
            visibleRegion = context.region
            idleRefreshTask?.cancel()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            refreshStations(around: context.region.center)
            scheduleIdleRefresh()
        }
        .onAppear {
            scheduleIdleRefresh()
        }
        .onChange(of: locationSearchRequestID) {
            locationSearchTask?.cancel()
            locationSearchTask = Task {
                await searchForLocation()
            }
        }
        .onReceive(app.location.$current.compactMap { $0 }) { coordinate in
            guard !hasCenteredOnUser else {
                return
            }

            hasCenteredOnUser = true
            position = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: Self.initialRegion.span
                )
            )
        }
        .onDisappear {
            viewportRefreshTask?.cancel()
            idleRefreshTask?.cancel()
            locationSearchTask?.cancel()
            phoneLookupTask?.cancel()
        }
    }

    private func select(_ station: Station) {
        if selectedStationID == station.id {
            withAnimation(.snappy) {
                selectedStationID = nil
            }
            phoneLookupTask?.cancel()
            return
        }

        withAnimation(.snappy) {
            selectedStationID = station.id
            position = .region(regionCenteringCallout(on: station))
        }
        selectedPhoneNumber = nil
        isPhoneLookupComplete = false
        phoneLookupTask?.cancel()
        phoneLookupTask = Task {
            let phoneNumber = await lookupPhoneNumber(for: station)
            guard !Task.isCancelled, selectedStationID == station.id else {
                return
            }
            selectedPhoneNumber = phoneNumber
            isPhoneLookupComplete = true
        }
    }

    private func regionCenteringCallout(on station: Station) -> MKCoordinateRegion {
        // Place the station slightly below centre so the marker and its callout
        // are centred together while preserving the user's current zoom level.
        let calloutOffset = visibleRegion.span.latitudeDelta * 0.16
        let latitude = min(90, station.lat + calloutOffset)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: station.lon),
            span: visibleRegion.span
        )
    }

    private func lookupPhoneNumber(for station: Station) async -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = station.name
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            let stationLocation = CLLocation(latitude: station.lat, longitude: station.lon)
            return response.mapItems
                .filter {
                    stationLocation.distance(from: $0.location) <= 1_000
                }
                .min {
                    stationLocation.distance(from: $0.location)
                        < stationLocation.distance(from: $1.location)
                }?
                .phoneNumber
        } catch {
            return nil
        }
    }

    private func searchForLocation() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(query), South Australia"
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -30.0002, longitude: 136.2092),
            span: MKCoordinateSpan(latitudeDelta: 13, longitudeDelta: 14)
        )
        request.resultTypes = .address

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled, let mapItem = response.mapItems.first else {
                return
            }

            let coordinate = mapItem.location.coordinate
            position = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                )
            )
            searchText = ""
            isSearchPresented = false
        } catch is CancellationError {
            return
        } catch {
            print("Location search failed:", error.localizedDescription)
        }
    }

    private func refreshStations(around coordinate: CLLocationCoordinate2D) {
        if let lastRequestedCenter {
            let previous = CLLocation(
                latitude: lastRequestedCenter.latitude,
                longitude: lastRequestedCenter.longitude
            )
            let next = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            guard previous.distance(from: next) >= 100 else {
                return
            }
        }

        lastRequestedCenter = coordinate
        viewportRefreshTask?.cancel()
        viewportRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }

            await app.refresh(around: coordinate)
        }
    }

    private func scheduleIdleRefresh() {
        idleRefreshTask?.cancel()
        idleRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else {
                    return
                }
                await app.refresh()
            }
        }
    }

    private var displayedStations: [Station] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return app.stations
        }

        return app.stations.filter { station in
            station.name.localizedCaseInsensitiveContains(query)
                || station.brand.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct StationCalloutView: View {
    let station: Station
    let preferredFuel: String
    let currentLocation: CLLocationCoordinate2D?
    let navigationApp: NavigationApp
    let lastUpdated: Date?
    let phoneNumber: String?
    let isPhoneLookupComplete: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(station.name)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 4)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close station details")
            }

            detailRow(systemImage: "mappin.and.ellipse", text: addressText)
            detailRow(
                systemImage: "phone",
                text: phoneNumber ?? (isPhoneLookupComplete ? "Phone unavailable" : "Looking up phone…")
            )
            detailRow(systemImage: "location", text: distanceText)

            HStack(alignment: .firstTextBaseline) {
                Text(openingStatus.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(openingStatus.color)

                Spacer(minLength: 8)

                Text(priceText)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }

            Text(updatedText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                navigate()
            } label: {
                Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(width: 285)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private func detailRow(systemImage: String, text: String) -> some View {
        Label {
            Text(text)
                .lineLimit(2)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var addressText: String {
        [station.address, station.postcode]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var distanceText: String {
        guard let currentLocation else {
            return "Distance unavailable"
        }

        let metres = CLLocation(
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude
        ).distance(
            from: CLLocation(latitude: station.lat, longitude: station.lon)
        )

        if metres < 1_000 {
            return "\(Int(metres.rounded())) m away"
        }
        return String(format: "%.1f km away", metres / 1_000)
    }

    private var priceText: String {
        guard let price = station.priceForSelection(preferredFuel) else {
            return "\(preferredFuel) —"
        }
        return String(format: "%@ %.1f¢", preferredFuel, price)
    }

    private var updatedText: String {
        guard let lastUpdated else {
            return "Last updated unavailable"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last updated \(formatter.localizedString(for: lastUpdated, relativeTo: .now))"
    }

    private var openingStatus: (text: String, color: Color) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Adelaide") ?? .current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)

        guard let hours = station.weeklyHours[weekday] else {
            return ("Hours unavailable", .secondary)
        }

        if hours.opens == "00:00" && (hours.closes == "23:59" || hours.closes == "00:00") {
            return ("Open 24/7", .green)
        }

        guard let openingMinutes = minutes(from: hours.opens),
              let closingMinutes = minutes(from: hours.closes) else {
            return ("Hours unavailable", .secondary)
        }

        let components = calendar.dateComponents([.hour, .minute], from: now)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let isOpen: Bool
        if closingMinutes >= openingMinutes {
            isOpen = currentMinutes >= openingMinutes && currentMinutes < closingMinutes
        } else {
            isOpen = currentMinutes >= openingMinutes || currentMinutes < closingMinutes
        }

        if isOpen {
            return ("Open · Closes \(displayTime(hours.closes))", .green)
        }
        return ("Closed", .red)
    }

    private func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return hour * 60 + minute
    }

    private func displayTime(_ value: String) -> String {
        guard let totalMinutes = minutes(from: value) else {
            return value
        }
        let hour = totalMinutes / 60
        let minute = totalMinutes % 60
        let period = hour < 12 ? "am" : "pm"
        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0
            ? "\(twelveHour) \(period)"
            : String(format: "%d:%02d %@", twelveHour, minute, period)
    }

    private func navigate() {
        let coordinate = "\(station.lat),\(station.lon)"

        switch navigationApp {
        case .appleMaps:
            openAppleMaps()
        case .googleMaps:
            openNavigationApp(
                appURL: URL(string: "comgooglemaps://?daddr=\(coordinate)&directionsmode=driving"),
                fallbackURL: URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate)&travelmode=driving")
            )
        case .waze:
            openNavigationApp(
                appURL: URL(string: "waze://?ll=\(coordinate)&navigate=yes"),
                fallbackURL: URL(string: "https://waze.com/ul?ll=\(coordinate)&navigate=yes")
            )
        }
    }

    private func openAppleMaps() {
        let mapItem = MKMapItem(
            location: CLLocation(latitude: station.lat, longitude: station.lon),
            address: nil
        )
        mapItem.name = station.name
        mapItem.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ]
        )
    }

    private func openNavigationApp(appURL: URL?, fallbackURL: URL?) {
        guard let appURL else { return }

        UIApplication.shared.open(appURL) { opened in
            guard !opened, let fallbackURL else { return }
            UIApplication.shared.open(fallbackURL)
        }
    }
}

private struct MapLocationControlGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.regularMaterial, in: Circle())
                .shadow(radius: 5, y: 2)
        }
    }
}

private struct StationAnnotationView: View {
    let brand: String
    let stationName: String
    let priceCents: Double?
    let showsPremiumLabel: Bool

    var body: some View {
        VStack(spacing: 1) {
            if showsPremiumLabel {
                Text("PREMIUM")
                    .font(.system(size: 7, weight: .heavy))
                    .lineLimit(1)
            }

            Text(priceText)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)

            ZStack {
                if let logoAssetName {
                    Image(logoAssetName)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                } else {
                    fallbackLogo
                }
            }
            .frame(width: 36, height: 24)
        }
        .frame(width: 48, height: showsPremiumLabel ? 58 : 48)
        .background(
            .white.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .modifier(StationMarkerGlassModifier())
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stationName) fuel station")
        .accessibilityValue(priceAccessibilityValue)
    }

    private var priceText: String {
        guard let priceCents, priceCents.isFinite else {
            return "—"
        }

        return String(format: "%.1f¢", priceCents)
    }

    private var priceAccessibilityValue: String {
        guard let priceCents, priceCents.isFinite else {
            return "Price unavailable"
        }

        let fuelDescription = showsPremiumLabel ? "Premium Diesel at " : ""
        return fuelDescription + String(format: "%.1f cents per litre", priceCents)
    }

    private struct StationMarkerGlassModifier: ViewModifier {
        @ViewBuilder
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.clear, in: .rect(cornerRadius: 10))
            } else {
                content
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.55), lineWidth: 1)
                    }
            }
        }
    }

    private var normalizedIdentity: String {
        "\(brand) \(stationName)".lowercased()
    }

    private var logoAssetName: String? {
        if normalizedIdentity.contains("on the run")
            || normalizedIdentity.contains("otr")
            || normalizedIdentity.contains("peregrine") {
            return "otr"
        } else if normalizedIdentity.contains("ampol")
                    || normalizedIdentity.contains("eg fuel") {
            return "ampol"
        } else if normalizedIdentity.contains("bp ")
                    || normalizedIdentity.hasPrefix("bp")
                    || normalizedIdentity.contains("british petroleum")
                    || normalizedIdentity.contains("ampm")
                    || normalizedIdentity.contains("am/pm")
                    || normalizedIdentity.contains("am pm") {
            return "bp"
        } else if normalizedIdentity.contains("shell")
                    || normalizedIdentity.contains("coles express")
                    || normalizedIdentity.contains("reddy express") {
            return "shell"
        } else if normalizedIdentity.contains("caltex")
                    || normalizedIdentity.contains("woolworths fuel") {
            return "caltex"
        } else if normalizedIdentity.contains("united petroleum")
                    || normalizedIdentity.contains("united fuel")
                    || normalizedIdentity.contains("united ") {
            return "united"
        } else if normalizedIdentity.contains("mobil") {
            return "mobil"
        } else if normalizedIdentity.contains("x convenience")
                    || normalizedIdentity.contains("x-convenience")
                    || normalizedIdentity.contains("xconvenience") {
            return "xconvenience"
        } else if normalizedIdentity.contains("leroy's")
                    || normalizedIdentity.contains("leroys")
                    || normalizedIdentity.contains("leroy’s") {
            return "leroys"
        } else if normalizedIdentity.contains("solo") {
            return "solo"
        } else if normalizedIdentity.contains("u-go")
                    || normalizedIdentity.contains("u go")
                    || normalizedIdentity.contains("ugo") {
            return "ugo"
        } else if normalizedIdentity.contains("lmct") {
            return "lmct"
        }

        return nil
    }

    private var fallbackLogo: some View {
        Text(initials)
            .font(.caption2.weight(.black))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(4)
    }

    private var initials: String {
        let fallbackName = ["independent", "unknown", "brand"].contains(brand.lowercased())
            ? stationName
            : brand
        let characters = fallbackName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return characters.isEmpty ? "?" : String(characters).uppercased()
    }
}
