import Charts
import SwiftUI

/// Native iOS Campus Manager dashboard.
///
/// Organized into **tabs** (Overview, Services, Barbers, Bookings) so campus managers can focus on one
/// area at a time—mirroring the main sections of the web `CampusManagerDashboard.tsx`. The Barbers
/// tab carries the web's nested layout: **Current** barbers first in the selector, then an
/// **Applications** queue (Current is the default sub-tab).
struct ProviderCampusManagerDashboardView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(ProviderShellNavigator.self) private var shellNavigator

    /// Primary dashboard areas (segment control + single scroll per selection).
    private enum CampusManagerMainTab: Int, CaseIterable, Identifiable {
        case overview = 0
        case serviceTypes
        case barbers
        case bookings

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .serviceTypes: "Services"
            case .barbers: "Barbers"
            case .bookings: "Bookings"
            }
        }
    }

    @State private var mainTab: CampusManagerMainTab = .overview

    /// Sub-tabs under **Barbers** (`Current` first, then `Applications`; default is Current).
    private enum BarbersSubTab: Int, CaseIterable, Identifiable {
        case current = 0
        case applications

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .applications: "Applications"
            case .current: "Current"
            }
        }
    }

    @State private var barbersSubTab: BarbersSubTab = .current

    @State private var campus: AdminCampusDTO?
    @State private var performance: AdminCampusPerformanceDTO?
    @State private var metricsSnapshot: AdminMetricsSnapshotDTO?
    @State private var metricsTimeline: CampusMetricsTimeline = .daily
    @State private var metricsChartSeries: CampusMetricsChartSeries = .revenue
    @State private var isLoadingMetrics = false
    @State private var selectedBucketIndex: Int?
    @State private var isChartScrubbing = false
    @State private var barbers: [AdminBarberDTO] = []
    @State private var bookings: [SimpleBookingDTO] = []

    @State private var isLoading = true
    @State private var errorText: String?

    @State private var bookingsStatusFilter: BookingFilter = .upcoming
    @State private var togglingBarberId: String?
    @State private var togglingError: String?

    // MARK: Applications queue state
    //
    // The Campus Manager dashboard pulls the same `/barber-applications` queue the web app uses.
    // The list is a UNION of registered + guest applications scoped by `campusId`; web filters
    // client-side to "actionable" rows (pending + approved guests without a user_id) and we match
    // that default while letting admins flip to **All** to inspect history.
    @State private var applications: [BarberApplicationListRowDTO] = []
    @State private var applicationsLoading = false
    @State private var applicationsError: String?
    @State private var applicationsShowOnlyActionable = true
    @State private var expandedApplicationId: String?
    @State private var applicationBusyId: String?
    @State private var pendingApplicationDecision: PendingApplicationDecision?

    /// Captured row + intended status so the confirmation dialog can describe and submit the
    /// change without re-querying the table after the user taps Approve / Reject / Revoke.
    private struct PendingApplicationDecision: Identifiable, Equatable {
        let id: UUID = UUID()
        let row: BarberApplicationListRowDTO
        let newStatus: BarberApplicationStatus
        let actionLabel: String
        let isDestructive: Bool
    }

    // MARK: Admin campus switcher state
    //
    // The web `CampusManagerDashboard` lets admins flip between any campus's CM view (regular
    // managers stay pinned to their own). We mirror that here:
    //   - `availableCampuses` is loaded from `/admin/campuses` once on admin sessions.
    //   - `adminViewingCampusId` overrides the JWT campus when set; `effectiveCampusId` resolves
    //     to the override or the user's home campus.
    @State private var availableCampuses: [AdminCampusDTO] = []
    @State private var adminViewingCampusId: String?
    @State private var availableCampusesLoaded = false
    @State private var isAssigningCampusManager = false

    /// Matches the three buckets exposed by `GET /bookings-simple/campus/:id?statusFilter=...`
    /// (`upcoming` → PENDING/ACCEPTED, `completed` → COMPLETED/PAID, `cancelled` → CANCELLED).
    enum BookingFilter: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case completed = "Completed"
        case cancelled = "Cancelled"
        var id: String { rawValue }

        var apiValue: String {
            switch self {
            case .upcoming: return "upcoming"
            case .completed: return "completed"
            case .cancelled: return "cancelled"
            }
        }
    }

    /// The user's own campus from the JWT — also the only campus a non-admin Campus Manager
    /// is ever allowed to act on.
    private var homeCampusId: String? { session.authUser?.campusId }

    /// Whether the signed-in user can cross-view other campuses (admins only). Regular Campus
    /// Managers are pinned to `homeCampusId`.
    private var canSwitchCampuses: Bool {
        session.authUser?.hasAdminPrivileges == true
    }

    /// Campus the dashboard is currently scoped to — admin override if set, otherwise the
    /// user's own campus. All load/refresh calls thread this id through.
    private var effectiveCampusId: String? {
        if canSwitchCampuses, let chosen = adminViewingCampusId, !chosen.isEmpty {
            return chosen
        }
        return homeCampusId
    }

    /// Display name for the campus currently being viewed. Prefers the freshly loaded campus
    /// object (richest fields), falls back to the catalog row for admins switching between
    /// campuses, and ultimately to the home-campus fields.
    private var effectiveCampusDisplayName: String {
        if let campus, !campus.displayName.isEmpty { return campus.displayName }
        if let cid = effectiveCampusId,
           let match = availableCampuses.first(where: { $0.id == cid })
        {
            return match.displayName
        }
        return "Your campus"
    }

    /// "City, State" for the campus currently being viewed (same lookup chain as `effectiveCampusDisplayName`).
    private var effectiveCampusLocationLine: String? {
        if let line = campus?.locationLine, !line.isEmpty { return line }
        if let cid = effectiveCampusId,
           let match = availableCampuses.first(where: { $0.id == cid })
        {
            return match.locationLine
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorText {
                Text(errorText)
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }

            if canSwitchCampuses {
                adminCampusSwitcherHeader
            }

            Picker("Section", selection: $mainTab) {
                ForEach(CampusManagerMainTab.allCases) { tab in
                    Text(tab.title)
                        .font(.provider(.body, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .tint(.providerOlive)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch mainTab {
                    case .overview:
                        overviewSection
                    case .serviceTypes:
                        ProviderCampusManagerServicesView()
                    case .barbers:
                        barbersSection
                    case .bookings:
                        bookingsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .providerNavigationStackDestinationBackdrop()
        .refreshable {
            await loadAll()
        }
        .task {
            await loadAll()
        }
        .navigationTitle("Campus Manager")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Campus Manager")
                    .font(.provider(.headline, weight: .semibold))
            }
        }
        .providerLavaScreenChrome()
        .onChange(of: metricsTimeline) { _, _ in
            selectedBucketIndex = nil
            Task { await reloadCampusMetricsTimeline() }
        }
        .onChange(of: metricsChartSeries) { _, _ in
            selectedBucketIndex = nil
        }
        .onDisappear {
            endChartScrubbingIfNeeded()
        }
        .confirmationDialog(
            applicationDecisionDialogTitle,
            isPresented: Binding(
                get: { pendingApplicationDecision != nil },
                set: { if !$0 { pendingApplicationDecision = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let decision = pendingApplicationDecision {
                Button(decision.actionLabel, role: decision.isDestructive ? .destructive : nil) {
                    let captured = decision
                    pendingApplicationDecision = nil
                    Task { await applyApplicationDecision(captured) }
                }
                Button("Cancel", role: .cancel) {
                    pendingApplicationDecision = nil
                }
            }
        } message: {
            if let decision = pendingApplicationDecision {
                Text(applicationDecisionDialogMessage(for: decision))
            }
        }
    }

    private var applicationDecisionDialogTitle: String {
        guard let decision = pendingApplicationDecision else { return "" }
        return "\(decision.actionLabel) \(decision.row.displayName)?"
    }

    private func applicationDecisionDialogMessage(for decision: PendingApplicationDecision) -> String {
        switch decision.newStatus {
        case .approved:
            if decision.row.origin == .guest, (decision.row.userId ?? "").isEmpty {
                return "They’ll receive an approval email and be promoted to a barber profile as soon as they sign up."
            }
            return "They’ll be promoted to a barber at \(campus?.displayName ?? "your campus") and notified by email."
        case .rejected:
            if decision.actionLabel == "Revoke approval" {
                return "This will revert their status to rejected. They won’t be promoted on signup."
            }
            return "They’ll be marked rejected. You can change this later if needed."
        case .underReview:
            return "Marks this application as under review."
        case .interviewScheduled:
            return "Marks an interview as scheduled."
        case .pending:
            return "Resets this application to pending."
        }
    }

    // MARK: - Admin campus switcher (admin-only top header)

    /// Admin-only chip that names the campus currently being viewed and lets admins jump to
    /// another campus's Campus Manager dashboard. Regular Campus Managers never see this — they
    /// remain pinned to `homeCampusId`. Mirrors the web `CampusManagerDashboard.tsx` admin
    /// campus filter.
    private var adminCampusSwitcherHeader: some View {
        HStack {
            Spacer(minLength: 0)

            Menu {
                if let homeCampusId,
                   let homeRow = availableCampuses.first(where: { $0.id == homeCampusId })
                {
                    Section("Your campus") {
                        adminCampusMenuButton(homeRow, isHome: true)
                    }
                }
                let others = availableCampuses.filter { $0.id != homeCampusId }
                if !others.isEmpty {
                    Section("Other campuses") {
                        ForEach(others) { row in
                            adminCampusMenuButton(row, isHome: false)
                        }
                    }
                } else if availableCampuses.isEmpty {
                    Text("Campus list not loaded yet")
                }
            } label: {
                HStack(spacing: 6) {
                    Text(effectiveCampusDisplayName)
                        .font(.provider(.subheadline, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.provider(.caption2, weight: .semibold))
                }
                .foregroundStyle(Color.lavaShellCream)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.white.opacity(0.10))
                )
                .overlay(
                    Capsule().strokeBorder(Color.lavaShellCream.opacity(0.25), lineWidth: 0.5)
                )
            }
            .disabled(availableCampuses.isEmpty)
            .opacity(availableCampuses.isEmpty ? 0.6 : 1.0)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func adminCampusMenuButton(_ row: AdminCampusDTO, isHome: Bool) -> some View {
        let selected = row.id == effectiveCampusId
        Button {
            Task { await switchAdminCampus(to: row.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.displayName)
                    if let loc = row.locationLine, !loc.isEmpty {
                        Text(loc).font(.provider(.caption))
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                } else if isHome {
                    Image(systemName: "house.fill")
                }
            }
        }
    }

    // MARK: - Overview

    private enum CampusMetricsTimeline: String, CaseIterable, Identifiable {
        case daily, weekly, monthly
        var id: String { rawValue }
        var segmentTitle: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            }
        }
        var apiPeriod: String { rawValue }
        var helperSubtitle: String {
            switch self {
            case .daily: return "Each day for the past week."
            case .weekly: return "Each week for the past month."
            case .monthly: return "Each month for the past six months."
            }
        }

        var chartBucketCount: Int {
            switch self {
            case .daily: return 7
            case .weekly: return 4
            case .monthly: return 6
            }
        }

        var bucketUnitSingular: String {
            switch self {
            case .daily: return "day"
            case .weekly: return "week"
            case .monthly: return "month"
            }
        }

        var bestBucketLabel: String { "Best \(bucketUnitSingular)" }

        var primaryMetricTitle: String { "Average per \(bucketUnitSingular)" }
    }

    private enum CampusMetricsChartSeries: String, CaseIterable, Identifiable {
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

    private struct CampusMetricPlotPoint: Identifiable {
        let id: String
        let bucketIndex: Int
        let date: Date
        let revenueDollars: Double
        let bookings: Int
        let signups: Int
    }

    private enum CampusMetricsDateParsing {
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

    private var chartMetricPoints: [CampusMetricPlotPoint] {
        normalizedCampusMetricPoints(from: metricsSnapshot, timeline: metricsTimeline)
    }

    private var selectedMetricPoint: CampusMetricPlotPoint? {
        guard let selectedBucketIndex,
              chartMetricPoints.indices.contains(selectedBucketIndex)
        else { return nil }
        return chartMetricPoints[selectedBucketIndex]
    }

    private var overviewSection: some View {
        sectionCard(
            title: "",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(effectiveCampusDisplayName)
                    .font(.provider(.title3, weight: .semibold))

                designatedManagerRow

                campusSummaryStatsStrip

            VStack(alignment: .leading, spacing: 12) {
                    Picker("Timeline", selection: $metricsTimeline) {
                        ForEach(CampusMetricsTimeline.allCases) { timeline in
                            Text(timeline.segmentTitle).tag(timeline)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Series", selection: $metricsChartSeries) {
                        ForEach(CampusMetricsChartSeries.allCases) { series in
                            Text(series.segmentTitle).tag(series)
                        }
                    }
                    .pickerStyle(.segmented)

                    ZStack {
                        if isLoading && metricsSnapshot == nil {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Loading chart…")
                                    .font(.provider(.footnote))
                                    .foregroundStyle(Color.lavaShellCreamSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                        } else {
                            campusMetricsTimelineChartView(points: chartMetricPoints)
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
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(overviewMetricsContextLabel)
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)

                    if selectedMetricPoint == nil {
                        Text(metricsTimeline.helperSubtitle)
                            .font(.provider(.caption2))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                }

                overviewMetricsGrid
            }
        }
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

    @ViewBuilder
    private var campusSummaryStatsStrip: some View {
        let isLoadingStats = isLoading && performance == nil
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], alignment: .leading, spacing: 12) {
            summaryStatCell(
                title: "\(effectiveCampusDisplayName) Volume",
                value: isLoadingStats ? "…" : dollarString(centsLike: performance?.totalRevenue)
            )
            summaryStatCell(
                title: "Bookings",
                value: isLoadingStats ? "…" : "\(performance?.totalBookings ?? 0)"
            )
            summaryStatCell(
                title: "Barbers",
                value: isLoadingStats ? "…" : "\(performance?.totalBarbers ?? 0)"
            )
            summaryStatCell(
                title: "Students",
                value: isLoadingStats ? "…" : "\(performance?.totalConsumers ?? 0)"
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    private func summaryStatCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.provider(.caption2))
                .foregroundStyle(Color.lavaShellCreamTertiary)
            Text(value)
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewMetricsContextLabel: String {
        if let point = selectedMetricPoint {
            return formattedChartPeriodLabel(for: point.date)
        }
        return metricsScopeTitle
    }

    @ViewBuilder
    private var overviewMetricsGrid: some View {
        if !chartMetricPoints.isEmpty {
            overviewMetricsPair(selectedPoint: selectedMetricPoint)
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
    private func overviewMetricsPair(selectedPoint: CampusMetricPlotPoint?) -> some View {
        let aggregate = chartRangeAggregate
        let periodCount = max(1, aggregate.periodCount)

        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], alignment: .leading, spacing: 10) {
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

    private func primaryMetricTitle(selectedPoint: CampusMetricPlotPoint?) -> String {
        if let selectedPoint {
            return formattedChartPeriodLabel(for: selectedPoint.date)
        }
        return metricsTimeline.primaryMetricTitle
    }

    private func primaryMetricValue(
        selectedPoint: CampusMetricPlotPoint?,
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
        let peak: CampusMetricPlotPoint?
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

    @ViewBuilder
    private func campusMetricsTimelineChartView(points: [CampusMetricPlotPoint]) -> some View {
        if points.isEmpty {
            Text("No data in this range yet (uses paid booking timestamps).")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        } else {
            Chart {
                switch metricsChartSeries {
                case .revenue:
                    ForEach(points) { pt in
                        let isSelected = selectedMetricPoint?.id == pt.id
                        AreaMark(
                            x: .value("Period", pt.bucketIndex),
                            y: .value("Revenue", pt.revenueDollars)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.providerOlive.opacity(isSelected || selectedMetricPoint == nil ? 0.55 : 0.25),
                                    Color.providerOlive.opacity(isSelected || selectedMetricPoint == nil ? 0.08 : 0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Period", pt.bucketIndex),
                            y: .value("Revenue", pt.revenueDollars)
                        )
                        .foregroundStyle(Color.providerOlive.opacity(isSelected || selectedMetricPoint == nil ? 1 : 0.45))
                        .lineStyle(StrokeStyle(lineWidth: isSelected ? 2.5 : 2))
                    }
                case .bookings:
                    ForEach(points) { pt in
                        let isSelected = selectedMetricPoint?.id == pt.id
                        BarMark(
                            x: .value("Period", pt.bucketIndex),
                            y: .value("Bookings", pt.bookings)
                        )
                        .foregroundStyle(Color.providerOlive.opacity(isSelected || selectedMetricPoint == nil ? 0.75 : 0.35))
                    }
                case .signups:
                    ForEach(points) { pt in
                        let isSelected = selectedMetricPoint?.id == pt.id
                        BarMark(
                            x: .value("Period", pt.bucketIndex),
                            y: .value("Sign-ups", pt.signups)
                        )
                        .foregroundStyle(Color.providerOlive.opacity(isSelected || selectedMetricPoint == nil ? 0.75 : 0.35))
                    }
                }

                if let selected = selectedMetricPoint {
                    RuleMark(x: .value("Selected", selected.bucketIndex))
                        .foregroundStyle(Color.lavaShellCream.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .frame(height: 236)
            .chartXScale(domain: chartXPlotDomain(for: points), range: .plotDimension(padding: 0))
            .chartYScale(domain: CampusMetricsChartScale.yDomain(for: points, series: metricsChartSeries))
            .chartXAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let plotRect = geometry[plotFrame]
                        let labelY = plotRect.maxY + 14
                        let gridColor = Color.lavaShellCream.opacity(0.12)
                        let gridStroke = StrokeStyle(lineWidth: 0.35)

                        ZStack {
                            campusMetricsPlotGrid(
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
                                            updateCampusChartSelection(
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
                    values: CampusMetricsChartScale.yAxisTickValues(
                        in: CampusMetricsChartScale.yDomain(for: points, series: metricsChartSeries)
                    )
                ) { value in
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(campusMetricsYAxisLabel(for: number))
                                .font(.provider(.caption2))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func campusMetricsPlotGrid(
        points: [CampusMetricPlotPoint],
        plotRect: CGRect,
        proxy: ChartProxy,
        color: Color,
        stroke: StrokeStyle
    ) -> some View {
        let yTicks = CampusMetricsChartScale.yAxisTickValues(
            in: CampusMetricsChartScale.yDomain(for: points, series: metricsChartSeries)
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

    private func campusMetricsYAxisLabel(for value: Double) -> String {
        switch metricsChartSeries {
        case .revenue: return chartYAxisRevenueLabel(for: value)
        case .bookings, .signups: return chartYAxisCountLabel(for: value)
        }
    }

    private enum CampusMetricsChartScale {
        static func yValue(for point: CampusMetricPlotPoint, series: CampusMetricsChartSeries) -> Double {
            switch series {
            case .revenue: return point.revenueDollars
            case .bookings: return Double(point.bookings)
            case .signups: return Double(point.signups)
            }
        }

        static func yDomain(
            for points: [CampusMetricPlotPoint],
            series: CampusMetricsChartSeries
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

    /// Places the label so a specific character sits on the gridline: middle letter (Daily) or "/" (Weekly).
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

    /// Tight x domain so the plot fills the chart width with no faded margin columns.
    private func chartXPlotDomain(for points: [CampusMetricPlotPoint]) -> ClosedRange<Int> {
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

    private func updateCampusChartSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [CampusMetricPlotPoint]
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

    /// Surfaces the designated campus manager for the campus currently being viewed. Reflects
    /// `users.first_name` / `last_name` joined by `/admin/campuses` (admin route) when available;
    /// for a non-admin Campus Manager viewing their own campus the admin row isn't reachable, so
    /// we fall back to the signed-in user's own name (they are the manager by definition there).
    @ViewBuilder
    private var designatedManagerRow: some View {
        if canSwitchCampuses {
            adminDesignatedManagerPickerRow
        } else {
            staticDesignatedManagerRow
        }
    }

    private var staticDesignatedManagerRow: some View {
        let info = designatedManagerInfo()
        return HStack(alignment: .center, spacing: 6) {
            designatedManagerPrefixLabel
            Text(info.name)
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
            if info.isCurrentUser {
                tag(text: "YOU", tint: Color.providerOlive)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var designatedManagerPrefixLabel: some View {
        Text("Campus Manager:")
            .font(.provider(.subheadline))
            .foregroundStyle(Color.lavaShellCreamSecondary)
    }

    private var adminDesignatedManagerPickerRow: some View {
        let selectedUserId = currentCampusManagerUserId
        let displayName = designatedManagerInfo().name

        return HStack(alignment: .center, spacing: 6) {
            designatedManagerPrefixLabel

            Menu {
                Button {
                    Task { await updateCampusManagerAssignment(barberUserId: nil) }
                } label: {
                    HStack {
                        Text("No campus manager assigned")
                        if selectedUserId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if barbers.isEmpty {
                    Text("No barbers on this campus")
                } else {
                    ForEach(barbers) { barber in
                        Button {
                            Task { await updateCampusManagerAssignment(barberUserId: barber.id) }
                        } label: {
                            HStack {
                                Text(barber.displayName)
                                if barber.id == selectedUserId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(1)
                    if isAssigningCampusManager {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.provider(.caption2, weight: .semibold))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
                }
            }
            .disabled(isAssigningCampusManager)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var currentCampusManagerUserId: String? {
        if let managerId = campus?.managerId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !managerId.isEmpty
        {
            return managerId
        }
        if let cid = effectiveCampusId,
           let row = availableCampuses.first(where: { $0.id == cid }),
           let managerId = row.managerId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !managerId.isEmpty
        {
            return managerId
        }
        return barbers.first(where: { $0.isCampusManager == true })?.id
    }

    /// Resolves who to render in `designatedManagerRow`. Order:
    ///   1. The freshly loaded campus's `managerName` (richest, comes from admin endpoint).
    ///   2. The admin's catalog row for the viewed campus.
    ///   3. The signed-in user's own name when they're viewing their home campus and we have
    ///      no other source (a non-admin CM is, by definition, the designated manager).
    ///   4. "Unassigned" as a last resort.
    private func designatedManagerInfo() -> (name: String, isCurrentUser: Bool) {
        let myId = session.authUser?.id
        let myName = sessionDisplayName()
        let viewingId = effectiveCampusId

        if let managerName = campus?.managerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !managerName.isEmpty
        {
            let isMe = (campus?.managerId == myId) && myId != nil
            return (managerName, isMe)
        }
        if let cid = viewingId,
           let row = availableCampuses.first(where: { $0.id == cid }),
           let managerName = row.managerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !managerName.isEmpty
        {
            let isMe = (row.managerId == myId) && myId != nil
            return (managerName, isMe)
        }
        if !canSwitchCampuses, viewingId == homeCampusId, !myName.isEmpty {
            return (myName, true)
        }
        return ("Unassigned", false)
    }

    private func sessionDisplayName() -> String {
        let f = session.authUser?.firstName ?? ""
        let l = session.authUser?.lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty { return joined }
        return session.authUser?.email ?? ""
    }

    // MARK: - Barbers (Applications + Current sub-tabs)

    @ViewBuilder
    private var barbersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Barbers section", selection: $barbersSubTab) {
                ForEach(BarbersSubTab.allCases) { sub in
                    Text(sub.title).tag(sub)
                }
            }
            .pickerStyle(.segmented)
            .tint(.providerOlive)

            switch barbersSubTab {
            case .applications:
                applicationsSection
            case .current:
                currentBarbersSection
            }
        }
    }

    private var currentBarbersSection: some View {
        sectionCard(
            title: "Barbers",
            subtitle: barbers.isEmpty && !isLoading
                ? "No barbers assigned to this campus yet."
                : "\(barbers.count) barber\(barbers.count == 1 ? "" : "s") in your campus."
        ) {
            VStack(spacing: 10) {
                if let togglingError {
                    Text(togglingError)
                        .font(.provider(.caption))
                        .foregroundStyle(.red)
                }
                ForEach(barbers) { barber in
                    barberRow(barber)
                }
                if isLoading, barbers.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Loading barbers…").font(.provider(.footnote)).foregroundStyle(Color.lavaShellCreamSecondary) }
                }
            }
        }
    }

    // MARK: - Applications queue

    /// Web parity: by default show only the rows the CM can act on.
    /// Toggling **Show all** drops the client-side filter so admins / curious CMs can inspect
    /// approved + rejected history (server returns everything for the campus).
    private var visibleApplications: [BarberApplicationListRowDTO] {
        guard applicationsShowOnlyActionable else { return applications }
        return applications.filter { $0.isActionableInCampusManagerQueue }
    }

    private var applicationsSection: some View {
        sectionCard(
            title: "Applications",
            subtitle: applicationsSubtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Show all")
                        .font(.provider(.subheadline, weight: .medium))
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { !applicationsShowOnlyActionable },
                        set: { applicationsShowOnlyActionable = !$0 }
                    ))
                    .labelsHidden()
                    .tint(.providerOlive)
                }

                if let applicationsError, !applicationsError.isEmpty {
                    Text(applicationsError)
                        .font(.provider(.caption))
                        .foregroundStyle(.red)
                }

                if applicationsLoading, applications.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading applications…")
                            .font(.provider(.footnote))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
                } else if visibleApplications.isEmpty {
                    Text(applicationsShowOnlyActionable
                        ? "No pending applications right now. New submissions will appear here for review."
                        : "No applications have been submitted to this campus yet.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(visibleApplications) { app in
                            applicationRow(app)
                        }
                    }
                }
            }
        }
    }

    private var applicationsSubtitle: String {
        if applicationsShowOnlyActionable {
            let count = applications.filter { $0.isActionableInCampusManagerQueue }.count
            switch count {
            case 0: return "Pending submissions awaiting your review."
            case 1: return "1 application waiting for your decision."
            default: return "\(count) applications waiting for your decision."
            }
        }
        return "All applications submitted to this campus, newest first."
    }

    @ViewBuilder
    private func applicationRow(_ app: BarberApplicationListRowDTO) -> some View {
        let isExpanded = expandedApplicationId == app.id
        let isBusy = applicationBusyId == app.id

        VStack(alignment: .leading, spacing: 10) {
            Button {
                if expandedApplicationId == app.id {
                    expandedApplicationId = nil
                } else {
                    expandedApplicationId = app.id
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    AvatarView(url: nil, fallbackName: app.displayName)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(app.displayName)
                                .font(.provider(.subheadline, weight: .semibold))
                                .foregroundStyle(Color.lavaShellCream)
                            if app.origin == .guest {
                                tag(text: "GUEST", tint: Color.orange.opacity(0.7))
                            }
                        }
                        if let email = app.email, !email.isEmpty {
                            Text(email)
                                .font(.provider(.caption))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            if let years = app.yearsExperience, !years.isEmpty {
                                Text("\(years) yr\(years == "1" ? "" : "s")")
                            }
                            if app.yearsExperience?.isEmpty == false,
                               let count = app.specialties?.count, count > 0
                            {
                                Text("·")
                            }
                            if let count = app.specialties?.count, count > 0 {
                                Text("\(count) specialt\(count == 1 ? "y" : "ies")")
                            }
                            if (app.yearsExperience?.isEmpty == false) || (app.specialties?.isEmpty == false),
                               let when = app.createdAt
                            {
                                Text("·")
                                Text(relativeShort(when))
                            } else if let when = app.createdAt {
                                Text(relativeShort(when))
                            }
                        }
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        applicationStatusBadge(app)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.provider(.caption, weight: .semibold))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                applicationDetailView(app, isBusy: isBusy)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isExpanded ? 0.08 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(isExpanded ? 0.18 : 0.10), lineWidth: 0.5)
        )
        .opacity(isBusy ? 0.55 : 1.0)
    }

    @ViewBuilder
    private func applicationDetailView(_ app: BarberApplicationListRowDTO, isBusy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(Color.lavaShellCream.opacity(0.15))

            applicationFactGrid(app)

            if let why = app.whyBeBarber?.trimmingCharacters(in: .whitespacesAndNewlines), !why.isEmpty {
                applicationParagraph(title: "Why they want to be a CampusCuts barber", text: why)
            }
            if let notes = app.additionalNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                applicationParagraph(title: "Additional notes", text: notes)
            }

            applicationContactRow(app)

            applicationActionRow(app, isBusy: isBusy)
        }
    }

    private func applicationFactGrid(_ app: BarberApplicationListRowDTO) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], alignment: .leading, spacing: 10) {
            applicationFactCell(title: "Experience", value: app.yearsExperience.map { "\($0) year\($0 == "1" ? "" : "s")" })
            applicationFactCell(title: "Hours / week", value: app.availableHours)
            applicationFactCell(
                title: "License",
                value: licenseSummary(app)
            )
            applicationFactCell(
                title: "Owns tools",
                value: app.hasOwnTools == nil ? nil : (app.hasOwnTools == true ? "Yes" : "No")
            )
            applicationFactCell(title: "Phone", value: app.phoneNumber)
            applicationFactCell(title: "Social", value: app.socialMedia)
            applicationFactCell(
                title: "Specialties",
                value: app.specialties?.isEmpty == false ? app.specialties?.joined(separator: ", ") : nil
            )
            applicationFactCell(
                title: "Submitted",
                value: app.createdAt.map { absoluteShort($0) }
            )
        }
    }

    private func applicationFactCell(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.provider(.caption2))
                .foregroundStyle(Color.lavaShellCreamTertiary)
            Text(value?.isEmpty == false ? value! : "—")
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func licenseSummary(_ app: BarberApplicationListRowDTO) -> String? {
        guard let hasLicense = app.hasLicense else { return nil }
        if hasLicense {
            if let num = app.licenseNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !num.isEmpty {
                return "Yes · \(num)"
            }
            return "Yes"
        }
        return "No"
    }

    private func applicationParagraph(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.provider(.caption2, weight: .semibold))
                .foregroundStyle(Color.lavaShellCreamTertiary)
                .textCase(.uppercase)
            Text(text)
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Contact strip: matches web "Schedule Interview" UX where managers reach out via email /
    /// phone / SMS rather than calling the status API. Buttons hand off to iOS via standard URL
    /// schemes (`mailto:`, `tel:`, `sms:`) and are only shown when the field is present.
    @ViewBuilder
    private func applicationContactRow(_ app: BarberApplicationListRowDTO) -> some View {
        let emailURL = mailtoURL(for: app)
        let phoneURL = telURL(for: app)
        let smsURL = smsURL(for: app)

        if emailURL != nil || phoneURL != nil || smsURL != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Contact")
                    .font(.provider(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    if let emailURL {
                        Link(destination: emailURL) {
                            contactPill(systemImage: "envelope", label: "Email")
                        }
                    }
                    if let phoneURL {
                        Link(destination: phoneURL) {
                            contactPill(systemImage: "phone", label: "Call")
                        }
                    }
                    if let smsURL {
                        Link(destination: smsURL) {
                            contactPill(systemImage: "message", label: "Text")
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func contactPill(systemImage: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(label).font(.provider(.caption, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.12), in: Capsule())
        .foregroundStyle(Color.lavaShellCream)
    }

    @ViewBuilder
    private func applicationActionRow(_ app: BarberApplicationListRowDTO, isBusy: Bool) -> some View {
        let isApprovedGuestAwaitingSignup = app.statusEnum == .approved
            && app.origin == .guest
            && (app.userId ?? "").isEmpty

        HStack(spacing: 8) {
            if isApprovedGuestAwaitingSignup {
                applicationActionButton(
                    title: "Revoke approval",
                    systemImage: "arrow.uturn.backward",
                    tint: Color.red.opacity(0.55),
                    isBusy: isBusy
                ) {
                    pendingApplicationDecision = PendingApplicationDecision(
                        row: app,
                        newStatus: .rejected,
                        actionLabel: "Revoke approval",
                        isDestructive: true
                    )
                }
            } else if app.statusEnum != .approved, app.statusEnum != .rejected {
                applicationActionButton(
                    title: "Approve",
                    systemImage: "checkmark.circle.fill",
                    tint: Color.providerOlive.opacity(0.9),
                    isBusy: isBusy
                ) {
                    pendingApplicationDecision = PendingApplicationDecision(
                        row: app,
                        newStatus: .approved,
                        actionLabel: "Approve",
                        isDestructive: false
                    )
                }
                applicationActionButton(
                    title: "Reject",
                    systemImage: "xmark.circle.fill",
                    tint: Color.red.opacity(0.55),
                    isBusy: isBusy
                ) {
                    pendingApplicationDecision = PendingApplicationDecision(
                        row: app,
                        newStatus: .rejected,
                        actionLabel: "Reject",
                        isDestructive: true
                    )
                }
            } else {
                Text(app.statusEnum == .approved ? "Approved" : "Rejected")
                    .font(.provider(.footnote, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            Spacer(minLength: 0)
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func applicationActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.provider(.subheadline, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(Color.lavaShellCream)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func applicationStatusBadge(_ app: BarberApplicationListRowDTO) -> some View {
        let label = app.statusEnum?.displayLabel ?? app.status.replacingOccurrences(of: "_", with: " ").capitalized
        let tint: Color = switch app.statusEnum {
        case .approved: Color.providerOlive
        case .rejected: Color.red.opacity(0.65)
        case .interviewScheduled: Color.blue.opacity(0.7)
        case .underReview: Color.orange.opacity(0.75)
        case .pending, .none: Color.orange.opacity(0.55)
        }
        return Text(label)
            .font(.provider(.caption2, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
            .foregroundStyle(Color.lavaShellCream)
    }

    // MARK: Contact URL builders

    private func mailtoURL(for app: BarberApplicationListRowDTO) -> URL? {
        guard let email = app.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            return nil
        }
        let escaped = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
        return URL(string: "mailto:\(escaped)")
    }

    private func telURL(for app: BarberApplicationListRowDTO) -> URL? {
        guard let raw = app.phoneNumber else { return nil }
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private func smsURL(for app: BarberApplicationListRowDTO) -> URL? {
        guard let raw = app.phoneNumber else { return nil }
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "sms:\(digits)")
    }

    // MARK: Date formatting helpers

    private func relativeShort(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    private func absoluteShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }

    // MARK: Loaders / actions

    private func loadApplications() async {
        guard let cid = effectiveCampusId else { return }
        applicationsLoading = true
        defer { applicationsLoading = false }
        applicationsError = nil
        do {
            let result = try await ProviderBarberApplicationService.listApplications(
                campusId: cid,
                status: nil,
                page: 1,
                limit: 100
            )
            applications = result.applications
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            applications = []
            applicationsError = msg ?? "Could not load applications (\(code))."
        } catch {
            applications = []
            applicationsError = error.localizedDescription
        }
    }

    private func applyApplicationDecision(_ decision: PendingApplicationDecision) async {
        applicationBusyId = decision.row.id
        defer { applicationBusyId = nil }
        applicationsError = nil
        do {
            try await ProviderBarberApplicationService.updateApplicationStatus(
                id: decision.row.id,
                status: decision.newStatus
            )
            // Refresh from server so approval side-effects (barber promotion + campus link)
            // are reflected accurately rather than guessed at locally.
            await loadApplications()
            // Approvals create a barber record; reload the Current Barbers list too.
            if decision.newStatus == .approved {
                await reloadCurrentBarbers()
            }
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            applicationsError = msg ?? "Status update failed (\(code))."
        } catch {
            applicationsError = error.localizedDescription
        }
    }

    private func reloadCurrentBarbers() async {
        guard let cid = effectiveCampusId else { return }
        if let updated = try? await ProviderCampusManagerService.campusBarbers(campusId: cid) {
            barbers = updated
        }
    }

    private func barberRow(_ barber: AdminBarberDTO) -> some View {
        Button {
            let route = ProviderShellRoute.adminBarberDetail(barber)
            shellNavigator.pushRoute(route)
        } label: {
            HStack(spacing: 12) {
                AvatarView(url: barber.avatarURL, fallbackName: barber.displayName)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(barber.displayName)
                            .font(.provider(.subheadline, weight: .semibold))
                        if barber.isCampusManager == true {
                            tag(text: "CM", tint: Color.providerOlive)
                        }
                    }
                    Text(barber.email ?? "—")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    HStack(spacing: 8) {
                        Text("\(barber.completedBookings ?? 0) booking\(barber.completedBookings == 1 ? "" : "s")")
                        Text("·")
                        Text(dollarString(centsLike: Double(barber.totalVolumeCents ?? 0)))
                    }
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                Spacer()
                visibilityToggle(barber)
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
    private func visibilityToggle(_ barber: AdminBarberDTO) -> some View {
        let isOn = barber.isActive ?? false
        Button {
            Task { await toggleBarberVisibility(barber) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "eye" : "eye.slash")
                Text(isOn ? "Visible" : "Hidden")
                    .font(.provider(.caption, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? Color.providerOlive.opacity(0.4) : Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(togglingBarberId == barber.id)
        .opacity(togglingBarberId == barber.id ? 0.5 : 1.0)
    }

    // MARK: - Bookings

    private var bookingsSection: some View {
        sectionCard(
            title: "Bookings",
            subtitle: "Recent activity across your campus."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Status", selection: $bookingsStatusFilter) {
                    ForEach(BookingFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: bookingsStatusFilter) { _, _ in
                    Task { await loadBookings() }
                }

                if bookings.isEmpty {
                    Text(isLoading ? "Loading bookings…" : "No bookings for this filter.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                } else {
                    ForEach(bookings.prefix(50)) { b in
                        bookingRow(b)
                    }
                    if bookings.count > 50 {
                        Text("Showing first 50 of \(bookings.count). Open the web dashboard for full filtering.")
                            .font(.provider(.caption2))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                }
            }
        }
    }

    private func bookingRow(_ b: SimpleBookingDTO) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.consumerDisplayName)
                    .font(.provider(.title3, weight: .semibold))
                Text(b.barberDisplayName)
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                Text(b.serviceDisplayName)
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                if let t = b.scheduledTime {
                    Text(t, style: .date)
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                    + Text(" · ")
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                    + Text(t, style: .time)
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
            }
            Spacer()
            statusBadge(b.statusUpper)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Data

    private func loadAll() async {
        if canSwitchCampuses, !availableCampusesLoaded {
            await loadAvailableCampusesForAdmin()
        }
        guard let cid = effectiveCampusId else {
            errorText = "Your account isn't linked to a campus. Reach out to support."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        errorText = nil
        _ = try? await ProviderAuthService.refreshAccessTokenIfPossible()
        async let campusInfo = ProviderCampusManagerService.campusInfo(campusId: cid)
        async let perf = ProviderCampusManagerService.campusPerformance(campusId: cid)
        async let barberList = ProviderCampusManagerService.campusBarbers(campusId: cid)
        async let metrics = fetchCampusMetricsSeries(campusId: cid, period: metricsTimeline.apiPeriod)
        do {
            let (c, p, bs) = try await (campusInfo, perf, barberList)
            campus = c
            performance = p
            barbers = bs
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Server returned \(code)."
        } catch {
            errorText = error.localizedDescription
        }
        metricsSnapshot = await metrics
        await loadBookings()
        await loadApplications()
    }

    /// Pulls the admin-only `/admin/campuses` catalog once so admins can switch between campus
    /// dashboards. Silently no-ops on transient errors — admins can pull-to-refresh to retry,
    /// and the dashboard still works on the user's home campus without the catalog.
    private func loadAvailableCampusesForAdmin() async {
        do {
            let campuses = try await ProviderAdminService.listCampuses()
            availableCampuses = campuses.sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            availableCampusesLoaded = true
        } catch {
            // Keep the dashboard usable; the switcher just won't open until the next refresh.
            availableCampuses = []
        }
    }

    /// Reset all campus-scoped state then refetch. Used by the admin switcher so stale data
    /// from one campus never leaks into another's view.
    private func switchAdminCampus(to newCampusId: String) async {
        guard newCampusId != effectiveCampusId else { return }
        adminViewingCampusId = newCampusId
        campus = nil
        performance = nil
        metricsSnapshot = nil
        selectedBucketIndex = nil
        barbers = []
        bookings = []
        applications = []
        expandedApplicationId = nil
        errorText = nil
        await loadAll()
    }

    /// Admin-only: assign or remove the designated campus manager (mirrors web `BarberPage` admin dashboard).
    private func updateCampusManagerAssignment(barberUserId: String?) async {
        guard canSwitchCampuses, let cid = effectiveCampusId else { return }

        isAssigningCampusManager = true
        defer { isAssigningCampusManager = false }

        do {
            if let barberUserId, !barberUserId.isEmpty {
                try await ProviderAdminService.assignCampusManager(
                    campusId: cid,
                    barberUserId: barberUserId,
                    action: "assign"
                )
            } else if let currentId = currentCampusManagerUserId {
                try await ProviderAdminService.assignCampusManager(
                    campusId: cid,
                    barberUserId: currentId,
                    action: "remove"
                )
            } else {
                return
            }

            async let campusInfo = ProviderCampusManagerService.campusInfo(campusId: cid)
            async let barberList = ProviderCampusManagerService.campusBarbers(campusId: cid)
            let (c, bs) = try await (campusInfo, barberList)
            campus = c
            barbers = bs
            if availableCampusesLoaded {
                availableCampuses = (try? await ProviderAdminService.listCampuses()) ?? availableCampuses
            }
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Server returned \(code)."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadBookings() async {
        guard let cid = effectiveCampusId else { return }
        do {
            bookings = try await ProviderCampusManagerService.campusBookings(
                campusId: cid,
                statusFilter: bookingsStatusFilter.apiValue
            )
        } catch {
            bookings = []
        }
    }

    private func reloadCampusMetricsTimeline() async {
        guard let cid = effectiveCampusId else { return }
        isLoadingMetrics = true
        defer { isLoadingMetrics = false }
        metricsSnapshot = await fetchCampusMetricsSeries(campusId: cid, period: metricsTimeline.apiPeriod)
    }

    private func fetchCampusMetricsSeries(campusId: String, period: String) async -> AdminMetricsSnapshotDTO? {
        try? await ProviderCampusManagerService.campusMetrics(campusId: campusId, period: period)
    }

    private func normalizedCampusMetricPoints(
        from snapshot: AdminMetricsSnapshotDTO?,
        timeline: CampusMetricsTimeline
    ) -> [CampusMetricPlotPoint] {
        let calendar = Calendar.current
        let bucketDates = Self.chartBucketDates(for: timeline, calendar: calendar)
        var totalsByBucket: [Date: (revenueDollars: Double, bookings: Int, signups: Int)] = [:]

        for row in snapshot?.data ?? [] {
            guard let parsedDate = CampusMetricsDateParsing.parse(row.date) else { continue }
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
            return CampusMetricPlotPoint(
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
        for timeline: CampusMetricsTimeline,
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
        }
    }

    private static func bucketStart(
        for date: Date,
        timeline: CampusMetricsTimeline,
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
        }
    }

    private func toggleBarberVisibility(_ barber: AdminBarberDTO) async {
        guard let recordId = barber.barberRecordId, !recordId.isEmpty else {
            togglingError = "Missing barber record id."
            return
        }
        let newValue = !(barber.isActive ?? false)
        togglingBarberId = barber.id
        togglingError = nil
        defer { togglingBarberId = nil }
        do {
            try await ProviderCampusManagerService.setBarberActive(barberRecordId: recordId, isActive: newValue)
            if let idx = barbers.firstIndex(where: { $0.id == barber.id }) {
                var updated = barbers[idx]
                updated = AdminBarberDTO(
                    id: updated.id,
                    barberRecordId: updated.barberRecordId,
                    firstName: updated.firstName,
                    lastName: updated.lastName,
                    email: updated.email,
                    profileImageUrl: updated.profileImageUrl,
                    isActive: newValue,
                    isCampusManager: updated.isCampusManager,
                    campusId: updated.campusId,
                    campusName: updated.campusName,
                    hasStripeSetup: updated.hasStripeSetup,
                    hasStripeAccountOnly: updated.hasStripeAccountOnly,
                    createdAt: updated.createdAt,
                    completedBookings: updated.completedBookings,
                    totalVolumeCents: updated.totalVolumeCents
                )
                barbers[idx] = updated
            }
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            togglingError = msg ?? "Visibility update failed (\(code))."
        } catch {
            togglingError = error.localizedDescription
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
            if !title.isEmpty || (subtitle.map { !$0.isEmpty } ?? false) {
                VStack(alignment: .leading, spacing: 2) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.provider(.title3, weight: .semibold))
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
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

    private func dollarString(centsLike: Double?) -> String {
        guard let v = centsLike else { return "$0.00" }
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
