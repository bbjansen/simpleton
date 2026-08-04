// Sources/Simpleton/KeychainManager.swift
import Foundation
import Security

enum KeychainManager {

    private static let service = "com.simpleton.ssh"

    /// Store a password in the Keychain for a given bookmark ID.
    static func storePassword(_ password: String, for bookmarkID: UUID) -> Bool {
        let account = bookmarkID.uuidString
        guard let data = password.data(using: .utf8) else { return false }

        // Delete existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new entry
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrLabel as String: "Simpleton SSH: \(account)",
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve a password from the Keychain for a given bookmark ID.
    static func retrievePassword(for bookmarkID: UUID) -> String? {
        let account = bookmarkID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
            let data = result as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return password
    }

    /// Delete a stored password for a bookmark ID.
    static func deletePassword(for bookmarkID: UUID) -> Bool {
        let account = bookmarkID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if a password exists for a bookmark ID (without retrieving it).
    static func hasPassword(for bookmarkID: UUID) -> Bool {
        let account = bookmarkID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }
}
