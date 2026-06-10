//
//  AuthInterceptor.swift
//  CampusCutsModule
//
//  Applies Bearer auth to outgoing requests, preferring Keychain tokens when present.
//

import Foundation

/// Prepares authorized `URLRequest` values for the CampusCuts API.
internal struct AuthInterceptor {
    private let session: UserSessionProtocol

    init(session: UserSessionProtocol) {
        self.session = session
    }

    func apply(to url: URL, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = Self.bearerToken(from: session)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private static func bearerToken(from session: UserSessionProtocol) -> String {
        if let keychain = CampusCutsAuthTokenStore.loadAccessToken(), !keychain.isEmpty {
            return keychain
        }
        return session.accessToken
    }
}
