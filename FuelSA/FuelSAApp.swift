// FuelSAApp.swift
import SwiftUI
import UserNotifications

@main
struct FuelSAApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    Notifier.requestAuth()
                    await appState.bootstrap()
                    GeofenceManager.shared.updateMonitoredStations(appState.stations, preferredFuel: appState.preferredFuel)
                }
        }
    }
}
