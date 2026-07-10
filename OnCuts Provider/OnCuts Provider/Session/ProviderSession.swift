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
    private(set) var lastError: String?

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

    var hasProviderProfile: Bool { barberProfile != nil }

    /// Signed-in account without a `barbers` row — show the provider application funnel
    /// (mirrors web redirecting non-barbers away from `BarberPage` toward application).
    var needsConsumerProviderEnrollment: Bool {
        guard isSignedIn, !hasProviderProfile else { return false }
        if authUser?.hasAdminPrivileges == true { return false }
        if authUser?.isBarberRole == true { return false }
        return true
    }

    func bootstrap() async {
        isBootstrapping = true
        let signedIn: Bool
        if OnCutsAuthTokenStore.loadAccessToken() == nil {
            signedIn = false
            authUser = nil
            barberProfile = nil
        } else {
            do {
                let me = try await ProviderAuthService.fetchAuthMe()
                authUser = me
                await ProviderAuthService.syncAccessTokenForElevatedPrivileges(me)
                await syncBarberProfileFromServer()
                signedIn = true
                await ProviderPushDeviceRegistration.refreshAfterSignIn()
            } catch {
                ProviderAuthService.clearSession()
                signedIn = false
                authUser = nil
                barberProfile = nil
            }
        }
        withAnimation(ProviderRootTransition.animation) {
            isSignedIn = signedIn
            isBootstrapping = false
        }
    }

    func signIn(email: String, password: String) async throws {
        lastError = nil
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
    }

    /// `GET /barbers/me`, then public `GET /barbers/user/:id` to auto-provision a row when the DB role allows.
    private func syncBarberProfileFromServer() async {
        barberProfile = try? await ProviderAuthService.fetchBarberMe()
        if barberProfile == nil, let id = authUser?.id {
            await ProviderBarberBootstrap.trySyncBarberRow(userId: id)
            barberProfile = try? await ProviderAuthService.fetchBarberMe()
        }
    }

    /// Pull-to-refresh from enrollment after approval.
    func retryProviderProfileSync() async {
        guard let id = authUser?.id else { return }
        await ProviderBarberBootstrap.trySyncBarberRow(userId: id)
        barberProfile = try? await ProviderAuthService.fetchBarberMe()
    }

    func refreshBarberProfileOnly() async {
        await retryProviderProfileSync()
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
        #if os(iOS)
        GoogleSignInAppSupport.signOutSDK()
        #endif
        withAnimation(ProviderRootTransition.animation) {
            isSignedIn = false
            authUser = nil
            barberProfile = nil
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
        #if os(iOS)
        GoogleSignInAppSupport.signOutSDK()
        #endif
        withAnimation(ProviderRootTransition.animation) {
            isSignedIn = false
            authUser = nil
            barberProfile = nil
            authPresentationEpoch &+= 1
        }
    }

    func clearLastError() { lastError = nil }
}
