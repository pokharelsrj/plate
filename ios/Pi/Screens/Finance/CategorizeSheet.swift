import SwiftUI

/// Pick a category for a transaction. "Apply to all" creates a merchant rule
/// (tags every matching transaction, now and future); off sets a single override.
struct CategorizeSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let transaction: FinanceTransaction
    let categories: [FinanceCategory]
    let onDone: (_ changed: Bool) -> Void

    @State private var applyToAll = true
    @State private var saving = false
    @State private var toast: Toast?

    private var merchantLabel: String {
        transaction.merchant?.isEmpty == false ? transaction.merchant! : transaction.description
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(merchantLabel).font(.piHeadline).foregroundStyle(Color.piText).lineLimit(2)
                        HStack {
                            Text(PiDate.shortLabel(transaction.date))
                            Text("·")
                            Text(transaction.amount.formatted(.currency(code: "USD")))
                            if let c = transaction.category { Text("·"); Text(c) }
                        }
                        .font(.piCaption).foregroundStyle(Color.piTextMuted)
                    }
                }

                Section {
                    Toggle(isOn: $applyToAll) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apply to all matching").font(.piBody)
                            Text(applyToAll ? "Creates a rule for this merchant" : "Tags just this one transaction")
                                .font(.piCaption).foregroundStyle(Color.piTextMuted)
                        }
                    }
                    if transaction.categoryId != nil {
                        Button(role: .destructive) {
                            Task { await clear() }
                        } label: { Label("Clear category", systemImage: "xmark.circle") }
                    }
                }

                ForEach(categories) { top in
                    Section(top.name) {
                        ForEach(top.subcategories ?? []) { sub in
                            categoryRow(sub, top: top)
                        }
                    }
                }
            }
            .navigationTitle("Categorize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDone(false); dismiss() }
                }
            }
            .overlay { if saving { ProgressView().controlSize(.large) } }
            .toast($toast)
        }
    }

    private func categoryRow(_ sub: FinanceCategory, top: FinanceCategory) -> some View {
        Button {
            Task { await assign(categoryId: sub.id) }
        } label: {
            HStack {
                Text(sub.name).font(.piBody).foregroundStyle(Color.piText)
                Spacer()
                if transaction.categoryId == sub.id {
                    Image(systemName: "checkmark").foregroundStyle(Color.piPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func assign(categoryId: Int) async {
        saving = true; defer { saving = false }
        do {
            if applyToAll {
                _ = try await session.financeClient.tagMerchant(
                    txnId: transaction.txnId, categoryId: categoryId, canonicalMerchant: transaction.merchant)
            } else {
                _ = try await session.financeClient.retag(txnId: transaction.txnId, categoryId: categoryId)
            }
            onDone(true); dismiss()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func clear() async {
        saving = true; defer { saving = false }
        do {
            _ = try await session.financeClient.retag(txnId: transaction.txnId, categoryId: nil)
            onDone(true); dismiss()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}
