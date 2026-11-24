import Foundation
import Security

/// Keychain storage for the sign in session (Sprint 6, Story S14). The
/// Apple user id, the display name and email Apple shared on the first
/// sign in, and the Supabase session tokens live here and nowhere else:
/// never in SwiftData, never in UserDefaults, never in source code.
/// Items are readable after the first unlock, so a background sync can
/// use them without the phone being unlocked.
enum KeychainHelper {
    static let service = "com.lexissapphirestudio.coffeeshopapp"

    enum Key: String, CaseIterable {
        case appleUserID
        case appleDisplayName
        case appleEmail
        case supabaseAccessToken
        case supabaseRefreshToken
        case supabaseUserID
        /// The access token expiry, stored as a time interval string.
        case supabaseTokenExpiry
    }

    @discardableResult
    static func save(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        guard status == errSecItemNotFound else { return false }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func string(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(for key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Clears every session item: sign out and account deletion.
    static func deleteAllSessionItems() {
        for key in Key.allCases {
            delete(for: key)
        }
    }
}
