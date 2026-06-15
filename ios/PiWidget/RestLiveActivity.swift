import ActivityKit
import WidgetKit
import SwiftUI

struct RestLiveActivity: Widget {
    /// Count-up interval — the system renders the live-ticking elapsed time;
    /// no process needs to stay awake.
    private func timerRange(_ state: RestTimerAttributes.ContentState) -> ClosedRange<Date> {
        state.startedAt...state.startedAt.addingTimeInterval(8 * 60 * 60)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock screen banner
            HStack(spacing: 14) {
                Image(systemName: "timer")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color("PiWorkoutGold"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST · \(context.state.exerciseName)")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(timerInterval: timerRange(context.state), countsDown: false)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                Button(intent: ResetRestTimerIntent()) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .tint(.secondary)
                Button(intent: CompleteExerciseIntent()) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .tint(Color("PiWorkoutGold"))
            }
            .padding(16)
            .activityBackgroundTint(Color("PiBg2").opacity(0.85))
            .activitySystemActionForegroundColor(Color("PiPrimary"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.exerciseName, systemImage: "dumbbell.fill")
                        .font(.caption)
                        .foregroundStyle(Color("PiWorkoutGold"))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: timerRange(context.state), countsDown: false)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Button(intent: ResetRestTimerIntent()) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        Button(intent: CompleteExerciseIntent()) {
                            Label("Done", systemImage: "checkmark")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("PiWorkoutGold"))
                    }
                    .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Color("PiWorkoutGold"))
            } compactTrailing: {
                Text(timerInterval: timerRange(context.state), countsDown: false)
                    .monospacedDigit()
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Color("PiWorkoutGold"))
            }
        }
    }
}
