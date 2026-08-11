import SwiftUI

/// Payouts hub **Cancellations** tab — per-operator client full-refund window.
/// Reads `GET /barbers/me` and writes `PUT /barbers/:id` `{ client_cancel_refund_hours }`.
/// Does not require Stripe Connect. Refund eligibility is enforced server-side.
struct ProviderCancellationRefundPolicyView: View {
    @Environment(ProviderSession.self) private var session

    @State private var barberProfileId: String?
    @State private var selectedHours: ClientCancelRefundHoursPreset = .one
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var toast: String?
    @State private var toastIsError = false
    @State private var toastResetTask: Task<Void, Never>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var chipsDisabled: Bool {
        isLoading || isSaving || barberProfileId == nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let toast {
                    Text(toast)
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(toastIsError ? Color.white : Color.lavaShellCream)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            toastIsError ? Color.red.opacity(0.88) : Color.providerOlive.opacity(0.45),
                            in: Capsule()
                        )
                }

                policyCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 36)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .task { await loadPolicy() }
        .refreshable { await loadPolicy() }
        .onDisappear {
            toastResetTask?.cancel()
            toastResetTask = nil
        }
    }

    private var policyCard: some View {
        VStack(spacing: 12) {
            Text("Client cancellation refunds")
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.providerOlive)
                    Text("Loading…")
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            } else {
                Text("Client receives full refund if cancelled at least")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ClientCancelRefundHoursPreset.allCases) { preset in
                        hourChip(preset)
                    }
                }

                (Text("Current: ") + Text(selectedHours.currentFooterLabel).fontWeight(.semibold))
                    .font(.provider(.subheadline))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Current: \(selectedHours.currentFooterLabel)")
            }
        }
        .padding(18)
        .background(
            Color.providerScheduleCardFill,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.providerScheduleCardStroke, lineWidth: 0.6)
        )
    }

    private func hourChip(_ preset: ClientCancelRefundHoursPreset) -> some View {
        let selected = selectedHours == preset
        return Button {
            Task { await saveHours(preset) }
        } label: {
            Text(preset.chipLabel)
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(selected ? Color(uiColor: ProviderAppearance.shellBase) : Color.lavaShellCream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    selected ? Color.lavaShellCream : Color.providerElevatedSurface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            selected ? Color.lavaShellCream : Color.providerElevatedSurfaceStroke,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(chipsDisabled)
        .opacity(chipsDisabled ? 0.6 : 1)
        .accessibilityLabel("\(preset.rawValue) hour\(preset.rawValue == 1 ? "" : "s")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func loadPolicy() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await ProviderAuthService.fetchBarberMe()
            barberProfileId = profile.id
            selectedHours = ClientCancelRefundHoursPreset.from(profile.clientCancelRefundHours)
        } catch {
            barberProfileId = session.barberProfile?.id
            selectedHours = .one
            showToast("Could not load cancellation settings", isError: true)
        }
    }

    private func saveHours(_ hours: ClientCancelRefundHoursPreset) async {
        guard hours != selectedHours else { return }
        guard let barberProfileId else {
            showToast("Operator profile not loaded yet", isError: true)
            return
        }
        let previous = selectedHours
        selectedHours = hours
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await ProviderAuthService.updateClientCancelRefundHours(
                barberId: barberProfileId,
                hours: hours.rawValue
            )
            selectedHours = ClientCancelRefundHoursPreset.from(saved)
            showToast(selectedHours.successToast, isError: false)
        } catch {
            selectedHours = previous
            showToast("Could not save cancellation window", isError: true)
        }
    }

    private func showToast(_ message: String, isError: Bool) {
        toast = message
        toastIsError = isError
        toastResetTask?.cancel()
        toastResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { toast = nil }
        }
    }
}
