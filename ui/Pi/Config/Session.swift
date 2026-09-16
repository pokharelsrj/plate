import Foundation
import Observation

/// App-wide auth + identity state. The API key lives in the Keychain;
/// everything else persists in UserDefaults.
@Observable
final class Session {
    private(set) var user: User?
    private(set) var apiKey: String?
    var baseURL: URL

    /// Set when the saved key was rejected — shown as a banner on the login screen.
    var sessionExpired = false

    /// The server's LAN/VPN address — the API is not exposed publicly. Override
    /// it under "Advanced" on the login screen to point at your own host.
    static let defaultBaseURL = URL(string: "http://pi.local:8080")!

    private static let userKey = "session.user"
    private static let baseURLKey = "session.baseURL"
    private static let lastEmailKey = "session.lastEmail"

    var isAuthenticated: Bool { apiKey != nil }

    var client: APIClient {
        APIClient(baseURL: baseURL, apiKey: apiKey)
    }

    /// Builds a client from persisted credentials for background work (health
    /// sync) that runs without a live Session. Returns nil if not signed in.
    static func backgroundClient() -> APIClient? {
        guard let key = Keychain.apiKey else { return nil }
        let urlStr = UserDefaults.standard.string(forKey: baseURLKey)
        let url = urlStr.flatMap { URL(string: $0) } ?? defaultBaseURL
        return APIClient(baseURL: url, apiKey: key)
    }

    var lastEmail: String {
        get { UserDefaults.standard.string(forKey: Self.lastEmailKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastEmailKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        if let s = defaults.string(forKey: Self.baseURLKey), let url = URL(string: s) {
            baseURL = url
        } else {
            baseURL = Self.defaultBaseURL
            defaults.set(baseURL.absoluteString, forKey: Self.baseURLKey)
        }
        apiKey = Keychain.apiKey
        if let data = defaults.data(forKey: Self.userKey) {
            user = try? APIClient.decoder.decode(User.self, from: data)
        }

        #if DEBUG
        // Test hooks — let simulator/UI-test launches inject credentials.
        let env = ProcessInfo.processInfo.environment
        if let s = env["PI_TEST_BASE_URL"], let u = URL(string: s) { baseURL = u }
        if let k = env["PI_TEST_API_KEY"] { apiKey = k }
        #endif

        NotificationCenter.default.addObserver(forName: .piUnauthorized, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.expire()
            }
        }
    }

    @MainActor
    func login(email: String, password: String, baseURL: URL) async throws {
        let resp = try await APIClient.login(baseURL: baseURL, email: email, password: password)
        self.baseURL = baseURL
        apiKey = resp.apiKey
        Keychain.apiKey = resp.apiKey
        setUser(resp.user)
        lastEmail = email
        sessionExpired = false
        UserDefaults.standard.set(baseURL.absoluteString, forKey: Self.baseURLKey)
    }

    @MainActor
    func signOut() {
        apiKey = nil
        Keychain.apiKey = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        sessionExpired = false
    }

    /// Saved key was rejected by the server — drop to login with a banner.
    @MainActor
    private func expire() {
        guard isAuthenticated else { return }
        apiKey = nil
        Keychain.apiKey = nil
        sessionExpired = true
    }

    func setUser(_ u: User) {
        user = u
        if let data = try? APIClient.encoder.encode(u) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        }
    }

    func setAPIKey(_ key: String) {
        apiKey = key
        Keychain.apiKey = key
    }

    @MainActor
    func refreshProfile() async {
        guard isAuthenticated else { return }
        if let fresh = try? await client.me() {
            setUser(fresh)
        }
    }
}
