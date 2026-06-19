import SwiftUI

struct ProviderBusinessAnalyticsPerformanceView: View {
    let bookings: [SimpleBookingDTO]
    let snapshot: BarberBusinessAnalyticsSnapshot
    @Binding var metricsTimeline: BarberPerformanceTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryStrip
            ProviderBarberPerformanceTimelineView(
                bookings: bookings,
                timeline: $metricsTimeline
            )
            cardVsCashCard
            earningsHeroCard
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(title: "Volume", value: ProviderAnalyticsFormatting.currency(cents: snapshot.grossVolumeCents))
            summaryCell(title: "Bookings", value: "\(snapshot.bookingCount)")
            summaryCell(title: "Clients", value: "\(snapshot.uniqueClientCount)")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func summaryCell(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.provider(.caption2, weight: .semibold))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text(value)
                .font(.provider(.caption, weight: .bold))
                .foregroundStyle(Color.lavaShellCream)
                .providerAnalyticsMonospacedValue()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var cardVsCashCard: some View {
        ProviderAnalyticsSectionCard(title: "Card vs cash", subtitle: nil) {
            VStack(spacing: 12) {
                paymentTypeBlock(
                    title: "Card",
                    volumeCents: snapshot.cardVolumeCents,
                    completionCount: snapshot.cardCompletionCount,
                    platformCutCents: snapshot.platformCutCents,
                    takeHomeCents: snapshot.cardTakeHomeCents
                )

                Divider().overlay(Color.lavaShellCream.opacity(0.12))

                paymentTypeBlock(
                    title: "Cash",
                    volumeCents: snapshot.cashVolumeCents,
                    completionCount: snapshot.cashCompletionCount,
                    platformCutCents: 0,
                    takeHomeCents: snapshot.cashTakeHomeCents
                )
            }
        }
    }

    private func paymentTypeBlock(
        title: String,
        volumeCents: Int,
        completionCount: Int,
        platformCutCents: Int,
        takeHomeCents: Int
    ) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                Spacer(minLength: 8)
                Text(ProviderAnalyticsFormatting.currency(cents: volumeCents))
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lavaShellCream)
                    .providerAnalyticsMonospacedValue()
            }

            metricRow(
                label: "Paid bookings",
                value: "\(completionCount)",
                detail: nil
            )

            if platformCutCents > 0 {
                metricRow(
                    label: "Platform fee",
                    value: ProviderAnalyticsFormatting.currency(cents: platformCutCents),
                    detail: nil,
                    valueColor: .red.opacity(0.88)
                )
            }

            metricRow(
                label: "Take-home",
                value: ProviderAnalyticsFormatting.currency(cents: takeHomeCents),
                detail: nil
            )
        }
    }

    private var earningsHeroCard: some View {
        VStack(spacing: 12) {
            Text("Estimated net take-home")
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 0) {
                takeHomeComparisonCell(
                    title: "Card",
                    value: ProviderAnalyticsFormatting.currency(cents: snapshot.cardTakeHomeCents)
                )
                takeHomeComparisonCell(
                    title: "Cash",
                    value: ProviderAnalyticsFormatting.currency(cents: snapshot.cashTakeHomeCents)
                )
            }

        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.providerOlive.opacity(0.35), Color.providerOlive.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.providerOlive.opacity(0.55), lineWidth: 1)
                )
        )
    }

    private func takeHomeComparisonCell(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text(value)
                .font(.provider(.title2, weight: .bold))
                .foregroundStyle(Color.lavaShellCream)
                .providerAnalyticsMonospacedValue()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricRow(
        label: String,
        value: String,
        detail: String?,
        valueColor: Color = Color.lavaShellCream
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(valueColor)
                    .providerAnalyticsMonospacedValue()
                if let detail {
                    Text(detail)
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}
