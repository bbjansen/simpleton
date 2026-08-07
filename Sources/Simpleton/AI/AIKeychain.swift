// Sources/Simpleton/AI/AIKeychain.swift
import Foundation
import Security
import SimpletonCore

/// Keychain storage for AI API keys. Separate from SSH KeychainManager.
enum AIKeychain {

    private static let service = "com.simpleton.ai"

    static func storeAPIKey(_ key: String, for provider: AIProvider) -> Bool {
        let account = "apiKey.\(provider.rawValue)"
        guard let data = key.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Upsert: SecItemUpdate the value in place if the item exists, otherwise SecItemAdd. This
        // deliberately avoids the old delete+add: on the file-based (login) keychain, SecItemDelete
        // is gated by an owner check tied to the creating binary's code signature, so a delete of an
        // item created by an *earlier build* fails with errSecInvalidOwnerEdit (-25244) and the
        // re-add then hits errSecDuplicateItem — silently dropping the new key. SecItemUpdate is not
        // subject to that owner check, so overwrites succeed reliably. (See TN3137.)
        let updateStatus = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    static func retrieveAPIKey(for provider: AIProvider) -> String? {
        let account = "apiKey.\(provider.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(for provider: AIProvider) {
        let account = "apiKey.\(provider.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Migrate an existing key to AfterFirstUnlock accessibility — at most once per provider.
    ///
    /// The previous implementation read the key (triggering a Keychain prompt) and then
    /// deleted + re-added the item on EVERY launch. The re-add gave the new item a fresh
    /// access-control list, destroying any "always allow" grant the user had given — so
    /// they were prompted for the password on every single launch. SecItemUpdate changes
    /// only the accessibility attribute in place: it does not read the secret and preserves
    /// the item's ACL. A one-shot flag stops it from running again once migrated.
    static func migrateAccessibility(for provider: AIProvider) {
        let flagKey = "aiKeychain.migrated.\(provider.rawValue)"
        if UserDefaults.standard.bool(forKey: flagKey) { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "apiKey.\(provider.rawValue)",
        ]
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            UserDefaults.standard.set(true, forKey: flagKey)
        }
    }

    /// Checks whether a key is stored without retrieving its data (avoids Keychain auth prompt).
    static func hasAPIKey(for provider: AIProvider) -> Bool {
        let account = "apiKey.\(provider.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
