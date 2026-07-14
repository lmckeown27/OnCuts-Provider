import SwiftUI

/// Payout Settings — pushed from the schedule hub **Payouts** button (same chrome as Edit Schedule / Services Offered).
/// Column: nav title → **Payouts | Analytics** tabs → scrollable body.
struct ProviderPayoutSettingsView: View {
    private enum MainTab: String, CaseIterable, Identifiable {
        case payouts = "Payouts"
        case analytics = "Analytics"
        var id: String { rawValue }
    }

    private struct FAQItem: Identifiable, Hashable {
        let id: String
        let title: String
        let body: String
    }

    @Environment(ProviderSession.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @State private var stripeGate = ProviderStripeOnboardingGate()
    @State private var connectBusy = false
    @State private var errorAlert: String?
    @State private var mainTab: MainTab = .payouts
    @State private var expandedFAQID: String?

    private static let stripePurple = Color(red: 99 / 255, green: 91 / 255, blue: 255 / 255)
    private static let stripeDashboardAppStoreURL = URL(string: "https://apps.apple.com/app/id978516833")!

    private static let faqItems: [FAQItem] = [
        FAQItem(
            id: "first-client-delay",
            title: "First-client money delay",
            body: "For new Stripe accounts, the first payout commonly takes 7-14 business days. That hold is Stripe’s new-account wait, not an OnCuts delay, and ends once your Connect account is established."
        ),
        FAQItem(
            id: "why-wait",
            title: "Why that wait exists",
            body: "Stripe uses the early window to finish KYC, watch for chargebacks, and reduce fraud risk on brand-new payout accounts. Until that clears, card earnings stay in Stripe rather than landing in your bank."
        ),
        FAQItem(
            id: "speed-after",
            title: "Speed after the wait",
            body: "After the new-account hold, eligible operators can use Instant Payouts when Stripe offers them. Otherwise funds follow your normal Stripe payout schedule (often daily or weekly) into your linked bank."
        ),
        FAQItem(
            id: "balance-bank",
            title: "Where to see balance and bank",
            body: "Open Stripe Express from this screen. Available balance, payout history, and bank details live in Stripe. OnCuts does not keep a separate operator wallet balance."
        ),
        FAQItem(
            id: "express",
            title: "What Stripe Express is",
            body: "Stripe Express is your connected payout dashboard. Use it for bank account, tax details, statements, and transfers from card payments clients make through OnCuts."
        ),
        FAQItem(
            id: "app",
            title: "What the Stripe App is",
            body: "The Stripe Dashboard app is optional. Install it from the App Store if you want balances and payout activity on your phone without opening Express in a browser."
        ),
        FAQItem(
            id: "cash-card",
            title: "Cash vs card",
            body: "Card payments settle through Stripe Connect to your bank. Cash is paid to you directly by the client. OnCuts does not deposit cash into Stripe. Track both in the Analytics tab."
        ),
    ]

    private var isFullyConnected: Bool {
        BarberStripeConnectStatus.isFullyConnected(stripeGate.status)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
            tabBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .providerNavigationStackDestinationBackdrop()
        .providerPageNavigationTitle("Payout Settings")
        .toolbar(.visible, for: .navigationBar)
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
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

    // MARK: - Chrome

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ProviderOliveChromeStyle.adminTabTrackFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ProviderOliveChromeStyle.adminTabTrackStroke(colorScheme), lineWidth: 0.6)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Payout Settings tabs")
    }

    private func tabButton(_ tab: MainTab) -> some View {
        let isSelected = mainTab == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                mainTab = tab
            }
        } label: {
            Text(tab.rawValue)
                .font(.provider(.subheadline, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(
                    isSelected
                        ? ProviderOliveChromeStyle.adminTabActiveForeground(colorScheme)
                        : ProviderOliveChromeStyle.adminTabInactiveForeground(colorScheme)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ProviderOliveChromeStyle.adminTabActiveFill(colorScheme))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var tabBody: some View {
        switch mainTab {
        case .payouts:
            payoutsTab
        case .analytics:
            ProviderBusinessAnalyticsView(embedsOwnNavigationStack: false)
        }
    }

    // MARK: - Payouts tab

    @ViewBuilder
    private var payoutsTab: some View {
        if !session.hasProviderProfile {
            ContentUnavailableView(
                "No barber profile",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Complete barber setup, then pull to refresh.")
            )
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if stripeGate.isLoading && !stripeGate.hasLoadedOnce {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(.providerOlive)
                Text("Checking Stripe Connect…")
                    .font(.provider(.subheadline))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isFullyConnected {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    connectedStatusBadge
                    faqSection
                    expressAndAppRow
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .refreshable { await stripeGate.refresh() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProviderPaymentsOnboardingGuideView(
                        blocking: false,
                        embedded: true,
                        gate: stripeGate
                    )
                }
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .refreshable { await stripeGate.refresh() }
        }
    }

    private var connectedStatusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.provider(size: 18, weight: .semibold))
            Text("Stripe Connect is Active")
                .font(.provider(.subheadline, weight: .semibold))
        }
        .foregroundStyle(Color.green)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.green.opacity(0.16))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.green.opacity(0.45), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stripe Connect is Active")
    }

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payouts Q&A")
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)

            VStack(spacing: 0) {
                ForEach(Array(Self.faqItems.enumerated()), id: \.element.id) { index, item in
                    faqRow(item)
                    if index < Self.faqItems.count - 1 {
                        Divider()
                            .overlay(Color.lavaShellCream.opacity(0.12))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.providerScheduleCardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.providerScheduleCardStroke, lineWidth: 0.6)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func faqRow(_ item: FAQItem) -> some View {
        let isExpanded = expandedFAQID == item.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    expandedFAQID = isExpanded ? nil : item.id
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text(item.title)
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .accessibilityHint(isExpanded ? "Collapse answer" : "Expand answer")
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])

            Text(item.body)
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .frame(maxHeight: isExpanded ? nil : 0, alignment: .top)
                .opacity(isExpanded ? 1 : 0)
                .clipped()
                .allowsHitTesting(isExpanded)
        }
    }

    private var expressAndAppRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await openStripeExpress() }
            } label: {
                HStack(spacing: 8) {
                    if connectBusy {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(connectBusy ? "Opening…" : "Open Stripe Express")
                        .font(.provider(.subheadline, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .background(Self.stripePurple, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(connectBusy)
            .accessibilityLabel("Open Stripe Express")

            Button {
                openURL(Self.stripeDashboardAppStoreURL)
            } label: {
                Text("Get Stripe App")
                    .font(.provider(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Self.stripePurple)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Self.stripePurple, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get Stripe App")
            .accessibilityHint("Optional. Opens the App Store.")
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
