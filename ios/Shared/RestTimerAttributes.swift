import ActivityKit
import Foundation

/// Live Activity payload for the rest stopwatch — shared between the app
/// (which starts/updates/ends it) and the widget extension (which renders it).
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var exerciseName: String
    }
}
