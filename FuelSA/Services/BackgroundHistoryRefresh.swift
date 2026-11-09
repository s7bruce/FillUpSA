import BackgroundTasks
import Foundation

enum BackgroundHistoryRefresh {
    nonisolated static let identifier = "au.sambruce.FillUpSA.price-history-refresh"

    nonisolated static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background App Refresh may be disabled; foreground synchronization still works.
        }
    }
}
