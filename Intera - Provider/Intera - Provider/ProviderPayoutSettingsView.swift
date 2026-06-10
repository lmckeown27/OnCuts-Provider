import SwiftUI

/// Stripe Connect payouts and booking estimates — parity with web `PaymentManagementModal` (Payout Settings).
struct ProviderPayoutSettingsView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(\.openURL) private var openURL

    @State private var summary: BarberPayoutSummaryDTO?
    @State private var connectStatus: BarberConnectStatusDTO?
    @State private var connectStatusUnknown = false
    @State private var isLoading = true
    @State private var connectBusy: ConnectBusy?
    @State private var errorAlert: String?

    private enum ConnectBusy {
        case dashboard
        case onboarding
    }

    var body: some View {
        Group {
            if !session.hasProviderProfile {
                ContentUnavailableView(
                    "No barber profile",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Complete your CampusCuts barber setup on the web, then return here and pull to refresh.")
                )
                .foregroundStyle(Color.lavaShellCream)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Stripe Connect payouts · booking estimates (not a platform balance)")
                            .font(.footnote)
                            .foregroundStyle(Color.lavaShellCreamSecondary)

                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(.providerOlive)
                                Text("Loading payout settings…")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.lavaShellCreamSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            if let summary, summary.hasBarberProfile {
                                revenueSection(summary)
                            }
                            stripeConnectSection
                            stripeMobileAppSection
                            howPaymentsWorkSection
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .refreshable { await load() }
            }
        }
        .providerNavigationStackDestinationBackdrop()
        .navigationTitle("Payout Settings")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .task { await load() }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorAlert != nil },
            set: { if !$0 { errorAlert = nil } }
        )) {
            Button("OK", role: .cancel) { errorAlert = nil }
        } message: {
            Text(errorAlert ?? "")
        }
    }

    private func revenueSection(_ s: BarberPayoutSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Revenue overview", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
            Text(
                "Figures reflect paid bookings and internal records for your reference. Payout cash is not stored in a platform balance—funds flow to your Stripe Connect account per Stripe’s schedule."
            )
            .font(.caption)
            .foregroundStyle(Color.lavaShellCreamSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated received")
                        .font(.caption)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    Text(s.displayTotalDollars, format: .currency(code: "USD"))
                        .font(.title3.weight(.bold))
                    Text(s.usesLedger ? "From ledger records (accounting); payouts still go through Stripe Connect." : "From paid bookings (~85% of service after platform fee + tips).")
                        .font(.caption2)
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Paid bookings")
                        .font(.caption)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    Text("\(s.paidBookingsCount)")
                        .font(.title3.weight(.bold))
                    Text("Completed checkout")
                        .font(.caption2)
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Last 30 days (estimate)")
                        .font(.caption)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    Text(Double(s.recent30DBarberCents) / 100, format: .currency(code: "USD"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.providerOlive)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridCellColumns(2)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            if s.usesLedger {
                HStack(spacing: 8) {
                    Text("Recorded settled: \(s.ledgerPaidOutDollars, format: .currency(code: "USD"))")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2), in: Capsule())
                    if s.ledgerPendingDollars > 0 {
                        Text("Recorded pending: \(s.ledgerPendingDollars, format: .currency(code: "USD"))")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.22), in: Capsule())
                    }
                }
                .foregroundStyle(Color.lavaShellCreamSecondary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private var stripeConnectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Stripe Connect", systemImage: "building.columns.fill")
                .font(.subheadline.weight(.semibold))
            Text("Open your Stripe Express dashboard to see payouts, balances, and bank transfers—or finish setup if you haven’t connected yet.")
                .font(.caption)
                .foregroundStyle(Color.lavaShellCreamSecondary)

            if connectStatusUnknown {
                Text("Could not load your Connect status. You can still open Stripe or start setup below.")
                    .font(.caption2)
                    .foregroundStyle(Color.orange.opacity(0.95))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }

            if connectStatusUnknown || connectStatus?.hasAccount == true {
                Button {
                    Task { await openStripeDashboard() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text(connectBusy == .dashboard ? "Opening…" : "Open Stripe dashboard")
                        Spacer()
                    }
                    .font(.body.weight(.semibold))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.providerOlive.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(connectBusy != nil)
            }

            Button {
                Task { await startStripeOnboarding() }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text(onboardingButtonTitle)
                    Spacer()
                }
                .font(.body.weight(.semibold))
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    (connectStatusUnknown || connectStatus?.hasAccount == true)
                        ? Color.white.opacity(0.1)
                        : Color.providerOlive.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
            .disabled(connectBusy != nil)
        }
        .padding(14)
        .background(Color.providerOlive.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.providerOlive.opacity(0.35), lineWidth: 1)
        )
    }

    /// Stripe Dashboard (merchant) — official App Store listing.
    private static let stripeDashboardAppStoreURL = URL(string: "https://apps.apple.com/app/id978516833")!

    private var stripeMobileAppSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Manage revenue on the go", systemImage: "iphone")
                .font(.subheadline.weight(.semibold))
            (
                Text("Download the ")
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    + Text("Stripe Dashboard").fontWeight(.semibold).foregroundStyle(Color.lavaShellCream)
                    + Text(
                        " app from the App Store once your Connect account is set up. It is the easiest way to watch your balance, payouts, and deposits in real time—and Stripe can notify you about new activity."
                    )
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            )
            .font(.caption)
            Button {
                openURL(Self.stripeDashboardAppStoreURL)
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Get Stripe Dashboard on the App Store")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                .font(.body.weight(.semibold))
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            Text("Use the web flow above first if you still need to finish Stripe Connect onboarding.")
                .font(.caption2)
                .foregroundStyle(Color.lavaShellCreamTertiary)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private var onboardingButtonTitle: String {
        if connectBusy == .onboarding { return "Redirecting…" }
        if connectStatus?.hasAccount == true { return "Continue or update payout details in Stripe" }
        return "Set up Stripe Connect"
    }

    private var howPaymentsWorkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How payments work")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                bulletRow("Customer pays in USD through Stripe Checkout (card / enabled methods).")
                bulletRow("Your share is paid out through Stripe Connect. The platform does not hold barber payout funds in a balance.")
                bulletRow("Use the buttons above to open Stripe or finish Connect onboarding.")
            }
            .font(.caption)
            .foregroundStyle(Color.lavaShellCreamSecondary)
        }
        .padding(.top, 4)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            connectStatusUnknown = false
        }
        async let sumTask: BarberPayoutSummaryDTO? = {
            try? await ProviderBarberPayoutService.fetchPayoutSummary()
        }()
        async let connTask: Result<BarberConnectStatusDTO, Error> = {
            do {
                return .success(try await ProviderBarberPayoutService.fetchConnectStatus())
            } catch {
                return .failure(error)
            }
        }()
        let (sum, connRes) = await (sumTask, connTask)
        await MainActor.run {
            summary = sum
            switch connRes {
            case .success(let st):
                connectStatus = st
                connectStatusUnknown = false
            case .failure:
                connectStatus = nil
                connectStatusUnknown = true
            }
            isLoading = false
        }
    }

    private func openStripeDashboard() async {
        await MainActor.run { connectBusy = .dashboard }
        defer { Task { @MainActor in connectBusy = nil } }
        do {
            let url = try await ProviderBarberPayoutService.fetchStripeDashboardURL()
            await MainActor.run { openURL(url) }
        } catch {
            await MainActor.run {
                errorAlert = Self.userMessage(for: error, fallback: "Could not open Stripe. Try completing Connect setup first.")
            }
        }
    }

    private func startStripeOnboarding() async {
        await MainActor.run { connectBusy = .onboarding }
        defer { Task { @MainActor in connectBusy = nil } }
        do {
            let url = try await ProviderBarberPayoutService.createConnectOnboardingURL()
            await MainActor.run { openURL(url) }
        } catch {
            await MainActor.run {
                errorAlert = Self.userMessage(for: error, fallback: "Could not start Stripe Connect.")
            }
        }
    }

    private static func userMessage(for error: Error, fallback: String) -> String {
        if let e = error as? CampusCutsHTTPError, case .httpStatus(_, let raw) = e {
            if let data = raw?.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any],
               let msg = err["message"] as? String,
               !msg.isEmpty {
                return msg
            }
        }
        return fallback
    }
}
