import CampusCutsModule
import Foundation
import Observation

@Observable @MainActor
final class ProviderSession {
    private(set) var isBootstrapping = true
    private(set) var isSignedIn = false
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
        defer { isBootstrapping = false }
        guard CampusCutsAuthTokenStore.loadAccessToken() != nil else {
            isSignedIn = false
            authUser = nil
            barberProfile = nil
            return
        }
        do {
            let me = try await ProviderAuthService.fetchAuthMe()
            authUser = me
            await ProviderAuthService.syncAccessTokenForElevatedPrivileges(me)
            await syncBarberProfileFromServer()
            isSignedIn = true
            // Cold launch with a stored JWT — refresh the device-registration record so the
            // backend can route APNs at this account on day-one of every session.
            await ProviderPushDeviceRegistration.refreshAfterSignIn()
        } catch {
            ProviderAuthService.clearSession()
            isSignedIn = false
            authUser = nil
            barberProfile = nil
        }
    }

    func signIn(email: String, password: String) async throws {
        lastError = nil
        let session = try await ProviderAuthService.login(email: email, password: password)
        ProviderAuthService.persistSession(session)
        try await refreshProfileAfterSignIn()
        isSignedIn = true
        await ProviderPushDeviceRegistration.refreshAfterSignIn()
    }

    /// After email verification during **Create account**.
    func adoptVerifiedSession(_ verified: CampusCutsVerifiedSession) async throws {
        lastError = nil
        ProviderAuthService.persistSession(verified)
        try await refreshProfileAfterSignIn()
        isSignedIn = true
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
            throw CampusCutsHTTPError.notAuthenticated
        }
        await ProviderPushDeviceRegistration.unregisterOnSignOut()
        try await ProviderAuthService.deleteAccount(userId: id, password: password)
        ProviderAuthService.clearSession()
        ProviderAwaitingPaymentTracker.shared.clearAll()
        #if os(iOS)
        GoogleSignInAppSupport.signOutSDK()
        #endif
        isSignedIn = false
        authUser = nil
        barberProfile = nil
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
        isSignedIn = false
        authUser = nil
        barberProfile = nil
    }

    func clearLastError() { lastError = nil }
}
