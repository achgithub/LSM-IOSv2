import Foundation
import Security

/// Stable anonymous device identifier for cloud lifecycle management.
/// Generated once on first cloud use and stored in the Keychain — it acts as
/// an ownership credential for cloud backup/lifecycle, so UserDefaults (readable
/// by backup tools) is not an appropriate store.
///
/// Migration: if a value exists in UserDefaults under the old key, it is moved
/// to the Keychain on first access and deleted from UserDefaults.
enum ManagerToken {
    private static let keychainService = "com.sportsmanager.LSM"
    private static let keychainAccount = "managerCloudToken"
    private static let legacyDefaultsKey = "lsmManagerCloudToken"

    static var current: String {
        if let existing = keychainValue() { return existing }
        // Migrate from UserDefaults if present.
        if let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey) {
            save(legacy)
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            return legacy
        }
        let new = UUID().uuidString.lowercased()
        save(new)
        return new
    }

    private static func keychainValue() -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      keychainService,
            kSecAttrAccount as String:      keychainAccount,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    private static func save(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      keychainService,
            kSecAttrAccount as String:      keychainAccount,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String:        data,
        ]
        SecItemDelete(query as CFDictionary) // remove any prior value
        SecItemAdd(query as CFDictionary, nil)
    }
}
