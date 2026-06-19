import SwiftUI

/// Stripe Connect payouts — parity with web `PaymentManagementModal` (Payout Settings).
struct ProviderPayoutSettingsView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(\.openURL) private var openURL

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
                    description: Text("Complete barber setup on the web, then pull to refresh.")
                )
                .foregroundStyle(Color.lavaShellCream)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(.providerOlive)
                                Text("Loading…")
                                    .font(.provider(.subheadline))
                                    .foregroundStyle(Color.lavaShellCreamSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            stripeConnectSection
                            stripeMobileAppSection
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Payout Settings")
                    .font(.provider(.headline, weight: .semibold))
            }
        }
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

    private var stripeConnectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stripe Connect")
                .font(.provider(.title2, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)

            VStack(alignment: .leading, spacing: 12) {
                Text("Open Stripe to view payouts or finish bank setup.")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)

                if connectStatusUnknown {
                    Text("Status unavailable — you can still open Stripe below.")
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.orange.opacity(0.95))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }

                if connectStatusUnknown || connectStatus?.hasAccount == true {
                    actionButton(
                        title: connectBusy == .dashboard ? "Opening…" : "Open Stripe dashboard",
                        prominent: true
                    ) {
                        Task { await openStripeDashboard() }
                    }
                }

                actionButton(
                    title: onboardingButtonTitle,
                    prominent: !(connectStatusUnknown || connectStatus?.hasAccount == true)
                ) {
                    Task { await startStripeOnboarding() }
                }
            }
            .padding(14)
            .background(Color.providerOlive.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.providerOlive.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private static let stripeDashboardAppStoreURL = URL(string: "https://apps.apple.com/app/id978516833")!

    private var stripeMobileAppSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stripe App")
                .font(.provider(.title2, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)

            VStack(alignment: .leading, spacing: 12) {
                Text("Optional — track balances and payout activity on your phone.")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)

                actionButton(title: "Get Stripe Dashboard app", prominent: false) {
                    openURL(Self.stripeDashboardAppStoreURL)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func actionButton(title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.provider(.body, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    prominent ? Color.providerOlive.opacity(0.45) : Color.white.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(.plain)
        .disabled(connectBusy != nil)
    }

    private var onboardingButtonTitle: String {
        if connectBusy == .onboarding { return "Redirecting…" }
        if connectStatus?.hasAccount == true { return "Update payout details" }
        return "Set up Stripe Connect"
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            connectStatusUnknown = false
        }
        let connRes: Result<BarberConnectStatusDTO, Error> = await {
            do {
                return .success(try await ProviderBarberPayoutService.fetchConnectStatus())
            } catch {
                return .failure(error)
            }
        }()
        await MainActor.run {
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
                errorAlert = Self.userMessage(for: error, fallback: "Could not open Stripe. Finish Connect setup first.")
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
