//
//  ContentView.swift
//  
//
//  Created by Samuel Bruce on 9/10/2025.
//

import Charts
import CoreLocation
import MapKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var isFuelSelectionExpanded = false
    @State private var isSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var isCheapestPresented = false
    @State private var isTrendsPresented = false
    @State private var searchText = ""
    @State private var locationSearchRequestID: UUID?
    @State private var stationLimitRefreshTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            StationMapView(
                searchText: $searchText,
                isSearchPresented: $isSearchPresented,
                locationSearchRequestID: locationSearchRequestID,
                onSettings: {
                    isSettingsPresented = true
                }
            )
            .ignoresSafeArea()

            if isFuelSelectionExpanded || isSearchPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy) {
                            isFuelSelectionExpanded = false
                            isSearchPresented = false
                            searchText = ""
                        }
                    }
            }

            VStack(spacing: 10) {
                FloatingHeader(
                    isLoading: app.isLoading,
                    isSearchPresented: isSearchPresented,
                    onSearch: {
                        withAnimation(.snappy) {
                            isFuelSelectionExpanded = false
                            isSearchPresented.toggle()
                            if !isSearchPresented {
                                searchText = ""
                            }
                        }
                    },
                    onRefresh: {
                        Task { await app.refresh() }
                    }
                )

                if isSearchPresented {
                    StationSearchControl(
                        searchText: $searchText,
                        isPresented: $isSearchPresented,
                        onSubmit: {
                            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                return
                            }
                            locationSearchRequestID = UUID()
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    FuelSelectionControl(
                        selection: $app.preferredFuel,
                        isExpanded: $isFuelSelectionExpanded
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if !isSearchPresented && !isFuelSelectionExpanded {
                MapInsightControls(
                    onCheapest: { isCheapestPresented = true },
                    onTrends: { isTrendsPresented = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.horizontal)
                .padding(.top, 62)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
                preferredFuel: $app.preferredFuel,
                excludedBrands: $app.excludedBrands,
                maximumVisibleStations: $app.maximumVisibleStations,
                navigationApp: $app.navigationApp
            )
        }
        .sheet(isPresented: $isCheapestPresented) {
            CheapestStationsView()
                .environmentObject(app)
        }
        .sheet(isPresented: $isTrendsPresented) {
            FuelPriceTrendsView()
                .environmentObject(app)
        }
        .onChange(of: app.preferredFuel) {
            Task {
                await app.refresh()
            }
        }
        .onChange(of: app.excludedBrands) {
            Task {
                await app.refresh()
            }
        }
        .onChange(of: app.maximumVisibleStations) {
            stationLimitRefreshTask?.cancel()
            stationLimitRefreshTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else {
                    return
                }
                await app.refresh()
            }
        }
    }
}

private struct SettingsView: View {
    private let fuelTypes = ["E10", "91", "95", "98", "Diesel", "LPG"]

    @Binding var preferredFuel: String
    @Binding var excludedBrands: Set<String>
    @Binding var maximumVisibleStations: Int
    @Binding var navigationApp: NavigationApp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Fuel") {
                    Picker("Preferred Fuel", selection: $preferredFuel) {
                        ForEach(fuelTypes, id: \.self) { fuelType in
                            Text(fuelType)
                                .tag(fuelType)
                        }
                    }
                }

                Section("Stations") {
                    NavigationLink {
                        BrandFilterView(
                            brands: availableBrands,
                            excludedBrands: $excludedBrands
                        )
                    } label: {
                        LabeledContent(
                            "Station Brands",
                            value: brandFilterSummary
                        )
                    }
                }

                Section("Navigation") {
                    Picker("Open directions in", selection: $navigationApp) {
                        ForEach(NavigationApp.allCases) { app in
                            Text(app.displayName)
                                .tag(app)
                        }
                    }
                }

                Section("Notifications") {
                    Text("Fuel alerts use your preferred fuel and can be managed in iPhone Settings.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Text("Stations shown")

                        Spacer()

                        TextField(
                            "60",
                            value: stationLimitBinding,
                            format: .number
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .accessibilityLabel("Stations shown")
                    }
                } header: {
                    Text("Map")
                } footer: {
                    Text("Choose up to 100 of the closest stations to the map centre.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var stationLimitBinding: Binding<Int> {
        Binding(
            get: {
                maximumVisibleStations
            },
            set: { newValue in
                maximumVisibleStations = min(
                    max(newValue, 1),
                    AppState.maximumAllowedVisibleStations
                )
            }
        )
    }

    private var availableBrands: [String] {
        Station.brandFilterOptions.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var brandFilterSummary: String {
        excludedBrands.isEmpty ? "All" : "\(excludedBrands.count) hidden"
    }
}

private struct BrandFilterView: View {
    let brands: [String]
    @Binding var excludedBrands: Set<String>

    var body: some View {
        List {
            if brands.isEmpty {
                ContentUnavailableView(
                    "No Brands Available",
                    systemImage: "fuelpump",
                    description: Text("Refresh nearby stations to load brand options.")
                )
            } else {
                Section {
                    ForEach(brands, id: \.self) { brand in
                        Toggle(
                            brand,
                            isOn: Binding(
                                get: {
                                    !excludedBrands.contains(brand)
                                },
                                set: { isIncluded in
                                    if isIncluded {
                                        excludedBrands.remove(brand)
                                    } else {
                                        excludedBrands.insert(brand)
                                    }
                                }
                            )
                        )
                    }
                } footer: {
                    Text("Only enabled brands will appear on the map.")
                }
            }
        }
        .navigationTitle("Station Brands")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Show All") {
                    excludedBrands.removeAll()
                }
                .disabled(excludedBrands.isEmpty)
            }
        }
    }
}

