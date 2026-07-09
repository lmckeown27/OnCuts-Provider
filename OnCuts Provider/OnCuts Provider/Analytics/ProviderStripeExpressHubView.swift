import SwiftUI

struct ProviderStripeExpressHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let connectStatus: BarberConnectStatusDTO?
    let connectStatusUnknown: Bool
    var onRefresh: () async -> Void

    @State private var connectBusy = false
    @State private var errorAlert: String?

    private var isConnected: Bool { connectStatus?.hasAccount == true }
    private var identityVerified: Bool { connectStatus?.detailsSubmitted == true }
    private var cardProcessingActive: Bool { connectStatus?.chargesEnabled == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                connectionBanner
                setupChecklistCard
                portalSummaryCard
                openStripeButton
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .providerNavigationStackDestinationBackdrop()
        .navigationTitle("Stripe Express")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .refreshable { await onRefresh() }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorAlert != nil },
            set: { if !$0 { errorAlert = nil } }
        )) {
            Button("OK", role: .cancel) { errorAlert = nil }
        } message: {
            Text(errorAlert ?? "")
        }
    }

    private var connectionBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .shadow(color: (isConnected ? Color.green : Color.orange).opacity(0.65), radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(isConnected ? "Stripe Connect active" : "Stripe Connect incomplete")
                    .font(.provider(.subheadline, weight: .bold))
                Text(connectStatusUnknown
                    ? "We couldn't verify your status. You can still open Stripe below."
                    : isConnected
                        ? "Payouts and card processing are managed in your Express dashboard."
                        : "Finish setup to accept card payments and receive payouts.")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.green.opacity(isConnected ? 0.18 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.green.opacity(isConnected ? 0.55 : 0.25), lineWidth: 1)
                )
        )
    }

    private var setupChecklistCard: some View {
        ProviderAnalyticsSectionCard(
            title: "Setup checklist",
            subtitle: "Core milestones for getting paid through Stripe."
        ) {
            VStack(spacing: 10) {
                checklistItem(title: "Account linked", complete: isConnected)
                checklistItem(title: "Identity verified", complete: identityVerified)
                checklistItem(title: "Card processing active", complete: cardProcessingActive)
            }
        }
    }

    private var portalSummaryCard: some View {
        ProviderAnalyticsSectionCard(
            title: "Inside the portal",
            subtitle: "What you can manage in Stripe Express."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                bullet("View payout schedule and bank deposits")
                bullet("Update identity and tax information")
                bullet("Review charges, refunds, and disputes")
                bullet("Download statements and payout reports")
            }
        }
    }

    private var openStripeButton: some View {
        Button {
            Task { await openStripeExpress() }
        } label: {
            HStack(spacing: 10) {
                Text(connectBusy ? "Opening…" : "Open Stripe Express")
                    .font(.provider(.body, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.provider(.body, weight: .bold))
            }
            .foregroundStyle(Color.lavaShellCream)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.39, green: 0.36, blue: 0.96))
            )
        }
        .buttonStyle(ProviderAnalyticsScalePressStyle())
        .disabled(connectBusy)
    }

    private func checklistItem(title: String, complete: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(complete ? Color.green : Color.lavaShellCream.opacity(0.35))
            Text(title)
                .font(.provider(.subheadline, weight: .semibold))
            Spacer(minLength: 0)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.provider(.body, weight: .bold))
                .foregroundStyle(Color.providerOlive)
            Text(text)
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
    }

    private func openStripeExpress() async {
        connectBusy = true
        defer { connectBusy = false }
        do {
            let url: URL
            if isConnected {
                url = try await ProviderBarberPayoutService.fetchStripeDashboardURL()
            } else {
                url = try await ProviderBarberPayoutService.createConnectOnboardingURL()
            }
            await MainActor.run { openURL(url) }
        } catch {
            errorAlert = (error as? LocalizedError)?.errorDescription ?? "Could not open Stripe Express."
        }
    }
}
