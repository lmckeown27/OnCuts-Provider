import Foundation
import Observation

// MARK: - ProviderAwaitingPaymentTracker

/// Derives operator “waiting” banners from server booking fields, branched on
/// `ProviderFrontendConfigStore.paymentTimingMode`:
/// - **on_accept** — unpaid `ACCEPTED` (service pay) or tip-pending `COMPLETED`
/// - **after_complete** — unpaid `COMPLETED` only (confirmed `ACCEPTED` is not waiting)
///
/// The legacy session-local “Request Payment” ID set is retained only so existing
/// dashboard `.onReceive` refresh wiring keeps working; reconcile now rebuilds from
/// the latest list fetch.
@Observable
@MainActor
final class ProviderAwaitingPaymentTracker {
    static let shared = ProviderAwaitingPaymentTracker()

    static let didChangeNotification = Notification.Name("ProviderAwaitingPaymentTrackerDidChange")

    /// IDs currently shown in waiting banners. Updated by `reconcile`.
    private(set) var requestedIds: Set<String> = [] {
        didSet {
            guard oldValue != requestedIds else { return }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    private init() {}

    func markRequested(_ id: String) {
        guard !id.isEmpty else { return }
        requestedIds.insert(id)
    }

    func clearRequest(for id: String) {
        requestedIds.remove(id)
    }

    func clearAll() {
        requestedIds.removeAll()
    }

    /// Rebuild waiting IDs from the latest barber booking list.
    func reconcile(with bookings: [SimpleBookingDTO]) {
        requestedIds = Set(
            bookings
                .filter(\.countsTowardAwaitingPaymentBadge)
                .map(\.id)
        )
    }

    static func isAwaitingServicePayment(_ booking: SimpleBookingDTO) -> Bool {
        booking.isAwaitingServicePayment
    }

    static func isAwaitingTip(_ booking: SimpleBookingDTO) -> Bool {
        booking.isAwaitingTip
    }

    /// @available — old name; prefer `countsTowardAwaitingPaymentBadge`.
    static func isAwaitingEligible(status: String, paidAt: Date? = nil) -> Bool {
        if paidAt != nil { return false }
        let s = status.uppercased()
        switch ProviderPaymentTiming.mode {
        case .onAccept:
            return s == "ACCEPTED" || s == "COMPLETED"
        case .afterComplete:
            return s == "COMPLETED"
        }
    }

    static func awaitingPaymentBookings(from bookings: [SimpleBookingDTO]) -> [SimpleBookingDTO] {
        bookings.filter(\.countsTowardAwaitingPaymentBadge)
    }

    static func awaitingTipBookings(from bookings: [SimpleBookingDTO]) -> [SimpleBookingDTO] {
        bookings.filter(\.isAwaitingTip)
    }

    static func hasCompletedAwaitingPayment(in bookings: [SimpleBookingDTO]) -> Bool {
        bookings.contains(where: \.isCompletedAwaitingConsumerPayment)
    }
}
