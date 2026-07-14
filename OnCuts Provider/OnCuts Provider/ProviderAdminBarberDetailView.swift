import SwiftUI

/// Detail view for a single barber as seen from the Admin or Campus-Manager dashboard.
///
/// Shows the barber's profile summary, a "visible to consumers" toggle (Admin / CM can hide a barber),
/// per-provider payment / commission settings, and the most-recent bookings from
/// `/admin/barbers/:id/bookings`.
struct ProviderAdminBarberDetailView: View {
    @State private var barber: AdminBarberDTO
    @State private var bookings: [AdminBarberBookingDTO] = []
    @State private var isLoading = true
    @State private var isToggling = false
    @State private var isMessaging = false
    @State private var isSavingCommission = false
    @State private var commissionFeePercentInput = ""
    @State private var commissionFreeRemainingInput = "0"
    @State private var commissionSaveMessage: String?
    @State private var errorText: String?

    init(barber: AdminBarberDTO) {
        _barber = State(initialValue: barber)
        _commissionFeePercentInput = State(initialValue: Self.feePercentInput(from: barber))
        _commissionFreeRemainingInput = State(
            initialValue: String(barber.commissionFreeBookingsRemaining ?? 0)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileCard
                paymentSettingsCard
                if let errorText {
                    Text(errorText)
                        .font(.provider(.footnote))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }
                if let commissionSaveMessage {
                    Text(commissionSaveMessage)
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.green.opacity(0.9))
                        .padding(.horizontal, 12)
                }
                bookingsCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .providerNavigationStackDestinationBackdrop()
        .refreshable { await loadBookings() }
        .task { await loadBookings() }
        .providerPageNavigationTitle(barber.displayName)
        .providerLavaScreenChrome()
        .onChange(of: barber.id) { _, _ in
            syncCommissionFormFromBarber()
        }
    }

