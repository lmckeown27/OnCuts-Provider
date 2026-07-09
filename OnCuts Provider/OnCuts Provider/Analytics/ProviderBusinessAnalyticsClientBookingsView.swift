import SwiftUI

struct ProviderBusinessAnalyticsClientBookingsView: View {
    let client: BarberClient
    let bookings: [SimpleBookingDTO]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                clientHeader

                if bookings.isEmpty {
                    Text("No bookings found for this client.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(bookings) { booking in
                            bookingRow(booking)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .providerNavigationStackDestinationBackdrop()
        .foregroundStyle(Color.lavaShellCream)
        .providerLavaScreenChrome()
    }

    private var clientHeader: some View {
        VStack(spacing: 6) {
            Text(client.name)
                .font(.provider(.title3, weight: .bold))
                .foregroundStyle(Color.lavaShellCream)
                .multilineTextAlignment(.center)

            Text("\(client.bookingCount) bookings · \(ProviderAnalyticsFormatting.currency(cents: client.lifetimeVolumeCents)) revenue")
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .multilineTextAlignment(.center)
                .providerAnalyticsMonospacedValue()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 4)
    }

    private func bookingRow(_ booking: SimpleBookingDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(booking.serviceDisplayName)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(bookingAmount(booking))
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lavaShellCream)
                    .providerAnalyticsMonospacedValue()
            }

            HStack(spacing: 8) {
                Text(booking.statusDisplayTitle)
                    .font(.provider(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(booking.statusDisplayTint, in: Capsule())

                if let payment = paymentLabel(for: booking) {
                    Text(payment)
                        .font(.provider(.caption2, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Scheduled \(booking.formattedSchedule())")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                if let paidAt = booking.paidAt {
                    Text("Paid \(paidAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))")
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                if let location = booking.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                    Text(location)
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                )
        )
    }

    private func bookingAmount(_ booking: SimpleBookingDTO) -> String {
        let cents = booking.totalPaidCents ?? booking.priceUsdCents ?? 0
        return ProviderAnalyticsFormatting.currency(cents: cents)
    }

    private func paymentLabel(for booking: SimpleBookingDTO) -> String? {
        guard booking.paidAt != nil else { return nil }
        return booking.isCashPayment ? "Cash" : "Card"
    }
}
