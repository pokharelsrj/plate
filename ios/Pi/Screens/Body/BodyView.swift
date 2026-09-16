import SwiftUI
import Charts

struct BodyView: View {
    @Environment(Session.self) private var session

    @State private var data: BodyResponse?
    @State private var error: String?
    @State private var tab = "weight"

    @State private var entryDate = Date()
    @State private var weightText = ""
    @State private var chest = SiteReadings()
    @State private var abdomen = SiteReadings()
    @State private var thigh = SiteReadings()
    @State private var isSaving = false
    @State private var toast: Toast?

    /// Three caliper readings for one skinfold site. The site value used for the
    /// BF% calculation is the average of whichever readings are filled in.
    struct SiteReadings {
        var r1 = ""
        var r2 = ""
        var r3 = ""
        var values: [Double] {
            [r1, r2, r3]
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                .filter { $0 > 0 }
        }
        var average: Double? {
            let v = values
            guard !v.isEmpty else { return nil }
            return v.reduce(0, +) / Double(v.count)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LoadableView(value: data, error: error, retry: { Task { await load() } }) { body in
                    VStack(spacing: 16) {
                        Picker("Metric", selection: $tab) {
                            Text("Weight").tag("weight")
                            Text("Body Fat").tag("bf")
                        }
                        .pickerStyle(.segmented)

                        if tab == "weight" {
                            weightChart(body)
                            weeklyAverages(body)
                            weightForm
                            weightHistory(body)
                        } else {
                            bfChart(body)
                            bfForm
                            bfHistory(body)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.piBg)
            .navigationTitle("Body")
            .task {
                await load()
                prefill(for: entryDate)
            }
            .refreshable { await load() }
            .onChange(of: entryDate) { _, newDate in prefill(for: newDate) }
            .toast($toast)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Charts

    @ViewBuilder
    private func weightChart(_ body: BodyResponse) -> some View {
        let points = body.history
            .compactMap { m -> (Date, Double)? in
                guard let w = m.weightLbs, let d = PiDate.parseDay(m.date) else { return nil }
                return (d, w)
            }
            .sorted { $0.0 < $1.0 }
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow("Weight · last \(points.count) entries", color: .piWeightTeal)
                    Spacer()
                    if let latest = body.latestWeightLbs {
                        Text(String(format: "%.1f lb", latest))
                            .font(.piMetricSmall)
                            .foregroundStyle(Color.piWeightTeal)
                    }
                }
                Chart(points, id: \.0) { point in
                    LineMark(x: .value("Date", point.0), y: .value("Weight", point.1))
                        .foregroundStyle(Color.piWeightTeal)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", point.0), y: .value("Weight", point.1))
                        .foregroundStyle(Color.piWeightTeal)
                        .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
            }
            .piCard()
        }
    }

    @ViewBuilder
    private func bfChart(_ body: BodyResponse) -> some View {
        let points = body.history
            .compactMap { m -> (Date, Double)? in
                guard let bf = m.bfPercent, let d = PiDate.parseDay(m.date) else { return nil }
                return (d, bf)
            }
            .sorted { $0.0 < $1.0 }
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow("Body fat %", color: .piBFPink)
                    Spacer()
                    if let latest = body.latestBfPercent {
                        Text(String(format: "%.1f%%", latest))
                            .font(.piMetricSmall)
                            .foregroundStyle(Color.piBFPink)
                    }
                }
                Chart(points, id: \.0) { point in
                    LineMark(x: .value("Date", point.0), y: .value("BF%", point.1))
                        .foregroundStyle(Color.piBFPink)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", point.0), y: .value("BF%", point.1))
                        .foregroundStyle(Color.piBFPink)
                        .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
            }
            .piCard()
        }
    }

    // MARK: - Weekly averages

    private struct WeekAvg: Identifiable {
        let id: Date        // week start
        let label: String
        let avg: Double
        let count: Int
        let delta: Double?  // change vs the previous (older) week
    }

