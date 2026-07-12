import SwiftUI

/// Stripe Connect payouts — Profile hub that reuses the Payments Onboarding Guide (non-blocking).
struct ProviderPayoutSettingsView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @State private var stripeGate = ProviderStripeOnboardingGate()

    private static let stripeDashboardAppStoreURL = URL(string: "https://apps.apple.com/app/id978516833")!

    var body: some View {
        Group {
            if !session.hasProviderProfile {
                ContentUnavailableView(
                    "No barber profile",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Complete barber setup on the web, then pull to refresh.")
                )
                .foregroundStyle(Color.lavaShellCream)
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
    }

    private var stripeMobileAppSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stripe App")
                .font(.provider(.title2, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)

            VStack(alignment: .leading, spacing: 12) {
                Text("Optional — track balances and payout activity on your phone.")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)

                Button {
                    openURL(Self.stripeDashboardAppStoreURL)
                } label: {
                    Text("Get Stripe Dashboard app")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(ProviderOliveChromeStyle.adminTabInactiveForeground(colorScheme))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(ProviderOliveChromeStyle.adminTabTrackFill(colorScheme))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            ProviderOliveChromeStyle.adminTabTrackStroke(colorScheme),
                                            lineWidth: 0.6
                                        )
                                }
                        }
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
        .padding(.horizontal, 16)
    }
}
