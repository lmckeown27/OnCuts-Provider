import SwiftUI

/// Stripe Connect payouts — hub for operators who are fully onboarded, or the
/// Payments Onboarding Guide when Connect is still incomplete.
struct ProviderPayoutSettingsView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var stripeGate = ProviderStripeOnboardingGate()
    @State private var connectBusy = false
    @State private var errorAlert: String?

    private static let stripePurple = Color(red: 99 / 255, green: 91 / 255, blue: 255 / 255)
    private static let stripeDashboardAppStoreURL = URL(string: "https://apps.apple.com/app/id978516833")!

    private var isFullyConnected: Bool {
        BarberStripeConnectStatus.isFullyConnected(stripeGate.status)
    }

    var body: some View {
        Group {
            if !session.hasProviderProfile {
                ContentUnavailableView(
                    "No barber profile",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Complete barber setup on the web, then pull to refresh.")
                )
                .foregroundStyle(Color.lavaShellCream)
            } else if stripeGate.isLoading && !stripeGate.hasLoadedOnce {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.providerOlive)
                    Text("Checking Stripe Connect…")
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isFullyConnected {
                connectedHub
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ProviderPaymentsOnboardingGuideView(
                            blocking: false,
                            embedded: true,
                            gate: stripeGate
                        )
                        stripeMobileAppSection
                    }
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .refreshable { await stripeGate.refresh() }
            }
        }
        .providerNavigationStackDestinationBackdrop()
        .navigationTitle("Payout Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Payout Settings")
                    .font(.provider(.headline, weight: .semibold))
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .task {
            if session.hasProviderProfile {
                await stripeGate.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, session.hasProviderProfile else { return }
            Task { await stripeGate.refresh() }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorAlert != nil },
            set: { if !$0 { errorAlert = nil } }
        )) {
            Button("OK", role: .cancel) { errorAlert = nil }
        } message: {
            Text(errorAlert ?? "")
        }
    }

    // MARK: - Fully onboarded hub

    private var connectedHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                connectedStatusCard
                openExpressSection
                stripeMobileAppSection
            }
            .padding(16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await stripeGate.refresh() }
    }

    private var connectedStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.provider(size: 22))
                    .foregroundStyle(Color.green)
                Text("Stripe Connect active")
                    .font(.provider(.title3, weight: .semibold))
            }

            Text("You're fully onboarded with Stripe. Charges and payouts are enabled for your OnCuts operator account.")
                .font(.provider(.body))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.green.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private var openExpressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stripe Express")
                .font(.provider(.title2, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)

            VStack(alignment: .leading, spacing: 12) {
                Text("Manage your bank account, tax details, payouts, and statements in Stripe Express.")
                    .font(.provider(.body))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await openStripeExpress() }
                } label: {
                    HStack(spacing: 10) {
                        if connectBusy {
                            ProgressView()
                                .tint(Color.white)
                        }
                        Text(connectBusy ? "Opening…" : "Open Stripe Express")
                            .font(.provider(.headline, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Self.stripePurple, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(connectBusy)
            }
            .padding(14)
            .background(Color.providerScheduleCardFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.providerScheduleCardStroke, lineWidth: 0.6)
            )
        }
    }

    private var stripeMobileAppSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stripe App")
                .font(.provider(.title2, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)

            VStack(alignment: .leading, spacing: 12) {
                Text("Optional — track balances and payout activity on your phone.")
                    .font(.provider(.body))
                    .foregroundStyle(Color.lavaShellCreamSecondary)

                Button {
                    openURL(Self.stripeDashboardAppStoreURL)
                } label: {
                    Text("Get Stripe Dashboard app")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            Self.stripePurple,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.providerScheduleCardFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.providerScheduleCardStroke, lineWidth: 0.6)
            )
        }
    }

    private func openStripeExpress() async {
        connectBusy = true
        defer { connectBusy = false }
        do {
            let url = try await ProviderBarberPayoutService.fetchStripeDashboardURL()
            openURL(url)
        } catch {
            errorAlert = (error as? LocalizedError)?.errorDescription
                ?? "Could not open Stripe Express."
        }
    }
}
