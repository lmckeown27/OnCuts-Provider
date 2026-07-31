import Charts
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// `NSURLErrorCancelled` (-999) when a prior `URLSession` task is cancelled—**not** a user-visible failure.
private func providerAdminIsBenignRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
}

/// Native iOS Admin dashboard.
///
/// Tabs mirror the daily-driver flows of the web `AdminDashboard.tsx`:
///   * **Performance** — platform totals, **time-series chart** (daily / weekly / monthly / yearly), plus
///     **campus search** (typeahead) to scope or clear to aggregate headline revenue / bookings / payout metrics.
///   * **Operators** — **Current** providers with Visible/Hidden, Stripe, and (All Campuses)
///     Location filters (opened from a filter button). Campus scope uses pin proximity (~8km).
///     Row location shows `serviceLocationLabel` (never nearest campus name). **Applications** — approve / reject.
///   * **Users** — every platform user (optionally scoped by campus) with simple in-memory search; tap →
///     push the admin user-detail screen (consumer bookings).
///   * **Services** — platform service catalog (price / duration bounds, activate / deactivate).
struct ProviderAdminDashboardView: View {
    private enum AdminDashboardDestination: Hashable {
        case barber(AdminBarberDTO)
        case user(AdminPlatformUserDTO)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var adminDetailPath = NavigationPath()

    enum Tab: String, CaseIterable, Identifiable {
        case performance = "Performance"
        case barbers = "Operators"
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

        /// Compact label under the tab icon — fits five segments on narrow phones.
        var tabLabel: String {
            switch self {
            case .performance: "Perf."
            case .barbers: "Operators"
            case .users: "Users"
            case .services: "Services"
            case .safety: "Safety"
            }
        }
    }

    /// Outer hub inside Operators: roster tools vs onboarding bulk tools.
    enum OperatorsHubTab: String, CaseIterable, Identifiable {
        case operators = "Operators"
        case onboarding = "Onboarding"
        var id: String { rawValue }
    }

    /// Sub-selectors inside the Operators hub (Current roster vs Applications).
    enum BarbersSubTab: String, CaseIterable, Identifiable {
        case current = "Current"
        case applications = "Applications"
        var id: String { rawValue }
    }