private struct CheapestStationsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var model = CheapestStationsModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView("Finding the cheapest nearby fuel…")
                } else if let errorMessage = model.errorMessage {
                    ContentUnavailableView(
                        "Prices Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if model.stations.isEmpty {
                    ContentUnavailableView(
                        "No Stations Found",
                        systemImage: "fuelpump",
                        description: Text("No stations selling \(app.preferredFuel) were found within 25 km.")
                    )
                } else {
                    List(model.stations) { station in
                        cheapestStationRow(station)
                    }
                }
            }
            .navigationTitle("Cheapest \(app.preferredFuel)")
            .navigationSubtitle("Within 25 km of your location")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: app.preferredFuel) {
            await loadStations()
        }
    }

    private func cheapestStationRow(_ station: Station) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.headline)
                Text(stationDistance(station))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(priceText(station))
                .font(.title3.weight(.bold))
                .monospacedDigit()

            Button {
                openDirections(to: station, using: app.navigationApp)
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Navigate to \(station.name)")
        }
        .padding(.vertical, 4)
    }

    private func loadStations() async {
        await model.load(
            around: app.location.current,
            fuel: app.preferredFuel,
            excludingBrands: app.excludedBrands
        )
    }

    private func distance(from origin: CLLocation, to station: Station) -> CLLocationDistance {
        origin.distance(from: CLLocation(latitude: station.lat, longitude: station.lon))
    }

    private func stationDistance(_ station: Station) -> String {
        guard let coordinate = app.location.current else { return "Distance unavailable" }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let kilometres = distance(from: origin, to: station) / 1_000
        return String(format: "%.1f km away", kilometres)
    }

    private func priceText(_ station: Station) -> String {
        guard let price = station.priceForSelection(app.preferredFuel) else { return "—" }
        return String(format: "%.1f¢", price)
    }
}

private enum TrendRange: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    var id: Int { rawValue }
    var title: String { "\(rawValue)D" }
}

private struct FuelPriceTrendsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var range: TrendRange = .thirtyDays

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Time Range", selection: $range) {
                        ForEach(TrendRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    if points.isEmpty {
                        ContentUnavailableView(
                            "Building Price History",
                            systemImage: "chart.xyaxis.line",
                            description: Text("FuelSA will record nearby \(app.preferredFuel) prices as you use the app. Check back after future price updates.")
                        )
                        .frame(minHeight: 280)
                    } else {
                        Text(usesServerHistory ? "South Australian market average" : "Average near your device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Chart(points) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Average price", point.average)
                            )
                            .foregroundStyle(.tint)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Average price", point.average)
                            )
                            .foregroundStyle(.tint)
                        }
                        .chartYAxisLabel("Cents per litre")
                        .frame(height: 260)

                        HStack(spacing: 10) {
                            statisticCard(title: "Low", value: minimumPrice, color: .green)
                            statisticCard(title: "Average", value: averagePrice, color: .blue)
                            statisticCard(title: "High", value: maximumPrice, color: .red)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("\(app.preferredFuel) Price Trends")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: "\(app.preferredFuel)-\(range.rawValue)") {
            await app.ensureHistory(days: range.rawValue)
        }
    }

    private var points: [FuelPriceHistoryPoint] {
        app.historyPoints(days: range.rawValue)
    }

    private var usesServerHistory: Bool { points.contains { $0.source == .server } }

    private var minimumPrice: Double { points.map(\.low).min() ?? 0 }
    private var maximumPrice: Double { points.map(\.high).max() ?? 0 }
    private var averagePrice: Double {
        guard !points.isEmpty else { return 0 }
        return points.map(\.average).reduce(0, +) / Double(points.count)
    }

    private func statisticCard(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f¢", value))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private func openDirections(to station: Station, using navigationApp: NavigationApp) {
    let coordinate = "\(station.lat),\(station.lon)"

    switch navigationApp {
    case .appleMaps:
        let mapItem = MKMapItem(
            location: CLLocation(latitude: station.lat, longitude: station.lon),
            address: nil
        )
        mapItem.name = station.name
        mapItem.openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
    case .googleMaps:
        openNavigationURL(
            URL(string: "comgooglemaps://?daddr=\(coordinate)&directionsmode=driving"),
            fallback: URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate)&travelmode=driving")
        )
    case .waze:
        openNavigationURL(
            URL(string: "waze://?ll=\(coordinate)&navigate=yes"),
            fallback: URL(string: "https://waze.com/ul?ll=\(coordinate)&navigate=yes")
        )
    }
}

