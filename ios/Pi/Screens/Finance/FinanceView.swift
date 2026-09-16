import SwiftUI

enum TxnFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case uncategorized = "To Tag"
    case transfers = "Transfers"
    var id: String { rawValue }
}

enum AccountFilter: String, CaseIterable, Identifiable {
    case all = "All", checking = "Checking", savings = "Savings", credit = "Card"
    var id: String { rawValue }
    var apiValue: String? {
        switch self {
        case .all: return nil
        case .checking: return "checking"
        case .savings: return "savings"
        case .credit: return "credit_card"
        }
    }
}

struct FinanceView: View {
    @Environment(Session.self) private var session

    @State private var page: TransactionsPage?
    @State private var summary: FinanceSummary?
    @State private var categories: [FinanceCategory] = []
    @State private var error: String?
    @State private var filter: TxnFilter = .all
    @State private var account: AccountFilter = .all
    @State private var categoryFilter: FinanceCategory?
    @State private var search = ""
    @State private var selected: FinanceTransaction?
    @State private var showUpload = false
    @State private var toast: Toast?
    @State private var deepLinkInsights = false

    var body: some View {
        NavigationStack {
            Group {
                if !session.financeConfigured {
                    notConfigured
                } else {
                    LoadableView(value: page, error: error, retry: { Task { await load() } }) { page in
                        list(page)
                    }
                }
            }
            .background(Color.piBg)
            .navigationTitle("Finance")
            .navigationDestination(isPresented: $deepLinkInsights) { InsightsView() }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.environment["PI_TEST_FINANCE_SCREEN"] == "insights" {
                    deepLinkInsights = true
                }
                #endif
            }
            .toolbar {
                if session.financeConfigured {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { InsightsView() } label: { Image(systemName: "chart.pie.fill") }
                    }
                    ToolbarItem(placement: .topBarTrailing) { categoryMenu }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showUpload = true } label: { Image(systemName: "arrow.up.doc") }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search merchant or description")
            .onSubmit(of: .search) { Task { await load() } }
            .onChange(of: filter) { Task { await load() } }
            .onChange(of: account) { Task { await loadSummary(); await load() } }
            .onChange(of: categoryFilter) { Task { await load() } }
            .task { await loadAll() }
            .refreshable { await loadAll() }
            .sheet(item: $selected) { txn in
                CategorizeSheet(transaction: txn, categories: categories) { changed in
                    if changed { Task { await loadAll() } }
                }
            }
            .sheet(isPresented: $showUpload) {
                UploadStatementView { imported in
                    if imported { Task { await loadAll() } }
                }
            }
            .toast($toast)
        }
    }

    // MARK: - Subviews

    private var notConfigured: some View {
        ContentUnavailableView {
            Label("Finance not set up", systemImage: "creditcard")
        } description: {
            Text("Add your finance server key in Settings → Finance to load transactions.")
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button { categoryFilter = nil } label: {
                Label("All categories", systemImage: categoryFilter == nil ? "checkmark" : "")
            }
            ForEach(categories) { top in
                Menu(top.name) {
                    ForEach(top.subcategories ?? []) { sub in
                        Button {
                            categoryFilter = sub
                        } label: {
                            Label(sub.name, systemImage: categoryFilter?.id == sub.id ? "checkmark" : "")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: categoryFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func list(_ page: TransactionsPage) -> some View {
        List {
            if let summary {
                Section { SummaryHeader(summary: summary, scope: account == .all ? nil : account.rawValue) }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            Section {
                accountChips
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                Picker("Filter", selection: $filter) {
                    ForEach(TxnFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                if let cat = categoryFilter {
                    HStack {
                        Pill(cat.name, color: .piPrimary)
                        Spacer()
                        Button("Clear") { categoryFilter = nil }
                            .font(.piCaption).foregroundStyle(Color.piPrimary)
                    }
                    .listRowBackground(Color.clear)
                }
                if page.transactions.isEmpty {
                    Text("No transactions.").font(.piBody).foregroundStyle(Color.piTextMuted)
                } else {
                    ForEach(page.transactions) { txn in
                        Button { selected = txn } label: { TransactionRow(txn: txn) }
                            .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("\(page.total) transactions")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var accountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AccountFilter.allCases) { a in
                    FinanceChip(label: a.rawValue, selected: account == a) { account = a }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Loading

    private func loadAll() async {
        async let s: Void = loadSummary()
        async let c: Void = loadCategories()
        async let t: Void = load()
        _ = await (s, c, t)
    }

    private func load() async {
        do {
            page = try await session.financeClient.transactions(
                accountType: account.apiValue,
                categoryId: categoryFilter?.id,
                uncategorized: filter == .uncategorized,
                isTransfer: filter == .transfers ? true : nil,
                query: search,
                limit: 500)
            error = nil
        } catch {
            if page == nil { self.error = error.localizedDescription }
            else { toast = Toast(message: error.localizedDescription, isError: true) }
        }
    }

    private func loadSummary() async {
        summary = try? await session.financeClient.summary(accountType: account.apiValue)
    }

    private func loadCategories() async {
        if let resp = try? await session.financeClient.categories() {
            categories = resp.categories
        }
    }
}

// MARK: - Components

struct FinanceChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.piSubheadline)
                .fontWeight(selected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Color.piPrimary : Color.piBg3)
                .foregroundStyle(selected ? Color.piOnPrimary : Color.piText)
                .clipShape(Capsule())
        }
        .buttonStyle(.piPressable)
    }
}

struct SummaryHeader: View {
    let summary: FinanceSummary
    var scope: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let scope { Eyebrow(scope) }
            HStack(spacing: 12) {
                stat("Income", summary.income, .piCalGood)
                stat("Spending", summary.spending, .piDanger)
                stat("Net", summary.net, summary.net >= 0 ? .piCalGood : .piDanger)
            }
        }
        .piCard()
    }
    private func stat(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(label)
            Text(value.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                .font(.piMetricSmall)
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TransactionRow: View {
    let txn: FinanceTransaction
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(txn.merchant?.isEmpty == false ? txn.merchant! : txn.description)
                    .font(.piBody)
                    .foregroundStyle(Color.piText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(PiDate.shortLabel(txn.date))
                        .font(.piCaption)
                        .foregroundStyle(Color.piTextMuted)
                    if let category = txn.category {
                        Pill(category, color: txn.isTransfer ? .piTextMuted : .piPrimary)
                    } else {
                        Pill("Uncategorized", color: .piWarn)
                    }
                }
            }
            Spacer()
            Text(txn.amount.formatted(.currency(code: "USD")))
                .font(.piMetricSmall)
                .foregroundStyle(txn.amount < 0 ? Color.piText : Color.piCalGood)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
