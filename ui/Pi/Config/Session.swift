import Foundation
import Observation

/// App-wide auth + identity state. The API key lives in the Keychain;
/// everything else persists in UserDefaults.
@Observable
final class Session {
    private(set) var user: User?
    private(set) var apiKey: String?

    /// Always the one server. Kept as a property rather than used inline so the
    /// DEBUG test hook below can still point a simulator somewhere else.
    private(set) var baseURL = Session.defaultBaseURL

    /// Set when the saved key was rejected — shown as a banner on the login screen.
    var sessionExpired = false

    /// The only server this app talks to.
    static let defaultBaseURL = URL(string: "https://api.srijanpokharel.com")!

    private static let userKey = "session.user"
    /// No longer written. Read once at launch only to delete it — builds before
    /// the address became fixed persisted a LAN URL here, and with the override
    /// gone there'd be no way to escape a stale one.
    private static let legacyBaseURLKey = "session.baseURL"
    private static let lastEmailKey = "session.lastEmail"

    var isAuthenticated: Bool { apiKey != nil }

    var client: APIClient {
        APIClient(baseURL: baseURL, apiKey: apiKey)
    }

    /// Builds a client from persisted credentials for background work (health
    /// sync) that runs without a live Session. Returns nil if not signed in.
    static func backgroundClient() -> APIClient? {
        guard let key = Keychain.apiKey else { return nil }
        return APIClient(baseURL: defaultBaseURL, apiKey: key)
    }

    var lastEmail: String {
        get { UserDefaults.standard.string(forKey: Self.lastEmailKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastEmailKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.legacyBaseURLKey)
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
    func login(email: String, password: String) async throws {
        let resp = try await APIClient.login(baseURL: baseURL, email: email, password: password)
        apiKey = resp.apiKey
        Keychain.apiKey = resp.apiKey
        setUser(resp.user)
        lastEmail = email
        sessionExpired = false
    }

    /// Creates an account and signs straight into it.
    @MainActor
    func signUp(email: String, password: String, displayName: String,
                inviteCode: String) async throws {
        let resp = try await APIClient.signup(baseURL: baseURL, email: email, password: password,
                                              displayName: displayName, inviteCode: inviteCode)
        apiKey = resp.apiKey
        Keychain.apiKey = resp.apiKey
        setUser(resp.user)
        lastEmail = email
        sessionExpired = false
    }

    /// Deletes the account server-side, then clears local state. Throws
    /// without signing out if the server refuses — deleting the last admin,
    /// for instance.
    @MainActor
    func deleteAccount() async throws {
        try await client.deleteAccount()
        signOut()
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
