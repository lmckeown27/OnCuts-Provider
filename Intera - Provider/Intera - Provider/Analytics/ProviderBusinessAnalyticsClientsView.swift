import SwiftUI

struct ProviderBusinessAnalyticsClientsView: View {
    let clients: [BarberClient]
    var onSelectClient: (BarberClient) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(clients.count == 1 ? "1 client" : "\(clients.count) clients")
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            if clients.isEmpty {
                Text("Clients appear here after their first booking with you.")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(clients) { client in
                        clientCard(client)
                    }
                }
            }
        }
    }

    private func clientCard(_ client: BarberClient) -> some View {
        Button {
            onSelectClient(client)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(client.name)
                        .font(.provider(.body, weight: .bold))
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(1)

                    if let email = client.email, !email.isEmpty {
                        Text(email)
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 12) {
                        Text("\(client.bookingCount) bookings")
                            .providerAnalyticsMonospacedValue()
                        Text(ProviderAnalyticsFormatting.currency(cents: client.lifetimeVolumeCents))
                            .providerAnalyticsMonospacedValue()
                    }
                    .font(.provider(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamTertiary)

                    Text("Last booked \(client.formattedLastBooking)")
                        .font(.provider(.caption2))
                        .italic()
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream.opacity(0.28))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(ProviderAnalyticsScalePressStyle())
    }
}
