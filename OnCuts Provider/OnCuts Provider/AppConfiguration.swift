import Foundation

/// REST and messaging origins for OnCuts Provider.
/// Third-party auth URLs mirror the consumer app (`AuthBackendVerification` uses these, not hard-coded hosts).
enum AppConfiguration {
    /// `https://oncuts.com/api/v1` — trailing path only; callers append `/bookings-simple`, etc.
    static var apiV1BaseURL: URL {
        if let override = ProcessInfo.processInfo.environment["CAMPUSCUTS_API_BASE"],
           let url = URL(string: override.trimmingCharacters(in: .whitespacesAndNewlines)),
           !override.isEmpty {
            return url
        }
        return URL(string: "https://oncuts.com/api/v1")!
    }

    /// Socket.IO origin (scheme + host, no `/api/v1`).
    static var messagingSocketOriginURL: URL {
        if let override = ProcessInfo.processInfo.environment["CAMPUSCUTS_SOCKET_ORIGIN"],
           let url = URL(string: override.trimmingCharacters(in: .whitespacesAndNewlines)),
           !override.isEmpty {
            return url
        }
        return URL(string: "https://oncuts.com")!
    }

    static var apiV1BaseTrimmed: String {
        apiV1BaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Web **provider** dashboard (`BarberPage` parity: schedule, services, availability, payouts, etc.).
    static var providerWebDashboardURL: URL {
        URL(string: "https://oncuts.com/web/barber")!
    }

    /// Public web app origin for shareable client links (uses socket-origin override when set).
    /// Production prefers `www.oncuts.com` to match marketing booking URLs.
    static var webAppOriginURL: URL {
        let origin = messagingSocketOriginURL
        let host = (origin.host ?? "").lowercased()
        if host == "oncuts.com" || host == "www.oncuts.com" {
            return URL(string: "https://www.oncuts.com")!
        }
        return origin
    }

    /// Client booking page for a barber record id (`barbers.id`) — `/web/consumer/book/:barberId`.
    static func consumerBookingPageURL(barberId: String) -> URL? {
        let trimmed = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return webAppOriginURL
            .appendingPathComponent("web")
            .appendingPathComponent("consumer")
            .appendingPathComponent("book")
            .appendingPathComponent(trimmed)
    }

    /// Public legal pages (web `TermsOfServicePage` / `PrivacyPolicyPage` routes).
    static var termsOfServiceURL: URL {
        ProviderAppBranding.termsOfServiceURL
    }

    static var privacyPolicyURL: URL {
        ProviderAppBranding.privacyPolicyURL
    }

    // MARK: - OAuth (same contract as consumer `AuthBackendVerification`)

    /// `POST …/api/v1/auth/google` — JSON `{ "idToken": "<jwt>" }`.
    static var urlAuthGoogle: URL {
        apiV1BaseURL.appendingPathComponent("auth/google")
    }

    /// `POST …/api/v1/auth/apple` — JSON `{ "identityToken": "<jwt>", … }`.
    static var urlAuthApple: URL {
        apiV1BaseURL.appendingPathComponent("auth/apple")
    }

    /// Legacy path when the gateway only forwards `/api/auth/apple` (consumer retries on **404** from `urlAuthApple`).
    static var urlAuthAppleLegacy: URL {
        let api = apiV1BaseURL.deletingLastPathComponent()
        return api.appendingPathComponent("auth/apple")
    }
}
