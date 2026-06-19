import Charts
import SwiftUI

/// Native iOS Admin dashboard.
///
/// Tabs mirror the daily-driver flows of the web `AdminDashboard.tsx`:
///   * **Performance** — platform totals, **time-series chart** (daily / weekly / monthly / yearly), plus
///     **campus search** (typeahead) to scope or clear to aggregate headline revenue / bookings / payout metrics.
///   * **Barbers** — every barber (optionally scoped by campus) with Stripe status badges; tap → push the
///     admin barber-detail screen (bookings + visibility toggle).
///   * **Users** — every platform user (optionally scoped by campus) with simple in-memory search; tap →
///     push the admin user-detail screen (consumer bookings).
///   * **Services** — platform service catalog (price / duration bounds, activate / deactivate).
struct ProviderAdminDashboardView: View {
    private enum AdminDashboardDestination: Hashable {
        case barber(AdminBarberDTO)
        case user(AdminPlatformUserDTO)
    }

    @State private var adminDetailPath = NavigationPath()

    enum Tab: String, CaseIterable, Identifiable {
        case performance = "Performance"
        case barbers = "Barbers"
        case users = "Users"
        case services = "Services"
        case safety = "Safety"
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .performance: "chart.xyaxis.line"
            case .barbers: "scissors"
            case .users: "person.2.fill"
            case .services: "list.bullet.rectangle.fill"
            case .safety: "shield.lefthalf.filled"
            }
        }
    }

    /// Reports status chip on the Safety tab. `all` is the only value that omits the `status`
    /// query parameter when calling `/admin/moderation/reports`. Web defaults to `open`.
    enum ReportsStatusFilter: String, CaseIterable, Identifiable {
        case open
        case all
        case resolved
        case dismissed

        var id: String { rawValue }

        var chipLabel: String {
            switch self {
            case .open: "Open"
            case .all: "All"
            case .resolved: "Resolved"
            case .dismissed: "Dismissed"
            }
        }

        var apiStatus: AdminModerationReportStatus? {
            switch self {
            case .all: nil
            case .open: .open
            case .resolved: .resolved
            case .dismissed: .dismissed
            }
        }
    }

    @State private var tab: Tab = .performance
    @State private var campuses: [AdminCampusDTO] = []
    @State private var selectedCampusId: String? = nil
    @State private var stats: AdminPlatformStatsDTO?
    @State private var performance: AdminCampusPerformanceDTO?
    @State private var barbers: [AdminBarberDTO] = []
    @State private var users: [AdminPlatformUserDTO] = []
    @State private var userSearch: String = ""
    @State private var usersVisibleCount = 25

    @State private var isLoading = true
    @State private var errorText: String?

    @State private var metricsSnapshot: AdminMetricsSnapshotDTO?
    @State private var metricsTimeline: MetricsTimeline = .daily
    @State private var metricsChartSeries: MetricsChartSeries = .revenue
    @State private var isLoadingMetrics = false
    @State private var selectedBucketIndex: Int?
    @State private var isChartScrubbing = false

    // MARK: Safety tab state
    //
    // Banned users and UGC reports are independent: each has its own loader, filter, and
    // error surface so a failing reports query doesn't blank the banned-users list and vice
    // versa. Action busy ids let us dim the row that's being mutated without forcing a global
    // spinner. Confirmation dialogs are driven by optional captured payloads (the row + the
    // intended action) which the dialog body unwraps to render its copy.
    @State private var moderationReports: [AdminModerationReportDTO] = []
    @State private var bannedUsers: [AdminBannedUserDTO] = []
    @State private var reportsStatusFilter: ReportsStatusFilter = .open
    @State private var bannedCategoryFilter: AdminBannedUserCategory = .all
    @State private var reportsLoading = false
    @State private var bannedLoading = false
    @State private var reportsError: String?
    @State private var bannedError: String?
    @State private var busyReportId: String?
    @State private var busyUnbanUserId: String?
    @State private var pendingReportResolution: PendingReportResolution?
    @State private var pendingUnban: AdminBannedUserDTO?

    private struct PendingReportResolution: Identifiable, Equatable {
        let id: UUID = UUID()
        let report: AdminModerationReportDTO
        let action: AdminModerationResolveAction
    }

    var body: some View {
        NavigationStack(path: $adminDetailPath) {
            adminDashboardRoot
                .navigationDestination(for: AdminDashboardDestination.self) { destination in
                    switch destination {
                    case .barber(let barber):
                        ProviderAdminBarberDetailView(barber: barber)
                            .providerShellHostDestinationRegistration()
                    case .user(let user):
                        ProviderAdminUserDetailView(user: user)
                            .providerShellHostDestinationRegistration()
                    }
                }
        }
    }

    private var adminDashboardRoot: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                campusPickerCard
                if let errorText {
                    Text(errorText)
                        .font(.provider(.footnote))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }
                tabPicker
                switch tab {
                case .performance: performanceTab
                case .barbers: barbersTab
                case .users: usersTab
                case .services: ProviderAdminServicesView()
                case .safety: safetyTab
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .providerNavigationStackDestinationBackdrop()
        .refreshable { await loadAll() }
        .task { await loadAll() }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Admin")
                    .font(.provider(.headline, weight: .semibold))
            }
        }
        .providerLavaScreenChrome()
        .onChange(of: userSearch) { _, _ in
            usersVisibleCount = 25
        }
        .onChange(of: metricsTimeline) { _, _ in
            selectedBucketIndex = nil
            Task { await reloadMetricsTimeline() }
        }
        .onChange(of: metricsChartSeries) { _, _ in
            selectedBucketIndex = nil
        }
        .onChange(of: reportsStatusFilter) { _, _ in
            Task { await loadModerationReports() }
        }
        .onChange(of: bannedCategoryFilter) { _, _ in
            Task { await loadBannedUsers() }
        }
        .confirmationDialog(
            pendingReportResolutionTitle,
            isPresented: Binding(
                get: { pendingReportResolution != nil },
                set: { if !$0 { pendingReportResolution = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = pendingReportResolution {
                Button(pending.action.displayLabel, role: pending.action.bansUser ? .destructive : nil) {
                    let captured = pending
                    pendingReportResolution = nil
                    Task { await applyReportResolution(captured) }
                }
                Button("Cancel", role: .cancel) {
                    pendingReportResolution = nil
                }
            }
        } message: {
            if let pending = pendingReportResolution {
                Text(pendingReportResolutionMessage(for: pending))
            }
        }
        .confirmationDialog(
            pendingUnbanTitle,
            isPresented: Binding(
                get: { pendingUnban != nil },
                set: { if !$0 { pendingUnban = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = pendingUnban {
                Button("Unban") {
                    let captured = target
                    pendingUnban = nil
                    Task { await applyUnban(captured) }
                }
                Button("Cancel", role: .cancel) {
                    pendingUnban = nil
                }
            }
        } message: {
            if let target = pendingUnban {
                Text("\(target.displayName) will be able to sign in, get discovered, and make bookings again. You can re-ban them later if needed.")
            }
        }
    }

    // MARK: - Metrics timeline (chart — parity with former Campus Manager overview)

    private enum MetricsTimeline: String, CaseIterable, Identifiable {
        case daily, weekly, monthly, yearly
        var id: String { rawValue }
        var segmentTitle: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            }
        }
        var apiPeriod: String { rawValue }
        var helperSubtitle: String {
            switch self {
            case .daily: return "Each day for the past week."
            case .weekly: return "Each week for the past month."
            case .monthly: return "Each month for the past six months."
            case .yearly: return "Each year for the past ten years."
            }
        }

        var chartBucketCount: Int {
            switch self {
            case .daily: return 7
            case .weekly: return 4
            case .monthly: return 6
            case .yearly: return 10
            }
        }

        var bucketUnitSingular: String {
            switch self {
            case .daily: return "day"
            case .weekly: return "week"
            case .monthly: return "month"
            case .yearly: return "year"
            }
        }

        var bestBucketLabel: String { "Best \(bucketUnitSingular)" }
        var primaryMetricTitle: String { "Average per \(bucketUnitSingular)" }
    }

    private enum MetricsChartSeries: String, CaseIterable, Identifiable {
        case revenue, bookings, signups
        var id: String { rawValue }
        var segmentTitle: String {
            switch self {
            case .revenue: return "Revenue"
            case .bookings: return "Bookings"
            case .signups: return "Sign-ups"
            }
        }
    }

    private struct MetricPlotPoint: Identifiable {
        let id: String
        let bucketIndex: Int
        let date: Date
        let revenueDollars: Double
        let bookings: Int
        let signups: Int
    }

    private enum MetricsDateParsing {
        static let isoFrac: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        static let isoBasic: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        static func parse(_ raw: String) -> Date? {
            isoFrac.date(from: raw) ?? isoBasic.date(from: raw)
        }
    }

    private var chartMetricPoints: [MetricPlotPoint] {
        normalizedMetricPoints(from: metricsSnapshot, timeline: metricsTimeline)
    }

    private var selectedMetricPoint: MetricPlotPoint? {
        guard let selectedBucketIndex,
              chartMetricPoints.indices.contains(selectedBucketIndex)
        else { return nil }
        return chartMetricPoints[selectedBucketIndex]
    }

    private var chartRangeAggregate: (revenueDollars: Double, bookings: Int, signups: Int, periodCount: Int) {
        let points = chartMetricPoints
        return (
            revenueDollars: points.reduce(0) { $0 + $1.revenueDollars },
            bookings: points.reduce(0) { $0 + $1.bookings },
            signups: points.reduce(0) { $0 + $1.signups },
            periodCount: points.count
        )
    }

    private var metricsScopeTitle: String {
        "\(metricsTimeline.segmentTitle) \(metricsChartSeries.segmentTitle)"
    }

    private var metricsContextLabel: String {
        if let point = selectedMetricPoint {
            return formattedChartPeriodLabel(for: point.date)
        }
        return metricsScopeTitle
    }

    // MARK: - Header chrome

    private var sortedCampuses: [AdminCampusDTO] {
        campuses.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var campusScopeLabel: String {
        guard let id = selectedCampusId,
              let c = campuses.first(where: { $0.id == id })
        else { return "All Campuses" }
        return c.displayName
    }

    private var campusPickerCard: some View {
        Menu {
            Button {
                selectedCampusId = nil
                Task { await loadScopedData() }
            } label: {
                HStack {
                    Text("All Campuses")
                    if selectedCampusId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if campuses.isEmpty {
                Text(isLoading ? "Loading campuses…" : "No campuses available")
            } else {
                ForEach(sortedCampuses) { campus in
                    Button {
                        selectedCampusId = campus.id
                        Task { await loadScopedData() }
                    } label: {
                        HStack {
                            Text(campus.displayName)
                            if selectedCampusId == campus.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Text(campusScopeLabel)
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .padding(.trailing, 14)
                }
        }
        .accessibilityLabel("Campus scope")
        .accessibilityValue(campusScopeLabel)
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                adminTabButton(item)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Admin section")
    }

    private func adminTabButton(_ item: Tab) -> some View {
        let isSelected = tab == item
        return Button {
            tab = item
        } label: {
            Image(systemName: item.systemImage)
                .font(.provider(.body, weight: isSelected ? .semibold : .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.providerOlive : Color.lavaShellCreamSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Performance tab

    private var performanceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            platformStatsCard
            performanceTimelineCard
            performanceCard
        }
    }

    private var performanceTimelineCard: some View {
        sectionCard(
            title: "Performance over time",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Timeline", selection: $metricsTimeline) {
                    ForEach(MetricsTimeline.allCases) { t in
                        Text(t.segmentTitle).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Series", selection: $metricsChartSeries) {
                    ForEach(MetricsChartSeries.allCases) { s in
                        Text(s.segmentTitle).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                ZStack {
                    if isLoading && metricsSnapshot == nil {
                        loadingRow("Loading chart…")
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                    } else {
                        metricsTimelineChartView(points: chartMetricPoints)
                            .padding(.bottom, 12)
                    }
                    if isLoadingMetrics {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                        ProgressView()
                            .controlSize(.regular)
                    }
                }

                if !chartMetricPoints.isEmpty, selectedMetricPoint == nil {
                    Text("Press and drag on the chart to inspect a single \(metricsTimeline.bucketUnitSingular).")
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(metricsContextLabel)
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)

                    if selectedMetricPoint == nil {
                        Text(metricsTimeline.helperSubtitle)
                            .font(.provider(.caption2))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                }

                metricsSummaryGrid
            }
        }
    }

    @ViewBuilder
    private var metricsSummaryGrid: some View {
        if !chartMetricPoints.isEmpty {
            metricsSummaryPair(selectedPoint: selectedMetricPoint)
        } else if isLoading || isLoadingMetrics {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading \(metricsScopeTitle.lowercased())…")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
        } else {
            Text("No \(metricsScopeTitle.lowercased()) data in this range yet.")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
    }

    @ViewBuilder
    private func metricsSummaryPair(selectedPoint: MetricPlotPoint?) -> some View {
        let aggregate = chartRangeAggregate
        let periodCount = max(1, aggregate.periodCount)

        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
            metricCell(
                title: primaryMetricTitle(selectedPoint: selectedPoint),
                value: primaryMetricValue(
                    selectedPoint: selectedPoint,
                    aggregate: aggregate,
                    periodCount: periodCount
                )
            )
            metricCell(
                title: metricsTimeline.bestBucketLabel,
                value: bestMetricValue() ?? "—"
            )
        }
    }

    private func primaryMetricTitle(selectedPoint: MetricPlotPoint?) -> String {
        if let selectedPoint {
            return formattedChartPeriodLabel(for: selectedPoint.date)
        }
        return metricsTimeline.primaryMetricTitle
    }

    private func primaryMetricValue(
        selectedPoint: MetricPlotPoint?,
        aggregate: (revenueDollars: Double, bookings: Int, signups: Int, periodCount: Int),
        periodCount: Int
    ) -> String {
        if let selectedPoint {
            switch metricsChartSeries {
            case .revenue: return formatRevenueDollars(selectedPoint.revenueDollars)
            case .bookings: return "\(selectedPoint.bookings)"
            case .signups: return "\(selectedPoint.signups)"
            }
        }

        switch metricsChartSeries {
        case .revenue:
            return formatRevenueDollars(aggregate.revenueDollars / Double(periodCount))
        case .bookings:
            return formattedAverage(aggregate.bookings, periods: periodCount)
        case .signups:
            return formattedAverage(aggregate.signups, periods: periodCount)
        }
    }

    private func bestMetricValue() -> String? {
        let peak: MetricPlotPoint?
        switch metricsChartSeries {
        case .revenue:
            peak = chartMetricPoints.max(by: { $0.revenueDollars < $1.revenueDollars })
            guard let peak else { return nil }
            return formatRevenueDollars(peak.revenueDollars)
        case .bookings:
            peak = chartMetricPoints.max(by: { $0.bookings < $1.bookings })
            guard let peak else { return nil }
            return "\(peak.bookings)"
        case .signups:
            peak = chartMetricPoints.max(by: { $0.signups < $1.signups })
            guard let peak else { return nil }
            return "\(peak.signups)"
        }
    }

    @ChartContentBuilder
    private func performanceAreaLineSeries(
        points: [MetricPlotPoint],
        seriesLabel: String,
        yValue: @escaping (MetricPlotPoint) -> Double
    ) -> some ChartContent {
        ForEach(points) { pt in
            let isSelected = selectedMetricPoint?.id == pt.id
            let isDimmed = !(isSelected || selectedMetricPoint == nil)
            AreaMark(
                x: .value("Period", pt.bucketIndex),
                y: .value(seriesLabel, yValue(pt))
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.providerOlive.opacity(isDimmed ? 0.25 : 0.55),
                        Color.providerOlive.opacity(isDimmed ? 0.04 : 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Period", pt.bucketIndex),
                y: .value(seriesLabel, yValue(pt))
            )
            .foregroundStyle(Color.providerOlive.opacity(isDimmed ? 0.45 : 1))
            .lineStyle(StrokeStyle(lineWidth: isSelected ? 2.5 : 2))
        }
    }

    @ViewBuilder
    private func metricsTimelineChartView(points: [MetricPlotPoint]) -> some View {
        if points.isEmpty {
            Text("No data in this range yet (uses paid booking timestamps).")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        } else {
            Chart {
                switch metricsChartSeries {
                case .revenue:
                    performanceAreaLineSeries(
                        points: points,
                        seriesLabel: "Revenue",
                        yValue: { $0.revenueDollars }
                    )
                case .bookings:
                    performanceAreaLineSeries(
                        points: points,
                        seriesLabel: "Bookings",
                        yValue: { Double($0.bookings) }
                    )
                case .signups:
                    performanceAreaLineSeries(
                        points: points,
                        seriesLabel: "Sign-ups",
                        yValue: { Double($0.signups) }
                    )
                }

                if let selected = selectedMetricPoint {
                    RuleMark(x: .value("Selected", selected.bucketIndex))
                        .foregroundStyle(Color.lavaShellCream.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .frame(height: 236)
            .chartXScale(domain: chartXPlotDomain(for: points), range: .plotDimension(padding: 0))
            .chartYScale(domain: MetricsChartScale.yDomain(for: points, series: metricsChartSeries))
            .chartXAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let plotRect = geometry[plotFrame]
                        let labelY = plotRect.maxY + 14
                        let gridColor = Color.lavaShellCream.opacity(0.12)
                        let gridStroke = StrokeStyle(lineWidth: 0.35)

                        ZStack {
                            metricsPlotGrid(
                                points: points,
                                plotRect: plotRect,
                                proxy: proxy,
                                color: gridColor,
                                stroke: gridStroke
                            )

                            ForEach(points) { pt in
                                if let xPosition = proxy.position(forX: pt.bucketIndex) {
                                    anchoredXAxisLabel(text: chartXAxisLabel(for: pt.date))
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
                                            beginChartScrubShellSuppressionIfNeeded()
                                            updateChartSelection(
                                                at: value.location,
                                                proxy: proxy,
                                                geometry: geometry,
                                                points: points
                                            )
                                        }
                                        .onEnded { _ in
                                            endChartScrubbingIfNeeded()
                                        }
                                )
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(
                    position: .leading,
                    values: MetricsChartScale.yAxisTickValues(
                        in: MetricsChartScale.yDomain(for: points, series: metricsChartSeries)
                    )
                ) { value in
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metricsYAxisLabel(for: number))
                                .font(.provider(.caption2))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metricsPlotGrid(
        points: [MetricPlotPoint],
        plotRect: CGRect,
        proxy: ChartProxy,
        color: Color,
        stroke: StrokeStyle
    ) -> some View {
        let yTicks = MetricsChartScale.yAxisTickValues(
            in: MetricsChartScale.yDomain(for: points, series: metricsChartSeries)
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

            ForEach(points) { pt in
                if let xPosition = proxy.position(forX: pt.bucketIndex) {
                    Path { path in
                        path.move(to: CGPoint(x: plotRect.minX + xPosition, y: plotRect.minY))
                        path.addLine(to: CGPoint(x: plotRect.minX + xPosition, y: plotRect.maxY))
                    }
                    .stroke(color, style: stroke)
                }
            }
        }
    }

    private func metricsYAxisLabel(for value: Double) -> String {
        switch metricsChartSeries {
        case .revenue: return chartYAxisRevenueLabel(for: value)
        case .bookings, .signups: return chartYAxisCountLabel(for: value)
        }
    }

    private enum MetricsChartScale {
        static func yValue(for point: MetricPlotPoint, series: MetricsChartSeries) -> Double {
            switch series {
            case .revenue: return point.revenueDollars
            case .bookings: return Double(point.bookings)
            case .signups: return Double(point.signups)
            }
        }

        static func yDomain(
            for points: [MetricPlotPoint],
            series: MetricsChartSeries
        ) -> ClosedRange<Double> {
            let maxValue = points.map { yValue(for: $0, series: series) }.max() ?? 0
            switch series {
            case .revenue:
                return 0 ... niceUpperBound(for: maxValue, minimum: 100, stepCount: 5)
            case .bookings, .signups:
                return 0 ... niceUpperBound(for: maxValue, minimum: 4, stepCount: 5)
            }
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

    private func anchoredXAxisLabel(text: String) -> some View {
        let font = UIFont.provider(size: 11, weight: .regular, textStyle: .caption2)
        let anchorIndex = chartXAxisAnchorCharacterIndex(for: text)
        let shift = chartXAxisAnchorShift(text: text, anchorIndex: anchorIndex, font: font)

        return Color.clear
            .frame(width: 0, height: 14)
            .overlay {
                Text(text)
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .fixedSize()
                    .offset(x: shift)
            }
    }

    private func chartXAxisAnchorCharacterIndex(for text: String) -> Int {
        switch metricsTimeline {
        case .daily:
            return max(0, (text.count - 1) / 2)
        case .weekly:
            if let slashIndex = text.firstIndex(of: "/") {
                return text.distance(from: text.startIndex, to: slashIndex)
            }
            return max(0, (text.count - 1) / 2)
        case .monthly, .yearly:
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

    private func chartXPlotDomain(for points: [MetricPlotPoint]) -> ClosedRange<Int> {
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

    private func chartYAxisCountLabel(for value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func chartXAxisLabel(for date: Date) -> String {
        switch metricsTimeline {
        case .daily:
            return date.formatted(.dateTime.weekday(.abbreviated))
        case .weekly:
            return date.formatted(.dateTime.month(.defaultDigits).day())
        case .monthly:
            return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        case .yearly:
            return date.formatted(.dateTime.year(.defaultDigits))
        }
    }

    private func formattedChartPeriodLabel(for date: Date) -> String {
        switch metricsTimeline {
        case .daily:
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        case .weekly:
            return "Week of \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .monthly:
            return date.formatted(.dateTime.month(.wide).year())
        case .yearly:
            return date.formatted(.dateTime.year())
        }
    }

    private func formatRevenueDollars(_ dollars: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }

    private func formattedAverage(_ total: Int, periods: Int) -> String {
        let average = Double(total) / Double(max(1, periods))
        return average.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func updateChartSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [MetricPlotPoint]
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

    private func endChartScrubbingIfNeeded() {
        selectedBucketIndex = nil
        endChartScrubShellSuppressionIfNeeded()
    }

    #if os(iOS)
    private func beginChartScrubShellSuppressionIfNeeded() {
        guard !isChartScrubbing else { return }
        isChartScrubbing = true
        ProviderShellNavigationPopBridge.shared.beginShellDismissGestureSuppression()
    }

    private func endChartScrubShellSuppressionIfNeeded() {
        guard isChartScrubbing else { return }
        isChartScrubbing = false
        ProviderShellNavigationPopBridge.shared.endShellDismissGestureSuppression()
    }
    #else
    private func beginChartScrubShellSuppressionIfNeeded() {}
    private func endChartScrubShellSuppressionIfNeeded() {}
    #endif

    private var platformTotalsTitle: String {
        selectedCampusId == nil ? "Platform totals" : "\(campusScopeLabel) Totals"
    }

    private var platformStatsCard: some View {
        sectionCard(title: platformTotalsTitle, subtitle: nil) {
            if selectedCampusId == nil {
                if let s = stats {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                        metricCell(title: "Users", value: "\(s.totalUsers ?? 0)")
                        metricCell(title: "Bookings", value: "\(s.totalBookings ?? 0)")
                        metricCell(title: "Barbers", value: "\(s.totalBarbers ?? 0)")
                        metricCell(title: "Campuses", value: "\(s.totalCampuses ?? 0)")
                    }
                } else {
                    loadingRow("Loading platform stats…")
                }
            } else if let p = performance {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                    let userCount = (p.totalConsumers ?? 0) + (p.totalBarbers ?? 0)
                    metricCell(title: "Users", value: "\(userCount)")
                    metricCell(title: "Bookings", value: "\(p.totalBookings ?? 0)")
                    metricCell(title: "Barbers", value: "\(p.totalBarbers ?? 0)")
                    metricCell(title: "Consumers", value: "\(p.totalConsumers ?? 0)")
                }
            } else {
                loadingRow("Loading campus totals…")
            }
        }
    }

    private var performanceCard: some View {
        sectionCard(
            title: selectedCampusId == nil ? "Aggregate performance" : "Campus performance",
            subtitle: nil
        ) {
            if let p = performance {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                    metricCell(title: "Total bookings", value: "\(p.totalBookings ?? 0)")
                    metricCell(title: "Completed", value: "\(p.completedBookings ?? 0)")
                    metricCell(title: "Cancelled", value: "\(p.cancelledBookings ?? 0)")
                    metricCell(title: "Active barbers", value: "\(p.activeBarbers ?? 0) / \(p.totalBarbers ?? 0)")
                    metricCell(title: "Total revenue", value: dollarString(centsLike: p.totalRevenue))
                    metricCell(title: "Platform fees", value: dollarString(centsLike: p.totalPlatformFees))
                    metricCell(title: "Net platform", value: dollarString(centsLike: p.netPlatformRevenue))
                    metricCell(title: "Barber earnings", value: dollarString(centsLike: p.totalBarberEarnings))
                    metricCell(title: "Card revenue", value: dollarString(centsLike: p.cardRevenue))
                    metricCell(title: "Cash revenue", value: dollarString(centsLike: p.cashRevenue))
                    metricCell(title: "Tips", value: dollarString(centsLike: p.totalTips))
                    metricCell(title: "Avg rating", value: ratingString(p.averageRating, reviews: p.totalReviews))
                }

                stripePerformanceBlock(p)
            } else {
                loadingRow("Loading performance…")
            }
        }
    }

    @ViewBuilder
    private func stripePerformanceBlock(_ p: AdminCampusPerformanceDTO) -> some View {
        if hasStripeAnalyticsFields(p) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stripe analytics")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .padding(.top, 6)
                Text("Estimated from booking card volume and platform fees (same model as the web admin).")
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                    metricCell(title: "Total Stripe fees (est.)", value: dollarString(centsLike: p.estimatedStripeFees))
                    metricCell(title: "Card processing (est.)", value: dollarString(centsLike: p.stripeProcessingFees))
                    metricCell(title: "Connect fees (est.)", value: dollarString(centsLike: p.stripeConnectFees))
                    metricCell(title: "Active account billing", value: dollarString(centsLike: p.activeAccountBilling))
                    metricCell(title: "Volume billing", value: dollarString(centsLike: p.volumeBilling))
                    metricCell(title: "Payout fees (est.)", value: dollarString(centsLike: p.payoutFees))
                    metricCell(title: "Connect accounts (est.)", value: optionalCount(p.activeConnectAccounts))
                    metricCell(title: "Est. payouts", value: optionalCount(p.estimatedPayouts))
                    metricCell(title: "Completed paid txs", value: optionalCount(p.completedTransactionCount))
                }
            }
        }
    }

    private func hasStripeAnalyticsFields(_ p: AdminCampusPerformanceDTO) -> Bool {
        p.estimatedStripeFees != nil
            || p.stripeProcessingFees != nil
            || p.stripeConnectFees != nil
            || p.activeAccountBilling != nil
            || p.volumeBilling != nil
            || p.payoutFees != nil
            || p.activeConnectAccounts != nil
            || p.estimatedPayouts != nil
            || p.completedTransactionCount != nil
    }

    private func optionalCount(_ v: Int?) -> String {
        guard let v else { return "—" }
        return "\(v)"
    }

    // MARK: - Barbers tab

    private struct BarberCampusGroup: Identifiable {
        let id: String
        let title: String
        let barbers: [AdminBarberDTO]
    }

    private var barberCampusGroups: [BarberCampusGroup] {
        var buckets: [String: [AdminBarberDTO]] = [:]
        for barber in barbers {
            let key = barber.campusId ?? "__unassigned__"
            buckets[key, default: []].append(barber)
        }

        return buckets.map { campusId, members in
            BarberCampusGroup(
                id: campusId,
                title: barberCampusSectionTitle(forCampusId: campusId, sample: members.first),
                barbers: members.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            )
        }
        .sorted {
            if $0.id == "__unassigned__" { return false }
            if $1.id == "__unassigned__" { return true }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func barberCampusSectionTitle(forCampusId campusId: String, sample: AdminBarberDTO?) -> String {
        if campusId == "__unassigned__" { return "Unassigned campus" }
        if let campus = campuses.first(where: { $0.id == campusId }) {
            return campus.displayName
        }
        if let name = sample?.campusName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "Campus"
    }

    private var barbersTabSubtitle: String {
        if selectedCampusId != nil {
            return "\(barbers.count) loaded."
        }
        let groupCount = barberCampusGroups.count
        if groupCount <= 1 {
            return "\(barbers.count) loaded."
        }
        return "\(barbers.count) providers across \(groupCount) campuses."
    }

    private var barbersTab: some View {
        sectionCard(title: "Barbers", subtitle: barbersTabSubtitle) {
            VStack(spacing: 10) {
                if barbers.isEmpty {
                    Text(isLoading ? "Loading barbers…" : "No barbers found for this scope.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                } else if selectedCampusId != nil {
                    ForEach(barbers) { barber in
                        barberRow(barber, showCampusLabel: false)
                    }
                } else {
                    ForEach(barberCampusGroups) { group in
                        barberCampusSection(group)
                    }
                }
            }
        }
    }

    private func barberCampusSection(_ group: BarberCampusGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                Text("\(group.barbers.count) provider\(group.barbers.count == 1 ? "" : "s")")
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )

            ForEach(group.barbers) { barber in
                barberRow(barber, showCampusLabel: false)
            }
        }
    }

    private func barberRow(_ barber: AdminBarberDTO, showCampusLabel: Bool = true) -> some View {
        Button {
            adminDetailPath.append(AdminDashboardDestination.barber(barber))
        } label: {
            HStack(spacing: 12) {
                ProviderSquaredAvatarView(
                    url: barber.avatarURL,
                    fallbackName: barber.displayName,
                    size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(barber.displayName)
                            .font(.provider(.subheadline, weight: .semibold))
                        if barber.isActive == false { tag(text: "Hidden", tint: Color.red.opacity(0.7)) }
                    }
                    Text(barber.email ?? "—")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    HStack(spacing: 8) {
                        if showCampusLabel, let cn = barber.campusName {
                            Text(cn)
                            Text("·")
                        }
                        Text("\(barber.completedBookings ?? 0) bookings")
                        Text("·")
                        Text(dollarString(centsLike: Double(barber.totalVolumeCents ?? 0)))
                    }
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                    stripeBadges(barber)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func stripeBadges(_ barber: AdminBarberDTO) -> some View {
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

    // MARK: - Users tab

    private let usersPageSize = 25

    private var filteredUsers: [AdminPlatformUserDTO] {
        let q = userSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter { u in
            (u.email?.lowercased().contains(q) ?? false)
                || u.displayName.lowercased().contains(q)
                || (u.role?.lowercased().contains(q) ?? false)
                || (u.campusName?.lowercased().contains(q) ?? false)
        }
    }

    private var displayedUsers: [AdminPlatformUserDTO] {
        Array(filteredUsers.prefix(usersVisibleCount))
    }

    private var usersTabSubtitle: String {
        let total = filteredUsers.count
        let shown = min(usersVisibleCount, total)
        return "\(shown) of \(total) shown."
    }

    private var usersTab: some View {
        sectionCard(title: "Users", subtitle: usersTabSubtitle) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                    TextField("Search users", text: $userSearch)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !userSearch.isEmpty {
                        Button { userSearch = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                if filteredUsers.isEmpty {
                    Text(isLoading ? "Loading users…" : "No matching users.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                } else {
                    ForEach(displayedUsers) { user in
                        userRow(user)
                    }
                    if filteredUsers.count > usersVisibleCount {
                        Button {
                            usersVisibleCount += usersPageSize
                        } label: {
                            Text("Show next \(usersPageSize)")
                                .font(.provider(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.providerOlive)
                    }
                }
            }
        }
    }

    private func userRow(_ user: AdminPlatformUserDTO) -> some View {
        Button {
            adminDetailPath.append(AdminDashboardDestination.user(user))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.provider(.subheadline, weight: .semibold))
                        if user.isActive == false { tag(text: "Blocked", tint: Color.red.opacity(0.7)) }
                    }
                    Text(user.email ?? "—")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    HStack(spacing: 6) {
                        Text(user.prettyRole)
                        if let campus = user.campusName, !campus.isEmpty {
                            Text("·")
                            Text(campus)
                        }
                    }
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Safety tab

    /// Two stacked sections matching the web Admin **Safety** layout: Reports queue with
    /// resolve actions on top, banned users with Unban below. Both are filterable; neither is
    /// campus-scoped (platform-wide moderation surface).
    private var safetyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            reportsSection
            bannedUsersSection
        }
    }

    // MARK: Reports section

    private var reportsSection: some View {
        sectionCard(
            title: "Reports",
            subtitle: reportsSubtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                safetyFilterMenu(
                    title: "Status",
                    options: ReportsStatusFilter.allCases,
                    selection: $reportsStatusFilter,
                    label: { $0.chipLabel }
                )

                if let reportsError, !reportsError.isEmpty {
                    Text(reportsError)
                        .font(.provider(.caption))
                        .foregroundStyle(.red)
                }

                if reportsLoading, moderationReports.isEmpty {
                    loadingRow("Loading reports…")
                } else if moderationReports.isEmpty {
                    Text(emptyReportsMessage)
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(moderationReports) { report in
                            reportRow(report)
                        }
                    }
                }
            }
        }
    }

    private var reportsSubtitle: String {
        switch reportsStatusFilter {
        case .open: "Open reports awaiting your decision."
        case .all: "All reports submitted across the platform."
        case .resolved: "Reports that have been actioned."
        case .dismissed: "Reports that have been dismissed."
        }
    }

    private var emptyReportsMessage: String {
        switch reportsStatusFilter {
        case .open: "No open reports right now. New submissions will appear here."
        case .all: "No reports have been submitted yet."
        case .resolved: "No resolved reports yet."
        case .dismissed: "No dismissed reports yet."
        }
    }

    @ViewBuilder
    private func reportRow(_ report: AdminModerationReportDTO) -> some View {
        let isBusy = busyReportId == report.id
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        reportStatusBadge(report)
                        if let reason = report.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                            Text(reason.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.provider(.caption, weight: .semibold))
                                .foregroundStyle(Color.lavaShellCream)
                        }
                        Spacer(minLength: 0)
                        if let when = report.createdAt {
                            Text(relativeShort(when))
                                .font(.provider(.caption2))
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                        }
                    }
                    Text("Reported: \(report.reportedUserDisplayName)")
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                    if let email = report.reportedUserEmail, !email.isEmpty {
                        Text(email)
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .lineLimit(1)
                    }
                    Text("Reporter: \(report.reporterDisplayName)")
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
            }

            if let descr = report.description?.trimmingCharacters(in: .whitespacesAndNewlines), !descr.isEmpty {
                Text(descr)
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let preview = report.subjectContent?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                Text("“\(preview)”")
                    .font(.provider(.footnote)).italic()
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }
            if !report.isOpen,
               let notes = report.resolutionNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
               !notes.isEmpty
            {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resolution notes")
                        .font(.provider(.caption2, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                    Text(notes)
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCream)
                }
            }

            if report.isOpen {
                reportActionRow(report, isBusy: isBusy)
            } else if let action = report.resolutionAction, !action.isEmpty {
                Text("Action: \(action.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(report.isOpen ? Color.orange.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .opacity(isBusy ? 0.55 : 1.0)
    }

    @ViewBuilder
    private func reportActionRow(_ report: AdminModerationReportDTO, isBusy: Bool) -> some View {
        HStack(spacing: 8) {
            reportActionButton(report: report, action: .banReportedUser, tint: Color.red.opacity(0.65), isBusy: isBusy)
            reportActionButton(report: report, action: .removeMessageAndBan, tint: Color.red.opacity(0.5), isBusy: isBusy)
            Spacer(minLength: 0)
            Menu {
                Button {
                    pendingReportResolution = PendingReportResolution(report: report, action: .removeMessage)
                } label: {
                    Label(AdminModerationResolveAction.removeMessage.displayLabel, systemImage: AdminModerationResolveAction.removeMessage.systemImage)
                }
                Button {
                    pendingReportResolution = PendingReportResolution(report: report, action: .dismiss)
                } label: {
                    Label(AdminModerationResolveAction.dismiss.displayLabel, systemImage: AdminModerationResolveAction.dismiss.systemImage)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis.circle")
                    Text("More")
                        .font(.provider(.caption, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.lavaShellCream)
            }
            .disabled(isBusy)
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func reportActionButton(
        report: AdminModerationReportDTO,
        action: AdminModerationResolveAction,
        tint: Color,
        isBusy: Bool
    ) -> some View {
        Button {
            pendingReportResolution = PendingReportResolution(report: report, action: action)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.systemImage)
                Text(action.displayLabel)
                    .font(.provider(.caption, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
            .foregroundStyle(Color.lavaShellCream)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func reportStatusBadge(_ report: AdminModerationReportDTO) -> some View {
        let label = report.statusEnum?.displayLabel ?? report.status.capitalized
        let tint: Color = switch report.statusEnum {
        case .open: Color.orange.opacity(0.75)
        case .resolved: Color.providerOlive
        case .dismissed: Color.gray.opacity(0.55)
        case .none: Color.gray.opacity(0.55)
        }
        return Text(label)
            .font(.provider(.caption2, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
            .foregroundStyle(Color.lavaShellCream)
    }

    // MARK: Banned users section

    private var bannedUsersSection: some View {
        sectionCard(
            title: "Banned users",
            subtitle: bannedSubtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                safetyFilterMenu(
                    title: "Category",
                    options: AdminBannedUserCategory.allCases,
                    selection: $bannedCategoryFilter,
                    label: { $0.chipLabel }
                )

                if let bannedError, !bannedError.isEmpty {
                    Text(bannedError)
                        .font(.provider(.caption))
                        .foregroundStyle(.red)
                }

                if bannedLoading, bannedUsers.isEmpty {
                    loadingRow("Loading banned users…")
                } else if bannedUsers.isEmpty {
                    Text(bannedCategoryFilter == .all
                        ? "No users are currently banned."
                        : "No banned \(bannedCategoryFilter.chipLabel.lowercased()) right now.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(bannedUsers) { user in
                            bannedUserRow(user)
                        }
                    }
                }
            }
        }
    }

    private var bannedSubtitle: String {
        if bannedCategoryFilter == .all {
            return "Accounts with `isBanned = true`. Unban restores sign-in, discovery, and booking."
        }
        return "Banned \(bannedCategoryFilter.chipLabel.lowercased())."
    }

    @ViewBuilder
    private func bannedUserRow(_ user: AdminBannedUserDTO) -> some View {
        let isBusy = busyUnbanUserId == user.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(url: nil, fallbackName: user.displayName)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream)
                        tag(text: "BANNED", tint: Color.red.opacity(0.7))
                        if let count = user.openReportCount, count > 0 {
                            tag(text: "\(count) open", tint: Color.orange.opacity(0.65))
                        }
                    }
                    if let email = user.email, !email.isEmpty {
                        Text(email)
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(user.categoryLabel)
                        if let campus = user.campusName, !campus.isEmpty {
                            Text("·")
                            Text(campus)
                        }
                        if let when = user.updatedAt {
                            Text("·")
                            Text(relativeShort(when))
                        }
                    }
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                    if let listing = user.barberListingStateLabel {
                        Text(listing)
                            .font(.provider(.caption2))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    pendingUnban = user
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward.circle")
                        Text("Unban")
                            .font(.provider(.caption, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.providerOlive.opacity(0.9), in: Capsule())
                    .foregroundStyle(Color.lavaShellCream)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.red.opacity(0.25), lineWidth: 0.5)
        )
        .opacity(isBusy ? 0.55 : 1.0)
    }

    // MARK: Safety dialog copy + shared filter chips

    private var pendingReportResolutionTitle: String {
        guard let pending = pendingReportResolution else { return "" }
        return "\(pending.action.displayLabel)?"
    }

    private func pendingReportResolutionMessage(for pending: PendingReportResolution) -> String {
        let target = pending.report.reportedUserDisplayName
        switch pending.action {
        case .dismiss:
            return "Dismisses the report against \(target) without taking action. The reporter is not notified."
        case .removeMessage:
            return "Removes the reported content but leaves \(target)'s account active. The report will be marked resolved."
        case .banReportedUser:
            return "Bans \(target) — they lose sign-in, discovery, and any active bookings will be cancelled."
        case .removeMessageAndBan:
            return "Removes the reported content and bans \(target). Active bookings will be cancelled."
        }
    }

    private var pendingUnbanTitle: String {
        guard let target = pendingUnban else { return "" }
        return "Unban \(target.displayName)?"
    }

    /// Compact filter picker for Safety tab sections (Reports status, Banned user category).
    @ViewBuilder
    private func safetyFilterMenu<Option: Hashable & Identifiable>(
        title: String,
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) -> some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    HStack {
                        Text(label(option))
                        if selection.wrappedValue == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                Text("\(title): \(label(selection.wrappedValue))")
                    .font(.provider(.subheadline, weight: .medium))
                    .foregroundStyle(Color.lavaShellCream)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .accessibilityLabel("\(title) filter")
        .accessibilityValue(label(selection.wrappedValue))
    }

    private func relativeShort(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Data

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        errorText = nil
        _ = try? await ProviderAuthService.refreshAccessTokenIfPossible()
        async let st = ProviderAdminService.platformStats()
        async let cs = ProviderAdminService.listCampuses()
        do {
            let (s, c) = try await (st, cs)
            stats = s
            campuses = c
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Server returned \(code)."
        } catch {
            errorText = error.localizedDescription
        }
        await loadScopedData()
        await loadSafety()
    }

    /// Fetch both Safety lists in parallel. Errors are scoped to each list so a partial outage
    /// (reports up, banned-users down) still surfaces the available data.
    private func loadSafety() async {
        async let reportsTask: () = loadModerationReports()
        async let bannedTask: () = loadBannedUsers()
        _ = await (reportsTask, bannedTask)
    }

    private func loadModerationReports() async {
        reportsLoading = true
        defer { reportsLoading = false }
        reportsError = nil
        do {
            moderationReports = try await ProviderAdminService.listModerationReports(
                status: reportsStatusFilter.apiStatus
            )
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            moderationReports = []
            reportsError = msg ?? "Could not load reports (\(code))."
        } catch {
            moderationReports = []
            reportsError = error.localizedDescription
        }
    }

    private func loadBannedUsers() async {
        bannedLoading = true
        defer { bannedLoading = false }
        bannedError = nil
        do {
            bannedUsers = try await ProviderAdminService.listBannedUsers(
                category: bannedCategoryFilter
            )
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            bannedUsers = []
            bannedError = msg ?? "Could not load banned users (\(code))."
        } catch {
            bannedUsers = []
            bannedError = error.localizedDescription
        }
    }

    private func applyReportResolution(_ pending: PendingReportResolution) async {
        busyReportId = pending.report.id
        defer { busyReportId = nil }
        reportsError = nil
        do {
            try await ProviderAdminService.resolveModerationReport(
                reportId: pending.report.id,
                action: pending.action
            )
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            reportsError = msg ?? "Resolution failed (\(code))."
        } catch {
            reportsError = error.localizedDescription
        }
        // Refresh both lists — ban-causing actions affect banned-users too.
        await loadModerationReports()
        if pending.action.bansUser {
            await loadBannedUsers()
        }
    }

    private func applyUnban(_ target: AdminBannedUserDTO) async {
        busyUnbanUserId = target.id
        defer { busyUnbanUserId = nil }
        bannedError = nil
        do {
            try await ProviderAdminService.unbanUser(userId: target.id)
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            bannedError = msg ?? "Unban failed (\(code))."
        } catch {
            bannedError = error.localizedDescription
        }
        await loadBannedUsers()
    }

    private func loadScopedData() async {
        selectedBucketIndex = nil
        usersVisibleCount = 25
        let scope = selectedCampusId
        async let perfTask = fetchPerformance(campusId: scope)
        async let barbersTask = fetchBarbers(campusId: scope)
        async let usersTask = fetchUsers(campusId: scope)
        async let metricsTask = fetchMetricsSeries(campusId: scope, period: metricsTimeline.apiPeriod)
        let (p, bs, us, m) = await (perfTask, barbersTask, usersTask, metricsTask)
        performance = p
        barbers = bs
        users = us
        metricsSnapshot = m
    }

    private func reloadMetricsTimeline() async {
        isLoadingMetrics = true
        selectedBucketIndex = nil
        defer { isLoadingMetrics = false }
        metricsSnapshot = await fetchMetricsSeries(campusId: selectedCampusId, period: metricsTimeline.apiPeriod)
    }

    private func fetchMetricsSeries(campusId: String?, period: String) async -> AdminMetricsSnapshotDTO? {
        do {
            if let id = campusId {
                return try await ProviderAdminService.campusMetrics(campusId: id, period: period)
            }
            return try await ProviderAdminService.aggregateMetrics(period: period)
        } catch {
            return nil
        }
    }

    private func normalizedMetricPoints(
        from snapshot: AdminMetricsSnapshotDTO?,
        timeline: MetricsTimeline
    ) -> [MetricPlotPoint] {
        let calendar = Calendar.current
        let bucketDates = Self.chartBucketDates(for: timeline, calendar: calendar)
        var totalsByBucket: [Date: (revenueDollars: Double, bookings: Int, signups: Int)] = [:]

        for row in snapshot?.data ?? [] {
            guard let parsedDate = MetricsDateParsing.parse(row.date) else { continue }
            let bucket = Self.bucketStart(for: parsedDate, timeline: timeline, calendar: calendar)
            let cents = row.revenue ?? 0
            let existing = totalsByBucket[bucket] ?? (0, 0, 0)
            totalsByBucket[bucket] = (
                revenueDollars: existing.revenueDollars + Double(cents) / 100.0,
                bookings: existing.bookings + (row.bookings ?? 0),
                signups: existing.signups + (row.users ?? 0)
            )
        }

        let dayFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return formatter
        }()

        return bucketDates.enumerated().map { index, bucket in
            let totals = totalsByBucket[bucket] ?? (0, 0, 0)
            return MetricPlotPoint(
                id: dayFormatter.string(from: bucket),
                bucketIndex: index,
                date: bucket,
                revenueDollars: totals.revenueDollars,
                bookings: totals.bookings,
                signups: totals.signups
            )
        }
    }

    private static func chartBucketDates(
        for timeline: MetricsTimeline,
        calendar: Calendar
    ) -> [Date] {
        let count = timeline.chartBucketCount
        let anchor = calendar.startOfDay(for: Date())

        switch timeline {
        case .daily:
            return (0..<count).compactMap { offset in
                calendar.date(byAdding: .day, value: -(count - 1 - offset), to: anchor)
            }

        case .weekly:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
            return (0..<count).compactMap { offset in
                calendar.date(byAdding: .weekOfYear, value: -(count - 1 - offset), to: weekStart)
            }

        case .monthly:
            let monthStart = calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor
            return (0..<count).compactMap { offset in
                calendar.date(byAdding: .month, value: -(count - 1 - offset), to: monthStart)
            }

        case .yearly:
            let yearStart = calendar.dateInterval(of: .year, for: anchor)?.start ?? anchor
            return (0..<count).compactMap { offset in
                calendar.date(byAdding: .year, value: -(count - 1 - offset), to: yearStart)
            }
        }
    }

    private static func bucketStart(
        for date: Date,
        timeline: MetricsTimeline,
        calendar: Calendar
    ) -> Date {
        switch timeline {
        case .daily:
            return calendar.startOfDay(for: date)
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
                ?? calendar.startOfDay(for: date)
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)?.start
                ?? calendar.startOfDay(for: date)
        case .yearly:
            return calendar.dateInterval(of: .year, for: date)?.start
                ?? calendar.startOfDay(for: date)
        }
    }

    private func fetchPerformance(campusId: String?) async -> AdminCampusPerformanceDTO? {
        if let id = campusId {
            return try? await ProviderAdminService.campusPerformance(campusId: id)
        }
        return try? await ProviderAdminService.aggregatePerformance()
    }

    private func fetchBarbers(campusId: String?) async -> [AdminBarberDTO] {
        if let id = campusId {
            return (try? await ProviderAdminService.campusBarbers(campusId: id)) ?? []
        }
        return (try? await ProviderAdminService.allBarbers()) ?? []
    }

    private func fetchUsers(campusId: String?) async -> [AdminPlatformUserDTO] {
        do {
            return try await ProviderAdminService.listUsers(campusId: campusId)
        } catch {
            if errorText == nil {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            return []
        }
    }

    // MARK: - Helpers

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

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

    private func metricCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.provider(.caption2))
                .foregroundStyle(Color.lavaShellCreamTertiary)
            Text(value)
                .font(.provider(.subheadline, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func tag(text: String, tint: Color) -> some View {
        Text(text)
            .font(.provider(.caption2, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.6), in: Capsule())
    }

    private func loadingRow(_ msg: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(msg).font(.provider(.footnote)).foregroundStyle(Color.lavaShellCreamSecondary)
        }
    }

    private func dollarString(centsLike: Double?) -> String {
        guard let v = centsLike else { return "—" }
        let dollars = v / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }

    private func ratingString(_ avg: Double?, reviews: Int?) -> String {
        guard let avg, avg > 0 else { return "—" }
        return String(format: "%.2f", avg) + " (\(reviews ?? 0))"
    }
}
