import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Human-readable booking status labels and colors aligned with the web dashboard.
enum ProviderBookingStatusDisplay {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case pending
        case accepted
        case paid
        case completed
        case cancelled
        case rejected

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .pending: return "Pending"
            case .accepted: return "Accepted"
            case .paid: return "Paid"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            case .rejected: return "Rejected"
            }
        }

        func matches(_ booking: SimpleBookingDTO) -> Bool {
            guard self != .all else { return true }
            let norm = ProviderBookingStatusDisplay.normalized(booking.status)
            switch self {
            case .paid:
                // Upcoming paid appointments (service paid, not yet marked complete).
                // Legacy finished `PAID`+`completedAt` rows belong with Completed.
                return booking.isUpcomingPaidAppointment
            case .completed:
                // Marked complete (tip pending or settled) + legacy finished PAID.
                return norm == "completed" || booking.isLegacyFinishedPaid
            case .accepted:
                return norm == "accepted"
            default:
                return norm == rawValue
            }
        }
    }

    static func title(for raw: String?) -> String {
        switch normalized(raw) {
        case "pending": return "Pending"
        case "accepted": return "Accepted"
        case "booked": return "Booked"
        case "completed": return "Completed"
        case "rejected": return "Rejected"
        case "cancelled", "canceled": return "Cancelled"
        case "paid": return "Paid"
        case "in_progress": return "In Progress"
        case "refunded": return "Refunded"
        case "disputed": return "Disputed"
        default:
            guard let raw, !raw.isEmpty else { return "Unknown" }
            return raw
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    /// Status pill colors on booking detail (matches `BookingDetailViewController.statusPalette`).
    static func detailPillColors(for raw: String?) -> (background: Color, foreground: Color) {
        switch normalized(raw) {
        case "paid", "completed":
            return (Color(uiColor: ProviderChatDesignTokens.Color.statusGreen), .white)
        case "accepted", "booked", "in_progress":
            return (Color(uiColor: ProviderAppearance.olive), .white)
        case "pending":
            return (Color(uiColor: ProviderChatDesignTokens.Color.statusYellow), Color(white: 0.1))
        case "cancelled", "canceled", "rejected":
            return (Color.providerElevatedSurface, Color.lavaShellCreamSecondary)
        default:
            return (Color.providerElevatedSurface, Color.lavaShellCreamSecondary)
        }
    }

    /// Conversation inbox status label — pending yellow, accepted olive, completed light green.
    static func inboxStatusLabelColor(for raw: String?) -> Color {
        switch normalized(raw) {
        case "pending":
            return Color(uiColor: ProviderChatDesignTokens.Color.statusYellow)
        case "accepted", "booked", "in_progress":
            return Color.providerOlive
        case "completed", "paid":
            return Color(uiColor: ProviderChatDesignTokens.Color.statusGreen)
        case "cancelled", "canceled", "rejected", "refunded", "disputed":
            return Color.lavaShellCreamSecondary
        default:
            return Color.lavaShellCreamSecondary
        }
    }

    /// Capsule backgrounds for booking status chips — olive + frosted glass (same family as schedule / header pills).
    static func swiftUITint(for raw: String?) -> Color {
        switch normalized(raw) {
        case "pending":
            return Color.providerElevatedSurface
        case "accepted", "booked", "in_progress":
            return Color.providerOlive.opacity(0.28)
        case "completed", "paid":
            return Color.providerScheduleCompletedAppointmentFill
        case "cancelled", "canceled", "rejected", "refunded", "disputed":
            return Color.providerElevatedSurface
        default:
            return Color.providerElevatedSurface
        }
    }

    #if canImport(UIKit)
    /// Inbox / chat conversation status pills — readable in light and dark mode.
    static func uiKitBadgeColors(for raw: String?) -> (background: UIColor, foreground: UIColor) {
        let olive = ProviderAppearance.olive
        let fg = ProviderAppearance.primaryText
        let fgSecondary = ProviderAppearance.secondaryText
        let chip = ProviderAppearance.elevatedSurface

        switch normalized(raw) {
        case "pending":
            return (chip, fg)
        case "accepted", "booked", "in_progress":
            return (olive.withAlphaComponent(0.28), fg)
        case "completed", "paid":
            return (UIColor.systemGreen.withAlphaComponent(0.35), fg)
        case "cancelled", "canceled", "rejected", "refunded", "disputed":
            return (chip, fgSecondary)
        default:
            return (chip, fgSecondary)
        }
    }
    #endif

    static func normalized(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    /// Upcoming / active appointments on the main schedule.
    static func isScheduleBooked(status raw: String?) -> Bool {
        switch normalized(raw) {
        case "accepted", "booked", "in_progress": return true
        default: return false
        }
    }

    /// Appointments counted in the weekly summary (`[x] appointments this/that week`).
    /// Same set as main-schedule visibility (includes tip-pending Completed).
    static func isUpcomingScheduleAppointment(_ booking: SimpleBookingDTO) -> Bool {
        booking.isVisibleOnMainSchedule
    }

    /// Status is Completed (label helper). Slot frees only after tip is decided — see ``SimpleBookingDTO/isVisibleOnMainSchedule``.
    static func isScheduleCompleted(status raw: String?) -> Bool {
        switch normalized(raw) {
        case "completed": return true
        default: return false
        }
    }

    /// Collapses backend statuses into schedule card labels when applicable.
    static func scheduleSlotTitle(for raw: String?) -> String? {
        if isScheduleCompleted(status: raw) { return "Completed" }
        switch normalized(raw) {
        case "pending":
            return "Pending"
        case "paid":
            return "Paid"
        case "accepted", "booked", "in_progress":
            return "Booked"
        default:
            return nil
        }
    }

    /// Weekly grid appointment block fill — pending (yellow), paid/completed (light green), or upcoming olive.
    static func scheduleAppointmentFill(for booking: SimpleBookingDTO) -> Color {
        if booking.isAwaitingServicePayment || booking.isAwaitingPostCompletePayment {
            return Color(uiColor: ProviderChatDesignTokens.Color.statusYellow)
        }
        if booking.isUpcomingPaidAppointment
            || booking.isAwaitingTip
            || ProviderBookingStatusDisplay.normalized(booking.status) == "paid" {
            return Color.providerScheduleCompletedAppointmentFill
        }
        switch normalized(booking.status) {
        case "pending":
            return Color(uiColor: ProviderChatDesignTokens.Color.statusYellow)
        case "completed":
            return Color.providerScheduleCompletedAppointmentFill
        default:
            return Color.providerScheduleUpcomingAppointmentFill
        }
    }

    /// Original-slot fill while drag-moving a booking — desaturated/greyed status color
    /// (plain opacity on yellow still reads as bright against the schedule).
    static func scheduleAppointmentMoveOriginFill(for booking: SimpleBookingDTO) -> Color {
        #if canImport(UIKit)
        Color(uiColor: scheduleAppointmentMoveOriginUIColor(for: booking))
        #else
        scheduleAppointmentFill(for: booking).opacity(0.28)
        #endif
    }

    #if canImport(UIKit)
    private static func scheduleAppointmentMoveOriginUIColor(for booking: SimpleBookingDTO) -> UIColor {
        let base: UIColor
        if booking.isAwaitingServicePayment || booking.isAwaitingPostCompletePayment {
            base = ProviderChatDesignTokens.Color.statusYellow
        } else if booking.isUpcomingPaidAppointment
            || booking.isAwaitingTip
            || normalized(booking.status) == "paid"
            || normalized(booking.status) == "completed" {
            base = UIColor(Color.providerScheduleCompletedAppointmentFill)
        } else {
            switch normalized(booking.status) {
            case "pending":
                base = ProviderChatDesignTokens.Color.statusYellow
            default:
                base = UIColor(Color.providerScheduleUpcomingAppointmentFill)
            }
        }
        return base.providerMixed(with: .systemGray3, amount: 0.58).withAlphaComponent(0.82)
    }
    #endif

    /// Status-only visibility (legacy). Prefer ``SimpleBookingDTO/isVisibleOnMainSchedule``
    /// (tip-settled Completed must be filtered with `tipDecidedAt`).
    static func isVisibleOnMainSchedule(status raw: String?) -> Bool {
        switch normalized(raw) {
        case "pending", "accepted", "booked", "in_progress", "paid", "completed":
            return true
        default:
            return false
        }
    }

    /// Week chevron tickers — on-schedule bookings outside the viewed week.
    static func countsForWeekNavigationTicker(_ booking: SimpleBookingDTO) -> Bool {
        guard booking.isVisibleOnMainSchedule else { return false }
        return booking.providerEffectiveScheduledTime != nil
    }

    /// Bookings in terminal / completed states cannot have an actionable consumer reschedule request.
    static func isEligibleForPendingRescheduleRequest(status raw: String?) -> Bool {
        switch normalized(raw) {
        case "cancelled", "canceled", "rejected", "refunded", "disputed", "completed":
            return false
        default:
            return true
        }
    }

    /// Whether a booking still occupies the calendar for overlap / conflict checks.
    /// Upcoming paid appointments block; completed / cancelled do not.
    static func blocksScheduleConflict(_ booking: SimpleBookingDTO) -> Bool {
        guard booking.isVisibleOnMainSchedule else { return false }
        switch normalized(booking.status) {
        case "pending":
            return false
        default:
            return true
        }
    }
}

/// Status pill matching `BookingDetailViewController` — mode-aware operator labels.
struct ProviderBookingDetailStatusPill: View {
    let booking: SimpleBookingDTO

    var body: some View {
        let colors = ProviderBookingStatusDisplay.detailPillColors(for: booking.status)
        Text(booking.operatorStatusBadgeTitle)
            .font(.provider(.caption, weight: .semibold))
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colors.background, in: Capsule())
    }
}

extension SimpleBookingDTO {
    var statusDisplayTitle: String {
        operatorStatusBadgeTitle
    }

    /// Mode-aware badge for operator surfaces (calendar / lists / detail).
    var operatorStatusBadgeTitle: String {
        if isAwaitingServicePayment {
            return "Awaiting Payment"
        }
        if isConfirmedUnpaidAccepted {
            return "Confirmed"
        }
        if isAwaitingPostCompletePayment {
            return "Awaiting Payment"
        }
        if isAwaitingTip {
            return "Awaiting Tip"
        }
        return ProviderBookingStatusDisplay.title(for: status)
    }

    var statusDisplayTint: Color {
        ProviderBookingStatusDisplay.swiftUITint(for: status)
    }

    var scheduleSlotTitle: String {
        ProviderBookingStatusDisplay.scheduleSlotTitle(for: status) ?? statusDisplayTitle
    }

    /// Label on weekly / day calendar cards.
    /// - on_accept unpaid ACCEPTED → “Awaiting Payment”
    /// - after_complete unpaid ACCEPTED → “Confirmed”
    /// - after_complete unpaid COMPLETED → “Awaiting Payment”
    /// - on_accept tip-pending COMPLETED → “Completed”
    var scheduleCardTitle: String {
        if isAwaitingServicePayment {
            return "Awaiting Payment"
        }
        if isConfirmedUnpaidAccepted {
            return "Confirmed"
        }
        if isAwaitingPostCompletePayment {
            return "Awaiting Payment"
        }
        // Tip-pending COMPLETED stays on the calendar as “Completed”.
        if isAwaitingTip {
            return "Completed"
        }
        return scheduleSlotTitle
    }

    /// Calendar occupancy:
    /// - Both modes: `PENDING` / `ACCEPTED` / `IN_PROGRESS` occupy the slot.
    /// - on_accept: upcoming `PAID` + tip-pending `COMPLETED`.
    /// - after_complete: unpaid `COMPLETED` until consumer pays; early `PAID` after
    ///   complete is finished and does not occupy.
    var isVisibleOnMainSchedule: Bool {
        guard !isCancelledOrRejected else { return false }
        switch ProviderBookingStatusDisplay.normalized(status) {
        case "pending", "accepted", "booked", "in_progress":
            return true
        case "paid":
            return isUpcomingPaidAppointment
        case "completed":
            switch paymentTimingMode {
            case .onAccept:
                return isAwaitingTip
            case .afterComplete:
                return paidAt == nil
            }
        default:
            return false
        }
    }

    var scheduleAppointmentFillColor: Color {
        ProviderBookingStatusDisplay.scheduleAppointmentFill(for: self)
    }

    var scheduleAppointmentMoveOriginFillColor: Color {
        ProviderBookingStatusDisplay.scheduleAppointmentMoveOriginFill(for: self)
    }
}

#if canImport(UIKit)
private extension UIColor {
    /// Linear RGB mix toward `other` by `amount` (0 = self, 1 = other).
    func providerMixed(with other: UIColor, amount: CGFloat) -> UIColor {
        let t = min(1, max(0, amount))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        let ok1 = getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        let ok2 = other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        guard ok1, ok2 else {
            return self.withAlphaComponent(0.35)
        }
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}
#endif
