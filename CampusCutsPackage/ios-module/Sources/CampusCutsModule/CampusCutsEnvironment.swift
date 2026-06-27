//
//  CampusCutsEnvironment.swift
//  CampusCutsModule
//

import Foundation

/// API host configuration for the CampusCuts backend.
public enum CampusCutsEnvironment: Sendable, Hashable {
    /// Production API (`https://avilaplatforms.com/api/v1`).
    case production
    /// Override for staging or local development.
    case custom(baseURL: URL)

    public var apiBaseURL: URL {
        switch self {
        case .production:
            return URL(string: "https://avilaplatforms.com/api/v1")!
        case .custom(let url):
            return url
        }
    }
}