    private var profileCard: some View {
        sectionCard(title: "Profile", subtitle: barber.email) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ProviderSquaredAvatarView(
                        url: barber.avatarURL,
                        fallbackName: barber.displayName,
                        size: 56
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(barber.displayName)
                            .font(.provider(.title3, weight: .semibold))
                        Text(barber.publicLocationDisplay)
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                        HStack(spacing: 6) {
                            if barber.hasStripeSetup == true {
                                tag(text: "Payouts on", tint: Color.green.opacity(0.55))
                            } else if barber.hasStripeAccountOnly == true {
                                tag(text: "Stripe pending", tint: Color.orange.opacity(0.55))
                            } else {
                                tag(text: "No Stripe", tint: Color.white.opacity(0.18))
                            }
                        }
                    }
                    Spacer()
                }
                visibilityRow
                messageBarberButton
            }
        }
    }

    private var paymentSettingsCard: some View {
        sectionCard(
            title: "Payment settings",
            subtitle: "Default commission 15% · tips never commissioned"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Commission rate (%)")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    TextField("15 (default)", text: $commissionFeePercentInput)
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCream)
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Color.providerScheduleActionBackground,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.providerScheduleActionBorder, lineWidth: 0.8)
                        )
                        .disabled(isSavingCommission)
                    Text("Leave blank to use the platform default (15%)")
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Commission-free bookings remaining")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    TextField("0", text: $commissionFreeRemainingInput)
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCream)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Color.providerScheduleActionBackground,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.providerScheduleActionBorder, lineWidth: 0.8)
                        )
                        .disabled(isSavingCommission)
                    Text("Next N card bookings take $0 platform fee, then the rate above applies")
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }

                Button {
                    Task { await savePaymentSettings() }
                } label: {
                    Group {
                        if isSavingCommission {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.providerOnOliveFill)
                        } else {
                            Text("Save payment settings")
                                .font(.provider(.subheadline, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(.providerOlive)
                .disabled(isSavingCommission || barber.barberRecordId == nil)

                HStack(spacing: 8) {
                    Button {
                        commissionFreeRemainingInput = "5"
                    } label: {
                        Text("Set 5 free")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSavingCommission)

                    Button {
                        commissionFeePercentInput = ""
                        commissionFreeRemainingInput = "0"
                    } label: {
                        Text("Reset to default")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSavingCommission)
                }
            }
        }
    }

    private var messageBarberButton: some View {
        Button {
            Task { await messageBarber() }
        } label: {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text(isMessaging ? "Opening chat…" : "Message barber")
                    .font(.provider(.subheadline, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            .foregroundStyle(Color.lavaShellCream)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.providerOlive.opacity(0.22))
            )
        }
        .buttonStyle(.plain)
        .disabled(isMessaging)
    }

    @MainActor
    private func messageBarber() async {
        isMessaging = true
        defer { isMessaging = false }
        errorText = nil
        do {
            _ = try await ProviderBarberChatOpener.openSupportChat(barberUserId: barber.id)
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Could not open chat (\(code))."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var visibilityRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Visible to consumers")
                    .font(.provider(.subheadline, weight: .semibold))
                Text(barber.isActive == true
                     ? "Customers can see and book this barber."
                     : "Hidden from the consumer marketplace.")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { barber.isActive ?? false },
                set: { newValue in
                    Task { await setActive(newValue) }
                }
            ))
            .labelsHidden()
            .tint(Color.providerOlive)
            .disabled(isToggling)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var bookingsCard: some View {
        sectionCard(title: "Recent bookings", subtitle: bookings.isEmpty ? nil : "\(bookings.count) loaded.") {
            if bookings.isEmpty {
                Text(isLoading ? "Loading bookings…" : "No bookings yet.")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(bookings.prefix(50)) { b in
                        bookingRow(b)
                    }
                    if bookings.count > 50 {
                        Text("Showing first 50 of \(bookings.count). Refine on the web dashboard for more.")
                            .font(.provider(.caption2))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                }
            }
        }
    }

    private func bookingRow(_ b: AdminBarberBookingDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(b.consumerDisplayName)
                    .font(.provider(.title3, weight: .semibold))
                Spacer()
                statusBadge((b.status ?? "").uppercased())
            }
            HStack(spacing: 6) {
                Text(b.serviceDisplayName)
                if let p = b.totalPaidCents ?? b.priceCents {
                    Text("·")
                    Text(dollarStringFromCents(p))
                }
                if let pm = b.paymentMethod, !pm.isEmpty {
                    Text("·"); Text(pm.capitalized)
                }
            }
            .font(.provider(.caption))
            .foregroundStyle(Color.lavaShellCreamSecondary)
            if let t = b.scheduledTime {
                Text(t, format: .dateTime.month().day().year().hour().minute())
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            if let r = b.reviewRating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.provider(.caption2)).foregroundStyle(.yellow)
                    Text(String(format: "%.1f", r)).font(.provider(.caption2))
                    if let text = b.reviewText, !text.isEmpty {
                        Text("· \(text)")
                            .font(.provider(.caption2))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Actions

    private func loadBookings() async {
        guard let recordId = barber.barberRecordId else {
            isLoading = false
            errorText = "Missing barber record id."
            return
        }
        isLoading = true
        defer { isLoading = false }
        errorText = nil
        do {
            bookings = try await ProviderAdminService.barberBookings(barberRecordId: recordId)
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Server returned \(code)."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func setActive(_ newValue: Bool) async {
        guard let recordId = barber.barberRecordId else { return }
        let previous = barber.isActive ?? false
        // Optimistic update so the Toggle reflects the intent immediately; revert on failure.
        barber = copyBarber(barber, isActive: newValue)
        isToggling = true
        defer { isToggling = false }
        do {
            try await ProviderAdminService.setBarberActive(barberRecordId: recordId, isActive: newValue)
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            barber = copyBarber(barber, isActive: previous)
            errorText = msg ?? "Visibility update failed (\(code))."
        } catch {
            barber = copyBarber(barber, isActive: previous)
            errorText = error.localizedDescription
        }
    }

    private func savePaymentSettings() async {
        guard let recordId = barber.barberRecordId else {
            errorText = "Missing provider profile id."
            return
        }

        let feeRaw = commissionFeePercentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let platformFeePercent: Double?
        if feeRaw.isEmpty {
            platformFeePercent = nil
        } else {
            guard let pct = Double(feeRaw), pct >= 0, pct <= 100 else {
                errorText = "Commission rate must be 0–100, or blank for default 15%."
                return
            }
            platformFeePercent = (pct * 100).rounded() / 100
        }

        let freeRaw = commissionFreeRemainingInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let freeRemaining = Int(freeRaw), freeRemaining >= 0 else {
            errorText = "Commission-free bookings must be a whole number ≥ 0."
            return
        }

        isSavingCommission = true
        errorText = nil
        commissionSaveMessage = nil
        defer { isSavingCommission = false }
        do {
            let updated = try await ProviderAdminService.updateBarberCommission(
                barberRecordId: recordId,
                platformFeePercent: platformFeePercent,
                commissionFreeBookingsRemaining: freeRemaining
            )
            barber = copyBarber(
                barber,
                platformFeePercent: updated.platformFeePercent,
                commissionFreeBookingsRemaining: updated.commissionFreeBookingsRemaining ?? freeRemaining,
                clearPlatformFeePercent: updated.platformFeePercent == nil
            )
            syncCommissionFormFromBarber()
            commissionSaveMessage = "Payment settings saved."
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Failed to save payment settings (\(code))."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func syncCommissionFormFromBarber() {
        commissionFeePercentInput = Self.feePercentInput(from: barber)
        commissionFreeRemainingInput = String(barber.commissionFreeBookingsRemaining ?? 0)
    }

    private static func feePercentInput(from barber: AdminBarberDTO) -> String {
        guard let pct = barber.platformFeePercent, pct.isFinite else { return "" }
        if pct.rounded() == pct {
            return String(Int(pct))
        }
        return String(pct)
    }

    private func copyBarber(
        _ b: AdminBarberDTO,
        isActive: Bool? = nil,
        platformFeePercent: Double? = nil,
        commissionFreeBookingsRemaining: Int? = nil,
        clearPlatformFeePercent: Bool = false
    ) -> AdminBarberDTO {
        let fee: Double?
        if clearPlatformFeePercent {
            fee = nil
        } else if let platformFeePercent {
            fee = platformFeePercent
        } else {
            fee = b.platformFeePercent
        }
        return AdminBarberDTO(
            id: b.id,
            barberRecordId: b.barberRecordId,
            firstName: b.firstName,
            lastName: b.lastName,
            email: b.email,
            profileImageUrl: b.profileImageUrl,
            isActive: isActive ?? b.isActive,
            isBanned: b.isBanned,
            isCampusManager: b.isCampusManager,
            campusId: b.campusId,
            campusName: b.campusName,
            hasStripeSetup: b.hasStripeSetup,
            hasStripeAccountOnly: b.hasStripeAccountOnly,
            createdAt: b.createdAt,
            completedBookings: b.completedBookings,
            totalVolumeCents: b.totalVolumeCents,
            serviceLocationLabel: b.serviceLocationLabel,
            hasServiceLocation: b.hasServiceLocation,
            platformFeePercent: fee,
            commissionFreeBookingsRemaining: commissionFreeBookingsRemaining ?? b.commissionFreeBookingsRemaining
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.provider(.title3, weight: .semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.providerScheduleCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.providerScheduleCardStroke, lineWidth: 0.6)
                )
        )
    }

    private func tag(text: String, tint: Color) -> some View {
        Text(text)
            .font(.provider(.caption2, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.6), in: Capsule())
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let tint: Color = {
            switch status {
            case "COMPLETED", "PAID": return .green
            case "CANCELLED": return .red
            case "PENDING", "CONFIRMED": return .orange
            default: return Color.white.opacity(0.25)
            }
        }()
        Text(status.prefix(1) + status.dropFirst().lowercased())
            .font(.provider(.caption2, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.25), in: Capsule())
    }

    private func dollarStringFromCents(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(Double(cents) / 100.0)"
    }
}
