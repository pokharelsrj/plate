import Foundation
import BackgroundTasks

/// Schedules background HealthKit syncs:
///  - an **hourly** app-refresh that pushes the last couple of days, and
///  - a **full** sync (~a year) around 11:59 AM and 11:59 PM.
///
/// iOS does NOT guarantee exact timing: `earliestBeginDate` is a "no earlier than"
/// hint and the system throttles background runs based on usage/power. Each run
/// reschedules the next, so the hourly task fires roughly hourly and the full task
/// roughly twice a day. HealthKit background delivery (see
/// `HealthService.startBackgroundDelivery`) complements these by waking the app
/// whenever new samples are written, so nothing is missed between runs.
final class HealthBackgroundTasks {
    static let shared = HealthBackgroundTasks()
    static let fullSyncID = "com.srijanpokharel.pi.health.fullsync"
    static let hourlySyncID = "com.srijanpokharel.pi.health.hourly"

    private var registered = false

    /// Must be called before the app finishes launching (from the AppDelegate),
    /// per BGTaskScheduler's contract.
    func register() {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.fullSyncID, using: nil) { [weak self] task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleFullSync(task)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.hourlySyncID, using: nil) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleHourly(task)
        }
        schedule()
    }

    /// Queues the next full sync (11:59 AM/PM boundary) and the next hourly sync.
    func schedule() {
        scheduleFullSync()
        scheduleHourly()
    }

    private func scheduleFullSync() {
        let request = BGProcessingTaskRequest(identifier: Self.fullSyncID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Self.nextBoundary()
        try? BGTaskScheduler.shared.submit(request)
    }

    private func scheduleHourly() {
        let request = BGAppRefreshTaskRequest(identifier: Self.hourlySyncID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleFullSync(_ task: BGProcessingTask) {
        scheduleFullSync()  // reschedule the next run before working
        let work = Task {
            if let client = Session.backgroundClient() {
                try? await HealthService.shared.sync(daysBack: HealthService.fullSyncDays, client: client)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    private func handleHourly(_ task: BGAppRefreshTask) {
        scheduleHourly()  // reschedule the next hour before working
        let work = Task {
            if let client = Session.backgroundClient() {
                try? await HealthService.shared.sync(daysBack: HealthService.backgroundSyncDays, client: client)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// The next 11:59 AM or 11:59 PM in the future (local time).
    static func nextBoundary(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        var candidates: [Date] = []
        for (hour, minute) in [(11, 59), (23, 59)] {
            for dayOffset in 0...1 {
                if let base = cal.date(byAdding: .day, value: dayOffset, to: now),
                   let d = cal.date(bySettingHour: hour, minute: minute, second: 0, of: base),
                   d > now {
                    candidates.append(d)
                }
            }
        }
        return candidates.min() ?? now.addingTimeInterval(12 * 3600)
    }
}
