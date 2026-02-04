import Foundation
import Security

/// Secure storage utility using iOS Keychain
///
/// SECURITY: Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly for sensitive data,
/// which ensures data is only accessible when the device is unlocked and prevents
/// backup/restore to other devices.
///
/// Usage:
/// ```
/// // Store a value
/// try KeychainHelper.save("user@example.com", forKey: .userEmail)
///
/// // Retrieve a value
/// let email = KeychainHelper.load(forKey: .userEmail)
///
/// // Delete a value
/// KeychainHelper.delete(forKey: .userEmail)
/// ```
enum KeychainHelper {

    // MARK: - Keychain Keys

    /// Predefined keys for Keychain storage
    enum Key: String {
        case userEmail = "com.hoidma.userEmail"
        case sessionToken = "com.hoidma.sessionToken"
        case refreshToken = "com.hoidma.refreshToken"
    }

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case encodingFailed
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Item already exists in Keychain"
            case .itemNotFound:
                return "Item not found in Keychain"
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            case .encodingFailed:
                return "Failed to encode data for Keychain"
            case .decodingFailed:
                return "Failed to decode data from Keychain"
            }
        }
    }

    // MARK: - Service Identifier

    private static let service = Bundle.main.bundleIdentifier ?? "com.hoidma"

    // MARK: - Public API

    /// Save a string value to Keychain
    /// - Parameters:
    ///   - value: The string value to store
    ///   - key: The key to store it under
    /// - Throws: KeychainError if save fails
    static func save(_ value: String, forKey key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data, forKey: key)
    }

    /// Save data to Keychain
    /// - Parameters:
    ///   - data: The data to store
    ///   - key: The key to store it under
    /// - Throws: KeychainError if save fails
    static func save(_ data: Data, forKey key: Key) throws {
        // Build query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            // SECURITY: Only accessible when device is unlocked, not backed up
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Try to add the item
        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue
            ]

            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)

            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Load a string value from Keychain
    /// - Parameter key: The key to retrieve
    /// - Returns: The stored string, or nil if not found
    static func load(forKey key: Key) -> String? {
        guard let data = loadData(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Load data from Keychain
    /// - Parameter key: The key to retrieve
    /// - Returns: The stored data, or nil if not found
    static func loadData(forKey key: Key) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    /// Delete a value from Keychain
    /// - Parameter key: The key to delete
    /// - Returns: true if deleted (or didn't exist), false on error
    @discardableResult
    static func delete(forKey key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Success or item not found are both acceptable
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if a value exists in Keychain
    /// - Parameter key: The key to check
    /// - Returns: true if the key exists
    static func exists(forKey key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Delete all items for this app from Keychain
    /// Use with caution - this removes all stored credentials
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        SecItemDelete(query as CFDictionary)
    }
}
