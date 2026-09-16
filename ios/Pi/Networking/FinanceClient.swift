import Foundation

/// Client for the finance FastAPI backend (separate service on the Pi, :8090).
/// Mirrors APIClient's style but targets a different host/key and adds multipart
/// upload for statement PDFs. Reuses APIClient's snake_case JSON coders.
struct FinanceClient {
    let baseURL: URL
    let apiKey: String?

    private func makeRequest(_ path: String, method: String, query: [URLQueryItem], body: (any Encodable)?) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try APIClient.encoder.encode(body)
        }
        return request
    }

    @discardableResult
    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await APIClient.urlSession.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.server("invalid response") }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw APIError.unauthorized
        case 403: throw APIError.forbidden
        case 404: throw APIError.notFound
        default:  throw APIError.server(Self.errorMessage(from: data) ?? "Server error (\(http.statusCode))")
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        (try? APIClient.decoder.decode([String: String].self, from: data))?["error"]
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET",
                                       query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws -> T {
        let req = try makeRequest(path, method: method, query: query, body: body)
        let data = try await perform(req)
        do { return try APIClient.decoder.decode(T.self, from: data) }
        catch { throw APIError.decode(error) }
    }

    // MARK: - Endpoints

    func ping() async throws { _ = try await perform(try makeRequest("/health/ping", method: "GET", query: [], body: nil)) }

    func transactions(accountType: String? = nil, categoryId: Int? = nil,
                      uncategorized: Bool = false, isTransfer: Bool? = nil,
                      query: String? = nil, limit: Int = 200, offset: Int = 0) async throws -> TransactionsPage {
        var items = [URLQueryItem(name: "limit", value: String(limit)),
                     URLQueryItem(name: "offset", value: String(offset))]
        if let accountType { items.append(.init(name: "account_type", value: accountType)) }
        if let categoryId { items.append(.init(name: "category_id", value: String(categoryId))) }
        if uncategorized { items.append(.init(name: "uncategorized", value: "true")) }
        if let isTransfer { items.append(.init(name: "is_transfer", value: isTransfer ? "true" : "false")) }
        if let query, !query.isEmpty { items.append(.init(name: "q", value: query)) }
        return try await request("/transactions", query: items)
    }

    func trends(months: Int = 6, accountType: String? = nil) async throws -> FinanceTrendsResponse {
        var items = [URLQueryItem(name: "months", value: String(months))]
        if let accountType { items.append(.init(name: "account_type", value: accountType)) }
        return try await request("/reports/trends", query: items)
    }

    func categories() async throws -> CategoriesResponse { try await request("/categories") }

    func summary(accountType: String? = nil, dateFrom: String? = nil, dateTo: String? = nil,
                 excludeTransfers: Bool = true) async throws -> FinanceSummary {
        var items = [URLQueryItem(name: "exclude_transfers", value: excludeTransfers ? "true" : "false")]
        if let accountType { items.append(.init(name: "account_type", value: accountType)) }
        if let dateFrom { items.append(.init(name: "date_from", value: dateFrom)) }
        if let dateTo { items.append(.init(name: "date_to", value: dateTo)) }
        return try await request("/reports/summary", query: items)
    }

    func byCategory(accountType: String? = nil, dateFrom: String? = nil, dateTo: String? = nil,
                    excludeTransfers: Bool = true) async throws -> ByCategoryResponse {
        var items = [URLQueryItem(name: "exclude_transfers", value: excludeTransfers ? "true" : "false")]
        if let accountType { items.append(.init(name: "account_type", value: accountType)) }
        if let dateFrom { items.append(.init(name: "date_from", value: dateFrom)) }
        if let dateTo { items.append(.init(name: "date_to", value: dateTo)) }
        return try await request("/reports/by-category", query: items)
    }

    /// Re-tag a single transaction. categoryId == nil clears the override.
    func retag(txnId: String, categoryId: Int?) async throws -> FinanceTransaction {
        struct Body: Encodable {
            let categoryId: Int?
            enum CodingKeys: String, CodingKey { case categoryId }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(categoryId, forKey: .categoryId)  // writes explicit null
            }
        }
        return try await request("/transactions/\(txnId)", method: "PATCH", body: Body(categoryId: categoryId))
    }

    /// Tag this transaction's merchant once -> creates a rule matching all of them.
    func tagMerchant(txnId: String, categoryId: Int, canonicalMerchant: String?) async throws -> TagMerchantResult {
        struct Body: Encodable { let categoryId: Int; let canonicalMerchant: String? }
        return try await request("/transactions/\(txnId)/tag-merchant", method: "POST",
                                 body: Body(categoryId: categoryId, canonicalMerchant: canonicalMerchant))
    }

    /// Upload a PDF statement (multipart/form-data) for server-side parsing + import.
    func uploadStatement(fileData: Data, filename: String) async throws -> UploadResult {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.badURL }
        components.path = "/statements/upload"
        guard let url = components.url else { throw APIError.badURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/pdf\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60   // parsing a PDF can take a few seconds
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
        req.httpBody = body
        let data = try await perform(req)
        do { return try APIClient.decoder.decode(UploadResult.self, from: data) }
        catch { throw APIError.decode(error) }
    }
}
