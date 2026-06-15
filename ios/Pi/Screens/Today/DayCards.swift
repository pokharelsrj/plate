import SwiftUI

/// Card stack for a day snapshot — shared by Today and DayDetail.
struct DaySnapshotCards: View {
    let snapshot: TodaySnapshot
    /// When set, section taps navigate to the matching tab (Today screen only).
    var router: Router?

    @AppStorage("dailyStepGoal") private var stepGoal = 10000
    @AppStorage("sleepGoalHours") private var sleepGoal = 7.5

    var body: some View {
        VStack(spacing: 14) {
            if let sys = snapshot.system {
                systemCard(sys)
            }
            if let health = snapshot.health {
                healthCard(health)
            }
            if let nutrition = snapshot.nutrition {
                nutritionCard(nutrition)
            }
            if let body = snapshot.body {
                bodyCard(body)
            }
            if let workout = snapshot.workout {
                workoutCard(workout)
            }
            if let gym = snapshot.gym, !gym.checkins.isEmpty {
                gymCard(gym)
            }
            if isEmptyDay {
                ContentUnavailableView("No data for this day",
                                       systemImage: "moon.zzz",
                                       description: Text("Nothing was logged or synced."))
                    .padding(.top, 40)
            }
        }
    }

    private var isEmptyDay: Bool {
        snapshot.health == nil && snapshot.nutrition == nil && snapshot.body == nil
            && snapshot.workout == nil && (snapshot.gym?.checkins.isEmpty ?? true)
    }

    // MARK: - System

