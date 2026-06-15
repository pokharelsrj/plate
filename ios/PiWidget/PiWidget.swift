import WidgetKit
import SwiftUI

@main
struct PiWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        RestLiveActivity()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let cached: SharedCache.CachedToday?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, cached: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, cached: SharedCache.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: .now, cached: SharedCache.read())
        // The app refreshes the cache and reloads timelines; this is a fallback cadence.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PiTodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(Color("PiBg2"), for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's steps, sleep, calories and workout at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        if let cached = entry.cached, isFresh(cached) {
            switch family {
            case .systemMedium:
                medium(cached.snapshot)
            default:
                small(cached.snapshot)
            }
        } else {
            VStack(spacing: 6) {
                Text("π")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("PiPrimary"))
                Text("Open Pi to load today")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("PiTextMuted"))
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Treat cache from a previous calendar day as stale — yesterday's numbers
    /// shouldn't masquerade as today's.
    private func isFresh(_ cached: SharedCache.CachedToday) -> Bool {
        Calendar.current.isDateInToday(cached.fetchedAt)
    }

    // MARK: - Small

    private func small(_ snap: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            metricRow("figure.walk", value: steps(snap), color: Color("PiStepsOrange"))
            metricRow("moon.fill", value: sleep(snap), color: Color("PiSleepPurple"))
            metricRow("dumbbell.fill", value: volume(snap), color: Color("PiWorkoutGold"))
            metricRow("flame.fill", value: calories(snap), color: Color("PiCalGood"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Medium

    private func medium(_ snap: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    metricRow("figure.walk", value: steps(snap), color: Color("PiStepsOrange"))
                    metricRow("moon.fill", value: sleep(snap), color: Color("PiSleepPurple"))
                    metricRow("heart.fill", value: restingHR(snap), color: Color("PiBFPink"))
                }
                VStack(alignment: .leading, spacing: 7) {
                    metricRow("flame.fill", value: calories(snap), color: Color("PiCalGood"))
                    metricRow("dumbbell.fill", value: volume(snap), color: Color("PiWorkoutGold"))
                    metricRow("checkmark.circle.fill",
                              value: (snap.gym?.checkins.isEmpty == false) ? "Gym ✓" : "No gym yet",
                              color: Color("PiGymCyan"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("TODAY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color("PiTextMuted"))
            Spacer()
            Text(entry.cached?.fetchedAt ?? entry.date, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(Color("PiTextMuted"))
        }
    }

    private func metricRow(_ icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color("PiText"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Formatting

    private func steps(_ s: TodaySnapshot) -> String {
        guard let v = s.health?.steps else { return "— steps" }
        return "\(v.formatted()) steps"
    }

    private func sleep(_ s: TodaySnapshot) -> String {
        guard let h = s.health?.sleepAsleepH, h > 0 else { return "— sleep" }
        let m = Int((h * 60).rounded())
        return "\(m / 60)h \(m % 60)m sleep"
    }

    private func volume(_ s: TodaySnapshot) -> String {
        guard let w = s.workout, w.totalSets > 0 else { return "no sets yet" }
        return "\(Int(w.totalVolumeLbs).formatted()) lb · \(w.totalSets) sets"
    }

    private func calories(_ s: TodaySnapshot) -> String {
        guard let c = s.nutrition?.calories else { return "— kcal" }
        if let budget = s.nutrition?.calorieBudget, budget > 0 {
            return "\(Int(c)) / \(Int(budget)) kcal"
        }
        return "\(Int(c)) kcal"
    }

    private func restingHR(_ s: TodaySnapshot) -> String {
        guard let hr = s.health?.restingHr else { return "— bpm" }
        return "\(Int(hr)) bpm resting"
    }
}