    @ViewBuilder
    private func weeklyAverages(_ body: BodyResponse) -> some View {
        let weeks = weeklyWeightAverages(body)
        if !weeks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Weekly average", color: .piWeightTeal)
                ForEach(weeks) { wk in
                    HStack(spacing: 8) {
                        Text(wk.label)
                            .font(.piSubheadline)
                            .foregroundStyle(Color.piTextMuted)
                        Text("·  \(wk.count) \(wk.count == 1 ? "entry" : "entries")")
                            .font(.piCaption)
                            .foregroundStyle(Color.piTextMuted)
                        Spacer()
                        if let d = wk.delta, abs(d) >= 0.05 {
                            let down = d < 0
                            Text(String(format: "%@ %.1f", down ? "↓" : "↑", abs(d)))
                                .font(.piCaption)
                                .foregroundStyle(down ? Color.piWeightTeal : Color.piTextMuted)
                        }
                        Text(String(format: "%.1f lb", wk.avg))
                            .font(.piBody)
                            .foregroundStyle(Color.piText)
                            .frame(width: 84, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
            .piCard()
        }
    }

    /// Groups weigh-ins into calendar weeks (locale-aware) and averages whatever
    /// data exists in each week — most recent week first.
    private func weeklyWeightAverages(_ body: BodyResponse) -> [WeekAvg] {
        let cal = Calendar.current
        var buckets: [Date: [Double]] = [:]
        for m in body.history {
            guard let w = m.weightLbs, let d = PiDate.parseDay(m.date),
                  let week = cal.dateInterval(of: .weekOfYear, for: d)?.start else { continue }
            buckets[week, default: []].append(w)
        }
        guard !buckets.isEmpty else { return [] }

        let starts = buckets.keys.sorted(by: >)
        let todayStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start
        var out: [WeekAvg] = []
        for (i, start) in starts.enumerated() {
            let vals = buckets[start] ?? []
            let avg = vals.reduce(0, +) / Double(vals.count)
            var delta: Double?
            if i + 1 < starts.count, let prev = buckets[starts[i + 1]], !prev.isEmpty {
                delta = avg - prev.reduce(0, +) / Double(prev.count)
            }
            out.append(WeekAvg(id: start,
                               label: weekLabel(start, todayStart: todayStart, cal: cal),
                               avg: avg, count: vals.count, delta: delta))
        }
        return out
    }

    private func weekLabel(_ start: Date, todayStart: Date?, cal: Calendar) -> String {
        if let t = todayStart {
            if cal.isDate(start, inSameDayAs: t) { return "This week" }
            if let last = cal.date(byAdding: .weekOfYear, value: -1, to: t),
               cal.isDate(start, inSameDayAs: last) { return "Last week" }
        }
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let s = start.formatted(.dateTime.month(.abbreviated).day())
        let e = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(s) – \(e)"
    }

    // MARK: - Entry forms

    private var weightForm: some View {
        let existing = entry(for: entryDate)
        let isEditing = existing?.weightLbs != nil
        return VStack(spacing: 12) {
            HStack {
                Eyebrow(isEditing ? "Editing \(PiDate.shortLabel(PiDate.dayString(entryDate)))" : "New entry",
                        color: isEditing ? .piWeightTeal : .piTextMuted)
                Spacer()
            }
            DatePicker("Date", selection: $entryDate, in: ...Date(), displayedComponents: .date)
                .font(.piBody)
            HStack {
                TextField("Weight (lb)", text: $weightText)
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(Color.piBg3)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                saveButton(enabled: Double(weightText) != nil, title: isEditing ? "Update" : "Save") {
                    await save(weight: Double(weightText))
                }
            }
            if isEditing {
                Text("A weight is already logged for this day — saving updates it.")
                    .font(.piCaption)
                    .foregroundStyle(Color.piTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .piCard()
    }

    private var bfForm: some View {
        let existing = entry(for: entryDate)
        let isEditing = existing?.bfPercent != nil || existing?.chestMm != nil
        let cAvg = chest.average, aAvg = abdomen.average, tAvg = thigh.average
        return VStack(spacing: 12) {
            HStack {
                Eyebrow(isEditing ? "Editing \(PiDate.shortLabel(PiDate.dayString(entryDate)))" : "New entry",
                        color: isEditing ? .piBFPink : .piTextMuted)
                Spacer()
            }
            DatePicker("Date", selection: $entryDate, in: ...Date(), displayedComponents: .date)
                .font(.piBody)
            caliperSite("Chest", $chest)
            caliperSite("Abdomen", $abdomen)
            caliperSite("Thigh", $thigh)
            Text("Take 3 caliper readings (mm) per site — each site is averaged, then BF% is computed (Jackson-Pollock 3-site).")
                .font(.piCaption)
                .foregroundStyle(Color.piTextMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            saveButton(enabled: cAvg != nil && aAvg != nil && tAvg != nil, title: isEditing ? "Update" : "Save") {
                await save(chest: cAvg, abdomen: aAvg, thigh: tAvg)
            }
            if isEditing {
                Text("Body fat is already logged for this day — saving updates it.")
                    .font(.piCaption)
                    .foregroundStyle(Color.piTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .piCard()
    }

    private func caliperSite(_ label: String, _ site: Binding<SiteReadings>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Eyebrow(label)
                Spacer()
                if let a = site.wrappedValue.average {
                    Text(String(format: "avg %.1f mm", a))
                        .font(.piCaption)
                        .foregroundStyle(Color.piBFPink)
                }
            }
            HStack(spacing: 8) {
                readingField("#1", site.r1)
                readingField("#2", site.r2)
                readingField("#3", site.r3)
            }
        }
    }

    private func readingField(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .padding(10)
            .background(Color.piBg3)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func saveButton(enabled: Bool, title: String = "Save", action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                isSaving = true
                await action()
                isSaving = false
            }
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(Color.piOnPrimary)
                } else {
                    Text(title).font(.piHeadline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(enabled ? Color.piPrimary : Color.piBg3)
            .foregroundStyle(enabled ? Color.piOnPrimary : Color.piTextMuted)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.piPressable)
        .disabled(!enabled || isSaving)
    }

    // MARK: - History lists

    private func weightHistory(_ body: BodyResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("History")
            ForEach(body.history.filter { $0.weightLbs != nil }) { m in
                HStack {
                    Text(PiDate.shortLabel(m.date))
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piTextMuted)
                    Spacer()
                    Text(String(format: "%.1f lb", m.weightLbs ?? 0))
                        .font(.piBody)
                        .foregroundStyle(Color.piText)
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.piTextMuted)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { selectForEdit(m) }
            }
        }
        .piCard()
    }

    private func bfHistory(_ body: BodyResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("History")
            ForEach(body.history.filter { $0.bfPercent != nil }) { m in
                HStack {
                    Text(PiDate.shortLabel(m.date))
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piTextMuted)
                    Spacer()
                    if let c = m.chestMm, let a = m.abdomenMm, let t = m.thighMm {
                        Text("\(Int(c))/\(Int(a))/\(Int(t))")
                            .font(.piCaption)
                            .foregroundStyle(Color.piTextMuted)
                    }
                    Text(String(format: "%.1f%%", m.bfPercent ?? 0))
                        .font(.piBody)
                        .foregroundStyle(Color.piBFPink)
                        .frame(width: 64, alignment: .trailing)
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.piTextMuted)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { selectForEdit(m) }
            }
        }
        .piCard()
    }

    // MARK: - Actions

    /// Existing stored record for a day, if any.
    private func entry(for date: Date) -> BodyMetric? {
        let day = PiDate.dayString(date)
        return data?.history.first { $0.date == day }
    }

    /// Loads a day's stored values into the form so it edits in place. Only the
    /// stored (already-averaged) caliper value is known, so it seeds the first
    /// reading; re-measuring fills #2/#3 and re-averages.
    private func prefill(for date: Date) {
        let e = entry(for: date)
        weightText = e?.weightLbs.map(numStr) ?? ""
        chest = SiteReadings(r1: e?.chestMm.map(numStr) ?? "")
        abdomen = SiteReadings(r1: e?.abdomenMm.map(numStr) ?? "")
        thigh = SiteReadings(r1: e?.thighMm.map(numStr) ?? "")
    }

    private func selectForEdit(_ m: BodyMetric) {
        guard let d = PiDate.parseDay(m.date) else { return }
        entryDate = d           // triggers onChange → prefill
        prefill(for: d)         // also handles tapping the already-selected day
    }

    private func numStr(_ d: Double) -> String {
        abs(d - d.rounded()) < 0.0001 ? String(Int(d.rounded())) : String(format: "%.1f", d)
    }

    private func load() async {
        do {
            data = try await session.client.bodyHistory(days: 90)
            error = nil
        } catch {
            if data == nil { self.error = error.localizedDescription }
        }
    }

    private func save(weight: Double? = nil, chest: Double? = nil, abdomen: Double? = nil, thigh: Double? = nil) async {
        do {
            _ = try await session.client.submitBody(date: PiDate.dayString(entryDate),
                                                    weightLbs: weight,
                                                    chestMm: chest,
                                                    abdomenMm: abdomen,
                                                    thighMm: thigh)
            toast = Toast(message: "Saved")
            await load()
            prefill(for: entryDate)  // reflect the saved record as editable
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}