private func openNavigationURL(_ appURL: URL?, fallback: URL?) {
    guard let appURL else { return }
    UIApplication.shared.open(appURL) { opened in
        guard !opened, let fallback else { return }
        UIApplication.shared.open(fallback)
    }
}

private struct FloatingHeader: View {
    let isLoading: Bool
    let isSearchPresented: Bool
    let onSearch: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Fill Up SA")
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Button(action: onSearch) {
                Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(FloatingControlGlassModifier())
            .accessibilityLabel(isSearchPresented ? "Close station search" : "Search stations")

            if isLoading {
                ProgressView()
                    .frame(width: 44, height: 44)
                    .modifier(FloatingControlGlassModifier())
            } else {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .modifier(FloatingControlGlassModifier())
                .accessibilityLabel("Refresh fuel prices")
            }
        }
    }
}

private struct MapInsightControls: View {
    let onCheapest: () -> Void
    let onTrends: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            floatingButton(
                systemImage: "tag.fill",
                accessibilityLabel: "Cheapest nearby fuel",
                action: onCheapest
            )
            floatingButton(
                systemImage: "chart.xyaxis.line",
                accessibilityLabel: "Fuel price trends",
                action: onTrends
            )
        }
    }

    private func floatingButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(FloatingControlGlassModifier())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct FloatingControlGlassModifier: ViewModifier {
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

private struct StationSearchControl: View {
    @Binding var searchText: String
    @Binding var isPresented: Bool
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Station, suburb or postcode", text: $searchText)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            Button {
                withAnimation(.snappy) {
                    searchText = ""
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close station search")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .modifier(StationSearchGlassModifier())
        .onAppear {
            isFocused = true
        }
    }
}

private struct StationSearchGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 3)
        }
    }
}

private struct FuelSelectionControl: View {
    private let fuelTypes = ["E10", "91", "95", "98", "Diesel", "LPG"]

    @Binding var selection: String
    @Binding var isExpanded: Bool
    @Namespace private var selectionHighlight
    @Namespace private var fuelLabelTransition

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "fuelpump.fill")
                    .font(.headline)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide fuel selection" : "Show fuel selection")

            if isExpanded {
                Divider()
                    .frame(height: 24)

                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(fuelTypes, id: \.self) { fuelType in
                            Button {
                                withAnimation(.smooth(duration: 0.22)) {
                                    selection = fuelType
                                    isExpanded = false
                                }
                            } label: {
                                Text(fuelType)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .foregroundStyle(Color.primary)
                                    .matchedGeometryEffect(
                                        id: fuelType,
                                        in: fuelLabelTransition
                                    )
                                    .background {
                                        if selection == fuelType {
                                            Capsule()
                                                .fill(Color.primary.opacity(0.14))
                                                .matchedGeometryEffect(
                                                    id: "fuelSelection",
                                                    in: selectionHighlight
                                                )
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection == fuelType ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        isExpanded = true
                    }
                } label: {
                    Text(selection)
                        .font(.headline)
                        .matchedGeometryEffect(
                            id: selection,
                            in: fuelLabelTransition
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show fuel selection")
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: isExpanded ? .infinity : nil, alignment: .leading)
        .modifier(FuelSelectionGlassModifier())
    }
}

private struct FuelSelectionGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 3)
        }
    }
}
