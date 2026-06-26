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

    /// Finished appointments still shown on the main schedule.
    static func isScheduleCompleted(status raw: String?) -> Bool {
        switch normalized(raw) {
        case "completed", "paid": return true
        default: return false
        }
    }

    /// Collapses backend statuses into the two schedule labels when applicable.
    static func scheduleSlotTitle(for raw: String?) -> String? {
        if isScheduleCompleted(status: raw) { return "Completed" }
        if isScheduleBooked(status: raw) { return "Booked" }
        return nil
    }

    /// Weekly grid appointment block fill — completed vs upcoming.
    static func scheduleAppointmentFill(for booking: SimpleBookingDTO) -> Color {
        if isScheduleCompleted(status: booking.status) {
            return Color.providerScheduleCompletedAppointmentFill
        }
        return Color.providerScheduleUpcomingAppointmentFill
    }

    /// Cancelled bookings are omitted from the main schedule entirely.
    static func isVisibleOnMainSchedule(status raw: String?) -> Bool {
        switch normalized(raw) {
        case "cancelled", "canceled": return false
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
        ProviderBookingStatusDisplay.isVisibleOnMainSchedule(status: status)
    }

    var scheduleAppointmentFillColor: Color {
        ProviderBookingStatusDisplay.scheduleAppointmentFill(for: self)
    }
}
