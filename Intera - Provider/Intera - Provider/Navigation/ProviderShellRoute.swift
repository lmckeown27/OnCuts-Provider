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
    /// Stripe Connect: dashboard + onboarding (`GET/POST /barber/connect/*`, `GET /barber/payout/summary`).
    /// Parity with web `PaymentManagementModal` / Payout Settings.
    case payoutSettings
    /// Native Campus Manager dashboard (campus barbers list, visibility toggles, campus bookings).
    /// Surfaced only when `AuthMeUser.hasCampusManagerPrivileges` is true.
    case campusManagerDashboard
    /// Native Admin dashboard (platform stats, campuses, barbers, users). Surfaced only when
    /// `AuthMeUser.hasAdminPrivileges` is true.
    case adminDashboard
    /// Push for `/admin/barbers/:id/bookings` and visibility controls.
    case adminBarberDetail(AdminBarberDTO)
    /// Push for `/admin/users/:id/bookings`.
    case adminUserDetail(AdminPlatformUserDTO)
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
}

extension Notification.Name {
    /// Posted when a booking is edited from a pushed detail so the schedule hub can refetch.
    static let providerBookingsChanged = Notification.Name("ProviderBookingsChanged")
}
