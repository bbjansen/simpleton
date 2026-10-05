// Sources/Simpleton/AI/AIKeychain.swift
import Foundation
import Security
import SimpletonCore

/// Keychain storage for AI API keys. Separate from SSH KeychainManager.
enum AIKeychain {

    private static let service = "com.simpleton.ai"

    /// Process-lifetime cache of retrieved keys, so the secret is read from the Keychain at most once
    /// per provider per launch. Reading the data (`retrieveAPIKey`) is the only call that can raise
    /// the macOS "allow access" prompt, and it fires on every AI-preferences open (autoLoadModels) and
    /// every request. Without this cache the user is prompted repeatedly; with it, once the key is in
    /// memory (from the first read, a save, or the last launch's "Always Allow"), no further reads —
    /// and no further prompts — happen for the rest of the session.
    private static var memoryCache: [String: String] = [:]
    private static let cacheLock = NSLock()
    private static func cacheStore(_ key: String, account: String) {
        cacheLock.lock()
        memoryCache[account] = key
        cacheLock.unlock()
    }
    private static func cacheLookup(_ account: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return memoryCache[account]
    }
    private static func cacheClear(_ account: String) {
        cacheLock.lock()
        memoryCache[account] = nil
        cacheLock.unlock()
    }

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
        if updateStatus == errSecSuccess {
            cacheStore(key, account: account)
            return true
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess {
                cacheStore(key, account: account)
                return true
            }
            return false
        }
        return false
    }

    static func retrieveAPIKey(for provider: AIProvider) -> String? {
        let account = "apiKey.\(provider.rawValue)"
        // Serve from the in-memory cache first — this is what turns "prompt every time AI prefs open"
        // into "prompt at most once per launch" (and none at all once a grant persists).
        if let cached = cacheLookup(account) { return cached }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let key = String(data: data, encoding: .utf8)
        else { return nil }
        cacheStore(key, account: account)
        return key
    }

    static func deleteAPIKey(for provider: AIProvider) {
        let account = "apiKey.\(provider.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        cacheClear(account)
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
