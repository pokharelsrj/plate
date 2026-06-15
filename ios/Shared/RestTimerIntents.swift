import ActivityKit
import AppIntents
import Foundation

/// UserDefaults keys shared by the app's view model and the lock-screen intents.
enum RestTimerStore {
    static let startKey = "workout.restStartedAt"
    static let stoppedKey = "workout.restStoppedAt"
    static let manualMarkKey = "workout.manualRestMark"
}

/// Lock-screen "reset / set done" — the set just physically ended, restart the
/// rest clock from now. Runs in the app's process via LiveActivityIntent.
struct ResetRestTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Reset rest timer"
    static var description = IntentDescription("Restarts the rest stopwatch from zero.")

    func perform() async throws -> some IntentResult {
        let now = Date()
        let defaults = UserDefaults.standard
        defaults.set(now, forKey: RestTimerStore.startKey)
        // Same semantics as the in-app "Set done": the next ADD SET must not reset.
        defaults.set(true, forKey: RestTimerStore.manualMarkKey)
        defaults.removeObject(forKey: RestTimerStore.stoppedKey)

        for activity in Activity<RestTimerAttributes>.activities {
            let state = RestTimerAttributes.ContentState(
                startedAt: now,
                exerciseName: activity.content.state.exerciseName
            )
            await activity.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(30 * 60)))
        }
        return .result()
    }
}

/// Lock-screen "complete exercise" — hide the timer and end the Live Activity.
/// The previous start time is kept so the app can offer "resume".
struct CompleteExerciseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete exercise"
    static var description = IntentDescription("Stops the rest stopwatch.")

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults.standard
        if let started = defaults.object(forKey: RestTimerStore.startKey) as? Date {
            defaults.set(started, forKey: RestTimerStore.stoppedKey)
        }
        defaults.removeObject(forKey: RestTimerStore.startKey)
        defaults.removeObject(forKey: RestTimerStore.manualMarkKey)

        for activity in Activity<RestTimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
