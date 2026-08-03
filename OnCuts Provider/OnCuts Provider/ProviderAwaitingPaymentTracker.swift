import Foundation
import Observation

// MARK: - ProviderAwaitingPaymentTracker

/// Derives operator “waiting” banners from server booking fields under the
/// pay-before-complete model:
/// - **Awaiting payment** — `ACCEPTED` with no `paidAt` (consumer must pay to lock)
/// - **Awaiting tip** — `COMPLETED` with no `tipDecidedAt`
///
/// The legacy session-local “Request Payment” ID set is retained only so existing
/// dashboard `.onReceive` refresh wiring keeps working; reconcile now rebuilds from
/// the latest list fetch.
@Observable
@MainActor
final class ProviderAwaitingPaymentTracker {
    static let shared = ProviderAwaitingPaymentTracker()

    static let didChangeNotification = Notification.Name("ProviderAwaitingPaymentTrackerDidChange")

    /// IDs currently shown in waiting banners (service pay + tip). Updated by `reconcile`.
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
                .filter { $0.isAwaitingServicePayment || $0.isAwaitingTip }
                .map(\.id)
        )
    }

    static func isAwaitingServicePayment(_ booking: SimpleBookingDTO) -> Bool {
        booking.isAwaitingServicePayment
    }

    static func isAwaitingTip(_ booking: SimpleBookingDTO) -> Bool {
        booking.isAwaitingTip
    }

    /// @available — old name; true when either service pay or tip is outstanding.
    static func isAwaitingEligible(status: String, paidAt: Date? = nil) -> Bool {
        if paidAt != nil {
            // Tip-wait uses COMPLETED + tipDecidedAt; status alone is insufficient.
            return false
        }
        let s = status.uppercased()
        return s == "ACCEPTED" || s == "COMPLETED"
    }

    static func awaitingPaymentBookings(from bookings: [SimpleBookingDTO]) -> [SimpleBookingDTO] {
        bookings.filter(\.isAwaitingServicePayment)
    }

    static func awaitingTipBookings(from bookings: [SimpleBookingDTO]) -> [SimpleBookingDTO] {
        bookings.filter(\.isAwaitingTip)
    }

    static func hasCompletedAwaitingPayment(in bookings: [SimpleBookingDTO]) -> Bool {
        bookings.contains(where: \.isAwaitingTip)
    }
}
