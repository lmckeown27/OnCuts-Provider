import Foundation
import UIKit
import UserNotifications

/// Parses APNs payloads and translates them into in-app `Notification.Name` posts.
///
/// Two payload shapes are accepted:
///   * Flat:  `{ "aps": { … }, "type": "message", "conversationId": 42, … }`
///   * Nested: `{ "aps": { … }, "data": { "type": "message", "conversationId": 42, … } }`
///
/// Nested keys are flattened so callers always read from a single dictionary. Numeric ids are
/// coerced through string → int when needed (consumer + backend payloads have used both shapes
/// historically).
@MainActor
enum ProviderPushPayloadRouter {
    /// Routing reason — exposed for debugging / future analytics, not for navigation logic.
    enum DispatchResult {
        case messaging(conversationId: Int)
        case bookingDetail(bookingId: String)
        case bookingsRefresh
        case requestsRefresh
        case noop
    }

    /// Refreshes in-app lists and badges when a push arrives in the **foreground** (banner only).
    /// Never opens Messages, the bookings sheet, or booking detail — navigation waits for a tap.
    static func refreshFromForegroundDelivery(userInfo: [AnyHashable: Any]) {
        let flat = flatten(userInfo: userInfo)
        let type = (flat["type"] as? String)?.lowercased() ?? ""

        let isBookingRequest = type.contains("booking_request") || type.contains("request_")
        let isBookingLifecycle = type.hasPrefix("booking_")
            || type.contains("payment")
            || type.contains("reminder")
            || type.contains("confirmation")
            || type.contains("cancel")
            || type.contains("complete")
        let isMessage = type == "message" || type == "new_message"

        if isMessage || isBookingRequest || isBookingLifecycle || type == "badge_update" {
            NotificationCenter.default.post(
                name: .providerMessagingUnreadCountShouldRefresh,
                object: nil
            )
        }

        if isBookingRequest || isBookingLifecycle {
            NotificationCenter.default.post(name: .providerBookingsListShouldRefresh, object: nil)
        }

        if isBookingRequest {
            NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
        }

        if isMessage, let conversationId = intValue(flat["conversationId"]) {
            NotificationCenter.default.post(
                name: .providerMessagingConversationShouldRefresh,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        }
    }

    /// Posts one or more `Notification.Name`s based on payload contents. Returns the primary
    /// dispatch reason (purely informational). Use for notification **taps** and cold-start routing.
    @discardableResult
    static func dispatch(userInfo: [AnyHashable: Any]) -> DispatchResult {
        let flat = flatten(userInfo: userInfo)
        let type = (flat["type"] as? String)?.lowercased() ?? ""

        // 1. Messaging push — primary signal is `conversationId`.
        if type == "message" || type == "new_message" {
            if let conversationId = intValue(flat["conversationId"]) {
                NotificationCenter.default.post(
                    name: .interaOpenMessagingConversation,
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
                NotificationCenter.default.post(
                    name: .providerMessagingUnreadCountShouldRefresh,
                    object: nil
                )
                return .messaging(conversationId: conversationId)
            }
            NotificationCenter.default.post(
                name: .providerMessagingUnreadCountShouldRefresh,
                object: nil
            )
            return .noop
        }

        // 2. Booking-related push — refresh lists and route into the unified Requests inbox.
        let isBookingRequest = type.contains("booking_request") || type.contains("request_")
        let isBookingLifecycle = type.hasPrefix("booking_")
            || type.contains("payment")
            || type.contains("reminder")
            || type.contains("confirmation")
            || type.contains("cancel")
            || type.contains("complete")

        if isBookingRequest || isBookingLifecycle {
            NotificationCenter.default.post(name: .providerBookingsListShouldRefresh, object: nil)
            if isBookingRequest {
                NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
                NotificationCenter.default.post(name: .interaOpenRequestsInbox, object: nil)
                return .requestsRefresh
            }
            if let bookingId = stringValue(flat["bookingId"]) {
                NotificationCenter.default.post(
                    name: .interaOpenBookingDetail,
                    object: nil,
                    userInfo: ["bookingId": bookingId]
                )
                return .bookingDetail(bookingId: bookingId)
            }
            return .bookingsRefresh
        }

        // 3. Unknown type but contains an id we recognize — opportunistically route on the id.
        if let conversationId = intValue(flat["conversationId"]) {
            NotificationCenter.default.post(
                name: .interaOpenMessagingConversation,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
            return .messaging(conversationId: conversationId)
        }
        if let bookingId = stringValue(flat["bookingId"]) {
            NotificationCenter.default.post(
                name: .interaOpenBookingDetail,
                object: nil,
                userInfo: ["bookingId": bookingId]
            )
            return .bookingDetail(bookingId: bookingId)
        }

        return .noop
    }

    /// Convenience wrapper for `UNNotificationResponse` (taps + actions).
    static func dispatch(response: UNNotificationResponse) {
        dispatch(userInfo: response.notification.request.content.userInfo)
    }

    /// Convenience wrapper for cold-start payloads delivered via `launchOptions`.
    static func dispatch(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] else { return }
        dispatch(userInfo: userInfo)
    }

    // MARK: - Flatten + coerce helpers

    /// Returns a dictionary where any nested `data: { … }` keys live at the top level alongside
    /// the original. Top-level keys win over nested ones if there's a collision — matches the
    /// consumer app's behavior.
    private static func flatten(userInfo: [AnyHashable: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        if let nested = userInfo["data"] as? [AnyHashable: Any] {
            for (k, v) in nested {
                if let key = k as? String { result[key] = v }
            }
        }
        for (k, v) in userInfo {
            if let key = k as? String, key != "aps", key != "data" {
                result[key] = v
            }
        }
        return result
    }

    /// Accepts `Int`, `Int64`, `String` (numeric), or `NSNumber` — APNs payloads inconsistently
    /// JSON-encode numeric ids depending on the server's serializer.
    private static func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let v as Int: return v
        case let v as Int64: return Int(v)
        case let v as NSNumber: return v.intValue
        case let v as String: return Int(v.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// Accepts `String`, `NSNumber`, or `UUID`. Returns `nil` for `NSNull` and empty strings.
    private static func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let v as String:
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let v as NSNumber:
            return v.stringValue
        case let v as UUID:
            return v.uuidString
        default:
            return nil
        }
    }
}
