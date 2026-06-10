import Foundation
import Observation

// MARK: - ProviderAwaitingPaymentTracker

/// In-memory store of bookings the *current session* has locally marked as having a
/// pending payment request.
///
/// **Why this exists.** The backend's `POST /bookings-simple/:id/request-payment`
/// endpoint transitions the booking's `status` from `ACCEPTED` directly to `COMPLETED`
/// and stamps `paymentRequestedAt`. There is no distinct server-side `AWAITING_PAYMENT`
/// status — once the consumer pays via `POST /bookings-simple/:id/confirm-payment` the
/// status moves to `PAID`. Because a freshly-`COMPLETED` booking is indistinguishable
/// from a barber-marked-complete-without-payment one based on `status` alone, we keep a
/// process-local set of "the user tapped Request Payment on these" so the dashboard
/// banner and the detail-VC pill have something concrete to key off.
///
/// This tracker is the shared piece that lets the dashboard render an "Awaiting Payment"
/// banner above the schedule even after the user has popped the detail view. The detail
/// VC writes IDs in via `markRequested(_:)`; the dashboard reads `requestedIds` (an
/// observable `Set`) and filters its loaded `bookings` against it.
///
/// **Update propagation.** We rely on two complementary mechanisms:
///   1. `@Observable` tracking. Reading `requestedIds` from a SwiftUI `body` registers
///      a per-view dependency, so the body re-evaluates automatically on the next
///      mutation.
///   2. `didChangeNotification` posted via `NotificationCenter` from every mutator. The
///      dashboard observes this with `.onReceive` and bumps a local `@State` counter,
///      which forces a body re-eval even in the edge cases where `@Observable` tracking
///      through a stored `let` reference to a singleton doesn't fire (e.g. the view was
///      off-screen behind a pushed UIKit VC when the mutation happened).
///
/// **Lifetime.** Process-scoped. Lost on cold launch, intentionally — the customer-facing
/// payment request was already sent server-side, so a freshly-launched dashboard simply
/// shows the booking as `COMPLETED` without the local banner, and the barber can re-
/// trigger from the detail screen if they want the in-app UI back.
///
/// **Sign-out.** Callers should invoke `clearAll()` from the sign-out path so a different
/// user signing in on the same device doesn't see a previous user's banners.
@Observable
@MainActor
final class ProviderAwaitingPaymentTracker {
    /// Single shared instance — there's only ever one signed-in provider at a time on
    /// device, and the detail VC + dashboard need to converge on the same set without
    /// threading an `@Environment` value through the booking nav bridge.
    static let shared = ProviderAwaitingPaymentTracker()

    /// Fired (on the main queue, since the class is `@MainActor`) every time
    /// `requestedIds` changes for any reason — `markRequested`, `clearRequest`,
    /// `clearAll`, or `reconcile(with:)`. The dashboard listens for this with
    /// `.onReceive` to guarantee its banner re-renders even when SwiftUI's `@Observable`
    /// dependency tracking misses the change (the typical reason: the mutation
    /// happened while the dashboard was off-screen behind a pushed UIKit view).
    static let didChangeNotification = Notification.Name("ProviderAwaitingPaymentTrackerDidChange")

    /// Booking IDs the user has tapped "Request Payment" on during this session. Drives
    /// the dashboard's awaiting-payment banner and re-hydrates the detail VC's local
    /// `paymentRequested` flag when the user re-enters a booking they already requested.
    ///
    /// The `didSet` posts `didChangeNotification` when the underlying set actually
    /// changes. The `oldValue != newValue` guard keeps no-op writes (e.g. inserting an
    /// already-present ID) from spamming the dashboard with redundant re-renders.
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

    /// Drops any tracked IDs whose underlying booking has reached a *resolved* state in
    /// the latest server fetch — i.e. the customer paid (status contains "PAID"), or the
    /// booking was cancelled / rejected. Called by
    /// `ProviderScheduleDashboardView.loadBookings()` right after the list refreshes so
    /// the banner can self-heal once the booking actually closes out.
    ///
    /// **Important — what we do NOT drop.** The backend's `POST /bookings-simple/:id/
    /// request-payment` endpoint transitions the booking's `status` from `ACCEPTED` to
    /// `COMPLETED` and stamps `payment_requested_at`. There is no separate
    /// `AWAITING_PAYMENT` status. Earlier versions of this method filtered to
    /// `status == "ACCEPTED"` only and therefore *removed* every ID immediately after a
    /// successful Request Payment — the banner could never appear. The current logic
    /// treats `COMPLETED` as a still-awaiting state when the booking is in our tracker,
    /// and only drops the ID once the booking reaches a truly resolved status.
    ///
    /// - Parameter bookings: the freshly-loaded full set returned by
    ///   `ProviderBookingsService.listBookings`.
    func reconcile(with bookings: [SimpleBookingDTO]) {
        let stillEligible = Set(
            bookings
                .filter { Self.isAwaitingEligible(status: $0.statusUpper, paidAt: $0.paidAt) }
                .map(\.id)
        )
        requestedIds = requestedIds.intersection(stillEligible)
    }

    /// Single source of truth for whether a booking *status* is compatible with the
    /// "Awaiting Payment" banner. Shared by `reconcile(with:)` here and the dashboard's
    /// `awaitingPaymentBookings` filter so the two never drift.
    ///
    /// We keep ACCEPTED (the pre-call state, in case the dashboard refresh races the
    /// `request-payment` round trip) *and* COMPLETED (the post-call state — see
    /// method doc above). We drop anything that contains PAID (paid out, payment
    /// resolved) or CANCEL / REJECT (booking torn down).
    static func isAwaitingEligible(status: String, paidAt: Date? = nil) -> Bool {
        if paidAt != nil { return false }
        let s = status.uppercased()
        if s.contains("PAID") { return false }
        if s.contains("CANCEL") || s.contains("REJECT") { return false }
        return s == "ACCEPTED" || s == "COMPLETED"
    }
}
