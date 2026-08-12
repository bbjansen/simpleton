// Sources/SimpletonCore/Core/CredentialStore.swift
import Foundation
import Security

/// Keychain-backed store for `ConnectionSecret`s, keyed by a `Connection`'s id. Generalizes the
/// SSH-only `KeychainManager` (service "com.simpleton.ssh") to a separate service for the generic
/// client-viewer connections. The secret is JSON-encoded and stored as the item's data blob.
public enum CredentialStore {

    private static let service = "com.simpleton.connection"

    @discardableResult
    public static func store(_ secret: ConnectionSecret, for id: UUID) -> Bool {
        guard let data = try? JSONEncoder().encode(secret) else { return false }
        let account = id.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Upsert: update in place if present, else add — mirrors KeychainManager's robustness
        // against errSecInvalidOwnerEdit from items created by an earlier build's signature.
        let updateStatus = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            addQuery[kSecAttrLabel as String] = "Simpleton Connection: \(account)"
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    public static func secret(for id: UUID) -> ConnectionSecret? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ConnectionSecret.self, from: data)
    }

    @discardableResult
    public static func delete(for id: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public static func has(id: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
}
