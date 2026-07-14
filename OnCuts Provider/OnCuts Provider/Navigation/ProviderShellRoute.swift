import Foundation
import SwiftUI

/// Deep links inside the signed-in **provider dashboard** shell (replaces flat `TabView` navigation).
enum ProviderShellRoute: Hashable {
    case messages
    case account
    /// Services & pricing: campus catalog (`GET /admin/services`) + barber specialties/pricing (`PUT /barbers/:id`).
    case services
    /// Weekly schedule, one-off time blocks, and Google Calendar wiring (in-app parity for the web
    /// `BarberPage` Availability modal + Google Calendar connect button).
    case availability
    /// Weekly availability editor only (day toggles + intervals) — not the full Availability hub.
    case weeklyScheduleEditor
    /// Payout Settings (Stripe Connect / Express + in-page Analytics) from the schedule hub **Payouts** control.
    case payoutSettings
    /// Native Admin dashboard (platform stats, campuses, barbers, users). Surfaced only when
    /// `AuthMeUser.hasAdminPrivileges` is true. Barber / user detail pushes happen inside the
    /// dashboard's own `NavigationStack`, not as separate shell stack entries.
    case adminDashboard
}

extension ProviderShellRoute {
    /// Backdrop for this route only (travels with the push transition — no shared shell underlay).
    var pushedBackdropStyle: ProviderNavigationStackDestinationBackdropStyle {
        switch self {
        case .messages:
            return .neutralGrey
        default:
            return .shell
        }
    }
}

extension Notification.Name {
    /// Posted when the provider edits weekly schedule, time blocks, or Google Calendar connection.
    /// Lets the schedule dashboard refetch availability + the day's slot list immediately.
    static let providerAvailabilityChanged = Notification.Name("ProviderAvailabilityChanged")
    /// Posted when the public discovery pin / manual-location toggle changes (Account settings).
    static let providerDiscoveryLocationChanged = Notification.Name("ProviderDiscoveryLocationChanged")
}

extension Notification.Name {
    /// Posted when a booking is edited from a pushed detail so the schedule hub can refetch.
    static let providerBookingsChanged = Notification.Name("ProviderBookingsChanged")
}
