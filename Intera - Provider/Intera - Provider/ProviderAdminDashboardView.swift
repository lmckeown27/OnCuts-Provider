import Charts
import SwiftUI

/// Native iOS Admin dashboard.
///
/// Three tabs mirror the daily-driver flows of the web `AdminDashboard.tsx`:
///   * **Performance** — platform totals, **time-series chart** (daily / weekly / monthly / yearly), plus
///     **campus search** (typeahead) to scope or clear to aggregate headline revenue / bookings / payout metrics.
///   * **Barbers** — every barber (optionally scoped by campus) with Stripe status badges; tap → push the
///     admin barber-detail screen (bookings + visibility toggle, shared with the CM dashboard).
///   * **Users** — every platform user (optionally scoped by campus) with simple in-memory search; tap →
///     push the admin user-detail screen (consumer bookings).
struct ProviderAdminDashboardView: View {
    @Environment(ProviderShellNavigator.self) private var shellNavigator

    enum Tab: String, CaseIterable, Identifiable {
        case performance = "Performance"
        case barbers = "Barbers"
        case users = "Users"
        case safety = "Safety"
        var id: String { rawValue }
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
    @State private var campusSearchText = ""

    @FocusState private var isCampusSearchFieldFocused: Bool

    @State private var isLoading = true
    @State private var errorText: String?

    @State private var metricsSnapshot: AdminMetricsSnapshotDTO?
    @State private var metricsTimeline: MetricsTimeline = .daily
    @State private var metricsChartSeries: MetricsChartSeries = .revenue
    @State private var isLoadingMetrics = false

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
        .providerLavaScreenChrome()
        .onChange(of: metricsTimeline) { _, _ in
            Task { await reloadMetricsTimeline() }
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

    // MARK: - Metrics timeline (chart)

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
            case .daily: return "Paid bookings in the last 30 days, grouped by day (Pacific)."
            case .weekly: return "Last 12 weeks, grouped by week."
            case .monthly: return "Last 12 months, grouped by month."
            case .yearly: return "Last 10 years, grouped by calendar year."
            }
        }
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

    // MARK: - Header chrome

