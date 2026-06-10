import Foundation
import os

private let pushLog = Logger(subsystem: "com.campuscuts.intera-provider", category: "push")

/// Thin wrapper over the two device-registration endpoints exposed by the CampusCuts backend:
///
///   * `POST /api/v1/notifications/register-device`
///   * `DELETE /api/v1/notifications/unregister-device`
///
/// Both expect a Bearer JWT (handled by `CampusCutsHTTPClient`). The token shape we send is the
/// raw **APNs hex token** — even though Firebase Messaging is also configured, server-side
/// delivery is APNs-driven, not FCM-driven.
@MainActor
enum ProviderPushNotificationAPI {
    /// Body: `{ "deviceToken": "<apns-hex>", "platform": "ios" }`. The platform value is the
    /// same string the consumer app sends so the backend doesn't need to disambiguate on the
    /// audience or bundle id.
    static func registerDevice(apnsHexToken: String) async throws {
        // Provider and consumer iOS apps ship with **different bundle identifiers** but share a
        // single CampusCuts backend + `mobile_devices` table. Sending `bundleId` here lets the
        // server set the correct APNs `apns-topic` per device — without it, the server falls
        // back to `process.env.APN_BUNDLE_ID` (typically the consumer bundle) and APN drops
        // provider pushes as topic mismatches.
        //
        // Backward-compatible with older backend builds: unknown JSON keys are ignored.
        var body: [String: Any] = [
            "deviceToken": apnsHexToken,
            "platform": "ios",
        ]
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            body["bundleId"] = bundleId
        }
        do {
            _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
                path: "notifications/register-device",
                method: "POST",
                jsonBody: body
            )
            pushLog.notice("registerDevice: HTTP success (bundleId=\(Bundle.main.bundleIdentifier ?? "<nil>", privacy: .public))")
        } catch {
            pushLog.error("registerDevice: HTTP error — \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Body: `{ "deviceToken": "<apns-hex>", "logoutSince": "<iso8601>" }`. The `logoutSince`
    /// watermark lets the backend ignore stale unregisters when a sign-out and sign-in race —
    /// the newer login's register call wins.
    ///
    /// `deviceToken` is optional because a sign-out can fire before APNs has delivered a token
    /// (rare but possible during first-launch). In that case we send only `logoutSince` and the
    /// server unregisters every record tied to the JWT's user.
    static func unregisterDevice(apnsHexToken: String?, logoutSince: Date) async throws {
        var body: [String: Any] = [
            "logoutSince": ProviderPushNotificationISODate.string(from: logoutSince),
        ]
        if let token = apnsHexToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            body["deviceToken"] = token
        }
        do {
            _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
                path: "notifications/unregister-device",
                method: "DELETE",
                jsonBody: body
            )
            pushLog.notice("unregisterDevice: HTTP success")
        } catch {
            pushLog.error("unregisterDevice: HTTP error — \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}

/// ISO-8601 with fractional seconds — the same format the backend emits and accepts for every
/// other timestamp on this surface (resolution timestamps, logout watermarks).
enum ProviderPushNotificationISODate {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
