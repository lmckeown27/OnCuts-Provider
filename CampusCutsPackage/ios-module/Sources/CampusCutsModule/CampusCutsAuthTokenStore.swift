//
//  CampusCutsAuthTokenStore.swift
//  CampusCutsModule
//
//  Keychain storage for JWT access/refresh tokens used with the live API.
//

import Foundation
import Security

/// Persists CampusCuts API tokens in the iOS Keychain (shared by the host app and this module).
public enum CampusCutsAuthTokenStore: Sendable {
    private static let service = "com.campuscuts.module.auth"
    private static let accessAccount = "jwt.access"
    private static let refreshAccount = "jwt.refresh"

    public static func save(accessToken: String, refreshToken: String?) {
        _ = saveString(accessToken, account: accessAccount)
        if let refreshToken {
            _ = saveString(refreshToken, account: refreshAccount)
        } else {
            delete(account: refreshAccount)
        }
    }

    public static func loadAccessToken() -> String? {
        loadString(account: accessAccount)
    }

    public static func loadRefreshToken() -> String? {
        loadString(account: refreshAccount)
    }

    public static func clear() {
        delete(account: accessAccount)
        delete(account: refreshAccount)
    }

    // MARK: - Keychain

    private static func saveString(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func loadString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