    private var campusPickerCard: some View {
        sectionCard(title: "Scope", subtitle: "Search by name, slug, or city. Leave scope cleared for all campuses.") {
            VStack(alignment: .leading, spacing: 10) {
                if selectedCampusId != nil {
                    HStack(spacing: 10) {
                        Text(selectedCampusName)
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            selectedCampusId = nil
                            campusSearchText = ""
                            isCampusSearchFieldFocused = false
                            Task { await loadScopedData() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.provider(.title3))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear campus and show all campuses")
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                    TextField("Search campuses…", text: $campusSearchText)
                        .textFieldStyle(.plain)
                        .focused($isCampusSearchFieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !campusSearchText.isEmpty {
                        Button {
                            campusSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

                if isCampusSearchFieldFocused {
                    campusSuggestionsPanel
                }
            }
        }
    }

    private var campusSuggestionsPanel: some View {
        let rows = campusAutocompleteRows
        let qTrim = campusSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return Group {
            if campuses.isEmpty {
                Text(isLoading ? "Loading campuses…" : "No campuses available.")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        selectedCampusId = nil
                        campusSearchText = ""
                        isCampusSearchFieldFocused = false
                        Task { await loadScopedData() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "globe")
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                            Text("All campuses")
                                .font(.provider(.subheadline, weight: .semibold))
                            Spacer(minLength: 8)
                            if selectedCampusId == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.providerOlive)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().opacity(0.25)

                    if rows.isEmpty, !qTrim.isEmpty {
                        Text("No campuses match “\(qTrim)”.")
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(rows) { campus in
                                    Button {
                                        selectedCampusId = campus.id
                                        campusSearchText = ""
                                        isCampusSearchFieldFocused = false
                                        Task { await loadScopedData() }
                                    } label: {
                                        campusSuggestionRow(campus)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 240)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    private var campusAutocompleteRows: [AdminCampusDTO] {
        let q = campusSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = campuses.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        if q.isEmpty {
            return Array(sorted.prefix(30))
        }
        return Array(sorted.filter { campusMatchesSearchQuery($0, query: q) }.prefix(40))
    }

    private func campusMatchesSearchQuery(_ c: AdminCampusDTO, query: String) -> Bool {
        if c.displayName.lowercased().contains(query) { return true }
        if let slug = c.slug, !slug.isEmpty, slug.lowercased().contains(query) { return true }
        if let city = c.city, !city.isEmpty, city.lowercased().contains(query) { return true }
        if let state = c.state, !state.isEmpty, state.lowercased().contains(query) { return true }
        if c.id.lowercased().contains(query) { return true }
        if let mgr = c.managerName, !mgr.isEmpty, mgr.lowercased().contains(query) { return true }
        return false
    }

    @ViewBuilder
    private func campusSuggestionRow(_ c: AdminCampusDTO) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.displayName)
                    .font(.provider(.subheadline, weight: .medium))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.leading)
                if let line = c.locationLine, !line.isEmpty {
                    Text(line)
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
            }
            Spacer(minLength: 8)
            if selectedCampusId == c.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.providerOlive)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selectedCampusId == c.id ? Color.white.opacity(0.06) : Color.clear)
        )
    }

    private var selectedCampusName: String {
        guard let id = selectedCampusId,
              let c = campuses.first(where: { $0.id == id }) else { return "All campuses" }
        return c.displayName
    }

    private var tabPicker: some View {
        Picker("Tab", selection: $tab) {
            ForEach(Tab.allCases) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
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
            subtitle: metricsTimeline.helperSubtitle
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
                    } else {
                        metricsTimelineChartView(points: parsedMetricPoints(from: metricsSnapshot))
                    }
                    if isLoadingMetrics {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                        ProgressView()
                            .controlSize(.regular)
                    }
                }
            }
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
                    ForEach(points) { pt in
                        AreaMark(
                            x: .value("Period", pt.date),
                            y: .value("Revenue", pt.revenueDollars)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.providerOlive.opacity(0.55), Color.providerOlive.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Period", pt.date),
                            y: .value("Revenue", pt.revenueDollars)
                        )
                        .foregroundStyle(Color.providerOlive)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                case .bookings:
                    ForEach(points) { pt in
                        BarMark(
                            x: .value("Period", pt.date),
                            y: .value("Bookings", pt.bookings)
                        )
                        .foregroundStyle(Color.providerOlive.opacity(0.75))
                    }
                case .signups:
                    ForEach(points) { pt in
                        BarMark(
                            x: .value("Period", pt.date),
                            y: .value("Sign-ups", pt.signups)
                        )
                        .foregroundStyle(Color.providerOlive.opacity(0.75))
                    }
                }
            }
            .frame(height: 220)
            .chartXAxis {
                AxisMarks(preset: .automatic, position: .bottom)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
    }

    private var platformStatsCard: some View {
        sectionCard(title: "Platform totals", subtitle: nil) {
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

    private var barbersTab: some View {
        sectionCard(title: "Barbers", subtitle: "\(barbers.count) loaded.") {
            VStack(spacing: 10) {
                if barbers.isEmpty {
                    Text(isLoading ? "Loading barbers…" : "No barbers found for this scope.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                } else {
                    ForEach(barbers) { barber in
                        barberRow(barber)
                    }
                }
            }
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
                        if barber.isCampusManager == true { tag(text: "CM", tint: Color.providerOlive) }
                        if barber.isActive == false { tag(text: "Hidden", tint: Color.red.opacity(0.7)) }
                    }
                    Text(barber.email ?? "—")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    HStack(spacing: 8) {
                        if let cn = barber.campusName { Text(cn); Text("·") }
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

    private var usersTab: some View {
        sectionCard(title: "Users", subtitle: "\(filteredUsers.count) of \(users.count) shown.") {
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
                    ForEach(filteredUsers.prefix(100)) { user in
                        userRow(user)
                    }
                    if filteredUsers.count > 100 {
                        Text("Showing first 100. Refine your search to narrow results.")
                            .font(.provider(.caption2))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                }
            }
        }
    }

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

    private func userRow(_ user: AdminPlatformUserDTO) -> some View {
        Button {
            let route = ProviderShellRoute.adminUserDetail(user)
            shellNavigator.pushRoute(route)
        } label: {
            HStack(spacing: 12) {
                AvatarView(url: user.avatarURL, fallbackName: user.displayName)
                    .frame(width: 36, height: 36)
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
                filterChipsRow(
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
                filterChipsRow(
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

    /// Generic horizontally scrolling chip row used for both filter strips on the Safety tab.
    /// Stays inside the parent sectionCard's padding while still allowing overflow when there
    /// are more chips than will fit on small screens.
    @ViewBuilder
    private func filterChipsRow<Option: Hashable & Identifiable>(
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    let isSelected = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(label(option))
                            .font(.provider(.caption, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(isSelected ? Color.providerOlive.opacity(0.85) : Color.white.opacity(0.10))
                            )
                            .foregroundStyle(Color.lavaShellCream)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

    private func parsedMetricPoints(from snapshot: AdminMetricsSnapshotDTO?) -> [MetricPlotPoint] {
        guard let rows = snapshot?.data else { return [] }
        let mapped: [MetricPlotPoint] = rows.compactMap { row in
            guard let d = MetricsDateParsing.parse(row.date) else { return nil }
            let cents = row.revenue ?? 0
            return MetricPlotPoint(
                id: row.date,
                date: d,
                revenueDollars: Double(cents) / 100.0,
                bookings: row.bookings ?? 0,
                signups: row.users ?? 0
            )
        }
        return mapped.sorted { $0.date < $1.date }
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
