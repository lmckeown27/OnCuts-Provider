//
//  KeychainManager.swift
//  CampusCuts
//
//  Secure storage for authentication tokens and sensitive data
//  Transferred from CampusKinect with CampusCuts adaptations
//

import Foundation
import Security

// MARK: - Keychain Keys
struct KeychainKeys {
    static let accessToken = "campuscuts.accessToken"
    static let refreshToken = "campuscuts.refreshToken"
    static let userID = "campuscuts.userID"
    static let userType = "campuscuts.userType" // "student" or "barber"
    static let biometricEnabled = "campuscuts.biometricEnabled"
}

// MARK: - Keychain Manager
class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.campuscuts.ios"
    
    private init() {}
    
    // MARK: - Generic Keychain Operations
    private func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
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
    
    private func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - String Operations
    func saveString(_ string: String, forKey key: String) -> Bool {
        guard let data = string.data(using: .utf8) else {
            return false
        }
        return save(key: key, data: data)
    }
    
    func getString(forKey key: String) -> String? {
        guard let data = load(key: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    func deleteString(forKey key: String) -> Bool {
        return delete(key: key)
    }
    
    // MARK: - Authentication Token Methods
    func saveAccessToken(_ token: String) async -> Bool {
        return saveString(token, forKey: KeychainKeys.accessToken)
    }
    
    func getAccessToken() async -> String? {
        return getString(forKey: KeychainKeys.accessToken)
    }
    
    func saveRefreshToken(_ token: String) async -> Bool {
        return saveString(token, forKey: KeychainKeys.refreshToken)
    }
    
    func getRefreshToken() async -> String? {
        return getString(forKey: KeychainKeys.refreshToken)
    }
    
    func saveUserID(_ userID: String) async -> Bool {
        return saveString(userID, forKey: KeychainKeys.userID)
    }
    
    func getUserID() async -> String? {
        return getString(forKey: KeychainKeys.userID)
    }
    
    func saveUserType(_ userType: String) async -> Bool {
        return saveString(userType, forKey: KeychainKeys.userType)
    }
    
    func getUserType() async -> String? {
        return getString(forKey: KeychainKeys.userType)
    }
    
    // MARK: - Biometric Settings
    func setBiometricEnabled(_ enabled: Bool) -> Bool {
        let value = enabled ? "true" : "false"
        return saveString(value, forKey: KeychainKeys.biometricEnabled)
    }
    
    func isBiometricEnabled() -> Bool {
        return getString(forKey: KeychainKeys.biometricEnabled) == "true"
    }
    
    // MARK: - Clear All Data
    func clearAllTokens() async -> Bool {
        let accessTokenDeleted = deleteString(forKey: KeychainKeys.accessToken)
        let refreshTokenDeleted = deleteString(forKey: KeychainKeys.refreshToken)
        let userIDDeleted = deleteString(forKey: KeychainKeys.userID)
        let userTypeDeleted = deleteString(forKey: KeychainKeys.userType)
        
        return accessTokenDeleted && refreshTokenDeleted && userIDDeleted && userTypeDeleted
    }
    
    // MARK: - Keychain Availability Check
    func isKeychainAvailable() -> Bool {
        let testKey = "keychain_test"
        let testValue = "test"
        
        let saveResult = saveString(testValue, forKey: testKey)
        if saveResult {
            _ = deleteString(forKey: testKey)
        }
        
        return saveResult
    }
}

