import Foundation
import Security

/// Minimal Keychain wrapper for storing API keys.
enum KeychainStore {
    private static let service = "WatchLLM"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Saves the value, replacing any previous one. An empty value deletes the entry.
    static func save(_ value: String, account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)

        let sanitized = value.filter { !$0.isWhitespace }
        guard !sanitized.isEmpty else { return }

        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(sanitized.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
