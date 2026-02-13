import Foundation
import Security

/// Simple Keychain wrapper for storing gateway tokens securely.
enum KeychainHelper {
    private static let service = "com.clawdbot.deck"

    /// Save a string value to the Keychain.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve a string value from the Keychain.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Convenience keys

extension KeychainHelper {
    /// Save a gateway token for a connection profile.
    static func saveGatewayToken(_ token: String, profileId: String) {
        save(key: "gateway-token-\(profileId)", value: token)
    }

    /// Load a gateway token for a connection profile.
    static func loadGatewayToken(profileId: String) -> String? {
        load(key: "gateway-token-\(profileId)")
    }

    /// Delete a gateway token for a connection profile.
    static func deleteGatewayToken(profileId: String) {
        delete(key: "gateway-token-\(profileId)")
    }
}
