import SwiftUI

/// Detail view for a single platform user as seen from the Admin dashboard.
/// Fetches the user's consumer bookings (`/admin/users/:id/bookings`) and renders profile info.
struct ProviderAdminUserDetailView: View {
    let user: AdminPlatformUserDTO

    @State private var bookings: [AdminConsumerBookingDTO] = []
    @State private var isLoading = true
    @State private var errorText: String?

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
        .providerPageNavigationTitle(user.displayName)
        .providerLavaScreenChrome()
    }

    private var profileCard: some View {
        sectionCard(title: "Profile", subtitle: user.email) {
            HStack(spacing: 12) {
                AvatarView(url: user.avatarURL, fallbackName: user.displayName)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.provider(.title3, weight: .semibold))
                    Text(user.prettyRole)
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    if let cn = user.campusName, !cn.isEmpty {
                        Text(cn).font(.provider(.caption2)).foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                    if user.isActive == false {
                        Text("Blocked")
                            .font(.provider(.caption2, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.7), in: Capsule())
                    }
                }
                Spacer()
            }
        }
    }

    private var bookingsCard: some View {
        sectionCard(
            title: "Bookings",
            subtitle: bookings.isEmpty ? nil : "\(bookings.count) loaded."
        ) {
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

    private func bookingRow(_ b: AdminConsumerBookingDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(b.barberDisplayName)
                    .font(.provider(.subheadline, weight: .semibold))
                Spacer()
                statusBadge((b.status ?? "").uppercased())
            }
            HStack(spacing: 6) {
                Text(b.serviceDisplayName)
                if let p = b.totalPaidCents ?? b.priceCents {
                    Text("·"); Text(dollarStringFromCents(p))
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
        isLoading = true
        defer { isLoading = false }
        errorText = nil
        do {
            bookings = try await ProviderAdminService.userBookings(userId: user.id)
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Server returned \(code)."
        } catch {
            errorText = error.localizedDescription
        }
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
