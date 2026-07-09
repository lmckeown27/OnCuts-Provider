import OnCutsModule
import CryptoKit
import Foundation
import os

private let pushLog = Logger(subsystem: ProviderAppBranding.loggerSubsystem, category: "push")

/// Coordinates the lifecycle of the iOS device registration record on the CampusCuts backend.
///
/// Touch points:
///   * `onAPNsTokenReceived(_:)` — called from `OnCutsProviderAppDelegate` once APNs hands us a
///     fresh hex device token. Stores it and re-registers if signed in.
///   * `refreshAfterSignIn()` — called from `ProviderSession` right after `isSignedIn` flips to
///     true (manual sign-in, OAuth verified-session adoption, or bootstrap on launch with a
///     stored JWT). Sends the most recent APNs token to the backend, subject to throttling.
///   * `unregisterOnSignOut()` — called from `ProviderSession.signOut()` **before** the JWT is
///     cleared so the DELETE can attach a Bearer header. Stamps `logoutSince` first so
///     overlapping sign-in races stay consistent.
///
/// Throttle policy: the same (token, JWT fingerprint) tuple is not re-registered within
/// `tokenReregistrationCooldownSeconds`. This matches the consumer app's behavior and avoids
/// hammering the endpoint when, e.g., the user backgrounds + foregrounds the app repeatedly.
@MainActor
enum ProviderPushDeviceRegistration {
    /// Two-minute cooldown on duplicate registrations with identical token + login. Set on the
    /// short side because re-registering is cheap and we'd rather over-register than miss a
    /// token rotation.
    static let tokenReregistrationCooldownSeconds: TimeInterval = 120

    /// Set by `OnCutsProviderAppDelegate` whenever APNs delivers a fresh device token. Stores
    /// the hex token, forwards it to Firebase Messaging if available, then opportunistically
    /// re-registers with the backend.
    static func onAPNsTokenReceived(_ hexToken: String) async {
        let normalized = hexToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            pushLog.error("onAPNsTokenReceived: empty token, ignoring")
            return
        }
        ProviderPushTokenStore.apnsHexToken = normalized
        pushLog.notice("onAPNsTokenReceived: stored token \(maskedToken(normalized), privacy: .public)")

        let hasJWT = OnCutsAuthTokenStore.loadAccessToken()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if hasJWT {
            await registerIfNeeded()
        } else {
            pushLog.notice("onAPNsTokenReceived: no JWT yet, deferring register-device until sign-in")
        }
    }

    /// Called after a successful sign-in (manual, OAuth verified-session, or bootstrap).
    /// Triggers a registration attempt if we have an APNs token cached. If we don't have a
    /// token yet — common on first launch — APNs will eventually fire
    /// `didRegisterForRemoteNotificationsWithDeviceToken` which calls `onAPNsTokenReceived` and
    /// completes the loop.
    static func refreshAfterSignIn() async {
        pushLog.notice("refreshAfterSignIn: triggering register-device check")
        await registerIfNeeded()
    }

    /// Inverse of `refreshAfterSignIn`. Must be called **before** clearing the auth token; the
    /// DELETE needs the Bearer header to identify which device registrations belong to this
    /// account.
    ///
    /// Errors are swallowed: a failed DELETE shouldn't block the user from signing out. The
    /// next sign-in will re-stamp `logoutSince` and re-register.
    static func unregisterOnSignOut() async {
        let stamp = ProviderPushTokenStore.stampLogoutSince()
        ProviderPushTokenStore.clearLastRegistration()
        pushLog.notice("unregisterOnSignOut: posting DELETE /notifications/unregister-device")
        do {
            try await ProviderPushNotificationAPI.unregisterDevice(
                apnsHexToken: ProviderPushTokenStore.apnsHexToken,
                logoutSince: stamp
            )
            pushLog.notice("unregisterOnSignOut: DELETE succeeded")
        } catch {
            pushLog.error("unregisterOnSignOut: DELETE failed — \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Internals

    private static func registerIfNeeded() async {
        guard let token = ProviderPushTokenStore.apnsHexToken else {
            pushLog.notice("registerIfNeeded: skip — no APNs token yet (waiting on iOS to deliver one)")
            return
        }
        guard let jwt = OnCutsAuthTokenStore.loadAccessToken()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !jwt.isEmpty
        else {
            pushLog.notice("registerIfNeeded: skip — no JWT in keychain (user not signed in)")
            return
        }
        let fingerprint = jwtFingerprint(jwt)

        if let last = ProviderPushTokenStore.lastRegistration,
           last.token == token,
           last.jwtFingerprint == fingerprint,
           Date().timeIntervalSince(last.registeredAt) < tokenReregistrationCooldownSeconds
        {
            pushLog.notice("registerIfNeeded: skip — same (token, login) was registered \(Int(Date().timeIntervalSince(last.registeredAt)))s ago")
            return
        }

        pushLog.notice("registerIfNeeded: POST /notifications/register-device token=\(maskedToken(token), privacy: .public)")
        do {
            try await ProviderPushNotificationAPI.registerDevice(apnsHexToken: token)
            ProviderPushTokenStore.setLastRegistration(token: token, jwtFingerprint: fingerprint)
            pushLog.notice("registerIfNeeded: register-device succeeded")
        } catch {
            pushLog.error("registerIfNeeded: register-device FAILED — \(String(describing: error), privacy: .public)")
        }
    }

    /// SHA-256 of the JWT, hex-truncated to 16 chars. Long enough to make collisions effectively
    /// impossible for our throttle comparison, short enough to keep `UserDefaults` tidy. The
    /// raw JWT is never written to disk by this module.
    private static func jwtFingerprint(_ jwt: String) -> String {
        let digest = SHA256.hash(data: Data(jwt.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}

/// `abcd…wxyz (N hex chars)` — never log the full hex token (it's a credential).
private func maskedToken(_ hex: String) -> String {
    guard hex.count >= 12 else { return "<short token>" }
    let head = hex.prefix(6)
    let tail = hex.suffix(6)
    return "\(head)…\(tail) (\(hex.count) chars)"
}
