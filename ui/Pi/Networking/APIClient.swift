import Foundation

extension Notification.Name {
    static let piUnauthorized = Notification.Name("piUnauthorized")
}

struct APIClient {
    let baseURL: URL
    let apiKey: String?

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Core request

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
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }
        return request
    }

    @discardableResult
    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.urlSession.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("invalid response")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            NotificationCenter.default.post(name: .piUnauthorized, object: nil)
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            throw APIError.conflict(Self.errorMessage(from: data) ?? "Conflict")
        default:
            throw APIError.server(Self.errorMessage(from: data) ?? "Server error (\(http.statusCode))")
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        (try? decoder.decode([String: String].self, from: data))?["error"]
    }

    func request<T: Decodable>(_ path: String,
                               method: String = "GET",
                               query: [URLQueryItem] = [],
                               body: (any Encodable)? = nil) async throws -> T {
        let req = try makeRequest(path, method: method, query: query, body: body)
        let data = try await perform(req)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decode(error)
        }
    }

    func requestVoid(_ path: String,
                     method: String,
                     query: [URLQueryItem] = [],
                     body: (any Encodable)? = nil) async throws {
        let req = try makeRequest(path, method: method, query: query, body: body)
        try await perform(req)
    }

    // MARK: - Auth (static — no key yet)

    static func login(baseURL: URL, email: String, password: String) async throws -> LoginResponse {
        let client = APIClient(baseURL: baseURL, apiKey: nil)
        return try await client.request("/api/auth/login", method: "POST",
                                        body: ["email": email, "password": password])
    }

    static func ping(baseURL: URL) async throws -> PingResponse {
        let client = APIClient(baseURL: baseURL, apiKey: nil)
        return try await client.request("/api/health/ping")
    }

    // MARK: - Me

    func me() async throws -> User { try await request("/api/me") }

    func updateMe(displayName: String?, dateOfBirth: String?, sex: String?) async throws -> User {
        struct Body: Encodable {
            let displayName: String?
            let dateOfBirth: String?
            let sex: String?
        }
        return try await request("/api/me", method: "PUT",
                                 body: Body(displayName: displayName, dateOfBirth: dateOfBirth, sex: sex))
    }

    func rotateKey() async throws -> RotateKeyResponse {
        try await request("/api/me/rotate-key", method: "POST")
    }

    // MARK: - Today / Calendar

    func today() async throws -> TodaySnapshot { try await request("/api/today") }

    func day(_ date: String) async throws -> TodaySnapshot {
        try await request("/api/day", query: [URLQueryItem(name: "date", value: date)])
    }

    func calendar(view: String, date: String) async throws -> CalendarResponse {
        try await request("/api/calendar", query: [
            URLQueryItem(name: "view", value: view),
            URLQueryItem(name: "date", value: date),
        ])
    }

    // MARK: - Workout

    func workout(date: String, exerciseId: Int64?) async throws -> WorkoutResponse {
        var query = [URLQueryItem(name: "date", value: date)]
        if let exerciseId {
            query.append(URLQueryItem(name: "exercise_id", value: String(exerciseId)))
        }
        return try await request("/api/workout", query: query)
    }

    func workoutStats(rangeDays: Int) async throws -> WorkoutStats {
        try await request("/api/workout/stats", query: [URLQueryItem(name: "range", value: String(rangeDays))])
    }

    func addSet(date: String, exerciseId: Int64, reps: Int, weightLbs: Double?) async throws -> WorkoutSet {
        struct Body: Encodable {
            let date: String
            let exerciseId: Int64
            let reps: Int
            let weightLbs: Double?
        }
        return try await request("/api/workout/set", method: "POST",
                                 body: Body(date: date, exerciseId: exerciseId, reps: reps, weightLbs: weightLbs))
    }

    func updateSet(id: Int64, reps: Int, weightLbs: Double?) async throws -> WorkoutSet {
        struct Body: Encodable {
            let reps: Int
            let weightLbs: Double?
        }
        return try await request("/api/workout/set/\(id)", method: "PUT",
                                 body: Body(reps: reps, weightLbs: weightLbs))
    }

    func deleteSet(id: Int64) async throws {
        try await requestVoid("/api/workout/set/\(id)", method: "DELETE")
    }

    // MARK: - Exercises & tags

    func exercises() async throws -> ExercisesResponse { try await request("/api/exercises") }

    func createExercise(name: String, bodyPart: String) async throws -> Exercise {
        try await request("/api/exercises", method: "POST",
                          body: ["name": name, "body_part": bodyPart])
    }

    func updateExercise(id: Int64, name: String, bodyPart: String) async throws -> Exercise {
        try await request("/api/exercises/\(id)", method: "PUT",
                          body: ["name": name, "body_part": bodyPart])
    }

    func deleteExercise(id: Int64) async throws {
        try await requestVoid("/api/exercises/\(id)", method: "DELETE")
    }

    func bodyParts() async throws -> BodyPartsResponse { try await request("/api/body-parts") }

    func createBodyPart(name: String) async throws {
        try await requestVoid("/api/body-parts", method: "POST", body: ["name": name])
    }

    func deleteBodyPart(name: String) async throws {
        try await requestVoid("/api/body-parts/\(name)", method: "DELETE")
    }

    // MARK: - Body metrics

    func bodyHistory(days: Int) async throws -> BodyResponse {
        try await request("/api/body", query: [URLQueryItem(name: "days", value: String(days))])
    }

    func submitBody(date: String, weightLbs: Double?, chestMm: Double?, abdomenMm: Double?, thighMm: Double?) async throws -> BodyMetric {
        struct Body: Encodable {
            let date: String
            let weightLbs: Double?
            let chestMm: Double?
            let abdomenMm: Double?
            let thighMm: Double?
        }
        return try await request("/api/body", method: "POST",
                                 body: Body(date: date, weightLbs: weightLbs, chestMm: chestMm, abdomenMm: abdomenMm, thighMm: thighMm))
    }

    // MARK: - Health ingest

    func ingestHealth(days: [HealthDay]) async throws {
        try await requestVoid("/api/health/ingest", method: "POST", body: ["days": days])
    }

    // MARK: - Trends

    func trends(rangeDays: Int) async throws -> TrendsResponse {
        try await request("/api/trends", query: [URLQueryItem(name: "range", value: String(rangeDays))])
    }

    // MARK: - Sync

    func syncStatus() async throws -> SyncStatusResponse { try await request("/api/sync") }

    func triggerSync(source: String, days: Int) async throws {
        try await requestVoid("/api/sync/trigger", method: "POST", query: [
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "days", value: String(days)),
        ])
    }

    // MARK: - Admin

    func adminUsers() async throws -> AdminUsersResponse { try await request("/api/admin/users") }

    func adminCreateUser(email: String, password: String, displayName: String, role: String, dateOfBirth: String?, sex: String?) async throws -> AdminCreatedUser {
        struct Body: Encodable {
            let email: String
            let password: String
            let displayName: String
            let role: String
            let dateOfBirth: String?
            let sex: String?
        }
        return try await request("/api/admin/users", method: "POST",
                                 body: Body(email: email, password: password, displayName: displayName, role: role, dateOfBirth: dateOfBirth, sex: sex))
    }

    func adminUpdateUser(id: Int64, displayName: String?, role: String?, isActive: Bool?) async throws -> User {
        struct Body: Encodable {
            let displayName: String?
            let role: String?
            let isActive: Bool?
        }
        return try await request("/api/admin/users/\(id)", method: "PUT",
                                 body: Body(displayName: displayName, role: role, isActive: isActive))
    }

    func adminResetPassword(id: Int64, password: String) async throws {
        try await requestVoid("/api/admin/users/\(id)/reset-password", method: "POST",
                              body: ["password": password])
    }

    func adminDeleteUser(id: Int64) async throws {
        try await requestVoid("/api/admin/users/\(id)", method: "DELETE")
    }
}
