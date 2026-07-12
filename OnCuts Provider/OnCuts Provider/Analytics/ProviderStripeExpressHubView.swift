import SwiftUI

/// Thin wrapper kept for any leftover call sites — forwards to the Payments Onboarding Guide.
struct ProviderStripeExpressHubView: View {
    @Environment(\.dismiss) private var dismiss

    let connectStatus: BarberConnectStatusDTO?
    let connectStatusUnknown: Bool
    var onRefresh: () async -> Void

    @State private var gate = ProviderStripeOnboardingGate()

    var body: some View {
        ProviderPaymentsOnboardingGuideView(
            blocking: false,
            gate: gate,
            onFullyConnected: { dismiss() }
        )
        .task {
            if let connectStatus {
                gate.applySeed(connectStatus)
            }
            await gate.refresh()
            await onRefresh()
        }
    }
}
