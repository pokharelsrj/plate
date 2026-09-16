import Foundation

// Codable models for the finance FastAPI backend. JSON is snake_case; the shared
// APIClient decoder uses .convertFromSnakeCase, so properties stay camelCase.

struct FinanceTransaction: Decodable, Identifiable, Hashable {
    let txnId: String
    let date: String
    let account: String
    let accountType: String
    let type: String
    let isTransfer: Bool
    let description: String
    let merchant: String?
    let amount: Double
    let balance: Double?
    let reference: String?
    let categoryId: Int?
    let category: String?
    let categorySource: String?
    let sourceFile: String?

    var id: String { txnId }
    var isUncategorized: Bool { categoryId == nil }
}

struct TransactionsPage: Decodable {
    let total: Int
    let count: Int
    let transactions: [FinanceTransaction]
}

struct FinanceCategory: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let parentId: Int?
    let kind: String
    let subcategories: [FinanceCategory]?
}

struct CategoriesResponse: Decodable {
    let categories: [FinanceCategory]
}

struct FinanceSummary: Decodable {
    let income: Double
    let spending: Double
    let net: Double
    let transactions: Int
    let uncategorized: Int
    let excludeTransfers: Bool
}

struct CategorySubtotal: Decodable, Hashable {
    let category: String
    let total: Double
    let count: Int
}

struct CategoryTotal: Decodable, Hashable {
    let total: Double
    let count: Int
    let subcategories: [CategorySubtotal]
}

struct ByCategoryResponse: Decodable {
    let byCategory: [String: CategoryTotal]
}

struct TrendPoint: Decodable, Identifiable, Hashable {
    let month: String          // "2026-01"
    let income: Double
    let spending: Double       // negative
    let net: Double
    let count: Int
    var id: String { month }

    /// "Jan" style label from the YYYY-MM month.
    var shortMonth: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: month) else { return month }
        return d.formatted(.dateTime.month(.abbreviated))
    }
}

struct FinanceTrendsResponse: Decodable {
    let months: [TrendPoint]
}

struct TagMerchantResult: Decodable {
    let transactionsCategorizedTotal: Int?
}

struct UploadResult: Decodable {
    let file: String
    let inserted: Int
    let duplicates: Int
    let categorizedOnImport: Int
    let reconciled: Bool?
    let statementTxns: Int?
    let accountTypeDetected: String?
}
