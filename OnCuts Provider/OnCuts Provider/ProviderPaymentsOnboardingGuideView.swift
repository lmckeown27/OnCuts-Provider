import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Payments Onboarding Guide — web `StripeHubModal` parity.
/// Education + a left Checklist drawer (chevron); Connect “done” comes only from live Stripe flags.
struct ProviderPaymentsOnboardingGuideView: View {
    @Environment(ProviderSession.self) private var session
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
    @State private var isChecklistOpen = false

    private let contentMaxWidth: CGFloat = 400
    private let checklistDrawerWidth: CGFloat = 300
    /// Stripe-brand purple for the primary Connect CTA.
    private static let stripePurple = Color(red: 99 / 255, green: 91 / 255, blue: 255 / 255)
    private static let stripeAboutURL = URL(string: "https://en.wikipedia.org/wiki/Stripe,_Inc.")!

    private var status: BarberConnectStatusDTO? { gate.status }
    private var isConnected: Bool { BarberStripeConnectStatus.isFullyConnected(status) }
    private var needsReconnect: Bool { status?.needsReconnect == true }

    var body: some View {
        Group {
            if embedded {
                embeddedChrome
                    .foregroundStyle(Color.lavaShellCream)
            } else {
                NavigationStack {
                    guideCanvas
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

    private var embeddedChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                checklistToggleButton
                Spacer(minLength: 0)
                signOutButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            guideCanvas
        }
    }

    @ToolbarContentBuilder
    private var guideToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            checklistToggleButton
                .fixedSize(horizontal: true, vertical: false)
        }
        if !blocking {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Color.lavaShellCream)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            signOutButton
        }
    }

    private var signOutButton: some View {
        Button("Sign Out") {
            Task { await session.signOut() }
        }
        .font(.provider(.subheadline, weight: .semibold))
        .foregroundStyle(Color.lavaShellCream)
        .accessibilityLabel("Sign out")
    }

    private var checklistToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isChecklistOpen.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isChecklistOpen ? "chevron.left" : "chevron.right")
                    .font(.provider(.body, weight: .bold))
                Text("Checklist")
                    .font(.provider(.body, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.lavaShellCream)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(minWidth: 120, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isChecklistOpen ? "Close checklist" : "Open checklist")
    }

    private var guideCanvas: some View {
        ZStack(alignment: .leading) {
            mainScroll
                .allowsHitTesting(!isChecklistOpen)

            if isChecklistOpen {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isChecklistOpen = false
                        }
                    }
                    .transition(.opacity)

                checklistDrawer
                    .frame(width: checklistDrawerWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }

    private var mainScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                    welcomeCopy
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
                    primaryCTA
                    if !isConnected {
                        whySeeingGuideBanner
                    }
                    if !blocking, !isConnected {
                        secondaryRecheckButton
                    }
                }
            }
            .padding(embedded ? 16 : 20)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.bottom, embedded ? 8 : 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.clear)
    }

    // MARK: - Copy

    private var whySeeingGuideBanner: some View {
        Text("You're seeing this because you still need to connect with Stripe to enable safe and secure payments.")
            .font(.provider(.subheadline, weight: .semibold))
            .foregroundStyle(Color.lavaShellCream)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
    }

    private var welcomeCopy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to OnCuts Operator!")
                .font(.provider(.title3, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            (
                Text("OnCuts relies on a third-party payment processing system. This third-party is Stripe, which you can read more about ")
                + Text("here").underline().foregroundColor(.blue)
                + Text(".")
            )
            .font(.provider(.body))
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture { openURL(Self.stripeAboutURL) }
            .accessibilityAddTraits(.isLink)
            .accessibilityHint("Opens Stripe’s Wikipedia page")

            Text("When a client pays you, the transaction is handled by Stripe. Stripe securely moves funds from your customers to your bank account.")
                .font(.provider(.body))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Stripe will ask for personal details (date of birth, address, bank account, and more). Interact with the button below to connect payouts with OnCuts.")
                .font(.provider(.body))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Stuck on a step? Open Checklist in the top left corner.")
                .font(.provider(.body, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Checklist drawer

    private var checklistDrawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Checklist")
                    .font(.provider(.headline, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isChecklistOpen = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close checklist")
            }

            Text("Static guidance for fields Stripe often asks for. Expanding an item does not verify or mark anything complete.")
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Self.checklistItems) { item in
                        checklistRow(item)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.providerOlive)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func checklistRow(_ item: ChecklistItem) -> some View {
        let expanded = expandedChecklistID == item.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedChecklistID = expanded ? nil : item.id
                }
            } label: {
                HStack(spacing: 10) {
                    Text(item.title)
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .overlay(Color.white.opacity(0.12))
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.detail)
                            .font(.provider(.subheadline))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        if item.isCopyable {
                            Button {
                                #if os(iOS)
                                UIPasteboard.general.string = item.detail
                                #endif
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.provider(.caption, weight: .semibold))
                                    .foregroundStyle(Color.lavaShellCreamSecondary)
                                    .padding(6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy text to clipboard")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    // MARK: - CTA

    private var primaryCTA: some View {
        Button {
            Task { await handlePrimaryCTA() }
        } label: {
            HStack(spacing: 10) {
                if connectBusy {
                    ProgressView()
                        .tint(Color.white)
                }
                Text(connectBusy ? "Opening…" : primaryCTATitle)
                    .font(.provider(.headline, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Self.stripePurple, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    // MARK: - Static checklist (guidance only — web StripeHubModal parity)

    private struct ChecklistItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        var isCopyable: Bool = false
    }

    private static let checklistItems: [ChecklistItem] = [
        ChecklistItem(
            id: "dob",
            title: "Date of birth",
            detail: "Your legal date of birth exactly as it appears on your government ID (MM / DD / YYYY)."
        ),
        ChecklistItem(
            id: "address",
            title: "Home address",
            detail: "Your current residential street address, city, state, and ZIP. Use the address on your ID or bank statements."
        ),
        ChecklistItem(
            id: "phone",
            title: "Phone number",
            detail: "A US mobile number you can receive SMS on. Use the same number you use for OnCuts Provider if possible."
        ),
        ChecklistItem(
            id: "ssn",
            title: "Last four digits of SSN",
            detail: "The last 4 digits of your Social Security number as the account representative. Stripe will never ask for your full SSN."
        ),
        ChecklistItem(
            id: "industry",
            title: "Industry",
            detail: "Other personal services",
            isCopyable: true
        ),
        ChecklistItem(
            id: "website",
            title: "Business website",
            detail: "https://oncuts.com",
            isCopyable: true
        ),
        ChecklistItem(
            id: "bank",
            title: "Bank account (external account)",
            detail: "Select your bank institution in Stripe (Chase, Wells Fargo, etc) and connect the account where you want payouts deposited."
        ),
        ChecklistItem(
            id: "link",
            title: "Continue with Link",
            detail: "Not now"
        ),
        ChecklistItem(
            id: "tos",
            title: "Accept terms of service",
            detail: "Read and accept the Stripe Connected Account Agreement. Payments and payouts stay blocked until you accept."
        ),
    ]
}
