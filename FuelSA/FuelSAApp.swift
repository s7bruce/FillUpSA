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
                    Notifier.configure()
                    Notifier.requestAuth()
                    await appState.bootstrap()
                    BackgroundHistoryRefresh.schedule()
                }
        }
        .backgroundTask(.appRefresh(BackgroundHistoryRefresh.identifier)) {
            await appState.syncServerHistory()
            BackgroundHistoryRefresh.schedule()
        }
    }
}
