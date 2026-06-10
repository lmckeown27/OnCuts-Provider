import Foundation

// MARK: - In-app routing notifications driven by push payloads
//
// Push handling intentionally never navigates from UIKit/AppDelegate code directly. Instead, the
// app delegate parses the APNs payload, extracts known keys (conversationId, bookingId, …) and
// posts these `Notification.Name`s. SwiftUI / UIKit observers translate the post into the
// appropriate hub state mutation (path mutation, view-model field, list refresh).
//
// Naming intentionally matches the **consumer app** so backend payloads work for both clients
// without per-app routing logic. If you add a new payload type, add the name here and a single
// dispatch in `ProviderPushPayloadRouter`.

extension Notification.Name {
    /// Posted with `userInfo["conversationId"]: Int` when a message push is delivered or tapped.
    /// The dashboard shell observes this to push the inbox + open the right thread.
    static let interaOpenMessagingConversation = Notification.Name("InteraOpenMessagingConversation")

    /// Posted with `userInfo["bookingId"]: String` when a booking *lifecycle* push is tapped
    /// (confirmed, paid, cancelled, etc.). Opens the all-bookings list — not incoming requests.
    static let interaOpenBookingDetail = Notification.Name("InteraOpenBookingDetail")

    /// Posted when a new **booking request** push is tapped (`new_booking_request`, etc.).
    /// The dashboard shell presents the pending-requests inbox sheet.
    static let interaOpenRequestsInbox = Notification.Name("InteraOpenRequestsInbox")

    /// Sent when a booking-related push or socket event implies the list of bookings is stale.
    /// Listeners refresh in place; no navigation side-effect.
    static let providerBookingsListShouldRefresh = Notification.Name("ProviderBookingsListShouldRefresh")

    /// Sent when a booking-request push implies the pending-requests inbox is stale (mirrors web
    /// `consumerBookingsListShouldRefresh` semantics, scoped to the barber's incoming requests).
    static let providerRequestsListShouldRefresh = Notification.Name("ProviderRequestsListShouldRefresh")

    /// Sent when any push implies the messaging unread count may have changed. The dashboard
    /// header observes this to refetch `/messages/unread-count` (or list conversations + sum).
    static let providerMessagingUnreadCountShouldRefresh = Notification.Name("ProviderMessagingUnreadCountShouldRefresh")
}
