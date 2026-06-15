import SwiftUI
import Charts

/// Trends over time — body weight for now; more metrics slot in as sections.
struct TrendsView: View {
    @Environment(Session.self) private var session

    @State private var data: TrendsResponse?
    @State private var error: String?
    @State private var rangeDays = 90

    var body: some View {
        ScrollView {
            LoadableView(value: data, error: error, retry: { Task { await load() } }) { trends in
                VStack(spacing: 16) {
                    Picker("Range", selection: $rangeDays) {
                        Text("30d").tag(30)
                        Text("90d").tag(90)
                        Text("180d").tag(180)
                        Text("1y").tag(365)
                    }
                    .pickerStyle(.segmented)

                    weightSection(trends)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.piBg)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: rangeDays) { await load() }
        .refreshable { await load() }
    }

    // MARK: - Weight

    private struct WeightPoint: Identifiable {
        let id: String
        let date: Date
        let weight: Double
        var movingAvg: Double?
    }

    private func weightPoints(_ trends: TrendsResponse) -> [WeightPoint] {
        var pts: [WeightPoint] = trends.points.compactMap { p in
            guard let w = p.weightLbs, let d = PiDate.parseDay(p.date) else { return nil }
            return WeightPoint(id: p.date, date: d, weight: w)
        }
        // 7-day trailing moving average over logged entries
        for i in pts.indices {
            let windowStart = Calendar.current.date(byAdding: .day, value: -6, to: pts[i].date)!
            let window = pts.filter { $0.date >= windowStart && $0.date <= pts[i].date }
            if window.count >= 2 {
                pts[i].movingAvg = window.reduce(0) { $0 + $1.weight } / Double(window.count)
            }
        }
        return pts
    }

    @ViewBuilder
    private func weightSection(_ trends: TrendsResponse) -> some View {
        let pts = weightPoints(trends)
        if pts.count < 2 {
            ContentUnavailableView("Not enough weight entries",
                                   systemImage: "chart.xyaxis.line",
                                   description: Text("Log your weight on the Body tab — trends appear once there are at least two entries in this range."))
                .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow("Body weight", color: .piWeightTeal)
                    Spacer()
                    if let latest = pts.last {
                        Text(String(format: "%.1f lb", latest.weight))
                            .font(.piMetricMed)
                            .foregroundStyle(Color.piWeightTeal)
                    }
                }

                statsRow(pts)

                Chart {
                    ForEach(pts) { p in
                        PointMark(x: .value("Date", p.date), y: .value("Weight", p.weight))
                            .foregroundStyle(Color.piWeightTeal.opacity(0.55))
                            .symbolSize(22)
                        LineMark(x: .value("Date", p.date), y: .value("Weight", p.weight))
                            .foregroundStyle(Color.piWeightTeal.opacity(0.35))
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(pts.filter { $0.movingAvg != nil }) { p in
                        LineMark(x: .value("Date", p.date), y: .value("7-day avg", p.movingAvg!),
                                 series: .value("Series", "avg"))
                            .foregroundStyle(Color.piWeightTeal)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 240)

                HStack(spacing: 14) {
                    legendSwatch("Daily", Color.piWeightTeal.opacity(0.45))
                    legendSwatch("7-day average", Color.piWeightTeal)
                }
            }
            .piCard()
        }
    }

    private func statsRow(_ pts: [WeightPoint]) -> some View {
        let first = pts.first!.weight
        let last = pts.last!.weight
        let delta = last - first
        let lo = pts.map(\.weight).min() ?? 0
        let hi = pts.map(\.weight).max() ?? 0
        return HStack {
            stat(String(format: "%+.1f lb", delta), "change",
                 color: abs(delta) < 0.05 ? .piTextMuted : (delta < 0 ? .piCalGood : .piWarn))
            stat(String(format: "%.1f", lo), "low", color: .piTextMuted)
            stat(String(format: "%.1f", hi), "high", color: .piTextMuted)
            stat("\(pts.count)", "entries", color: .piTextMuted)
        }
    }

    private func stat(_ value: String, _ label: String, color: Color) -> some View {
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

    private func legendSwatch(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 16, height: 3)
            Text(label)
                .font(.piCaption)
                .foregroundStyle(Color.piTextMuted)
        }
    }

    private func load() async {
        do {
            data = try await session.client.trends(rangeDays: rangeDays)
            error = nil
        } catch {
            if data == nil { self.error = error.localizedDescription }
        }
    }
}
