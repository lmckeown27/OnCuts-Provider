import OnCutsModule
import Foundation
import Observation
import SwiftUI

@Observable @MainActor
final class ProviderSession {
    private(set) var isBootstrapping = true
    private(set) var isSignedIn = false
    /// Bumped on sign-out so `AuthEntryView` remounts with a clean navigation stack.
    private(set) var authPresentationEpoch = 0
    private(set) var authUser: AuthMeUser?
    private(set) var barberProfile: BarberMeProfile?
    /// Remaining commission-free card bookings for the signed-in operator (hub + booking badges).
    private(set) var commissionFreeBookingsRemaining: Int = 0
    private(set) var lastError: String?

    func setCommissionFreeBookingsRemaining(_ value: Int) {
        commissionFreeBookingsRemaining = max(0, value)
    }

    var displayName: String {
        if let b = barberProfile {
            let r = b.resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !r.isEmpty { return r }
        }
        let f = authUser?.firstName ?? ""
        let l = authUser?.lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "Barber" : joined
    }

    var hasProviderProfile: Bool {
        guard let barberProfile else { return false }
        // Demoted / hidden operators keep a `barbers` row with `isActive = false`. They must not
        // unlock the operator shell — route them through the application funnel instead.
        return barberProfile.isActive != false
    }

    /// Signed-in account without an active `barbers` row — show the provider application funnel
    /// (mirrors web redirecting non-barbers away from `BarberPage` toward application).
    /// Also forced after the landing **Become an Operator?** path for consumer accounts.
    var needsConsumerProviderEnrollment: Bool {
        guard isSignedIn else { return false }
        if authUser?.hasAdminPrivileges == true { return false }
        if hasProviderProfile { return false }
        if pendingProviderEnrollment { return true }
        if authUser?.isConsumerAccount == true { return true }
        if authUser?.isBarberRole == true { return false }
        return true
    }

    /// Set when the user signs in via **Become an Operator?** so RootView opens enrollment
    /// instead of the operator shell, even before role/profile edge cases settle.
    private(set) var pendingProviderEnrollment = false

    func bootstrap() async {
        isBootstrapping = true
        let signedIn: Bool
        if OnCutsAuthTokenStore.loadAccessToken() == nil {
            signedIn = false
            authUser = nil
            barberProfile = nil
            commissionFreeBookingsRemaining = 0
            pendingProviderEnrollment = false
            ProviderFrontendConfigStore.shared.resetToDefault()
        } else {
            do {
                let me = try await ProviderAuthService.fetchAuthMe()
                authUser = me
                await ProviderAuthService.syncAccessTokenForElevatedPrivileges(me)
                await syncBarberProfileFromServer()
                signedIn = true
                await ProviderFrontendConfigStore.shared.refresh(force: true)
                await ProviderPushDeviceRegistration.refreshAfterSignIn()
            } catch {
                ProviderAuthService.clearSession()
                signedIn = false
                authUser = nil
                barberProfile = nil
                commissionFreeBookingsRemaining = 0
                pendingProviderEnrollment = false
                ProviderFrontendConfigStore.shared.resetToDefault()
            }
        }
        withAnimation(ProviderRootTransition.animation) {
            isSignedIn = signedIn
            isBootstrapping = false
        }
    }

    func signIn(email: String, password: String, routeToProviderEnrollment: Bool = false) async throws {
        lastError = nil
        pendingProviderEnrollment = routeToProviderEnrollment
        let session = try await ProviderAuthService.login(email: email, password: password)
        ProviderAuthService.persistSession(session)
        try await refreshProfileAfterSignIn()
        withAnimation(ProviderRootTransition.animation) {
            isSignedIn = true
        }
        await ProviderPushDeviceRegistration.refreshAfterSignIn()
    }

    /// After email verification during **Create account**.
    func adoptVerifiedSession(_ verified: OnCutsVerifiedSession) async throws {
        lastError = nil
        ProviderAuthService.persistSession(verified)
        try await refreshProfileAfterSignIn()
        withAnimation(ProviderRootTransition.animation) {
            isSignedIn = true
        }
        await ProviderPushDeviceRegistration.refreshAfterSignIn()
    }

    func refreshProfileAfterSignIn() async throws {
        authUser = try await ProviderAuthService.fetchAuthMe()
        if let authUser {
            await ProviderAuthService.syncAccessTokenForElevatedPrivileges(authUser)
        }
        await syncBarberProfileFromServer()
        await ProviderFrontendConfigStore.shared.refresh(force: true)
    }

