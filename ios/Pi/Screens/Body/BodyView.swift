import SwiftUI
import Charts

struct BodyView: View {
    @Environment(Session.self) private var session

    @State private var data: BodyResponse?
    @State private var error: String?
    @State private var tab = "weight"

    @State private var entryDate = Date()
    @State private var weightText = ""
    @State private var chestText = ""
    @State private var abdomenText = ""
    @State private var thighText = ""
    @State private var isSaving = false
    @State private var toast: Toast?

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
            .task { await load() }
            .refreshable { await load() }
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

    // MARK: - Entry forms

    private var weightForm: some View {
        VStack(spacing: 12) {
            DatePicker("Date", selection: $entryDate, in: ...Date(), displayedComponents: .date)
                .font(.piBody)
            HStack {
                TextField("Weight (lb)", text: $weightText)
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(Color.piBg3)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                saveButton(enabled: Double(weightText) != nil) {
                    await save(weight: Double(weightText))
                }
            }
        }
        .piCard()
    }

    private var bfForm: some View {
        VStack(spacing: 12) {
            DatePicker("Date", selection: $entryDate, in: ...Date(), displayedComponents: .date)
                .font(.piBody)
            HStack(spacing: 8) {
                caliperField("Chest", $chestText)
                caliperField("Abdomen", $abdomenText)
                caliperField("Thigh", $thighText)
            }
            Text("Caliper skinfold in mm — BF% is computed automatically (Jackson-Pollock 3-site).")
                .font(.piCaption)
                .foregroundStyle(Color.piTextMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            saveButton(enabled: Double(chestText) != nil && Double(abdomenText) != nil && Double(thighText) != nil) {
                await save(chest: Double(chestText), abdomen: Double(abdomenText), thigh: Double(thighText))
            }
        }
        .piCard()
    }

    private func caliperField(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(label)
            TextField("mm", text: text)
                .keyboardType(.decimalPad)
                .padding(10)
                .background(Color.piBg3)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func saveButton(enabled: Bool, action: @escaping () async -> Void) -> some View {
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
                    Text("Save").font(.piHeadline)
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
                }
                .padding(.vertical, 4)
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
                }
                .padding(.vertical, 4)
            }
        }
        .piCard()
    }

    // MARK: - Actions

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
            weightText = ""
            chestText = ""
            abdomenText = ""
            thighText = ""
            toast = Toast(message: "Saved")
            await load()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}
