import SwiftUI

/// Detail view for a single barber as seen from the Admin or Campus-Manager dashboard.
///
/// Shows the barber's profile summary, a "visible to consumers" toggle (Admin / CM can hide a barber),
/// and the most-recent bookings from `/admin/barbers/:id/bookings`.
struct ProviderAdminBarberDetailView: View {
    @State private var barber: AdminBarberDTO
    @State private var bookings: [AdminBarberBookingDTO] = []
    @State private var isLoading = true
    @State private var isToggling = false
    @State private var errorText: String?

    init(barber: AdminBarberDTO) {
        _barber = State(initialValue: barber)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileCard
                if let errorText {
                    Text(errorText)
                        .font(.provider(.footnote))
                        .foregroundStyle(.red)
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
        .navigationTitle(barber.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .providerLavaScreenChrome()
    }

    private var profileCard: some View {
        sectionCard(title: "Profile", subtitle: barber.email) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AvatarView(url: barber.avatarURL, fallbackName: barber.displayName)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(barber.displayName)
                            .font(.provider(.title3, weight: .semibold))
                        if let cn = barber.campusName { Text(cn).font(.provider(.caption)).foregroundStyle(Color.lavaShellCreamSecondary) }
                        HStack(spacing: 6) {
                            if barber.isCampusManager == true { tag(text: "Campus manager", tint: Color.providerOlive) }
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
            }
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
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Server returned \(code)."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func setActive(_ newValue: Bool) async {
        guard let recordId = barber.barberRecordId else { return }
        let previous = barber.isActive ?? false
        // Optimistic update so the Toggle reflects the intent immediately; revert on failure.
        barber = withIsActive(barber, newValue: newValue)
        isToggling = true
        defer { isToggling = false }
        do {
            try await ProviderAdminService.setBarberActive(barberRecordId: recordId, isActive: newValue)
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            barber = withIsActive(barber, newValue: previous)
            errorText = msg ?? "Visibility update failed (\(code))."
        } catch {
            barber = withIsActive(barber, newValue: previous)
            errorText = error.localizedDescription
        }
    }

    private func withIsActive(_ b: AdminBarberDTO, newValue: Bool) -> AdminBarberDTO {
        AdminBarberDTO(
            id: b.id,
            barberRecordId: b.barberRecordId,
            firstName: b.firstName,
            lastName: b.lastName,
            email: b.email,
            profileImageUrl: b.profileImageUrl,
            isActive: newValue,
            isCampusManager: b.isCampusManager,
            campusId: b.campusId,
            campusName: b.campusName,
            hasStripeSetup: b.hasStripeSetup,
            hasStripeAccountOnly: b.hasStripeAccountOnly,
            createdAt: b.createdAt,
            completedBookings: b.completedBookings,
            totalVolumeCents: b.totalVolumeCents
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
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
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

    private func statusBadge(_ status: String) -> some View {
        let tint: Color = switch status {
        case "COMPLETED", "PAID": Color.providerOlive
        case "CANCELLED", "REFUNDED", "DISPUTED": Color.red.opacity(0.7)
        case "PENDING": Color.orange.opacity(0.75)
        case "ACCEPTED", "IN_PROGRESS": Color.blue.opacity(0.7)
        default: Color.gray.opacity(0.6)
        }
        return Text(status.replacingOccurrences(of: "_", with: " "))
            .font(.provider(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
    }

    private func dollarStringFromCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}
