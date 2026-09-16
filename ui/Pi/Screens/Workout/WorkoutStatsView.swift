import SwiftUI
import Charts

/// Lifting analytics: PRs & estimated 1RM, set-volume by body part,
/// frequency / consistency, and per-exercise progression.
struct WorkoutStatsView: View {
    @Environment(Session.self) private var session

    @State private var data: WorkoutStats?
    @State private var error: String?
    @State private var rangeDays = 90
    @State private var selectedProgression: Int64?

    var body: some View {
        ScrollView {
            LoadableView(value: data, error: error, retry: { Task { await load() } }) { stats in
                VStack(spacing: 16) {
                    Picker("Range", selection: $rangeDays) {
                        Text("30d").tag(30)
                        Text("90d").tag(90)
                        Text("180d").tag(180)
                        Text("1y").tag(365)
                    }
                    .pickerStyle(.segmented)

                    frequencyCard(stats.frequency)
                    weeklySetsCard(stats.weeklySets)
                    progressionCard(stats.progressions)
                    prCard(stats.prs)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.piBg)
        .navigationTitle("Workout Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: rangeDays) { await load() }
        .refreshable { await load() }
    }

    // MARK: - Frequency

    private func frequencyCard(_ f: WorkoutStats.Frequency) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Frequency & consistency", color: .piGymCyan)
            let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 14) {
                stat("\(f.totalSessions)", "sessions", .piGymCyan)
                stat(String(format: "%.1f", f.sessionsPerWeek), "per week", .piGymCyan)
                stat(weekStreakLabel(f.weekStreak), "streak", .piCalGood)
                stat(daysSinceLabel(f.daysSinceLast), "since last", .piStepsOrange)
                stat("\(f.totalSets)", "total sets", .piWorkoutGold)
                stat(String(format: "%.1f", f.avgSetsPerSession), "sets / session", .piWeightTeal)
            }
        }
        .piCard()
    }

    private func weekStreakLabel(_ n: Int) -> String { "\(n) wk" + (n == 1 ? "" : "s") }
    private func daysSinceLabel(_ n: Int) -> String {
        n < 0 ? "—" : (n == 0 ? "today" : "\(n)d")
    }

    // MARK: - Weekly sets by body part

    private struct WeekBar: Identifiable {
        let id = UUID()
        let week: String
        let part: String
        let count: Int
    }

    @ViewBuilder
    private func weeklySetsCard(_ weeks: [WorkoutStats.WeeklySets]) -> some View {
        if weeks.isEmpty {
            EmptyView()
        } else {
            let bars: [WeekBar] = weeks.flatMap { w in
                w.byBodyPart.sorted { $0.key < $1.key }.map {
                    WeekBar(week: w.label, part: $0.key, count: $0.value)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("Weekly sets · by body part", color: .piWorkoutGold)
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Week", bar.week),
                        y: .value("Sets", bar.count)
                    )
                    .foregroundStyle(by: .value("Body part", bar.part))
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 240)
            }
            .piCard()
        }
    }

    // MARK: - Progression

    @ViewBuilder
    private func progressionCard(_ progs: [WorkoutStats.Progression]) -> some View {
        if progs.isEmpty {
            EmptyView()
        } else {
            let selectedId = selectedProgression ?? progs.first!.exerciseId
            let prog = progs.first { $0.exerciseId == selectedId } ?? progs.first!
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow("Progression", color: .piWeightTeal)
                    Spacer()
                    Picker("Exercise", selection: Binding(
                        get: { selectedId },
                        set: { selectedProgression = $0 }
                    )) {
                        ForEach(progs) { p in
                            Text(p.exercise).tag(p.exerciseId)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.piWeightTeal)
                }
                Text(prog.isBodyweight ? "Best reps per session" : "Estimated 1RM (lb)")
                    .font(.piCaption)
                    .foregroundStyle(Color.piTextMuted)

                let points = progPoints(prog)
                if points.count < 2 {
                    Text("Not enough sessions in this range to chart a trend.")
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piTextMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                } else {
                    Chart(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                            .foregroundStyle(Color.piWeightTeal)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                            .foregroundStyle(Color.piWeightTeal)
                            .symbolSize(24)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                }
            }
            .piCard()
        }
    }

    private struct ProgChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private func progPoints(_ prog: WorkoutStats.Progression) -> [ProgChartPoint] {
        prog.points.compactMap { p in
            guard let d = PiDate.parseDay(p.date) else { return nil }
            let v = prog.isBodyweight ? Double(p.bestReps) : p.estOneRm
            guard let value = v else { return nil }
            return ProgChartPoint(date: d, value: value)
        }
    }

    // MARK: - PRs

    private func prCard(_ prs: [WorkoutStats.PR]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Personal records · all-time", color: .piWorkoutGold)
            if prs.isEmpty {
                Text("No sets logged yet.")
                    .font(.piSubheadline)
                    .foregroundStyle(Color.piTextMuted)
            } else {
                ForEach(prs) { pr in
                    prRow(pr)
                    if pr.id != prs.last?.id {
                        Divider().overlay(Color.piBorder)
                    }
                }
            }
        }
        .piCard()
    }

    private func prRow(_ pr: WorkoutStats.PR) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.exercise)
                    .font(.piHeadline)
                    .foregroundStyle(Color.piText)
                Text("\(pr.bodyPart) · \(pr.sets) sets · best \(pr.bestReps) reps")
                    .font(.piCaption)
                    .foregroundStyle(Color.piTextMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let orm = pr.estOneRm {
                    Text("\(fmtWeight(orm)) lb")
                        .font(.piMetricSmall)
                        .foregroundStyle(Color.piWorkoutGold)
                    Text("est 1RM")
                        .font(.piCaption)
                        .foregroundStyle(Color.piTextMuted)
                } else {
                    Text("bodyweight")
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piTextMuted)
                }
                if let bw = pr.bestWeightLbs {
                    Text("\(fmtWeight(bw)) × \(pr.bestWeightReps)")
                        .font(.piCaption)
                        .foregroundStyle(Color.piTextMuted)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.piMetricSmall)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.piCaption)
                .foregroundStyle(Color.piTextMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        do {
            data = try await session.client.workoutStats(rangeDays: rangeDays)
            error = nil
        } catch {
            if data == nil { self.error = error.localizedDescription }
        }
    }
}
