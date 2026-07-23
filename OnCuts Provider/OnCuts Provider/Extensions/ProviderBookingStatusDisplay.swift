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
        case completed
        case paid
        case cancelled
        case rejected

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .pending: return "Pending"
            case .accepted: return "Accepted"
            case .completed: return "Completed"
            case .paid: return "Paid"
            case .cancelled: return "Cancelled"
            case .rejected: return "Rejected"
            }
        }

        func matches(_ booking: SimpleBookingDTO) -> Bool {
            guard self != .all else { return true }
            return ProviderBookingStatusDisplay.normalized(booking.status) == rawValue
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
    /// Includes pending requests and accepted/booked slots; excludes completed, paid, and cancelled.
    static func isUpcomingScheduleAppointment(_ booking: SimpleBookingDTO) -> Bool {
        guard booking.paidAt == nil else { return false }
        switch normalized(booking.status) {
        case "pending", "accepted", "booked", "in_progress":
            return true
        default:
            return false
        }
    }

    /// Finished appointments still shown on the main schedule (paid appointments are omitted entirely).
    static func isScheduleCompleted(status raw: String?) -> Bool {
        switch normalized(raw) {
        case "completed": return true
        default: return false
        }
    }

    /// Collapses backend statuses into the two schedule labels when applicable.
    static func scheduleSlotTitle(for raw: String?) -> String? {
        if isScheduleCompleted(status: raw) { return "Completed" }
        if isScheduleBooked(status: raw) { return "Booked" }
        return nil
    }

    /// Weekly grid appointment block fill — pending (yellow), completed, or upcoming.
    static func scheduleAppointmentFill(for booking: SimpleBookingDTO) -> Color {
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
        switch normalized(booking.status) {
        case "pending":
            base = ProviderChatDesignTokens.Color.statusYellow
        case "completed":
            base = UIColor(Color.providerScheduleCompletedAppointmentFill)
        default:
            base = UIColor(Color.providerScheduleUpcomingAppointmentFill)
        }
        return base.providerMixed(with: .systemGray3, amount: 0.58).withAlphaComponent(0.82)
    }
    #endif

    /// Cancelled and paid bookings are omitted from the main schedule entirely.
    static func isVisibleOnMainSchedule(status raw: String?) -> Bool {
        switch normalized(raw) {
        case "cancelled", "canceled", "paid": return false
        default: return true
        }
    }

    /// Week chevron tickers — any on-schedule booking outside the viewed week, excluding paid.
    static func countsForWeekNavigationTicker(_ booking: SimpleBookingDTO) -> Bool {
        guard isVisibleOnMainSchedule(status: booking.status) else { return false }
        if booking.paidAt != nil { return false }
        if normalized(booking.status) == "paid" { return false }
        return booking.providerEffectiveScheduledTime != nil
    }

    /// Bookings in terminal states cannot have an actionable consumer reschedule request.
    /// The backend auto-declines pending requests when a booking is cancelled.
    static func isEligibleForPendingRescheduleRequest(status raw: String?) -> Bool {
        switch normalized(raw) {
        case "cancelled", "canceled", "rejected", "refunded", "disputed", "completed", "paid":
            return false
        default:
            return true
        }
    }

    /// Whether a booking still occupies the calendar for overlap / conflict checks.
    /// Paid and concluded appointments (including completed) no longer block new times.
    static func blocksScheduleConflict(_ booking: SimpleBookingDTO) -> Bool {
        if booking.paidAt != nil { return false }
        switch normalized(booking.status) {
        case "cancelled", "canceled", "completed", "paid", "rejected", "refunded", "disputed", "pending":
            return false
        default:
            return true
        }
    }
}

/// Status pill matching `BookingDetailViewController` — solid olive for accepted, etc.
struct ProviderBookingDetailStatusPill: View {
    let status: String?

    var body: some View {
        let colors = ProviderBookingStatusDisplay.detailPillColors(for: status)
        Text(ProviderBookingStatusDisplay.title(for: status))
            .font(.provider(.caption, weight: .semibold))
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colors.background, in: Capsule())
    }
}

extension SimpleBookingDTO {
    var statusDisplayTitle: String {
        ProviderBookingStatusDisplay.title(for: status)
    }

    var statusDisplayTint: Color {
        ProviderBookingStatusDisplay.swiftUITint(for: status)
    }

    var scheduleSlotTitle: String {
        ProviderBookingStatusDisplay.scheduleSlotTitle(for: status) ?? statusDisplayTitle
    }

    var isVisibleOnMainSchedule: Bool {
        if paidAt != nil { return false }
        return ProviderBookingStatusDisplay.isVisibleOnMainSchedule(status: status)
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
