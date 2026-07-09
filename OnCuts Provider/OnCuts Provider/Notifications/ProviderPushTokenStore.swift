import Foundation

/// Thread-safe `UserDefaults` wrapper for everything push-related the provider app needs to
/// remember across launches.
///
/// What lives here:
///   * **`apnsHexToken`** — the most recent APNs device token in hex form (the wire shape the
///     CampusCuts backend stores in `notifications_device_registrations`).
///   * **Last successful registration tuple** (`token`, `jwtFingerprint`, `registeredAt`) — used
///     by `ProviderPushDeviceRegistration` to throttle redundant `POST /notifications/register-device`
///     calls. Re-registering the same token with the same JWT within 120s is a no-op.
///   * **`logoutSince`** — monotonically-increasing timestamp used by the unregister DELETE so
///     that if a sign-out + sign-in race overlaps, the backend can ignore stale unregisters.
///
/// We intentionally store a **fingerprint** of the JWT (SHA-256 prefix) rather than the raw
/// token; the JWT itself is stored separately by `CampusCutsAuthTokenStore` and rotated on
/// sign-in/sign-out. Storing the fingerprint lets us answer "is this the same login?" without
/// duplicating the auth token in two places.
enum ProviderPushTokenStore {
    private static let suite = UserDefaults.standard

    private enum Key {
        static let apnsHexToken = ProviderAppBranding.UserDefaultsKey.pushAPNsHexToken
        static let lastRegisteredToken = ProviderAppBranding.UserDefaultsKey.pushLastRegisteredToken
        static let lastRegisteredJWTFingerprint = ProviderAppBranding.UserDefaultsKey.pushLastRegisteredJWTFingerprint
        static let lastRegisteredAt = ProviderAppBranding.UserDefaultsKey.pushLastRegisteredAt
        static let logoutSince = ProviderAppBranding.UserDefaultsKey.pushLogoutSince
    }

    // MARK: - APNs hex token

    static var apnsHexToken: String? {
        get { suite.string(forKey: Key.apnsHexToken)?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        set {
            if let value = newValue?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                suite.set(value, forKey: Key.apnsHexToken)
            } else {
                suite.removeObject(forKey: Key.apnsHexToken)
            }
        }
    }

    // MARK: - Last successful registration metadata

    struct LastRegistration: Equatable {
        let token: String
        let jwtFingerprint: String
        let registeredAt: Date
    }

    static var lastRegistration: LastRegistration? {
        guard let token = suite.string(forKey: Key.lastRegisteredToken)?.nilIfEmpty,
              let fp = suite.string(forKey: Key.lastRegisteredJWTFingerprint)?.nilIfEmpty
        else { return nil }
        let ts = suite.double(forKey: Key.lastRegisteredAt)
        guard ts > 0 else { return nil }
        return LastRegistration(token: token, jwtFingerprint: fp, registeredAt: Date(timeIntervalSince1970: ts))
    }

    static func setLastRegistration(token: String, jwtFingerprint: String, at: Date = Date()) {
        suite.set(token, forKey: Key.lastRegisteredToken)
        suite.set(jwtFingerprint, forKey: Key.lastRegisteredJWTFingerprint)
        suite.set(at.timeIntervalSince1970, forKey: Key.lastRegisteredAt)
    }

    static func clearLastRegistration() {
        suite.removeObject(forKey: Key.lastRegisteredToken)
        suite.removeObject(forKey: Key.lastRegisteredJWTFingerprint)
        suite.removeObject(forKey: Key.lastRegisteredAt)
    }

    // MARK: - Logout watermark (race-safe unregister)

    /// Always-increasing timestamp the unregister DELETE sends so the backend can ignore stale
    /// requests if a sign-in fires before a previous sign-out's DELETE arrives.
    static var logoutSince: Date {
        let stored = suite.double(forKey: Key.logoutSince)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : Date(timeIntervalSince1970: 0)
    }

    /// Stamps a fresh "logged out at" time. Always uses the larger of `now` and the existing
    /// value to ensure monotonic ordering even under clock skew.
    @discardableResult
    static func stampLogoutSince(_ now: Date = Date()) -> Date {
        let existing = suite.double(forKey: Key.logoutSince)
        let candidate = max(existing, now.timeIntervalSince1970)
        suite.set(candidate, forKey: Key.logoutSince)
        return Date(timeIntervalSince1970: candidate)
    }
}

// MARK: - Helpers

private extension String {
    /// `nil` when the string is empty; otherwise `self`. Keeps stored-empty values from
    /// looking like a valid token to the rest of the registration flow.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
