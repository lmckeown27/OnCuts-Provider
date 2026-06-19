//
//  UserSessionProtocol.swift
//  CampusCutsModule
//
//  Contract that the Shell app's UserSession must conform to.
//  This module doesn't care HOW the user logged in, only that
//  it receives valid tokens and user info.
//

import Foundation

/// Protocol defining the user session data this module needs from the Shell
public protocol UserSessionProtocol {
    /// JWT access token for API authentication
    var accessToken: String { get }
    
    /// Unique user identifier
    var userId: String { get }
    
    /// User's email address
    var userEmail: String { get }
    
    /// User's display name
    var userName: String { get }
    
    /// User's role: CONSUMER, BARBER, or ADMIN (legacy CAMPUS_MANAGER should be treated as BARBER)
    var userRole: String { get }

    /// When the Shell stores `/me`, use this to expose admin dashboard entry points.
    var isAdmin: Bool { get }
    
    /// Refresh token for obtaining new access tokens (optional)
    var refreshToken: String? { get }
    
    /// Callback to refresh the access token when expired
    func refreshAccessToken() async throws -> String
    
    /// Callback to notify Shell that user wants to logout (default: no-op).
    func requestLogout()
}

/// Extension with default implementations for optional methods
public extension UserSessionProtocol {
    var refreshToken: String? { nil }

    /// Default when the Shell does not persist `/me` admin flag.
    var isAdmin: Bool { false }
    
    func refreshAccessToken() async throws -> String {
        // Default: return current token (Shell should override)
        return accessToken
    }

    func requestLogout() {}
}

