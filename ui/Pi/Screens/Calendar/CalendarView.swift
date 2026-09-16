import SwiftUI

struct CalendarView: View {
    @Environment(Session.self) private var session

    @State private var data: CalendarResponse?
    @State private var error: String?
    @State private var view = "month"
    @State private var anchorDate = PiDate.todayString

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                LoadableView(value: data, error: error, retry: { Task { await load() } }) { cal in
                    VStack(spacing: 16) {
                        header(cal)
                        weekdayRow
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(cal.cells) { cell in
                                NavigationLink(value: cell.date) {
                                    CalendarCellView(cell: cell)
                                }
                                .buttonStyle(.plain)
                                .disabled(!cell.inPeriod)
                            }
                        }
                        legend
                        statsCard(cal.stats)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.piBg)
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Today") {
                        anchorDate = PiDate.todayString
                    }
                    .disabled(anchorDate == PiDate.todayString)
                }
            }
            .navigationDestination(for: String.self) { date in
                DayDetailView(date: date)
            }
            .task(id: "\(view)-\(anchorDate)") { await load() }
            .refreshable { await load() }
        }
    }

    private func header(_ cal: CalendarResponse) -> some View {
        VStack(spacing: 12) {
            Picker("View", selection: $view) {
                Text("Month").tag("month")
                Text("Week").tag("week")
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    anchorDate = cal.prevDate
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 36)
                }
                Spacer()
                Text(cal.label)
                    .font(.piTitle)
                    .foregroundStyle(Color.piText)
                Spacer()
                Button {
                    anchorDate = cal.nextDate
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 36)
                }
            }
            .foregroundStyle(Color.piPrimary)
        }
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(.piEyebrow)
                    .foregroundStyle(Color.piTextMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot("Gym", .piGymCyan)
            legendDot("Workout", .piWorkoutGold)
            legendDot("Cals", .piCalGood)
            legendDot("Steps", .piStepsOrange)
            legendDot("Sleep", .piSleepPurple)
            legendDot("Weight", .piWeightTeal)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.piCaption)
                .foregroundStyle(Color.piTextMuted)
        }
    }

    private func statsCard(_ stats: CalendarResponse.CalendarStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(view == "week" ? "This week" : "This month")
            HStack {
                statItem("\(stats.gymDays)", "gym days", .piGymCyan)
                statItem("\(stats.workoutDays)", "workouts", .piWorkoutGold)
                statItem("\(Int(stats.avgCalories))", "avg cal", .piCalGood)
            }
            HStack {
                statItem("\(Int(stats.avgSteps).formatted())", "avg steps", .piStepsOrange)
                statItem(String(format: "%.1fh", stats.avgSleepH), "avg sleep", .piSleepPurple)
                statItem("\(stats.totalSets)", "sets", .piWeightTeal)
            }
        }
        .piCard()
    }

    private func statItem(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.piMetricSmall)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.piCaption)
                .foregroundStyle(Color.piTextMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        do {
            data = try await session.client.calendar(view: view, date: anchorDate)
            error = nil
        } catch {
            if data == nil { self.error = error.localizedDescription }
        }
    }
}

struct CalendarCellView: View {
    let cell: CalendarResponse.CalendarCell

    var body: some View {
        VStack(spacing: 3) {
            Text("\(cell.day)")
                .font(.system(size: 14, weight: cell.isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(cell.isToday ? Color.piOnPrimary : (cell.inPeriod ? Color.piText : Color.piTextMuted.opacity(0.4)))
                .frame(width: 26, height: 26)
                .background(cell.isToday ? Color.piPrimary : .clear)
                .clipShape(Circle())
            HStack(spacing: 2) {
                if cell.hasGym { dot(.piGymCyan) }
                if cell.hasWorkout { dot(.piWorkoutGold) }
                if cell.hasCalories { dot(.piCalGood) }
                if cell.hasSteps { dot(.piStepsOrange) }
            }
            .frame(height: 5)
            HStack(spacing: 2) {
                if cell.hasSleep { dot(.piSleepPurple) }
                if cell.hasWeight { dot(.piWeightTeal) }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(cell.inPeriod ? Color.piBg2 : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(cell.isToday ? Color.piPrimary.opacity(0.6) : Color.piBorder.opacity(cell.inPeriod ? 1 : 0), lineWidth: 1)
        )
        .opacity(cell.inPeriod ? 1 : 0.45)
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 4.5, height: 4.5)
    }
}
