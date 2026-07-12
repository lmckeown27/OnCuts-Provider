import Foundation
import Observation

/// Live Stripe Connect gate for the provider dashboard (web `useStripeOnboardingGate` parity).
/// Status is checked in the background; the guide is only presented after a load confirms
/// Connect is incomplete. “Done” is decided by live account flags — not checklist ticks.
@Observable
@MainActor
final class ProviderStripeOnboardingGate {
    private(set) var status: BarberConnectStatusDTO?
    private(set) var isLoading = false
    private(set) var hasLoadedOnce = false
    private(set) var lastError: String?

    /// Missing/errored status after a load ⇒ not connected.
    var isFullyConnected: Bool {
        BarberStripeConnectStatus.isFullyConnected(status)
    }

    /// Present the Payments Onboarding Guide only after status has been checked and Connect
    /// is incomplete (or the status call failed). While the first check is in flight, stay
    /// silent so the dashboard can load in the background.
    var shouldPresentGuide: Bool {
        guard hasLoadedOnce else { return false }
        return !isFullyConnected
    }

    /// Same as `shouldPresentGuide` — blocks interaction only once incompleteness is known.
    var isBlocking: Bool { shouldPresentGuide }

    /// Optional parent-provided snapshot before the first network refresh.
    func applySeed(_ status: BarberConnectStatusDTO) {
        self.status = status
        hasLoadedOnce = true
        lastError = nil
    }

    func refresh() async {
        if isLoading { return }
        isLoading = true
        lastError = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            status = try await ProviderBarberPayoutService.fetchConnectStatus()
        } catch {
            // Treat load failure as incomplete so the guide can still surface (web parity).
            status = nil
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
