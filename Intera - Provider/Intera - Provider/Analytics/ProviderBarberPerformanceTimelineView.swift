import Charts
import SwiftUI

/// Interactive performance timeline for a single barber (parity with Admin dashboard chart).
struct ProviderBarberPerformanceTimelineView: View {
    let bookings: [SimpleBookingDTO]
    @Binding var timeline: BarberPerformanceTimeline

    @State private var selectedBucketIndex: Int?

    private var chartPoints: [BarberPerformanceMetricPoint] {
        ProviderBarberBusinessAnalyticsEngine.normalizedMetricPoints(
            from: bookings,
            timeline: timeline
        )
    }

    private var selectedPoint: BarberPerformanceMetricPoint? {
        guard let selectedBucketIndex,
              chartPoints.indices.contains(selectedBucketIndex)
        else { return nil }
        return chartPoints[selectedBucketIndex]
    }

    private var scopeTitle: String {
        "\(timeline.segmentTitle) Revenue"
    }

    private var rangeAggregate: (revenueDollars: Double, periodCount: Int) {
        let points = chartPoints
        return (
            revenueDollars: points.reduce(0) { $0 + $1.revenueDollars },
            periodCount: points.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scopeTitle)
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Timeline", selection: $timeline) {
                    ForEach(BarberPerformanceTimeline.allCases) { item in
                        Text(item.segmentTitle).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                timelineChartView(points: chartPoints)
                    .padding(.bottom, 12)

                if !chartPoints.isEmpty, selectedPoint == nil {
                    Text("Press and drag on the chart to inspect a single \(timeline.bucketUnitSingular)")
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }

                summaryGrid
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                )
        )
        .onChange(of: timeline) { _, _ in
            selectedBucketIndex = nil
        }
    }

    @ViewBuilder
    private var summaryGrid: some View {
        if !chartPoints.isEmpty {
            let aggregate = rangeAggregate
            let periodCount = max(1, aggregate.periodCount)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .center,
                spacing: 10
            ) {
                summaryCell(
                    title: primaryMetricTitle,
                    value: primaryMetricValue(
                        selectedPoint: selectedPoint,
                        aggregate: aggregate,
                        periodCount: periodCount
                    )
                )
                summaryCell(
                    title: timeline.bestBucketLabel,
                    value: bestMetricValue() ?? "—"
                )
            }
        } else {
            Text("No \(scopeTitle.lowercased()) data in this range yet.")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
    }

    private func summaryCell(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.provider(.subheadline, weight: .bold))
                .foregroundStyle(Color.lavaShellCream)
                .providerAnalyticsMonospacedValue()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var primaryMetricTitle: String {
        if let selectedPoint {
            return formattedChartPeriodLabel(for: selectedPoint.date)
        }
        return timeline.primaryMetricTitle
    }

    private func primaryMetricValue(
        selectedPoint: BarberPerformanceMetricPoint?,
        aggregate: (revenueDollars: Double, periodCount: Int),
        periodCount: Int
    ) -> String {
        if let selectedPoint {
            return formatRevenueDollars(selectedPoint.revenueDollars)
        }
        return formatRevenueDollars(aggregate.revenueDollars / Double(periodCount))
    }

    private func bestMetricValue() -> String? {
        guard let peak = chartPoints.max(by: { $0.revenueDollars < $1.revenueDollars }) else { return nil }
        return formatRevenueDollars(peak.revenueDollars)
    }

    @ViewBuilder
    private func timelineChartView(points: [BarberPerformanceMetricPoint]) -> some View {
        if points.isEmpty {
            Text("No data in this range yet (uses paid booking timestamps).")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        } else {
            Chart {
                areaLineSeries(
                    points: points,
                    seriesLabel: "Revenue",
                    yValue: { $0.revenueDollars }
                )

                if let selected = selectedPoint {
                    RuleMark(x: .value("Selected", selected.bucketIndex))
                        .foregroundStyle(Color.lavaShellCream.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .frame(height: 236)
            .chartXScale(domain: chartXPlotDomain(for: points), range: .plotDimension(padding: 0))
            .chartYScale(domain: ChartScale.yDomain(for: points))
            .chartXAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let plotRect = geometry[plotFrame]
                        let labelY = plotRect.maxY + 14
                        let gridColor = Color.lavaShellCream.opacity(0.12)
                        let gridStroke = StrokeStyle(lineWidth: 0.35)

                        ZStack {
                            plotGrid(
                                points: points,
                                plotRect: plotRect,
                                proxy: proxy,
                                color: gridColor,
                                stroke: gridStroke
                            )

                            ForEach(points) { point in
                                if let xPosition = proxy.position(forX: point.bucketIndex) {
                                    anchoredXAxisLabel(text: chartXAxisLabel(for: point.date))
                                        .position(x: plotRect.minX + xPosition, y: labelY)
                                }
                            }

                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .frame(width: plotRect.width, height: plotRect.height)
                                .position(x: plotRect.midX, y: plotRect.midY)
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            updateSelection(
                                                at: value.location,
                                                proxy: proxy,
                                                geometry: geometry,
                                                points: points
                                            )
                                        }
                                        .onEnded { _ in
                                            selectedBucketIndex = nil
                                        }
                                )
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(
                    position: .leading,
                    values: ChartScale.yAxisTickValues(
                        in: ChartScale.yDomain(for: points)
                    )
                ) { value in
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(chartYAxisRevenueLabel(for: number))
                                .font(.provider(.caption2))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                        }
                    }
                }
            }
        }
    }

    @ChartContentBuilder
    private func areaLineSeries(
        points: [BarberPerformanceMetricPoint],
        seriesLabel: String,
        yValue: @escaping (BarberPerformanceMetricPoint) -> Double
    ) -> some ChartContent {
        ForEach(points) { point in
            let isSelected = selectedPoint?.id == point.id
            let isDimmed = !(isSelected || selectedPoint == nil)
            AreaMark(
                x: .value("Period", point.bucketIndex),
                y: .value(seriesLabel, yValue(point))
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.providerOlive.opacity(isDimmed ? 0.25 : 0.55),
                        Color.providerOlive.opacity(isDimmed ? 0.04 : 0.08),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Period", point.bucketIndex),
                y: .value(seriesLabel, yValue(point))
            )
            .foregroundStyle(Color.providerOlive.opacity(isDimmed ? 0.45 : 1))
            .lineStyle(StrokeStyle(lineWidth: isSelected ? 2.5 : 2))
        }
    }

    @ViewBuilder
    private func plotGrid(
        points: [BarberPerformanceMetricPoint],
        plotRect: CGRect,
        proxy: ChartProxy,
        color: Color,
        stroke: StrokeStyle
    ) -> some View {
        let yTicks = ChartScale.yAxisTickValues(
            in: ChartScale.yDomain(for: points)
        )

        ZStack {
            ForEach(yTicks, id: \.self) { tick in
                if let yPosition = proxy.position(forY: tick) {
                    Path { path in
                        path.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY + yPosition))
                        path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.minY + yPosition))
                    }
                    .stroke(color, style: stroke)
                }
            }

            ForEach(points) { point in
                if let xPosition = proxy.position(forX: point.bucketIndex) {
                    Path { path in
                        path.move(to: CGPoint(x: plotRect.minX + xPosition, y: plotRect.minY))
                        path.addLine(to: CGPoint(x: plotRect.minX + xPosition, y: plotRect.maxY))
                    }
                    .stroke(color, style: stroke)
                }
            }
        }
    }

    private enum ChartScale {
        static func yDomain(for points: [BarberPerformanceMetricPoint]) -> ClosedRange<Double> {
            let maxValue = points.map(\.revenueDollars).max() ?? 0
            return 0 ... niceUpperBound(for: maxValue, minimum: 100, stepCount: 5)
        }

        static func niceUpperBound(for value: Double, minimum: Double, stepCount: Int) -> Double {
            guard value > 0 else { return minimum }
            let padded = value * 1.12
            let rawStep = padded / Double(max(1, stepCount - 1))
            guard rawStep > 0 else { return minimum }
            let magnitude = pow(10, floor(log10(rawStep)))
            let niceStep = max(magnitude, ceil(rawStep / magnitude) * magnitude)
            return niceStep * Double(stepCount - 1)
        }

        static func yAxisTickValues(in domain: ClosedRange<Double>) -> [Double] {
            let tickCount = 5
            let span = domain.upperBound - domain.lowerBound
            guard span > 0 else { return [0, 1, 2, 3, 4] }
            let step = span / Double(tickCount - 1)
            return (0..<tickCount).map { domain.lowerBound + step * Double($0) }
        }
    }

    private static let xAxisLabelFontSize: CGFloat = 9

    private func anchoredXAxisLabel(text: String) -> some View {
        let font = UIFont.provider(size: Self.xAxisLabelFontSize, weight: .regular, textStyle: .caption2)
        let anchorIndex = chartXAxisAnchorCharacterIndex(for: text)
        let shift = chartXAxisAnchorShift(text: text, anchorIndex: anchorIndex, font: font)

        return Color.clear
            .frame(width: 0, height: 12)
            .overlay {
                Text(text)
                    .font(.provider(size: Self.xAxisLabelFontSize, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .fixedSize()
                    .offset(x: shift)
            }
    }

    private func chartXAxisAnchorCharacterIndex(for text: String) -> Int {
        switch timeline {
        case .daily:
            return max(0, (text.count - 1) / 2)
        case .weekly:
            if let slashIndex = text.firstIndex(of: "/") {
                return text.distance(from: text.startIndex, to: slashIndex)
            }
            return max(0, (text.count - 1) / 2)
        case .monthly:
            return max(0, (text.count - 1) / 2)
        }
    }

    private func chartXAxisAnchorShift(text: String, anchorIndex: Int, font: UIFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let nsText = text as NSString
        let totalWidth = nsText.size(withAttributes: attributes).width
        guard !text.isEmpty, anchorIndex < text.count else { return 0 }

        let prefix = nsText.substring(to: anchorIndex) as NSString
        let prefixWidth = prefix.size(withAttributes: attributes).width
        let anchorChar = nsText.substring(with: NSRange(location: anchorIndex, length: 1)) as NSString
        let charWidth = anchorChar.size(withAttributes: attributes).width
        let anchorCenterX = prefixWidth + charWidth / 2
        return totalWidth / 2 - anchorCenterX
    }

    private func chartXPlotDomain(for points: [BarberPerformanceMetricPoint]) -> ClosedRange<Int> {
        guard let lastIndex = points.last?.bucketIndex, lastIndex >= 0 else { return 0 ... 0 }
        return 0 ... lastIndex
    }

    private func chartYAxisRevenueLabel(for value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value >= 100 || value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func chartXAxisLabel(for date: Date) -> String {
        switch timeline {
        case .daily:
            return date.formatted(.dateTime.weekday(.abbreviated))
        case .weekly:
            return date.formatted(.dateTime.month(.defaultDigits).day())
        case .monthly:
            return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }

    private func formattedChartPeriodLabel(for date: Date) -> String {
        switch timeline {
        case .daily:
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        case .weekly:
            return "Week of \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .monthly:
            return date.formatted(.dateTime.month(.wide).year())
        }
    }

    private func formatRevenueDollars(_ dollars: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }

    private func updateSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [BarberPerformanceMetricPoint]
    ) {
        guard !points.isEmpty, let plotFrame = proxy.plotFrame else { return }
        let plotRect = geometry[plotFrame]
        let rawX = location.x - plotRect.origin.x
        let xInPlot = min(max(rawX, 0), plotRect.width)
        guard plotRect.width > 0 else { return }

        if let index: Int = proxy.value(atX: xInPlot, as: Int.self) {
            selectedBucketIndex = min(max(0, index), points.count - 1)
            return
        }

        let fraction = Double(xInPlot / plotRect.width)
        let rawIndex = Int((fraction * Double(points.count)).rounded(.down))
        selectedBucketIndex = min(max(0, rawIndex), points.count - 1)
    }
}