    enum BarberVisibilityFilter: String, CaseIterable, Identifiable {
        case visible
        case hidden
        var id: String { rawValue }
        var segmentTitle: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            }
        }
    }

    enum BarberStripeFilter: String, CaseIterable, Identifiable {
        case all
        case setup
        case notSetup
        var id: String { rawValue }
        var segmentTitle: String {
            switch self {
            case .all: "All"
            case .setup: "Stripe"
            case .notSetup: "No Stripe"
            }
        }
    }

    /// All Universities only — Near campus = pin has a nearest campus within ~8km.
    enum BarberLocationFilter: String, CaseIterable, Identifiable {
        case all
        case nearCampus
        case unassigned
        var id: String { rawValue }
        var segmentTitle: String {
            switch self {
            case .all: "All"
            case .nearCampus: "Near campus"
            case .unassigned: "Unassigned"
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
    @State private var operatorsHubTab: OperatorsHubTab = .operators
    @State private var barbersSubTab: BarbersSubTab = .current
    @State private var barberVisibilityFilter: BarberVisibilityFilter = .visible
    @State private var barberStripeFilter: BarberStripeFilter = .all
    @State private var barberLocationFilter: BarberLocationFilter = .all
    @State private var showingOperatorsFilters = false
    @State private var operatorSearch = ""
    @State private var campuses: [AdminCampusDTO] = []
    @State private var selectedCampusId: String? = nil
    @State private var stats: AdminPlatformStatsDTO?
    @State private var performance: AdminCampusPerformanceDTO?
    @State private var barbers: [AdminBarberDTO] = []
    @State private var barberApplications: [BarberApplicationListRowDTO] = []
    @State private var selectedBarberApplication: BarberApplicationListRowDTO?
    @State private var isLoadingApplications = false
    @State private var applicationsError: String?
    @State private var busyApplicationId: String?
    /// When set, the detail action row is in the inline "Are you sure?" Yes/No state for that kind.
    @State private var applicationInlineConfirmKind: PendingBarberApplicationAction.Kind?
    @State private var users: [AdminPlatformUserDTO] = []
    @State private var userSearch: String = ""
    @State private var usersVisibleCount = 25
    @State private var userRoleFilter: UserRoleFilter = .all
    @State private var showingUsersFilters = false

    @State private var isLoading = true
    @State private var errorText: String?

    @State private var metricsSnapshot: AdminMetricsSnapshotDTO?
    @State private var metricsTimeline: MetricsTimeline = .daily
    @State private var metricsChartSeries: MetricsChartSeries = .revenue
    @State private var metricsDisplayMode: MetricsDisplayMode = .list
    @State private var metricsListSeries: MetricsListSeries = .bookings
    @State private var metricsListPeriod: MetricsListPeriod = .all
    @State private var listWindowOptions: [AdminMetricsListWindowOptionDTO] = []
    @State private var listWindowCommitted: AdminMetricsListWindowDTO?
    @State private var listParentWithin: AdminMetricsListWindowDTO?
    @State private var isLoadingListWindowOptions = false
    @State private var metricsListBookings: [AdminMetricsBookingEventDTO] = []
    @State private var metricsListSignups: [AdminMetricsSignupEventDTO] = []
    @State private var isLoadingListEvents = false
    @State private var listEventsSortNewestFirst = true
    @State private var isLoadingMetrics = false
    @State private var selectedBucketIndex: Int?
    @State private var isChartScrubbing = false

    @State private var platformFeePercent: Double = 15
    @State private var platformFeeInput = "15"
    @State private var isEditingPlatformFee = false
    @State private var isLoadingPlatformFee = false
    @State private var isSavingPlatformFee = false

    // Onboarding hub
    @State private var onboardingScope: OnboardingScope = .all
    @State private var onboardingSelectedIds: Set<String> = []
    @State private var onboardingFreeInput = "5"
    @State private var onboardingKickbackInput = "10"
    @State private var onboardingSearch = ""
    @State private var showingOnboardingFilters = false
    @State private var onboardingStripeFilter: BarberStripeFilter = .all
    @State private var onboardingLocationFilter: BarberLocationFilter = .all
    @State private var onboardingFreeFilter: OnboardingFreeFilter = .all
    @State private var onboardingKickbackFilter: OnboardingKickbackFilter = .all
    @State private var isSavingOnboardingBulk = false
    @State private var pendingOnboardingBulk: PendingOnboardingBulk?
    @State private var onboardingSaveMessage: String?
    /// Bumped by Admin pull-to-refresh so the nested Services tab reloads instead of only
    /// having its in-flight `.task` cancelled.
    @State private var servicesReloadToken = 0

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

    @Environment(\.colorScheme) private var colorScheme

    private struct PendingReportResolution: Identifiable, Equatable {
        let id: UUID = UUID()
        let report: AdminModerationReportDTO
        let action: AdminModerationResolveAction
    }

    private struct PendingBarberApplicationAction: Identifiable, Equatable {
        enum Kind: String, Equatable {
            case approve
            case reject
        }

        let id: UUID = UUID()
        let application: BarberApplicationListRowDTO
        let kind: Kind

        var status: BarberApplicationStatus {
            kind == .approve ? .approved : .rejected
        }
    }

    var body: some View {
        adminBodyWithDialogs
    }

    private var adminNavigationRoot: some View {
        NavigationStack(path: $adminDetailPath) {
            adminDashboardChrome
                .navigationDestination(for: AdminDashboardDestination.self) { destination in
                    adminDestination(destination)
                }
        }
    }

    private var adminBodyWithOnChanges: some View {
        adminNavigationRoot
            .onChange(of: userSearch) { _, _ in usersVisibleCount = 25 }
            .onChange(of: userRoleFilter) { _, _ in usersVisibleCount = 25 }
            .onChange(of: metricsTimeline) { _, _ in
                selectedBucketIndex = nil
                Task { await reloadMetricsTimeline() }
            }
            .onChange(of: metricsChartSeries) { _, _ in selectedBucketIndex = nil }
            .onChange(of: metricsDisplayMode) { _, mode in
                if mode == .list {
                    Task { await reloadMetricsListEvents() }
                } else {
                    Task { await reloadMetricsTimeline() }
                }
            }
            .onChange(of: metricsListSeries) { _, series in
                if series == .profit {
                    listWindowCommitted = nil
                    metricsListPeriod = .all
                } else {
                    Task { await reloadMetricsListEvents() }
                }
            }
            .onChange(of: metricsListPeriod) { _, period in
                if period == .all {
                    listWindowCommitted = nil
                    listParentWithin = nil
                    listWindowOptions = []
                    Task { await reloadMetricsListEvents() }
                } else {
                    Task { await reloadListWindowOptions() }
                }
            }
            .onChange(of: reportsStatusFilter) { _, _ in
                Task { await loadModerationReports() }
            }
            .onChange(of: bannedCategoryFilter) { _, _ in
                Task { await loadBannedUsers() }
            }
    }

    private var adminBodyWithDialogs: some View {
        adminBodyWithOnChanges
            .confirmationDialog(
                pendingReportResolutionTitle,
                isPresented: Binding(
                    get: { pendingReportResolution != nil },
                    set: { if !$0 { pendingReportResolution = nil } }
                ),
                titleVisibility: .visible,
                actions: { reportResolutionDialogActions },
                message: { reportResolutionDialogMessage }
            )
            .confirmationDialog(
                pendingUnbanTitle,
                isPresented: Binding(
                    get: { pendingUnban != nil },
                    set: { if !$0 { pendingUnban = nil } }
                ),
                titleVisibility: .visible,
                actions: { unbanDialogActions },
                message: { unbanDialogMessage }
            )
            .confirmationDialog(
                pendingOnboardingBulkTitle,
                isPresented: Binding(
                    get: { pendingOnboardingBulk != nil },
                    set: { if !$0 { pendingOnboardingBulk = nil } }
                ),
                titleVisibility: .visible,
                actions: { onboardingBulkDialogActions },
                message: { onboardingBulkDialogMessage }
            )
    }

    @ViewBuilder private var reportResolutionDialogActions: some View {
        if let pending = pendingReportResolution {
            Button(pending.action.displayLabel, role: pending.action.bansUser ? .destructive : nil) {
                let captured = pending
                pendingReportResolution = nil
                Task { await applyReportResolution(captured) }
            }
            Button("Cancel", role: .cancel) { pendingReportResolution = nil }
        }
    }

    @ViewBuilder private var reportResolutionDialogMessage: some View {
        if let pending = pendingReportResolution {
            Text(pendingReportResolutionMessage(for: pending))
        }
    }

    @ViewBuilder private var unbanDialogActions: some View {
        if let target = pendingUnban {
            Button("Unban") {
                let captured = target
                pendingUnban = nil
                Task { await applyUnban(captured) }
            }
            Button("Cancel", role: .cancel) { pendingUnban = nil }
        }
    }

    @ViewBuilder private var unbanDialogMessage: some View {
        if let target = pendingUnban {
            Text("\(target.displayName) will be able to sign in, get discovered, and make bookings again. You can re-ban them later if needed.")
        }
    }

    @ViewBuilder private var onboardingBulkDialogActions: some View {
        if let pending = pendingOnboardingBulk {
            Button("Apply", role: .destructive) {
                let captured = pending
                pendingOnboardingBulk = nil
                Task { await applyOnboardingBulk(captured) }
            }
            Button("Cancel", role: .cancel) { pendingOnboardingBulk = nil }
        }
    }

    @ViewBuilder private var onboardingBulkDialogMessage: some View {
        if let pending = pendingOnboardingBulk {
            Text(pendingOnboardingBulkMessage(for: pending))
        }
    }

    @ViewBuilder
    private func adminDestination(_ destination: AdminDashboardDestination) -> some View {
        switch destination {
        case .barber(let barber):
            ProviderAdminBarberDetailView(
                barber: barber,
                platformFeePercent: platformFeePercent
            )
        case .user(let user):
            ProviderAdminUserDetailView(user: user)
        }
    }

    private var adminDashboardChrome: some View {
        VStack(spacing: 0) {
            adminSheetHeader
            tabPicker
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .background(ProviderAdminChrome.stoneBackground)

            ScrollView {
                adminScrollBody
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: ProviderAdminChrome.panelMaxWidth)
                    .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await loadAll() }
        }
        .background(ProviderAdminChrome.stoneBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadAll() }
    }

    @ViewBuilder
    private var adminScrollBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorText {
                Text(errorText)
                    .font(.provider(.footnote))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
            switch tab {
            case .performance: performanceTab
            case .barbers: barbersTab
            case .users: usersTab
            case .services: ProviderAdminServicesView(reloadToken: servicesReloadToken)
            case .safety: safetyTab
            }
        }
    }

    private var adminSheetHeader: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(ProviderAdminChrome.stoneBorder)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            ZStack {
                Text("Admin")
                    .font(.provider(.headline, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.provider(.body, weight: .semibold))
                            .foregroundStyle(ProviderAdminChrome.secondaryText)
                            .frame(width: 32, height: 32)
                            .background(ProviderAdminChrome.stoneMutedFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Admin")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .background(ProviderAdminChrome.stoneBackground)
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

    private enum MetricsDisplayMode: String, CaseIterable, Identifiable {
        case list, graph
        var id: String { rawValue }
        var segmentTitle: String {
            switch self {
            case .list: return "List"
            case .graph: return "Graph"
            }
        }
    }

    private enum MetricsListSeries: String, CaseIterable, Identifiable {
        case bookings, signups, profit
        var id: String { rawValue }
        var segmentTitle: String {
            switch self {
            case .bookings: return "Bookings"
            case .signups: return "Sign-ups"
            case .profit: return "Profit/Loss"
            }
        }

        var eventsType: String? {
            switch self {
            case .bookings: return "bookings"
            case .signups: return "signups"
            case .profit: return nil
            }
        }
    }

    private enum MetricsListPeriod: String, CaseIterable, Identifiable {
        case all, year, month, week, day
        var id: String { rawValue }
        var chipLabel: String {
            switch self {
            case .all: return "All time"
            case .year: return "Year"
            case .month: return "Month"
            case .week: return "Week"
            case .day: return "Day"
            }
        }

        var apiGranularity: String? {
            switch self {
            case .all: return nil
            case .year: return "year"
            case .month: return "month"
            case .week: return "week"
            case .day: return "day"
            }
        }
    }

    private enum UserRoleFilter: String, CaseIterable, Identifiable {
        case all, consumer, admin
        var id: String { rawValue }
        var chipLabel: String {
            switch self {
            case .all: return "All"
            case .consumer: return "Consumer"
            case .admin: return "Admin"
            }
        }
    }

    private enum OnboardingScope: String, CaseIterable, Identifiable {
        case all, selected
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All Operators"
            case .selected: return "Select Operators"
            }
        }
    }

    private enum OnboardingFreeFilter: String, CaseIterable, Identifiable {
        case all, withFree, none
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .withFree: return "Has free slots"
            case .none: return "No free slots"
            }
        }
    }

    private enum OnboardingKickbackFilter: String, CaseIterable, Identifiable {
        case all, withKickback, none
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .withKickback: return "Has kickback"
            case .none: return "No kickback"
            }
        }
    }

    private struct PendingOnboardingBulk: Identifiable, Equatable {
        enum Field: String, Equatable { case free, kickback }
        let id = UUID()
        let field: Field
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
                barberLocationFilter = .all
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
                        barberLocationFilter = .all
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
                .foregroundStyle(ProviderAdminChrome.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ProviderAdminChrome.stoneMutedFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(ProviderAdminChrome.stoneBorder, lineWidth: 0.6)
                        )
                )
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
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
                .fill(ProviderAdminChrome.stoneMutedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ProviderAdminChrome.stoneBorder, lineWidth: 0.6)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Admin section")
    }

    private func adminTabButton(_ item: Tab) -> some View {
        let isSelected = tab == item
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                tab = item
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(.provider(.body, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.monochrome)
                Text(item.tabLabel)
                    .font(.provider(.caption2, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(
                isSelected
                    ? ProviderAdminChrome.primaryText
                    : ProviderAdminChrome.secondaryText
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ProviderAdminChrome.cardBackground)
                        .shadow(color: Color.primary.opacity(0.06), radius: 2, y: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Performance tab

    private var performanceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            platformCommissionAndKPIsCard
            metricsModeRow
            switch metricsDisplayMode {
            case .graph:
                performanceTimelineCard
            case .list:
                metricsListSeriesPicker
                switch metricsListSeries {
                case .bookings:
                    metricsBookingsListCard
                case .signups:
                    metricsSignupsListCard
                case .profit:
                    performanceCard
                }
            }
        }
    }

    private var platformCommissionAndKPIsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Platform commission")
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(ProviderAdminChrome.primaryText)

                HStack(spacing: 10) {
                    Text("Commission %")
                        .font(.provider(.subheadline))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        TextField("15", text: $platformFeeInput)
                            .font(.provider(.body, weight: .semibold))
                            .foregroundStyle(ProviderAdminChrome.primaryText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!isEditingPlatformFee || isSavingPlatformFee)
                            .frame(minWidth: 52, maxWidth: 72)
                        Text("%")
                            .font(.provider(.subheadline))
                            .foregroundStyle(ProviderAdminChrome.tertiaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isEditingPlatformFee
                            ? ProviderAdminChrome.cardBackground
                            : ProviderAdminChrome.mutedFill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(ProviderAdminChrome.border, lineWidth: 1)
                    )
                }

                if isEditingPlatformFee {
                    HStack(spacing: 10) {
                        Button {
                            Task { await savePlatformFee() }
                        } label: {
                            Group {
                                if isSavingPlatformFee {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Text("Save")
                                        .font(.provider(.subheadline, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.providerOlive)
                        .disabled(isSavingPlatformFee)

                        Button {
                            platformFeeInput = Self.formatFeePercent(platformFeePercent)
                            isEditingPlatformFee = false
                        } label: {
                            Text("Cancel")
                                .font(.provider(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSavingPlatformFee)
                    }
                } else {
                    Button {
                        platformFeeInput = Self.formatFeePercent(platformFeePercent)
                        isEditingPlatformFee = true
                    } label: {
                        Text("Edit commission")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingPlatformFee)
                }
            }

            Divider().overlay(ProviderAdminChrome.separator)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                compactKPI(label: "Users", value: "\(stats?.totalUsers ?? 0)")
                compactKPI(
                    label: "Bookings",
                    value: performance.map { "\($0.totalBookings ?? 0)" } ?? "…"
                )
                compactKPI(
                    label: "Operators",
                    value: performance.map { "\($0.totalBarbers ?? 0)" } ?? "…"
                )
            }
        }
        .padding(14)
        .providerAdminCardBackground(cornerRadius: 14)
    }

    private func compactKPI(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.provider(.caption2, weight: .medium))
                .foregroundStyle(ProviderAdminChrome.tertiaryText)
                .textCase(.uppercase)
            Text(value)
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(ProviderAdminChrome.primaryText)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(
            ProviderAdminChrome.mutedFill,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var metricsModeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            pillSegmentedControl(
                selection: $metricsDisplayMode,
                items: MetricsDisplayMode.allCases,
                title: \.segmentTitle
            )
            .frame(maxWidth: .infinity)

            if metricsDisplayMode == .graph {
                pillSegmentedControl(
                    selection: $metricsTimeline,
                    items: MetricsTimeline.allCases,
                    title: \.segmentTitle,
                    compact: true
                )
                .frame(maxWidth: .infinity)
            } else if metricsListSeries != .profit {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MetricsListPeriod.allCases) { period in
                            chipButton(
                                title: period.chipLabel,
                                selected: metricsListPeriod == period
                            ) {
                                metricsListPeriod = period
                                if period != .all {
                                    listParentWithin = nil
                                }
                            }
                        }
                    }
                }
            }

            if metricsDisplayMode == .list,
               metricsListSeries != .profit,
               metricsListPeriod != .all {
                metricsListWindowPicker
            }
        }
    }

    @ViewBuilder
    private var metricsListWindowPicker: some View {
        if isLoadingListWindowOptions {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading windows…")
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            }
        } else if listWindowOptions.isEmpty {
            Text("No windows for this period yet.")
                .font(.provider(.caption))
                .foregroundStyle(ProviderAdminChrome.secondaryText)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(listWindowOptions) { option in
                        chipButton(
                            title: option.displayLabel,
                            selected: listWindowCommitted?.id == option.id
                        ) {
                            listWindowCommitted = option.asWindow
                            Task { await reloadMetricsListEvents() }
                        }
                    }
                }
            }
        }
    }

    private var metricsListSeriesPicker: some View {
        pillSegmentedControl(
            selection: $metricsListSeries,
            items: MetricsListSeries.allCases,
            title: \.segmentTitle
        )
    }

    private func pillSegmentedControl<T: Hashable & Identifiable>(
        selection: Binding<T>,
        items: [T],
        title: KeyPath<T, String>,
        compact: Bool = false
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = selection.wrappedValue.id == item.id
                Button {
                    selection.wrappedValue = item
                } label: {
                    Text(item[keyPath: title])
                        .font(.provider(compact ? .caption2 : .caption, weight: .semibold))
                        .foregroundStyle(
                            selected
                                ? ProviderAdminChrome.primaryText
                                : ProviderAdminChrome.secondaryText
                        )
                        .padding(.horizontal, compact ? 8 : 12)
                        .padding(.vertical, compact ? 6 : 8)
                        .frame(maxWidth: compact ? .infinity : nil)
                        .background {
                            if selected {
                                Capsule().fill(ProviderAdminChrome.cardBackground)
                                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ProviderAdminChrome.mutedFill, in: Capsule())
    }

    private func chipButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(
                    selected ? ProviderAdminChrome.primaryText : ProviderAdminChrome.secondaryText
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selected ? ProviderAdminChrome.cardBackground : ProviderAdminChrome.mutedFill,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(ProviderAdminChrome.border, lineWidth: selected ? 0 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var performanceTimelineCard: some View {
        sectionCard(
            title: "Performance over time",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
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
                            .fill(Color.primary.opacity(0.06))
                        ProgressView()
                            .controlSize(.regular)
                    }
                }

                if !chartMetricPoints.isEmpty, selectedMetricPoint == nil {
                    Text("Press and drag on the chart to inspect a single \(metricsTimeline.bucketUnitSingular).")
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                        .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(metricsContextLabel)
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(ProviderAdminChrome.primaryText)

                    if selectedMetricPoint == nil {
                        Text(metricsTimeline.helperSubtitle)
                            .font(.provider(.caption2))
                            .foregroundStyle(ProviderAdminChrome.tertiaryText)
                    }
                }

                metricsSummaryGrid
            }
        }
    }

    private var metricsBookingsListCard: some View {
        sectionCard(
            title: metricsListHeaderTitle(count: sortedMetricsListBookings.count, noun: "bookings"),
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ShareLink(
                        item: bookingsCSV,
                        preview: SharePreview("Bookings export")
                    ) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .font(.provider(.caption, weight: .semibold))
                    }
                    .disabled(sortedMetricsListBookings.isEmpty)

                    Spacer()

                    Button {
                        listEventsSortNewestFirst.toggle()
                    } label: {
                        Label(
                            listEventsSortNewestFirst ? "Latest" : "Earliest",
                            systemImage: "arrow.up.arrow.down"
                        )
                        .font(.provider(.caption, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }

                if isLoadingListEvents {
                    loadingRow("Loading bookings…")
                } else if sortedMetricsListBookings.isEmpty {
                    Text("No bookings in this window.")
                        .font(.provider(.footnote))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                } else {
                    ForEach(sortedMetricsListBookings) { event in
                        metricsBookingRow(event)
                    }
                }
            }
        }
    }

    private var metricsSignupsListCard: some View {
        sectionCard(
            title: metricsListHeaderTitle(count: sortedMetricsListSignups.count, noun: "sign-ups"),
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ShareLink(
                        item: signupsCSV,
                        preview: SharePreview("Sign-ups export")
                    ) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .font(.provider(.caption, weight: .semibold))
                    }
                    .disabled(sortedMetricsListSignups.isEmpty)

                    Spacer()

                    Button {
                        listEventsSortNewestFirst.toggle()
                    } label: {
                        Label(
                            listEventsSortNewestFirst ? "Latest" : "Earliest",
                            systemImage: "arrow.up.arrow.down"
                        )
                        .font(.provider(.caption, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }

                if isLoadingListEvents {
                    loadingRow("Loading sign-ups…")
                } else if sortedMetricsListSignups.isEmpty {
                    Text("No sign-ups in this window.")
                        .font(.provider(.footnote))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                } else {
                    ForEach(sortedMetricsListSignups) { event in
                        metricsSignupRow(event)
                    }
                }
            }
        }
    }

    private func metricsListHeaderTitle(count: Int, noun: String) -> String {
        let window = listWindowCommitted?.displayLabel
            ?? (metricsListPeriod == .all ? "All time" : metricsListPeriod.chipLabel)
        return "\(window) · \(count) \(noun)"
    }

    private var sortedMetricsListBookings: [AdminMetricsBookingEventDTO] {
        metricsListBookings.sorted { lhs, rhs in
            let l = lhs.paidAt ?? .distantPast
            let r = rhs.paidAt ?? .distantPast
            return listEventsSortNewestFirst ? l > r : l < r
        }
    }

    private var sortedMetricsListSignups: [AdminMetricsSignupEventDTO] {
        metricsListSignups.sorted { lhs, rhs in
            let l = lhs.createdAt ?? .distantPast
            let r = rhs.createdAt ?? .distantPast
            return listEventsSortNewestFirst ? l > r : l < r
        }
    }

    private func metricsBookingRow(_ event: AdminMetricsBookingEventDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.consumerDisplayName)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                Spacer()
                Text(dollarString(centsLike: Double(event.totalPaidCents ?? 0)))
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
            }
            Text("with \(event.barberDisplayName) · \(event.serviceDisplayName)")
                .font(.provider(.caption))
                .foregroundStyle(ProviderAdminChrome.secondaryText)
            HStack {
                if let paidAt = event.paidAt {
                    Text(paidAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }
                Spacer()
                if let tip = event.tipCents, tip > 0 {
                    Text("+\(dollarString(centsLike: Double(tip))) tip")
                        .font(.provider(.caption2, weight: .semibold))
                        .foregroundStyle(Color.green.opacity(0.85))
                }
            }
        }
        .padding(10)
        .background(ProviderAdminChrome.stoneMutedFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metricsSignupRow(_ event: AdminMetricsSignupEventDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.displayName)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                Text("·")
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                Text(prettyRole(event.role))
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
                Spacer()
            }
            if let email = event.email, !email.isEmpty {
                Text(email)
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            }
            HStack {
                if let created = event.createdAt {
                    Text(created.formatted(date: .abbreviated, time: .shortened))
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }
                if let campus = event.campusName, !campus.isEmpty {
                    Text("· \(campus)")
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(ProviderAdminChrome.stoneMutedFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var bookingsCSV: String {
        var lines = ["Booking ID,Status,Service,Amount,Tip,Month,Year,Date,Time,Consumer,Operator"]
        let cal = Calendar.current
        for e in sortedMetricsListBookings {
            let paid = e.paidAt
            let month = paid.map { String(cal.component(.month, from: $0)) } ?? ""
            let year = paid.map { String(cal.component(.year, from: $0)) } ?? ""
            let date = paid.map { $0.formatted(date: .numeric, time: .omitted) } ?? ""
            let time = paid.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            let amount = String(format: "%.2f", Double(e.totalPaidCents ?? 0) / 100.0)
            let tip = String(format: "%.2f", Double(e.tipCents ?? 0) / 100.0)
            lines.append([
                e.id,
                e.status ?? "",
                e.serviceDisplayName,
                amount,
                tip,
                month,
                year,
                date,
                time,
                e.consumerDisplayName,
                e.barberDisplayName,
            ].map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private var signupsCSV: String {
        var lines = ["User ID,Name,Email,Role,Campus,Month,Year,Date,Time"]
        let cal = Calendar.current
        for e in sortedMetricsListSignups {
            let created = e.createdAt
            let month = created.map { String(cal.component(.month, from: $0)) } ?? ""
            let year = created.map { String(cal.component(.year, from: $0)) } ?? ""
            let date = created.map { $0.formatted(date: .numeric, time: .omitted) } ?? ""
            let time = created.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            lines.append([
                e.id,
                e.displayName,
                e.email ?? "",
                e.role ?? "",
                e.campusName ?? "",
                month,
                year,
                date,
                time,
            ].map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func prettyRole(_ role: String?) -> String {
        let r = (role ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch r {
        case "ADMIN": return "Admin"
        case "BARBER", "PROVIDER": return "Operator"
        case "CAMPUS_MANAGER": return "Campus Manager"
        case "CONSUMER", "USER", "": return "Consumer"
        default: return role?.capitalized ?? "User"
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
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            }
        } else {
            Text("No \(metricsScopeTitle.lowercased()) data in this range yet.")
                .font(.provider(.footnote))
                .foregroundStyle(ProviderAdminChrome.secondaryText)
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
                .foregroundStyle(ProviderAdminChrome.secondaryText)
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
                        .foregroundStyle(ProviderAdminChrome.primaryText.opacity(0.45))
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
                        let gridColor = ProviderAdminChrome.primaryText.opacity(0.12)
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
                                .foregroundStyle(ProviderAdminChrome.secondaryText)
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
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
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
                        metricCell(title: "Operators", value: "\(s.totalBarbers ?? 0)")
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
                    metricCell(title: "Operators", value: "\(p.totalBarbers ?? 0)")
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
                    metricCell(title: "Active operators", value: "\(p.activeBarbers ?? 0) / \(p.totalBarbers ?? 0)")
                    metricCell(title: "Total revenue", value: dollarString(centsLike: p.totalRevenue))
                    metricCell(title: "Platform fees", value: dollarString(centsLike: p.totalPlatformFees))
                    metricCell(title: "Net platform", value: dollarString(centsLike: p.netPlatformRevenue))
                    metricCell(title: "Operator earnings", value: dollarString(centsLike: p.totalBarberEarnings))
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
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
                    .padding(.top, 6)
                Text("Estimated from booking card volume and platform fees (same model as the web admin).")
                    .font(.provider(.caption2))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)

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

    // MARK: - Operators tab

    private var filteredCurrentBarbers: [AdminBarberDTO] {
        barbers.filter { barber in
            let active = barber.isActive != false
            switch barberVisibilityFilter {
            case .visible where !active: return false
            case .hidden where active: return false
            default: break
            }

            switch barberStripeFilter {
            case .all: break
            case .setup where barberVisibilityFilter == .visible && barber.hasStripeSetup != true: return false
            case .notSetup where barberVisibilityFilter == .visible && barber.hasStripeSetup == true: return false
            default: break
            }

            // Location filters only apply under All Universities (campus list is already proximity-scoped).
            if selectedCampusId == nil {
                switch barberLocationFilter {
                case .all: break
                case .nearCampus where !barber.isNearCampusBucket: return false
                case .unassigned where !barber.isLocationUnassigned: return false
                default: break
                }
            }

            let q = operatorSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !q.isEmpty {
                let hay = "\(barber.displayName) \(barber.email ?? "") \(barber.publicLocationDisplay)".lowercased()
                if !hay.contains(q) { return false }
            }

            return true
        }
        .sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var barbersTabSubtitle: String {
        switch barbersSubTab {
        case .current:
            let shown = filteredCurrentBarbers.count
            return "\(shown) shown · \(barbers.count) loaded."
        case .applications:
            if isLoadingApplications, barberApplications.isEmpty {
                return "Loading applications…"
            }
            let n = barberApplications.count
            return n == 1 ? "1 application needs review." : "\(n) applications need review."
        }
    }

    private var currentBarbersEmptyMessage: String {
        if isLoading, barbers.isEmpty {
            return "Loading operators…"
        }
        if barbers.isEmpty {
            if selectedCampusId != nil {
                return "No operators with a public pin near this campus."
            }
            return "No operators found for this scope."
        }
        return "No operators match these filters."
    }

    private var operatorsFiltersAreNonDefault: Bool {
        if barberVisibilityFilter != .visible { return true }
        if barberVisibilityFilter == .visible, barberStripeFilter != .all { return true }
        if selectedCampusId == nil, barberLocationFilter != .all { return true }
        return false
    }

    private var operatorsFilterSummary: String {
        var parts: [String] = [barberVisibilityFilter.segmentTitle]
        if barberVisibilityFilter == .visible, barberStripeFilter != .all {
            parts.append(barberStripeFilter.segmentTitle)
        }
        if selectedCampusId == nil, barberLocationFilter != .all {
            parts.append(barberLocationFilter.segmentTitle)
        }
        return parts.joined(separator: " · ")
    }

    private var barbersTab: some View {
        sectionCard(title: "Operators", subtitle: barbersTabSubtitle) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Operators hub", selection: $operatorsHubTab) {
                    ForEach(OperatorsHubTab.allCases) { hub in
                        Text(hub.rawValue).tag(hub)
                    }
                }
                .pickerStyle(.segmented)

                switch operatorsHubTab {
                case .operators:
                    operatorsRosterContent
                case .onboarding:
                    onboardingHubContent
                }
            }
        }
        .sheet(isPresented: $showingOperatorsFilters) {
            operatorsFiltersSheet
        }
        .sheet(isPresented: $showingOnboardingFilters) {
            onboardingFiltersSheet
        }
    }

    @ViewBuilder
    private var operatorsRosterContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                TextField("Search for Operators…", text: $operatorSearch)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
            )

            Picker("Operators section", selection: $barbersSubTab) {
                ForEach(BarbersSubTab.allCases) { sub in
                    Text("\(sub.rawValue) (\(barbersSubTabCount(sub)))").tag(sub)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: barbersSubTab) { _, _ in
                selectedBarberApplication = nil
                applicationInlineConfirmKind = nil
            }

            switch barbersSubTab {
            case .current:
                currentBarbersList
            case .applications:
                barberApplicationsList
            }
        }
    }

    private func barbersSubTabCount(_ sub: BarbersSubTab) -> Int {
        switch sub {
        case .current: return filteredCurrentBarbers.count
        case .applications: return barberApplications.count
        }
    }

    private var onboardingHubContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                TextField("Search operators…", text: $onboardingSearch)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    showingOnboardingFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
            )

            Picker("Scope", selection: $onboardingScope) {
                ForEach(OnboardingScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: onboardingScope) { _, scope in
                if scope == .all { onboardingSelectedIds = [] }
            }

            onboardingMassApplyRow(
                title: "Commissionless bookings",
                text: $onboardingFreeInput,
                keyboard: .numberPad,
                actionTitle: onboardingScope == .all
                    ? "Add to All"
                    : "Add to \(onboardingSelectedIds.count)"
            ) {
                pendingOnboardingBulk = PendingOnboardingBulk(field: .free)
            }

            onboardingMassApplyRow(
                title: "Kickback %",
                text: $onboardingKickbackInput,
                keyboard: .decimalPad,
                actionTitle: onboardingScope == .all
                    ? "Apply to All"
                    : "Apply to \(onboardingSelectedIds.count)"
            ) {
                pendingOnboardingBulk = PendingOnboardingBulk(field: .kickback)
            }

            if let onboardingSaveMessage {
                Text(onboardingSaveMessage)
                    .font(.provider(.caption))
                    .foregroundStyle(Color.green.opacity(0.9))
            }

            if filteredOnboardingBarbers.isEmpty {
                Text("No operators match these filters.")
                    .font(.provider(.footnote))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            } else {
                ForEach(filteredOnboardingBarbers) { barber in
                    onboardingBarberRow(barber)
                }
            }
        }
    }

    private func onboardingMassApplyRow(
        title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.provider(.caption))
                .foregroundStyle(ProviderAdminChrome.secondaryText)
            HStack(spacing: 8) {
                TextField("0", text: text)
                    .font(.provider(.subheadline))
                    .keyboardType(keyboard)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        ProviderAdminChrome.stoneMutedFill,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .frame(maxWidth: 100)
                Button(actionTitle, action: action)
                    .font(.provider(.caption, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.providerOlive)
                    .disabled(isSavingOnboardingBulk || (onboardingScope == .selected && onboardingSelectedIds.isEmpty))
            }
        }
    }

    private func onboardingBarberRow(_ barber: AdminBarberDTO) -> some View {
        let recordId = barber.barberRecordId ?? barber.id
        return HStack(alignment: .center, spacing: 10) {
            if onboardingScope == .selected {
                Button {
                    if onboardingSelectedIds.contains(recordId) {
                        onboardingSelectedIds.remove(recordId)
                    } else {
                        onboardingSelectedIds.insert(recordId)
                    }
                } label: {
                    Image(systemName: onboardingSelectedIds.contains(recordId) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(Color.providerOlive)
                }
                .buttonStyle(.plain)
            }

            ProviderSquaredAvatarView(
                url: barber.avatarURL,
                fallbackName: barber.displayName,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(barber.displayName)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                HStack(spacing: 6) {
                    if barber.hasStripeSetup == true {
                        tag(text: "Stripe", tint: Color.green.opacity(0.45))
                    } else {
                        tag(text: "No Stripe", tint: ProviderAdminChrome.stoneMutedFill)
                    }
                    Text("\(barber.commissionFreeBookingsRemaining ?? 0) free")
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                    Text("·")
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                    Text(String(format: "%.1f%% kb", barber.kickbackPercent ?? 0))
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 4) {
                stepperButton(systemName: "plus") {
                    Task { await adjustOnboarding(barber: barber, field: .free, delta: 1) }
                }
                stepperButton(systemName: "minus") {
                    Task { await adjustOnboarding(barber: barber, field: .free, delta: -1) }
                }
            }
        }
        .padding(10)
        .background(ProviderAdminChrome.stoneMutedFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stepperButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.provider(.caption, weight: .bold))
                .foregroundStyle(ProviderAdminChrome.primaryText)
                .frame(width: 28, height: 28)
                .background(ProviderAdminChrome.stoneCard, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSavingOnboardingBulk)
    }

    private var filteredOnboardingBarbers: [AdminBarberDTO] {
        barbers.filter { barber in
            if onboardingStripeFilter == .setup, barber.hasStripeSetup != true { return false }
            if onboardingStripeFilter == .notSetup, barber.hasStripeSetup == true { return false }
            if onboardingLocationFilter == .nearCampus, barber.isLocationUnassigned { return false }
            if onboardingLocationFilter == .unassigned, !barber.isLocationUnassigned { return false }
            let free = barber.commissionFreeBookingsRemaining ?? 0
            if onboardingFreeFilter == .withFree, free <= 0 { return false }
            if onboardingFreeFilter == .none, free > 0 { return false }
            let kickback = barber.kickbackPercent ?? 0
            if onboardingKickbackFilter == .withKickback, kickback <= 0 { return false }
            if onboardingKickbackFilter == .none, kickback > 0 { return false }
            let q = onboardingSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if q.isEmpty { return true }
            let hay = "\(barber.displayName) \(barber.email ?? "")".lowercased()
            return hay.contains(q)
        }
    }

    private var onboardingFiltersSheet: some View {
        NavigationStack {
            Form {
                Section("Stripe") {
                    Picker("Stripe", selection: $onboardingStripeFilter) {
                        ForEach(BarberStripeFilter.allCases) { f in
                            Text(f.segmentTitle).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Location") {
                    Picker("Location", selection: $onboardingLocationFilter) {
                        ForEach(BarberLocationFilter.allCases) { f in
                            Text(f.segmentTitle).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Commission-free") {
                    Picker("Free slots", selection: $onboardingFreeFilter) {
                        ForEach(OnboardingFreeFilter.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                }
                Section("Kickback") {
                    Picker("Kickback", selection: $onboardingKickbackFilter) {
                        ForEach(OnboardingKickbackFilter.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                }
            }
            .navigationTitle("Onboarding filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingOnboardingFilters = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var currentBarbersList: some View {
        VStack(alignment: .leading, spacing: 10) {
            operatorsFilterButton

            if filteredCurrentBarbers.isEmpty {
                Text(currentBarbersEmptyMessage)
                    .font(.provider(.footnote))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            } else {
                ForEach(filteredCurrentBarbers) { barber in
                    barberRow(barber)
                }
            }
        }
    }

    private var operatorsFilterButton: some View {
        Button {
            showingOperatorsFilters = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                Text(operatorsFiltersAreNonDefault ? "Filters: \(operatorsFilterSummary)" : "Filters")
                    .font(.provider(.subheadline, weight: .medium))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if operatorsFiltersAreNonDefault {
                    Text("Edit")
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(ProviderAdminChrome.stoneBorder, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Operator filters")
        .accessibilityValue(operatorsFilterSummary)
    }

    private var operatorsFiltersSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                currentBarbersFilterControls
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ProviderAdminChrome.stoneBackground.ignoresSafeArea())
            .providerPageNavigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        barberVisibilityFilter = .visible
                        barberStripeFilter = .all
                        barberLocationFilter = .all
                    }
                    .disabled(!operatorsFiltersAreNonDefault)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingOperatorsFilters = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .tint(.providerOlive)
    }

    @ViewBuilder
    private var currentBarbersFilterControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            filterControlGroup(title: "Visibility") {
                Picker("Visibility", selection: $barberVisibilityFilter) {
                    ForEach(BarberVisibilityFilter.allCases) { filter in
                        Text(filter.segmentTitle).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: barberVisibilityFilter) { _, newValue in
                    if newValue != .visible {
                        barberStripeFilter = .all
                    }
                }
            }

            if barberVisibilityFilter == .visible {
                filterControlGroup(title: "Stripe") {
                    Picker("Stripe", selection: $barberStripeFilter) {
                        ForEach(BarberStripeFilter.allCases) { filter in
                            Text(filter.segmentTitle).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if selectedCampusId == nil {
                filterControlGroup(title: "Location") {
                    Picker("Location", selection: $barberLocationFilter) {
                        ForEach(BarberLocationFilter.allCases) { filter in
                            Text(filter.segmentTitle).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private func filterControlGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(ProviderAdminChrome.secondaryText)
            content()
        }
    }

    @ViewBuilder
    private var barberApplicationsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let applicationsError, !applicationsError.isEmpty {
                Text(applicationsError)
                    .font(.provider(.caption))
                    .foregroundStyle(.red)
            }

            if let selected = selectedBarberApplication {
                barberApplicationDetail(selected)
            } else if isLoadingApplications, barberApplications.isEmpty {
                loadingRow("Loading applications…")
            } else if barberApplications.isEmpty {
                Text("No applications need review for this scope.")
                    .font(.provider(.footnote))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            } else {
                ForEach(barberApplications) { application in
                    barberApplicationRow(application)
                }
            }
        }
    }

    private func barberApplicationRow(_ application: BarberApplicationListRowDTO) -> some View {
        let isBusy = busyApplicationId == application.id
        return Button {
            applicationInlineConfirmKind = nil
            selectedBarberApplication = application
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(application.displayName)
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(ProviderAdminChrome.primaryText)
                        if application.origin == .guest {
                            tag(text: "Guest", tint: Color.orange.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                        tag(
                            text: application.statusEnum?.displayLabel ?? application.status.capitalized,
                            tint: applicationStatusTint(application)
                        )
                    }
                    Text(application.email ?? "No email")
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let campus = application.campusName, !campus.isEmpty {
                            Text(campus)
                        }
                        if let years = application.yearsExperience, !years.isEmpty {
                            Text("·")
                            Text("\(years) yrs")
                        }
                        if let when = application.createdAt {
                            Text("·")
                            Text(relativeShort(when))
                        }
                    }
                    .font(.provider(.caption2))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
            )
            .opacity(isBusy ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func barberApplicationDetail(_ application: BarberApplicationListRowDTO) -> some View {
        let isBusy = busyApplicationId == application.id
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                selectedBarberApplication = nil
                applicationInlineConfirmKind = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back to Applications")
                }
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(ProviderAdminChrome.primaryText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(application.displayName)
                        .font(.provider(.title3, weight: .semibold))
                        .foregroundStyle(ProviderAdminChrome.primaryText)
                    if application.origin == .guest {
                        tag(text: "Guest", tint: Color.orange.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    tag(
                        text: application.statusEnum?.displayLabel ?? application.status.capitalized,
                        tint: applicationStatusTint(application)
                    )
                }
                Text(application.email ?? "No email")
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
                applicationDetailGrid(application)
                if let specialties = application.specialties, !specialties.isEmpty {
                    applicationDetailBlock(title: "Specialties", value: specialties.joined(separator: ", "))
                }
                applicationDetailBlock(
                    title: "Profession",
                    value: application.submittedProfessionLabel ?? "—"
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
            )

            if application.statusEnum == .pending {
                applicationDecisionButtons(application, isBusy: isBusy)
            }

            if isBusy {
                loadingRow("Updating application…")
            }
        }
    }

    @ViewBuilder
    private func applicationDecisionButtons(
        _ application: BarberApplicationListRowDTO,
        isBusy: Bool
    ) -> some View {
        VStack(spacing: 8) {
            if applicationInlineConfirmKind != nil {
                Text("Are you sure?")
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                switch applicationInlineConfirmKind {
                case nil:
                    Button {
                        applicationInlineConfirmKind = .approve
                    } label: {
                        Text("Approve")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.providerOlive)
                    .disabled(isBusy)

                    Button {
                        applicationInlineConfirmKind = .reject
                    } label: {
                        Text("Reject")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isBusy)

                case .approve:
                    // Pressed Approve → that slot becomes No; other slot becomes Yes.
                    Button {
                        applicationInlineConfirmKind = nil
                    } label: {
                        Text("No")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)

                    Button {
                        let pending = PendingBarberApplicationAction(application: application, kind: .approve)
                        applicationInlineConfirmKind = nil
                        Task { await applyBarberApplicationAction(pending) }
                    } label: {
                        Text("Yes")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.providerOlive)
                    .disabled(isBusy)

                case .reject:
                    // Pressed Reject → that slot becomes No; other slot becomes Yes.
                    Button {
                        let pending = PendingBarberApplicationAction(application: application, kind: .reject)
                        applicationInlineConfirmKind = nil
                        Task { await applyBarberApplicationAction(pending) }
                    } label: {
                        Text("Yes")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isBusy)

                    Button {
                        applicationInlineConfirmKind = nil
                    } label: {
                        Text("No")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
            }
        }
    }

    @ViewBuilder
    private func applicationDetailGrid(_ application: BarberApplicationListRowDTO) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            applicationMetricCell(
                title: "Experience",
                value: application.yearsExperience.map { "\($0) years" } ?? "—"
            )
            applicationMetricCell(title: "Phone", value: applicationPhoneDisplay(application.phoneNumber))
            applicationMetricCell(
                title: "Own tools",
                value: application.hasOwnTools == true ? "Yes" : (application.hasOwnTools == false ? "No" : "—")
            )
            if let when = application.createdAt {
                applicationMetricCell(title: "Applied", value: applicationAppliedDate(when))
            }
        }
    }

    private func applicationPhoneDisplay(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Not provided" }
        // Prefer the applicant's stored formatting (punctuation / spaces). Only reformat
        // legacy E.164 / digits-only values that were normalized before submit.
        let hasApplicantFormatting = trimmed.contains(where: { !$0.isNumber && $0 != "+" })
        if hasApplicantFormatting {
            return trimmed
        }
        let digits = trimmed.filter(\.isNumber)
        // Legacy NANP E.164 (`+1…` / `1…` / 10 digits) → `(555) 555-5555`.
        if digits.count == 11, digits.hasPrefix("1") {
            return PhoneNumberInputFormatter.format(String(digits.dropFirst()), regionCode: "US")
        }
        if digits.count == 10 {
            return PhoneNumberInputFormatter.format(digits, regionCode: "US")
        }
        let region = Locale.current.region?.identifier ?? "US"
        let formatted = PhoneNumberInputFormatter.format(trimmed, regionCode: region)
        return formatted.isEmpty ? trimmed : formatted
    }

    private func applicationAppliedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func applicationMetricCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.provider(.caption2))
                .foregroundStyle(ProviderAdminChrome.tertiaryText)
            Text(value)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(ProviderAdminChrome.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ProviderAdminChrome.stoneMutedFill)
        )
    }

    private func applicationDetailBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.provider(.caption2))
                .foregroundStyle(ProviderAdminChrome.tertiaryText)
            Text(value)
                .font(.provider(.footnote))
                .foregroundStyle(ProviderAdminChrome.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ProviderAdminChrome.stoneMutedFill)
        )
    }

    private func applicationStatusTint(_ application: BarberApplicationListRowDTO) -> Color {
        switch application.statusEnum {
        case .pending: return Color.orange.opacity(0.55)
        case .approved: return Color.green.opacity(0.55)
        case .rejected: return Color.red.opacity(0.55)
        case .underReview, .interviewScheduled: return Color.blue.opacity(0.45)
        case nil: return ProviderAdminChrome.stoneMutedFill
        }
    }

    private func barberRow(_ barber: AdminBarberDTO) -> some View {
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
                        if barber.isActive == false {
                            tag(text: "Hidden", tint: Color.red.opacity(0.7))
                        }
                        if barber.isBanned == true {
                            tag(text: "Banned", tint: Color.red.opacity(0.85))
                        }
                    }
                    Text(barber.email ?? "—")
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                    // Prefer the provider's public pin label exactly — never nearest campus name.
                    Text(barber.publicLocationDisplay)
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("\(barber.completedBookings ?? 0) bookings")
                        Text("·")
                        Text(dollarString(centsLike: Double(barber.totalVolumeCents ?? 0)))
                    }
                    .font(.provider(.caption2))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                    stripeBadges(barber)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
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
                tag(text: "No Stripe", tint: ProviderAdminChrome.stoneMutedFill)
            }
        }
    }

    // MARK: - Users tab

    private let usersPageSize = 25

    private var filteredUsers: [AdminPlatformUserDTO] {
        users.filter { u in
            switch userRoleFilter {
            case .all: break
            case .consumer:
                let r = (u.role ?? "").uppercased()
                if r == "ADMIN" || r == "BARBER" || r == "PROVIDER" || r == "CAMPUS_MANAGER" {
                    return false
                }
            case .admin:
                if (u.role ?? "").uppercased() != "ADMIN" { return false }
            }

            let q = userSearch.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return true }
            return (u.email?.lowercased().contains(q) ?? false)
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
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                    TextField("Search users…", text: $userSearch)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !userSearch.isEmpty {
                        Button { userSearch = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(ProviderAdminChrome.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showingUsersFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(ProviderAdminChrome.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ProviderAdminChrome.stoneMutedFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(ProviderAdminChrome.stoneBorder, lineWidth: 0.5)
                        )
                )
                if userRoleFilter != .all {
                    Text("Role: \(userRoleFilter.chipLabel)")
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                }
                if filteredUsers.isEmpty {
                    Text(isLoading ? "Loading users…" : "No matching users.")
                        .font(.provider(.footnote))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
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
        .sheet(isPresented: $showingUsersFilters) {
            NavigationStack {
                Form {
                    Section("Role") {
                        Picker("Role", selection: $userRoleFilter) {
                            ForEach(UserRoleFilter.allCases) { filter in
                                Text(filter.chipLabel).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .navigationTitle("User filters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingUsersFilters = false }
                    }
                }
            }
            .presentationDetents([.medium])
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
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                    HStack(spacing: 6) {
                        Text(user.prettyRole)
                        if let campus = user.campusName, !campus.isEmpty {
                            Text("·")
                            Text(campus)
                        }
                    }
                    .font(.provider(.caption2))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
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
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
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
                                .foregroundStyle(ProviderAdminChrome.primaryText)
                        }
                        Spacer(minLength: 0)
                        if let when = report.createdAt {
                            Text(relativeShort(when))
                                .font(.provider(.caption2))
                                .foregroundStyle(ProviderAdminChrome.tertiaryText)
                        }
                    }
                    Text("Reported: \(report.reportedUserDisplayName)")
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(ProviderAdminChrome.primaryText)
                    if let email = report.reportedUserEmail, !email.isEmpty {
                        Text(email)
                            .font(.provider(.caption))
                            .foregroundStyle(ProviderAdminChrome.secondaryText)
                            .lineLimit(1)
                    }
                    Text("Reporter: \(report.reporterDisplayName)")
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }
            }

            if let descr = report.description?.trimmingCharacters(in: .whitespacesAndNewlines), !descr.isEmpty {
                Text(descr)
                    .font(.provider(.footnote))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let preview = report.subjectContent?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                Text("“\(preview)”")
                    .font(.provider(.footnote)).italic()
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ProviderAdminChrome.stoneMutedFill)
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
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                    Text(notes)
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.primaryText)
                }
            }

            if report.isOpen {
                reportActionRow(report, isBusy: isBusy)
            } else if let action = report.resolutionAction, !action.isEmpty {
                Text("Action: \(action.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(.provider(.caption2))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ProviderAdminChrome.stoneMutedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(report.isOpen ? Color.orange.opacity(0.35) : ProviderAdminChrome.stoneBorder, lineWidth: 0.5)
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
                .background(ProviderAdminChrome.stoneMutedFill, in: Capsule())
                .foregroundStyle(ProviderAdminChrome.primaryText)
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
            .foregroundStyle(ProviderAdminChrome.primaryText)
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
            .foregroundStyle(ProviderAdminChrome.primaryText)
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
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
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
                            .foregroundStyle(ProviderAdminChrome.primaryText)
                        tag(text: "BANNED", tint: Color.red.opacity(0.7))
                        if let count = user.openReportCount, count > 0 {
                            tag(text: "\(count) open", tint: Color.orange.opacity(0.65))
                        }
                    }
                    if let email = user.email, !email.isEmpty {
                        Text(email)
                            .font(.provider(.caption))
                            .foregroundStyle(ProviderAdminChrome.secondaryText)
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
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                    if let listing = user.barberListingStateLabel {
                        Text(listing)
                            .font(.provider(.caption2))
                            .foregroundStyle(ProviderAdminChrome.tertiaryText)
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
                    .foregroundStyle(ProviderAdminChrome.primaryText)
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
                .fill(ProviderAdminChrome.stoneMutedFill)
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
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                Text("\(title): \(label(selection.wrappedValue))")
                    .font(.provider(.subheadline, weight: .medium))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(ProviderAdminChrome.stoneBorder, lineWidth: 0.5)
                    )
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
        async let feeTask: () = loadPlatformFee()
        do {
            let (s, c) = try await (st, cs)
            stats = s
            campuses = c
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Server returned \(code)."
        } catch {
            if !providerAdminIsBenignRequestCancellation(error) {
                errorText = error.localizedDescription
            }
        }
        await feeTask
        await loadScopedData()
        await loadSafety()
        servicesReloadToken &+= 1
        if metricsDisplayMode == .list {
            await reloadMetricsListEvents()
        }
    }

    private func loadPlatformFee() async {
        isLoadingPlatformFee = true
        defer { isLoadingPlatformFee = false }
        do {
            let pct = try await ProviderAdminService.fetchPlatformSettings()
            platformFeePercent = pct
            if !isEditingPlatformFee {
                platformFeeInput = Self.formatFeePercent(pct)
            }
        } catch {
            // Keep last known / default 15%.
        }
    }

    private static func formatFeePercent(_ pct: Double) -> String {
        if pct.rounded() == pct { return String(Int(pct)) }
        return String(format: "%.1f", pct)
    }

    private func savePlatformFee() async {
        guard let pct = Double(platformFeeInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              pct >= 0, pct <= 100 else {
            errorText = "Commission percent must be between 0 and 100."
            return
        }
        isSavingPlatformFee = true
        defer { isSavingPlatformFee = false }
        do {
            let saved = try await ProviderAdminService.updatePlatformSettings(platformFeePercent: pct)
            platformFeePercent = saved
            platformFeeInput = Self.formatFeePercent(saved)
            isEditingPlatformFee = false
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Failed to save platform commission (\(code))."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func reloadListWindowOptions() async {
        guard let granularity = metricsListPeriod.apiGranularity,
              let type = metricsListSeries.eventsType else {
            listWindowOptions = []
            return
        }
        isLoadingListWindowOptions = true
        defer { isLoadingListWindowOptions = false }
        do {
            listWindowOptions = try await ProviderAdminService.metricsEventsOptions(
                campusId: selectedCampusId,
                granularity: granularity,
                type: type,
                withinStart: listParentWithin?.start,
                withinEnd: listParentWithin?.end
            )
        } catch {
            listWindowOptions = []
        }
    }

    private func reloadMetricsListEvents() async {
        isLoadingListEvents = true
        defer { isLoadingListEvents = false }
        let start = listWindowCommitted?.start
        let end = listWindowCommitted?.end
        do {
            async let bookings = ProviderAdminService.metricsBookingEvents(
                campusId: selectedCampusId,
                start: start,
                end: end
            )
            async let signups = ProviderAdminService.metricsSignupEvents(
                campusId: selectedCampusId,
                start: start,
                end: end
            )
            let (b, s) = try await (bookings, signups)
            metricsListBookings = b
            metricsListSignups = s
        } catch {
            metricsListBookings = []
            metricsListSignups = []
        }
    }

    private var pendingOnboardingBulkTitle: String {
        guard let pending = pendingOnboardingBulk else { return "Confirm" }
        switch pending.field {
        case .free: return "Apply commission-free quota?"
        case .kickback: return "Apply kickback percent?"
        }
    }

    private func pendingOnboardingBulkMessage(for pending: PendingOnboardingBulk) -> String {
        let target: String
        switch onboardingScope {
        case .all:
            target = "all operators"
        case .selected:
            target = "\(onboardingSelectedIds.count) selected operators"
        }
        switch pending.field {
        case .free:
            return "Set commission-free bookings remaining to \(onboardingFreeInput) for \(target)."
        case .kickback:
            return "Set kickback percent to \(onboardingKickbackInput)% for \(target)."
        }
    }

    private func applyOnboardingBulk(_ pending: PendingOnboardingBulk) async {
        isSavingOnboardingBulk = true
        onboardingSaveMessage = nil
        defer { isSavingOnboardingBulk = false }
        do {
            let scope = onboardingScope == .all ? "all" : "selected"
            let ids = onboardingScope == .selected ? Array(onboardingSelectedIds) : nil
            let updated: Int
            switch pending.field {
            case .free:
                guard let free = Int(onboardingFreeInput.trimmingCharacters(in: .whitespacesAndNewlines)),
                      free >= 0 else {
                    errorText = "Commission-free bookings must be a whole number ≥ 0."
                    return
                }
                updated = try await ProviderAdminService.bulkUpdateBarberCommission(
                    scope: scope,
                    barberRecordIds: ids,
                    commissionFreeBookingsRemaining: free,
                    kickbackPercent: nil
                )
            case .kickback:
                guard let kickback = Double(onboardingKickbackInput.trimmingCharacters(in: .whitespacesAndNewlines)),
                      kickback >= 0, kickback <= 100 else {
                    errorText = "Kickback percent must be between 0 and 100."
                    return
                }
                updated = try await ProviderAdminService.bulkUpdateBarberCommission(
                    scope: scope,
                    barberRecordIds: ids,
                    commissionFreeBookingsRemaining: nil,
                    kickbackPercent: kickback
                )
            }
            onboardingSaveMessage = "Updated \(updated) operators."
            barbers = await fetchBarbers(campusId: selectedCampusId)
            NotificationCenter.default.post(name: .providerCommissionFreeQuotaChanged, object: nil)
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Bulk update failed (\(code))."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func adjustOnboarding(barber: AdminBarberDTO, field: PendingOnboardingBulk.Field, delta: Int) async {
        guard let recordId = barber.barberRecordId else { return }
        let free = max(0, (barber.commissionFreeBookingsRemaining ?? 0) + (field == .free ? delta : 0))
        let kickback = barber.kickbackPercent ?? 0
        do {
            let updated = try await ProviderAdminService.updateBarberCommission(
                barberRecordId: recordId,
                commissionFreeBookingsRemaining: free,
                kickbackPercent: kickback
            )
            if let idx = barbers.firstIndex(where: { $0.id == barber.id || $0.barberRecordId == recordId }) {
                var copy = barbers
                let b = copy[idx]
                copy[idx] = AdminBarberDTO(
                    id: b.id,
                    barberRecordId: b.barberRecordId,
                    firstName: b.firstName,
                    lastName: b.lastName,
                    email: b.email,
                    profileImageUrl: b.profileImageUrl,
                    isActive: b.isActive,
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
                    commissionFreeBookingsRemaining: updated.commissionFreeBookingsRemaining ?? free,
                    kickbackPercent: updated.kickbackPercent ?? kickback
                )
                barbers = copy
            }
            NotificationCenter.default.post(name: .providerCommissionFreeQuotaChanged, object: nil)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            moderationReports = []
            reportsError = msg ?? "Could not load reports (\(code))."
        } catch {
            guard !providerAdminIsBenignRequestCancellation(error) else { return }
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
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            bannedUsers = []
            bannedError = msg ?? "Could not load banned users (\(code))."
        } catch {
            guard !providerAdminIsBenignRequestCancellation(error) else { return }
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
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            reportsError = msg ?? "Resolution failed (\(code))."
        } catch {
            guard !providerAdminIsBenignRequestCancellation(error) else { return }
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
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            bannedError = msg ?? "Unban failed (\(code))."
        } catch {
            guard !providerAdminIsBenignRequestCancellation(error) else { return }
            bannedError = error.localizedDescription
        }
        await loadBannedUsers()
    }

    private func loadScopedData() async {
        selectedBucketIndex = nil
        usersVisibleCount = 25
        selectedBarberApplication = nil
        applicationInlineConfirmKind = nil
        let scope = selectedCampusId
        async let perfTask = fetchPerformance(campusId: scope)
        async let barbersTask = fetchBarbers(campusId: scope)
        async let usersTask = fetchUsers(campusId: scope)
        async let metricsTask = fetchMetricsSeries(campusId: scope, period: metricsTimeline.apiPeriod)
        async let applicationsTask = fetchActionableBarberApplications(campusId: scope)
        let (p, bs, us, m, appsResult) = await (perfTask, barbersTask, usersTask, metricsTask, applicationsTask)
        performance = p
        barbers = bs
        users = us
        metricsSnapshot = m
        switch appsResult {
        case .success(let apps):
            barberApplications = apps
            applicationsError = nil
        case .failure(let message):
            barberApplications = []
            applicationsError = message
        }
        if metricsDisplayMode == .list {
            await reloadMetricsListEvents()
        }
    }

    private enum ApplicationsLoadResult {
        case success([BarberApplicationListRowDTO])
        case failure(String)
    }

    private func fetchActionableBarberApplications(campusId: String?) async -> ApplicationsLoadResult {
        isLoadingApplications = true
        defer { isLoadingApplications = false }
        do {
            let result = try await ProviderBarberApplicationService.listApplications(
                campusId: campusId,
                limit: 200
            )
            return .success(result.applications.filter(\.isActionableInAdminApplicationQueue))
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            return .failure(msg ?? "Could not load applications (\(code)).")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func applyBarberApplicationAction(_ pending: PendingBarberApplicationAction) async {
        busyApplicationId = pending.application.id
        defer { busyApplicationId = nil }
        applicationsError = nil
        do {
            try await ProviderBarberApplicationService.updateApplicationStatus(
                id: pending.application.id,
                status: pending.status
            )
            barberApplications.removeAll { $0.id == pending.application.id }
            if selectedBarberApplication?.id == pending.application.id {
                selectedBarberApplication = nil
            }
            applicationInlineConfirmKind = nil
            if pending.kind == .approve {
                // Don't replace the list with [] if the refresh fails (try? previously wiped Current).
                do {
                    if let campusId = selectedCampusId {
                        barbers = try await ProviderAdminService.campusBarbers(campusId: campusId)
                    } else {
                        barbers = try await ProviderAdminService.allBarbers()
                    }
                } catch let OnCutsHTTPError.httpStatus(code, msg) {
                    applicationsError = msg ?? "Approved, but could not refresh operators (\(code))."
                } catch {
                    applicationsError = "Approved, but could not refresh operators: \(error.localizedDescription)"
                }
            }
        } catch let OnCutsHTTPError.httpStatus(code, msg) {
            applicationsError = msg ?? "Could not update application (\(code))."
        } catch {
            applicationsError = error.localizedDescription
        }
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
        do {
            if let id = campusId {
                return try await ProviderAdminService.campusBarbers(campusId: id)
            }
            return try await ProviderAdminService.allBarbers()
        } catch {
            if errorText == nil {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            // Keep whatever is already on screen rather than blanking Current on a transient failure.
            return barbers
        }
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
                    .foregroundStyle(ProviderAdminChrome.primaryText)
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
        .providerAdminCardBackground(cornerRadius: 16)
    }

    private func metricCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.provider(.caption2))
                .foregroundStyle(ProviderAdminChrome.tertiaryText)
            Text(value)
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(ProviderAdminChrome.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ProviderAdminChrome.mutedFill)
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
            Text(msg).font(.provider(.footnote)).foregroundStyle(ProviderAdminChrome.secondaryText)
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
