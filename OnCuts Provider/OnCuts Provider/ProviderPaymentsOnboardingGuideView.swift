import SwiftUI

/// Payments Onboarding Guide — web `StripeHubModal` parity.
/// Education + static Express field help; Connect “done” comes only from live Stripe flags.
struct ProviderPaymentsOnboardingGuideView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    /// When true, Close is hidden and swipe-dismiss is disabled by the presenter.
    var blocking: Bool
    /// When true, render as inline content (no NavigationStack / auth chrome) for Payout Settings.
    var embedded: Bool = false
    @Bindable var gate: ProviderStripeOnboardingGate
    var onFullyConnected: (() -> Void)? = nil

    @State private var connectBusy = false
    @State private var platformCTADisabled = false
    @State private var bannerMessage: String?
    @State private var errorAlert: String?
    @State private var expandedChecklistID: String?
    @State private var showConnectedToast = false

    private let contentMaxWidth: CGFloat = 400

    private var status: BarberConnectStatusDTO? { gate.status }
    private var isConnected: Bool { BarberStripeConnectStatus.isFullyConnected(status) }
    private var needsReconnect: Bool { status?.needsReconnect == true }

    var body: some View {
        Group {
            if embedded {
                guideScrollContent
                    .foregroundStyle(Color.lavaShellCream)
            } else {
                NavigationStack {
                    guideScrollContent
                        .navigationTitle("Payments Onboarding Guide")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { guideToolbar }
                        .foregroundStyle(Color.lavaShellCream)
                        .tint(Color.providerBrandGold)
                        .providerAuthIntegratedScreenChrome()
                }
                .interactiveDismissDisabled(blocking)
            }
        }
        .task {
            await refreshFromStripe()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshFromStripe() }
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

    @ToolbarContentBuilder
    private var guideToolbar: some ToolbarContent {
        if !blocking {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Color.lavaShellCream)
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if gate.isLoading {
                ProgressView()
                    .tint(Color.providerBrandGold)
            } else {
                Button {
                    Task { await refreshFromStripe() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(connectBusy)
                .accessibilityLabel("Refresh Stripe status")
            }
        }
    }

    private var guideScrollContent: some View {
        let content = VStack(alignment: .leading, spacing: 20) {
            if embedded {
                HStack {
                    Text("Payments Onboarding Guide")
                        .font(.provider(.title2, weight: .semibold))
                    Spacer(minLength: 0)
                    if gate.isLoading {
                        ProgressView()
                            .tint(Color.providerBrandGold)
                    } else {
                        Button {
                            Task { await refreshFromStripe() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color.providerBrandGold)
                        }
                        .disabled(connectBusy)
                    }
                }
            }

            if gate.isLoading && !gate.hasLoadedOnce {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.providerBrandGold)
                    Text("Checking Stripe Connect…")
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                educationCard
                statusBanner
                if let bannerMessage {
                    Text(bannerMessage)
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.orange.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showConnectedToast {
                    Text("You’re fully connected. Payouts and card charges are enabled.")
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                checklistSection
                primaryCTA
                if !blocking, !isConnected {
                    secondaryRecheckButton
                }
            }
        }
        .padding(embedded ? 16 : 20)
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.bottom, embedded ? 8 : 28)

        return Group {
            if embedded {
                content
            } else {
                ScrollView {
                    content
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Color.clear)
            }
        }
    }

    // MARK: - Sections

    private var educationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get paid through Stripe Connect")
                .font(.provider(.title3, weight: .semibold))
            Text(
                "OnCuts uses Stripe Express so clients can pay by card and your earnings deposit to your bank. Finish the Stripe form once — we’ll unlock your dashboard when charges and payouts are enabled."
            )
            .font(.provider(.subheadline))
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(bannerTint)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(bannerTitle)
                    .font(.provider(.subheadline, weight: .bold))
                Text(bannerSubtitle)
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(bannerTint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(bannerTint.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private var bannerTint: Color {
        if isConnected { return .green }
        if needsReconnect { return .orange }
        return Color.providerBrandGold
    }

    private var bannerTitle: String {
        if isConnected { return "Stripe Connect active" }
        if needsReconnect { return "Reconnect required" }
        if status?.hasAccount == true { return "Finish Stripe setup" }
        return "Stripe Connect incomplete"
    }

    private var bannerSubtitle: String {
        if isConnected {
            return "Charges and payouts are enabled. You can open Stripe Express anytime to manage your bank and tax details."
        }
        if needsReconnect {
            return "Your previous Connect account isn’t valid on this Stripe platform. Reconnect to create a fresh Express account."
        }
        if status?.hasAccount == true {
            return "Your Express account exists, but Stripe still needs details before charges and payouts can turn on."
        }
        if gate.lastError != nil {
            return "We couldn’t verify your status. Try again, or continue with Stripe to start setup."
        }
        return "Create your Express account and complete Stripe’s required fields to accept payments."
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Checklist")
                .font(.provider(.headline, weight: .semibold))
            Text("Static guidance for fields Stripe often asks for. Expanding an item does not verify or mark anything complete.")
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(Self.checklistItems) { item in
                    checklistRow(item)
                }
            }
        }
    }

    private func checklistRow(_ item: ChecklistItem) -> some View {
        let expanded = expandedChecklistID == item.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedChecklistID = expanded ? nil : item.id
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "circle")
                        .foregroundStyle(Color.lavaShellCream.opacity(0.35))
                    Text(item.title)
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(item.detail)
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var primaryCTA: some View {
        Button {
            Task { await handlePrimaryCTA() }
        } label: {
            HStack(spacing: 10) {
                if connectBusy {
                    ProgressView()
                        .tint(Color.providerOnBrandGold)
                }
                Text(connectBusy ? "Opening…" : primaryCTATitle)
                    .font(.provider(.headline, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.provider(.body, weight: .bold))
            }
            .foregroundStyle(Color.providerOnBrandGold)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.providerBrandGold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(connectBusy || platformCTADisabled)
        .opacity(platformCTADisabled ? 0.55 : 1)
    }

    private var primaryCTATitle: String {
        if isConnected { return "Open Stripe Express" }
        if needsReconnect { return "Reconnect Stripe" }
        if status?.hasAccount == true { return "Open Stripe" }
        return "Continue with Stripe"
    }

    private var secondaryRecheckButton: some View {
        Button {
            Task { await refreshFromStripe() }
        } label: {
            Text("I’ve finished in Stripe — check again")
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(Color.providerBrandGold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(connectBusy || gate.isLoading)
    }

    // MARK: - Actions

    private func refreshFromStripe() async {
        await gate.refresh()
        if BarberStripeConnectStatus.isFullyConnected(gate.status) {
            showConnectedToast = true
            platformCTADisabled = false
            bannerMessage = nil
            onFullyConnected?()
        }
    }

    private func handlePrimaryCTA() async {
        connectBusy = true
        defer { connectBusy = false }
        do {
            await gate.refresh()
            if BarberStripeConnectStatus.isFullyConnected(gate.status) {
                showConnectedToast = true
                if blocking {
                    onFullyConnected?()
                    return
                }
                let url = try await ProviderBarberPayoutService.fetchStripeDashboardURL()
                openURL(url)
                return
            }

            let url = try await ProviderBarberPayoutService.onboardingURL(for: gate.status)
            platformCTADisabled = false
            bannerMessage = nil
            openURL(url)
        } catch let platform as BarberConnectPlatformError {
            bannerMessage = platform.errorDescription
            platformCTADisabled = platform.disablesCTA
            if !platform.disablesCTA {
                errorAlert = platform.errorDescription
            }
        } catch {
            errorAlert = (error as? LocalizedError)?.errorDescription
                ?? "Could not open Stripe Connect."
        }
    }

    // MARK: - Static checklist (guidance only)

    private struct ChecklistItem: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    private static let checklistItems: [ChecklistItem] = [
        ChecklistItem(
            id: "dob",
            title: "Date of birth",
            detail: "Enter your legal date of birth exactly as it appears on your ID."
        ),
        ChecklistItem(
            id: "address",
            title: "Home address",
            detail: "Use your residential address. A PO box usually isn’t accepted for identity verification."
        ),
        ChecklistItem(
            id: "phone",
            title: "Phone number",
            detail: "A mobile number Stripe can use for verification codes and account security."
        ),
        ChecklistItem(
            id: "ssn",
            title: "Last 4 of SSN",
            detail: "US operators typically provide the last four digits of their Social Security Number."
        ),
        ChecklistItem(
            id: "industry",
            title: "Industry",
            detail: "Choose personal services / barber or beauty as appropriate for the work you offer on OnCuts."
        ),
        ChecklistItem(
            id: "website",
            title: "Website",
            detail: "If Stripe asks for a business website, use oncuts.com."
        ),
        ChecklistItem(
            id: "bank",
            title: "Bank account",
            detail: "Link the checking account where you want payouts deposited."
        ),
        ChecklistItem(
            id: "link",
            title: "Stripe Link (optional)",
            detail: "You can save details with Link to speed up future Stripe forms."
        ),
        ChecklistItem(
            id: "tos",
            title: "Terms of Service",
            detail: "Accept Stripe’s Connected Account Agreement to finish onboarding."
        ),
    ]
}
