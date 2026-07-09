//
//  OnCutsEnvironment.swift
//  OnCutsModule
//

import Foundation

/// API host configuration for the OnCuts backend.
public enum OnCutsEnvironment: Sendable, Hashable {
    /// Production API (`https://oncuts.com/api/v1`).
    case production
    /// Override for staging or local development.
    case custom(baseURL: URL)

    public var apiBaseURL: URL {
        switch self {
        case .production:
            return URL(string: "https://oncuts.com/api/v1")!
        case .custom(let url):
            return url
        }
    }
}