    /// `GET /barbers/me`, then public `GET /barbers/user/:id` to auto-provision a row when the DB role allows.
    private func syncBarberProfileFromServer() async {
        barberProfile = Self.activeProviderProfile(try? await ProviderAuthService.fetchBarberMe())
        if barberProfile == nil, let id = authUser?.id {
            await ProviderBarberBootstrap.trySyncBarberRow(userId: id)
            barberProfile = Self.activeProviderProfile(try? await ProviderAuthService.fetchBarberMe())
        }
        if hasProviderProfile {
            pendingProviderEnrollment = false
        }
    }

    private static func activeProviderProfile(_ profile: BarberMeProfile?) -> BarberMeProfile? {
        guard let profile else { return nil }
        guard profile.isActive != false else { return nil }
        return profile
    }

    /// Pull-to-refresh from enrollment after approval.
    func retryProviderProfileSync() async {
        guard let id = authUser?.id else { return }
        await ProviderBarberBootstrap.trySyncBarberRow(userId: id)
        barberProfile = Self.activeProviderProfile(try? await ProviderAuthService.fetchBarberMe())
        if hasProviderProfile {
            pendingProviderEnrollment = false
        }
    }

    func refreshBarberProfileOnly() async {
        await retryProviderProfileSync()
    }

    /// Owner `GET /barbers/me` only — do not use public `GET /barbers/:id` (404 when hidden).
    func refreshMarketplaceVisibilityFromMe() async {
        guard let me = try? await ProviderAuthService.fetchBarberMe() else { return }
        if let active = Self.activeProviderProfile(me) {
            barberProfile = active
        } else if let current = barberProfile, current.id == me.id {
            barberProfile = current.withMarketplaceHidden(me.isHidden == true)
        }
    }

    func applyMarketplaceHidden(_ hidden: Bool) {
        guard let current = barberProfile else { return }
        barberProfile = current.withMarketplaceHidden(hidden)
    }

    func applyBookingSlotIntervalMinutes(_ minutes: Int) {
        guard let current = barberProfile else { return }
        barberProfile = current.withBookingSlotIntervalMinutes(minutes)
    }

    func applyMaxAdvanceBookingDays(_ days: Int) {
        guard let current = barberProfile else { return }
        barberProfile = current.withMaxAdvanceBookingDays(days)
    }

    /// Async so the device-registration DELETE can complete while the JWT is still valid in the
    /// keychain — the request needs a Bearer header to identify which device records belong to
    /// the signed-out account. The call inside `unregisterOnSignOut()` swallows errors, so the
    /// sign-out itself can never hang on a flaky network.
    /// Hard-deletes the signed-in account on the server, then clears local session state.
    /// Mirrors web `ConsumerProfileEditor.handleDeleteAccount` + `DELETE /users/:id`.
    func deleteAccount(password: String?) async throws {
        guard let id = authUser?.id else {
            throw OnCutsHTTPError.notAuthenticated
        }
        await ProviderPushDeviceRegistration.unregisterOnSignOut()
        try await ProviderAuthService.deleteAccount(userId: id, password: password)
        ProviderAuthService.clearSession()
        ProviderAwaitingPaymentTracker.shared.clearAll()
        ProviderFrontendConfigStore.shared.resetToDefault()
        #if os(iOS)
        GoogleSignInAppSupport.signOutSDK()
        #endif
        withAnimation(ProviderRootTransition.animation) {
            isSignedIn = false
            authUser = nil
            barberProfile = nil
            commissionFreeBookingsRemaining = 0
            pendingProviderEnrollment = false
            authPresentationEpoch &+= 1
        }
    }

    func signOut() async {
        await ProviderPushDeviceRegistration.unregisterOnSignOut()
        ProviderAuthService.clearSession()
        // In-memory per-session local state — drop it now so the next sign-in on this
        // device doesn't inherit the previous user's "Awaiting Payment" banner. Bookings
        // are scoped to the JWT, so a leaked tracker ID could otherwise render a banner
        // that points at someone else's booking and would silently fail the `bookings`
        // intersection on the dashboard (or worse, succeed if the new user happens to
        // have a booking with a colliding UUID — astronomically unlikely but trivial to
        // foreclose).
        ProviderAwaitingPaymentTracker.shared.clearAll()
        ProviderFrontendConfigStore.shared.resetToDefault()
        #if os(iOS)
        GoogleSignInAppSupport.signOutSDK()
        #endif
        withAnimation(ProviderRootTransition.animation) {
            isSignedIn = false
            authUser = nil
            barberProfile = nil
            commissionFreeBookingsRemaining = 0
            pendingProviderEnrollment = false
            authPresentationEpoch &+= 1
        }
    }

    func clearLastError() { lastError = nil }
}
