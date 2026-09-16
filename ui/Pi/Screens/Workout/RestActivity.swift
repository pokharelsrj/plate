import ActivityKit
import Foundation

/// Manages the rest-timer Live Activity (lock screen + Dynamic Island).
@MainActor
enum RestActivity {
    private static var current: Activity<RestTimerAttributes>?

    /// Start a new activity, or retarget the existing one (reset / new set).
    static func start(startedAt: Date, exerciseName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(
            state: RestTimerAttributes.ContentState(startedAt: startedAt, exerciseName: exerciseName),
            staleDate: startedAt.addingTimeInterval(30 * 60)
        )
        if let existing = current ?? Activity<RestTimerAttributes>.activities.first {
            current = existing
            Task { await existing.update(content) }
        } else {
            current = try? Activity.request(attributes: RestTimerAttributes(), content: content)
        }
    }

    static func end() {
        current = nil
        Task {
            for activity in Activity<RestTimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
