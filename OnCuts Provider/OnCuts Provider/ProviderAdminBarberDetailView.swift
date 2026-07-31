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
    @State private var commissionFreeRemainingInput = "0"
    @State private var kickbackPercentInput = "0"
    @State private var commissionSaveMessage: String?
    @State private var errorText: String?
    private let platformFeePercent: Double

    init(barber: AdminBarberDTO, platformFeePercent: Double = 15) {
        _barber = State(initialValue: barber)
        _commissionFreeRemainingInput = State(
            initialValue: String(barber.commissionFreeBookingsRemaining ?? 0)
        )
        _kickbackPercentInput = State(initialValue: Self.kickbackPercentInput(from: barber))
        self.platformFeePercent = platformFeePercent
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
        .background(ProviderAdminChrome.canvasBackground.ignoresSafeArea())
        .providerAdminDismissesKeyboardOnOutsideTap()
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
                            .foregroundStyle(ProviderAdminChrome.secondaryText)
                        HStack(spacing: 6) {
                            if barber.hasStripeSetup == true {
                                tag(text: "Payouts on", tint: Color.green.opacity(0.55))
                            } else if barber.hasStripeAccountOnly == true {
                                tag(text: "Stripe pending", tint: Color.orange.opacity(0.55))
                            } else {
                                tag(text: "No Stripe", tint: Color.white.opacity(0.18))
                            }
                            if let free = barber.commissionFreeBookingsRemaining, free > 0 {
                                tag(text: "\(free) free", tint: Color.green.opacity(0.4))
                            }
                            if let kickback = barber.kickbackPercent, kickback > 0 {
                                tag(text: Self.kickbackTagLabel(kickback), tint: Color.providerOlive.opacity(0.55))
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
            subtitle: "Platform commission \(Self.formatFee(platformFeePercent))% · tips never commissioned"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Commission-free bookings remaining")
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                    TextField("0", text: $commissionFreeRemainingInput)
                        .font(.provider(.subheadline))
                        .foregroundStyle(ProviderAdminChrome.primaryText)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            ProviderAdminChrome.mutedFill,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(ProviderAdminChrome.border, lineWidth: 0.8)
                        )
                        .disabled(isSavingCommission)
                    Text("Next N card bookings take $0 platform fee (default 5), then \(Self.formatFee(platformFeePercent))% applies")
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider kickback %")
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                    TextField("0", text: $kickbackPercentInput)
                        .font(.provider(.subheadline))
                        .foregroundStyle(ProviderAdminChrome.primaryText)
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            ProviderAdminChrome.mutedFill,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(ProviderAdminChrome.border, lineWidth: 0.8)
                        )
                        .disabled(isSavingCommission)
                    Text("Only on commissionless bookings: platform pays this % of service (not tip) to the provider")
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
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
                        kickbackPercentInput = "10"
                    } label: {
                        Text("Set 10% kickback")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSavingCommission)
                }

                Button {
                    commissionFreeRemainingInput = "5"
                    kickbackPercentInput = "0"
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
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
            }
            .foregroundStyle(ProviderAdminChrome.primaryText)
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
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
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
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            } else {
                VStack(spacing: 10) {
                    ForEach(bookings.prefix(50)) { b in
                        bookingRow(b)
                    }
                    if bookings.count > 50 {
                        Text("Showing first 50 of \(bookings.count). Refine on the web dashboard for more.")
                            .font(.provider(.caption2))
                            .foregroundStyle(ProviderAdminChrome.tertiaryText)
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
            .foregroundStyle(ProviderAdminChrome.secondaryText)
            if let t = b.paidAt ?? b.scheduledTime {
                Text(t, format: .dateTime.month().day().year().hour().minute())
                    .font(.provider(.caption2))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
            }
            if let r = b.reviewRating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.provider(.caption2)).foregroundStyle(.yellow)
                    Text(String(format: "%.1f", r)).font(.provider(.caption2))
                    if let text = b.reviewText, !text.isEmpty {
                        Text("· \(text)")
                            .font(.provider(.caption2))
                            .foregroundStyle(ProviderAdminChrome.secondaryText)
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

        let freeRaw = commissionFreeRemainingInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let freeRemaining = Int(freeRaw), freeRemaining >= 0 else {
            errorText = "Commission-free bookings must be a whole number ≥ 0."
            return
        }

        let kickbackRaw = kickbackPercentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kickbackPercent = Double(kickbackRaw.isEmpty ? "0" : kickbackRaw),
              kickbackPercent >= 0, kickbackPercent <= 100 else {
            errorText = "Kickback percent must be between 0 and 100."
            return
        }
        let kickbackRounded = (kickbackPercent * 100).rounded() / 100

        isSavingCommission = true
        errorText = nil
        commissionSaveMessage = nil
        defer { isSavingCommission = false }
        do {
            let updated = try await ProviderAdminService.updateBarberCommission(
                barberRecordId: recordId,
                commissionFreeBookingsRemaining: freeRemaining,
                kickbackPercent: kickbackRounded
            )
            barber = copyBarber(
                barber,
                commissionFreeBookingsRemaining: updated.commissionFreeBookingsRemaining ?? freeRemaining,
                kickbackPercent: updated.kickbackPercent ?? kickbackRounded
            )
            syncCommissionFormFromBarber()
            commissionSaveMessage = "Payment settings saved."
            NotificationCenter.default.post(name: .providerCommissionFreeQuotaChanged, object: nil)
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Failed to save payment settings (\(code))."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func syncCommissionFormFromBarber() {
        commissionFreeRemainingInput = String(barber.commissionFreeBookingsRemaining ?? 0)
        kickbackPercentInput = Self.kickbackPercentInput(from: barber)
    }

    private static func kickbackPercentInput(from barber: AdminBarberDTO) -> String {
        let pct = barber.kickbackPercent ?? 0
        guard pct.isFinite else { return "0" }
        if pct.rounded() == pct {
            return String(Int(pct))
        }
        return String(pct)
    }

    private static func kickbackTagLabel(_ percent: Double) -> String {
        if percent.rounded() == percent {
            return "\(Int(percent))% kickback"
        }
        return String(format: "%.1f%% kickback", percent)
    }

    private static func formatFee(_ percent: Double) -> String {
        if percent.rounded() == percent { return String(Int(percent)) }
        return String(format: "%.1f", percent)
    }

    private func copyBarber(
        _ b: AdminBarberDTO,
        isActive: Bool? = nil,
        commissionFreeBookingsRemaining: Int? = nil,
        kickbackPercent: Double? = nil
    ) -> AdminBarberDTO {
        AdminBarberDTO(
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
            platformFeePercent: b.platformFeePercent,
            commissionFreeBookingsRemaining: commissionFreeBookingsRemaining ?? b.commissionFreeBookingsRemaining,
            kickbackPercent: kickbackPercent ?? b.kickbackPercent
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
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ProviderAdminChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(ProviderAdminChrome.border, lineWidth: 0.6)
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
