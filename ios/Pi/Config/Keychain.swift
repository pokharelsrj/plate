import Foundation
import Security

/// Minimal keychain wrapper for the API keys.
enum Keychain {
    private static let service = "com.srijanpokharel.pi.api"
    private static let account = "primary"
    private static let financeAccount = "finance"

    /// Key for the Go backend (issued at login).
    static var apiKey: String? {
        get { read(account) }
        set { write(account, newValue) }
    }

    /// Key for the separate finance backend (set in Settings → Finance).
    static var financeKey: String? {
        get { read(financeAccount) }
        set { write(financeAccount, newValue) }
    }

    private static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ account: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
