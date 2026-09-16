import SwiftUI
import Charts

/// Insights: cash-flow trend chart, spending-by-category donut, and the category
/// breakdown — all scoped by a period + account filter.
struct InsightsView: View {
    @Environment(Session.self) private var session

    @State private var period: FinancePeriod = .last6
    @State private var account: AccountFilter = .all
    @State private var trends: [TrendPoint] = []
    @State private var byCat: ByCategoryResponse?
    @State private var summary: FinanceSummary?
    @State private var error: String?

    /// Flattened (month, series, value) for the grouped cash-flow bar chart.
    private var cashflow: [CashflowBar] {
        trends.flatMap { t in
            [CashflowBar(month: t.shortMonth, series: "Income", value: t.income),
             CashflowBar(month: t.shortMonth, series: "Spending", value: abs(t.spending))]
        }
    }

    /// Top spending categories (negative totals) for the donut, biggest first.
    private var spendingSlices: [CategorySlice] {
        guard let byCat else { return [] }
        var slices: [CategorySlice] = []
        for (name, total) in byCat.byCategory where total.total < 0 {
            slices.append(CategorySlice(name: name, amount: abs(total.total)))
        }
        return slices.sorted { $0.amount > $1.amount }
    }

    /// Categories sorted for the breakdown list (biggest spend first).
    private var breakdownRows: [(name: String, total: CategoryTotal)] {
        guard let byCat else { return [] }
        var rows: [(name: String, total: CategoryTotal)] = []
        for (name, total) in byCat.byCategory {
            rows.append((name, total))
        }
        return rows.sorted { $0.total.total < $1.total.total }
    }

    var body: some View {
        ScrollView {
            LoadableView(value: byCat, error: error, retry: { Task { await load() } }) { _ in
                VStack(spacing: 16) {
                    controls
                    if let summary { SummaryHeader(summary: summary, scope: nil) }
                    cashflowCard
                    donutCard
                    breakdownCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.piBg)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FinancePeriod.allCases) { p in
                        FinanceChip(label: p.chip, selected: period == p) { period = p }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AccountFilter.allCases) { a in
                        FinanceChip(label: a.rawValue, selected: account == a) { account = a }
                    }
                }
            }
        }
        .onChange(of: period) { Task { await load() } }
        .onChange(of: account) { Task { await load() } }
    }

    // MARK: - Cards

    private var cashflowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Cash flow · last \(period.chartMonths) months")
            if cashflow.isEmpty {
                Text("No data").font(.piBody).foregroundStyle(Color.piTextMuted)
            } else {
                Chart(cashflow) { bar in
                    BarMark(
                        x: .value("Month", bar.month),
                        y: .value("Amount", bar.value)
                    )
                    .foregroundStyle(by: .value("Type", bar.series))
                    .position(by: .value("Type", bar.series))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale(["Income": Color.piCalGood, "Spending": Color.piDanger])
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 200)
            }
        }
        .piCard()
    }

    private var donutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Spending by category")
            if spendingSlices.isEmpty {
                Text("No spending in range").font(.piBody).foregroundStyle(Color.piTextMuted)
            } else {
                Chart(spendingSlices) { slice in
                    SectorMark(
                        angle: .value("Amount", slice.amount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Category", slice.name))
                    .cornerRadius(4)
                }
                .chartLegend(position: .bottom, alignment: .center, spacing: 8)
                .frame(height: 240)
            }
        }
        .piCard()
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Breakdown")
            ForEach(breakdownRows, id: \.name) { name, total in
                let isIncome = total.total >= 0
                HStack {
                    Text(name).font(.piBody).foregroundStyle(Color.piText)
                    Spacer()
                    Text("\(total.count)").font(.piCaption).foregroundStyle(Color.piTextMuted)
                    Text(total.total.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                        .font(.piMetricSmall)
                        .foregroundStyle(isIncome ? Color.piCalGood : Color.piText)
                        .frame(width: 96, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        }
        .piCard()
    }

    // MARK: - Loading

    private func load() async {
        let (from, to) = period.dateRange()
        do {
            let t = try await session.financeClient.trends(months: period.chartMonths, accountType: account.apiValue)
            trends = t.months
            async let cat = session.financeClient.byCategory(accountType: account.apiValue, dateFrom: from, dateTo: to)
            async let sum = session.financeClient.summary(accountType: account.apiValue, dateFrom: from, dateTo: to)
            byCat = try await cat
            summary = try await sum
            error = nil
        } catch {
            if byCat == nil { self.error = error.localizedDescription }
        }
    }
}

/// Granular analysis period: single months, rolling ranges, YTD, or all-time.
enum FinancePeriod: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, last3, last6, last12, ytd, all
    var id: String { rawValue }

    var chip: String {
        switch self {
        case .thisMonth: return "This Mo"
        case .lastMonth: return "Last Mo"
        case .last3: return "3M"
        case .last6: return "6M"
        case .last12: return "12M"
        case .ytd: return "YTD"
        case .all: return "All"
        }
    }

    /// How many months of history the cash-flow chart shows for this period.
    var chartMonths: Int {
        switch self {
        case .thisMonth, .lastMonth: return 6
        case .last3: return 3
        case .last6: return 6
        case .last12: return 12
        case .ytd: return max(1, Calendar.current.component(.month, from: Date()))
        case .all: return 12
        }
    }

    /// (date_from, date_to) in YYYY-MM-DD for scoping the summary / breakdown.
    func dateRange() -> (String?, String?) {
        let cal = Calendar.current
        let now = Date()
        let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        switch self {
        case .thisMonth:
            return (PiDate.dayString(startOfThisMonth), nil)
        case .lastMonth:
            let start = cal.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? startOfThisMonth
            let end = cal.date(byAdding: .day, value: -1, to: startOfThisMonth) ?? startOfThisMonth
            return (PiDate.dayString(start), PiDate.dayString(end))
        case .last3, .last6, .last12:
            let n = self == .last3 ? 3 : (self == .last6 ? 6 : 12)
            let start = cal.date(byAdding: .month, value: -(n - 1), to: startOfThisMonth) ?? startOfThisMonth
            return (PiDate.dayString(start), nil)
        case .ytd:
            let jan = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1)) ?? now
            return (PiDate.dayString(jan), nil)
        case .all:
            return (nil, nil)
        }
    }
}

private struct CashflowBar: Identifiable {
    let month: String
    let series: String
    let value: Double
    var id: String { "\(month)-\(series)" }
}

private struct CategorySlice: Identifiable {
    let name: String
    let amount: Double
    var id: String { name }
}