    private func systemCard(_ sys: TodaySnapshot.SystemMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Pi System")
            HStack(spacing: 8) {
                SystemDial(label: "CPU", value: sys.cpuPercent,
                           display: percentLabel(sys.cpuPercent), color: .piPrimary)
                SystemDial(label: "Mem", value: sys.memoryPercent,
                           display: percentLabel(sys.memoryPercent), color: .piGymCyan)
                SystemDial(label: "Disk", value: sys.diskPercent,
                           display: percentLabel(sys.diskPercent), color: .piStepsOrange)
                SystemDial(label: "Temp", value: sys.tempCelsius,
                           display: sys.tempCelsius > 0 ? "\(Int(sys.tempCelsius))°" : "—",
                           color: .piWarn)
            }
        }
        .piCard()
    }

    // MARK: - Health

    private func healthCard(_ h: HealthDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Health", tab: nil)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("Steps", color: .piStepsOrange)
                    Text((h.steps ?? 0).formatted())
                        .font(.piMetricLarge)
                        .foregroundStyle(Color.piText)
                        .minimumScaleFactor(0.85)
                    if let steps = h.steps {
                        Text("\(Int(Double(steps) / Double(max(stepGoal, 1)) * 100))% of goal")
                            .font(.piCaption)
                            .foregroundStyle(Color.piTextMuted)
                    }
                }
                Spacer()
                if let hr = h.restingHr {
                    VStack(alignment: .trailing, spacing: 2) {
                        Eyebrow("Resting HR", color: .piBFPink)
                        Text("\(Int(hr))")
                            .font(.piMetricLarge)
                            .foregroundStyle(Color.piText)
                        Text("bpm")
                            .font(.piCaption)
                            .foregroundStyle(Color.piTextMuted)
                    }
                }
            }
            if let asleep = h.sleepAsleepH, asleep > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Eyebrow("Sleep", color: .piSleepPurple)
                        Spacer()
                        Text(hoursLabel(asleep))
                            .font(.piMetricSmall)
                            .foregroundStyle(Color.piText)
                    }
                    SleepStageBar(deep: h.sleepDeepH ?? 0,
                                  core: h.sleepCoreH ?? 0,
                                  rem: h.sleepRemH ?? 0,
                                  awake: h.sleepAwakeH ?? 0)
                    HStack(spacing: 12) {
                        stageLegend("Deep", h.sleepDeepH, .piSleepDeep)
                        stageLegend("Core", h.sleepCoreH, .piSleepCore)
                        stageLegend("REM", h.sleepRemH, .piSleepRem)
                        stageLegend("Awake", h.sleepAwakeH, .piSleepAwake)
                    }
                }
            }
        }
        .piCard()
    }

    @ViewBuilder
    private func stageLegend(_ label: String, _ hours: Double?, _ color: Color) -> some View {
        if let hours, hours > 0 {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text("\(label) \(hoursLabel(hours))")
                    .font(.piCaption)
                    .foregroundStyle(Color.piTextMuted)
            }
        }
    }

    // MARK: - Nutrition

    private func nutritionCard(_ n: TodaySnapshot.Nutrition) -> some View {
        let calories = n.calories ?? 0
        let budget = n.calorieBudget ?? 0
        let ratio = budget > 0 ? calories / budget : 0
        let ringColor: Color = ratio > 1.0 ? .piCalOver : (ratio > 0.85 ? .piCalGood : .piCalLow)

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Nutrition", tab: nil)
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: ratio, color: ringColor, lineWidth: 8, size: 84)
                    VStack(spacing: 0) {
                        Text("\(Int(calories))")
                            .font(.piMetricSmall)
                            .foregroundStyle(Color.piText)
                        if budget > 0 {
                            Text("of \(Int(budget))")
                                .font(.piCaption)
                                .foregroundStyle(Color.piTextMuted)
                        }
                    }
                }
                VStack(spacing: 10) {
                    MacroBar(label: "Protein", grams: n.proteinG ?? 0, maxGrams: 200, color: .piCalGood)
                    MacroBar(label: "Carbs", grams: n.carbG ?? 0, maxGrams: 300, color: .piStepsOrange)
                    MacroBar(label: "Fat", grams: n.fatG ?? 0, maxGrams: 100, color: .piWorkoutGold)
                    MacroBar(label: "Fibre", grams: n.fibreG ?? 0, maxGrams: 50, color: .piGymCyan)
                }
            }
        }
        .piCard()
    }

    // MARK: - Body

    private func bodyCard(_ b: BodyMetric) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Body", tab: .body)
            HStack(spacing: 24) {
                if let w = b.weightLbs {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow("Weight", color: .piWeightTeal)
                        Text(String(format: "%.1f lb", w))
                            .font(.piMetricMed)
                            .foregroundStyle(Color.piText)
                    }
                }
                if let bf = b.bfPercent {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow("Body Fat", color: .piBFPink)
                        Text(String(format: "%.1f%%", bf))
                            .font(.piMetricMed)
                            .foregroundStyle(Color.piText)
                    }
                }
                Spacer()
            }
        }
        .piCard()
    }

    // MARK: - Workout

    private func workoutCard(_ w: TodaySnapshot.WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Workout", tab: .workout)
            HStack {
                Text("\(w.exerciseCount) exercises · \(w.totalSets) sets")
                    .font(.piSubheadline)
                    .foregroundStyle(Color.piTextMuted)
                Spacer()
                Text("\(Int(w.totalVolumeLbs).formatted()) lb")
                    .font(.piMetricSmall)
                    .foregroundStyle(Color.piWorkoutGold)
            }
            ForEach(w.groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(group.exerciseName)
                            .font(.piHeadline)
                            .foregroundStyle(Color.piText)
                        if let bp = group.bodyPart {
                            Pill(bp, color: .piWorkoutGold)
                        }
                        Spacer()
                    }
                    Text(group.sets.map { setLabel($0) }.joined(separator: "  ·  "))
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piTextMuted)
                }
                .padding(.vertical, 2)
            }
        }
        .piCard()
    }

    // MARK: - Gym

    private func gymCard(_ gym: TodaySnapshot.GymInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Gym Check-ins", color: .piGymCyan)
            ForEach(gym.checkins, id: \.self) { checkin in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.piGymCyan)
                    Text(checkinLabel(checkin))
                        .font(.piBody)
                        .foregroundStyle(Color.piText)
                }
            }
        }
        .piCard()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, tab: AppTab?) -> some View {
        if let router, let tab {
            Button {
                router.tab = tab
            } label: {
                HStack {
                    Text(title).font(.piTitle).foregroundStyle(Color.piText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piTextMuted)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())   // make the whole header row tappable, not just the glyphs
            }
            .buttonStyle(.piPressable)
        } else {
            Text(title).font(.piTitle).foregroundStyle(Color.piText)
        }
    }

    private func setLabel(_ s: WorkoutSet) -> String {
        if let w = s.weightLbs {
            return "\(s.reps)×\(w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w))"
        }
        return "\(s.reps) reps"
    }

    /// An idle Pi sits below 1% CPU — show a decimal there so it doesn't read as 0%.
    private func percentLabel(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f%%", v) : "\(Int(v))%"
    }

    private func hoursLabel(_ h: Double) -> String {
        let totalMinutes = Int((h * 60).rounded())
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    private func checkinLabel(_ iso: String) -> String {
        guard let date = PiDate.parseISO(iso) else { return iso }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
