import Charts
import SwiftUI

struct ProviderBusinessAnalyticsPerformanceView: View {
    let snapshot: BarberBusinessAnalyticsSnapshot
    @Binding var selectedPeriod: BarberAnalyticsPeriod
    var onOpenStripeHub: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryStrip
            timelinePills
            volumeChart
            metricsGrid
            stripeHubCard
            earningsHeroCard
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(title: "Period", value: snapshot.periodLabel)
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

    private var timelinePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BarberAnalyticsPeriod.allCases) { period in
                    Button {
                        selectedPeriod = period
                    } label: {
                        Text(period.summaryLabel)
                            .font(.provider(.caption, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedPeriod == period
                                        ? Color.providerOlive.opacity(0.55)
                                        : Color.white.opacity(0.08))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        selectedPeriod == period
                                            ? Color.providerOlive.opacity(0.85)
                                            : Color.lavaShellCream.opacity(0.18),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var volumeChart: some View {
        ProviderAnalyticsSectionCard(
            title: "Volume timeline",
            subtitle: "Paid booking volume across the selected period."
        ) {
            if snapshot.chartPoints.isEmpty {
                Text("No volume recorded for this period.")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                Chart {
                    ForEach(snapshot.chartPoints) { point in
                        let volumeDollars = Double(point.volumeCents) / 100
                        AreaMark(
                            x: .value("Period", point.date),
                            y: .value("Volume", volumeDollars)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.providerOlive.opacity(0.55), Color.providerOlive.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Period", point.date),
                            y: .value("Volume", volumeDollars)
                        )
                        .foregroundStyle(Color.providerOlive)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .frame(height: 220)
                .chartXAxis {
                    AxisMarks(preset: .automatic, position: .bottom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [4, 4]))
                            .foregroundStyle(Color.lavaShellCream.opacity(0.15))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                    .font(.provider(.caption2))
                                    .foregroundStyle(Color.lavaShellCreamSecondary)
                                    .providerAnalyticsMonospacedValue()
                            }
                        }
                    }
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            paymentMethodsCard
            earningsSplitCard
            bookingPipelineCard
        }
    }

    private var paymentMethodsCard: some View {
        ProviderAnalyticsSectionCard(title: "Payment methods", subtitle: "Card vs cash completions.") {
            VStack(spacing: 10) {
                metricRow(
                    label: "Card volume",
                    value: ProviderAnalyticsFormatting.currency(cents: snapshot.cardVolumeCents),
                    detail: "\(snapshot.cardCompletionCount) completed"
                )
                metricRow(
                    label: "Cash volume",
                    value: ProviderAnalyticsFormatting.currency(cents: snapshot.cashVolumeCents),
                    detail: "\(snapshot.cashCompletionCount) completed"
                )
            }
        }
        .gridCellColumns(2)
    }

    private var earningsSplitCard: some View {
        ProviderAnalyticsSectionCard(title: "Earnings split", subtitle: "Gross, platform cut, and take-home.") {
            VStack(alignment: .leading, spacing: 10) {
                metricRow(
                    label: "Gross volume",
                    value: ProviderAnalyticsFormatting.currency(cents: snapshot.grossVolumeCents),
                    detail: nil
                )
                metricRow(
                    label: "Platform cut",
                    value: ProviderAnalyticsFormatting.currency(cents: snapshot.platformCutCents),
                    detail: nil,
                    valueColor: .red.opacity(0.88)
                )
                metricRow(
                    label: "Take-home",
                    value: ProviderAnalyticsFormatting.currency(cents: snapshot.takeHomeCents),
                    detail: nil,
                    valueColor: .green.opacity(0.9)
                )

                Divider().overlay(Color.lavaShellCream.opacity(0.12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tip summary")
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    checklistRow("Tips collected", value: ProviderAnalyticsFormatting.currency(cents: snapshot.tipTotalCents))
                    checklistRow("Included in take-home", value: snapshot.tipTotalCents > 0 ? "Yes" : "No")
                }
            }
        }
        .gridCellColumns(2)
    }

    private var bookingPipelineCard: some View {
        ProviderAnalyticsSectionCard(title: "Booking pipeline", subtitle: "Pending, upcoming, and completed.") {
            VStack(spacing: 10) {
                metricRow(label: "Pending", value: "\(snapshot.pendingCount)", detail: nil)
                metricRow(label: "Upcoming", value: "\(snapshot.upcomingCount)", detail: nil)
                metricRow(
                    label: "Completion rate",
                    value: ProviderAnalyticsFormatting.percent(snapshot.completionRate),
                    detail: "\(snapshot.completedCount) completed"
                )
            }
        }
        .gridCellColumns(2)
    }

    private var stripeHubCard: some View {
        Button(action: onOpenStripeHub) {
            HStack(spacing: 12) {
                Image(systemName: "building.columns.fill")
                    .font(.provider(.title3))
                    .foregroundStyle(Color.providerOlive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stripe Express Hub")
                        .font(.provider(.subheadline, weight: .semibold))
                    Text("Manage payouts, identity, and card processing.")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream.opacity(0.45))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.providerOlive.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.providerOlive.opacity(0.45), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(ProviderAnalyticsScalePressStyle())
    }

    private var earningsHeroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated net take-home")
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text(ProviderAnalyticsFormatting.currency(cents: snapshot.estimatedNetTakeHomeCents))
                .font(.provider(.largeTitle, weight: .bold))
                .foregroundStyle(Color.lavaShellCream)
                .providerAnalyticsMonospacedValue()
            Text("After platform fees, including tips for the selected period.")
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                }
            }
        }
    }

    private func checklistRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.provider(.caption))
                .foregroundStyle(Color.providerOlive)
            Text(label)
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .providerAnalyticsMonospacedValue()
        }
    }
}
