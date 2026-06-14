import SwiftUI

/// In-app management for the things the web `BarberPage` exposes outside of bookings:
///   1. ~~Google Calendar busy-time integration~~ — parked behind `#if false` blocks in this
///      file until the integration is built out end-to-end. The state vars, section view,
///      OAuth sheet, and network helpers are still present so re-enabling is a single flag
///      flip; flip every `#if false` in this file to `#if true` (or delete the gates) to
///      restore the section. The backend service / DTO / route remain wired and untouched.
///   2. Weekly availability schedule (per-day enable + multiple intervals)
///   3. One-off `barber_time_blocks` for date-specific holds
///
/// Replaces the previous "managed on the web dashboard" caption on the schedule home.
struct ProviderAvailabilityEditorView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    // Weekly schedule
    @State private var weekly = WeeklyScheduleDTO()
    @State private var originalWeekly = WeeklyScheduleDTO()
    @State private var savingWeekly = false
    @State private var weeklyError: String?
    @State private var weeklyValidationError: String?
    @State private var weeklyEditorReady = false

    // Time blocks
    @State private var timeBlocks: [BarberTimeBlockDTO] = []
    @State private var blocksError: String?
    @State private var showingAddBlock = false
    @State private var deletingBlockIds: Set<String> = []

    // MARK: Google Calendar — TEMPORARILY DISABLED (see file header).
    #if false
    @State private var calendarStatus: GoogleCalendarStatusDTO?
    @State private var calendarBusy = false
    @State private var calendarError: String?
    @State private var pendingAuthURL: URL?
    @State private var showingSafari = false
    #endif

    // Page load — one gate so sections appear together, not as each API returns.
    @State private var isLoadingContent = true

    // Generic toast / save feedback
    @State private var savedToast: String?

    private var weeklyDirty: Bool { weekly != originalWeekly }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                if let savedToast {
                    inlineBanner(text: savedToast, tint: .green)
                }
                // googleCalendarSection — disabled until the integration is fully built out
                // (see `#if false` blocks throughout this file).
                weeklyScheduleSection
                timeBlocksSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .providerNavigationStackDestinationBackdrop()
        .navigationTitle("Manage availability")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task { await saveWeeklySchedule() }
                }
                .disabled(!weeklyDirty || savingWeekly || weeklyValidationError != nil)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .task {
            await loadAll()
        }
        .refreshable {
            await loadAll(forceRefresh: true)
        }
        .sheet(isPresented: $showingAddBlock, onDismiss: { /* nothing — list reloads on save */ }) {
            ProviderTimeBlockEditorSheet(
                barberId: session.barberProfile?.id,
                onSaved: { newBlock in
                    if let newBlock {
                        // Optimistic insert in sorted order.
                        var next = timeBlocks
                        next.append(newBlock)
                        next.sort(by: Self.blockSortOrder)
                        timeBlocks = next
                    } else {
                        Task { await loadTimeBlocks() }
                    }
                    NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
                    showSavedToast("Time block added.")
                }
            )
        }
        // Google Calendar OAuth sheet — parked alongside the rest of the integration.
        #if false
        .sheet(isPresented: $showingSafari, onDismiss: {
            Task { await loadCalendarStatus() }
        }) {
            if let url = pendingAuthURL {
                ProviderSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        #endif
    }

    // MARK: - Banner

    private func inlineBanner(text: String, tint: Color) -> some View {
        Text(text)
            .font(.provider(.footnote, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.6), lineWidth: 0.6)
            )
    }

    // MARK: - Sections

    // MARK: Google Calendar section — TEMPORARILY DISABLED (see file header).
    #if false
    private var googleCalendarSection: some View {
        sectionCard(title: "Google Calendar", subtitle: "Block bookable times with events from your Google Calendar.") {
            if isLoadingContent {
                sectionLoadingIndicator
            } else if let s = calendarStatus {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(s.connected ? Color.green : Color.lavaShellCream.opacity(0.35))
                            .frame(width: 9, height: 9)
                        Text(s.connected ? "Connected" : "Not connected")
                            .font(.provider(.subheadline, weight: .semibold))
                        Spacer()
                        if let at = s.connectedAt, s.connected {
                            Text(at.formatted(date: .abbreviated, time: .omitted))
                                .font(.provider(.caption))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                        }
                    }
                    if s.connected {
                        Toggle(isOn: Binding(
                            get: { s.syncEnabled ?? true },
                            set: { newValue in
                                calendarStatus = GoogleCalendarStatusDTO(
                                    connected: s.connected,
                                    connectedAt: s.connectedAt,
                                    syncEnabled: newValue
                                )
                                Task { await updateCalendarSync(newValue) }
                            }
                        )) {
                            Text("Sync busy events as blocks")
                                .font(.provider(.subheadline))
                        }
                        .tint(.providerOlive)
                    }
                    HStack(spacing: 10) {
                        if s.connected {
                            secondaryActionButton(
                                title: calendarBusy ? "Working…" : "Disconnect",
                                systemImage: "link.badge.plus",
                                disabled: calendarBusy,
                                role: .destructive
                            ) {
                                Task { await disconnectCalendar() }
                            }
                        } else {
                            primaryActionButton(
                                title: calendarBusy ? "Opening…" : "Connect Google Calendar",
                                systemImage: "link",
                                disabled: calendarBusy
                            ) {
                                Task { await connectCalendar() }
                            }
                        }
                    }
                }
            }
            if let calendarError {
                Text(calendarError)
                    .font(.provider(.caption))
                    .foregroundStyle(.red)
            }
        }
    }
    #endif // Google Calendar section

    private var weeklyScheduleSection: some View {
        sectionCard(title: "Weekly schedule", subtitle: "Set the hours you're available each weekday.") {
            if isLoadingContent {
                sectionLoadingIndicator
            } else if weeklyEditorReady {
                VStack(spacing: 12) {
                    ForEach(WeeklyScheduleDayKey.allCases) { day in
                        weeklyDayRow(day: day)
                    }
                }
            } else {
                weeklyScheduleSummary
            }
            if let weeklyValidationError {
                Text(weeklyValidationError)
                    .font(.provider(.caption))
                    .foregroundStyle(.red)
            }
            if let weeklyError {
                Text(weeklyError)
                    .font(.provider(.caption))
                    .foregroundStyle(.red)
            }
            if weeklyDirty, weeklyValidationError == nil {
                HStack(spacing: 10) {
                    Spacer()
                    Button("Discard") {
                        weekly = originalWeekly
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    primaryActionButton(
                        title: savingWeekly ? "Saving…" : "Save schedule",
                        systemImage: "checkmark.circle.fill",
                        disabled: savingWeekly
                    ) {
                        Task { await saveWeeklySchedule() }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var weeklyScheduleSummary: some View {
        VStack(spacing: 12) {
            ForEach(WeeklyScheduleDayKey.allCases) { day in
                let entry = weekly[day]
                HStack {
                    Text(day.displayName)
                        .font(.provider(.headline))
                    Spacer()
                    Text(entry.enabled ? weeklyIntervalSummary(entry) : "Not available")
                        .font(.provider(.caption))
                        .foregroundStyle(
                            entry.enabled ? Color.lavaShellCreamSecondary : Color.lavaShellCreamTertiary
                        )
                        .multilineTextAlignment(.trailing)
                }
                .padding(12)
                .background(weeklyDayRowBackground)
            }
        }
    }

    private func weeklyIntervalSummary(_ entry: DayScheduleDTO) -> String {
        entry.intervals
            .map { "\(Self.pretty12h($0.start)) – \(Self.pretty12h($0.end))" }
            .joined(separator: ", ")
    }

    private var weeklyDayRowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }

    private var sectionLoadingIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private func weeklyDayRow(day: WeeklyScheduleDayKey) -> some View {
        let dayBinding = Binding<DayScheduleDTO>(
            get: { weekly[day] },
            set: { weekly[day] = $0 }
        )
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.displayName)
                    .font(.provider(.headline))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { dayBinding.wrappedValue.enabled },
                    set: { newValue in
                        var current = dayBinding.wrappedValue
                        current.enabled = newValue
                        if newValue, current.intervals.isEmpty {
                            current.intervals = [ScheduleIntervalDTO(start: "09:00", end: "17:00")]
                        }
                        dayBinding.wrappedValue = current
                        recomputeValidation()
                    }
                ))
                .labelsHidden()
                .tint(.providerOlive)
            }
            if dayBinding.wrappedValue.enabled {
                ForEach(dayBinding.wrappedValue.intervals) { interval in
                    intervalRow(day: day, interval: interval)
                }
                Button {
                    addInterval(day: day)
                } label: {
                    Label("Add time slot", systemImage: "plus.circle")
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(Color.providerOlive)
                }
                .buttonStyle(.plain)
            } else {
                Text("Not available")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
        }
        .padding(12)
        .background(weeklyDayRowBackground)
    }

    @ViewBuilder
    private func intervalRow(day: WeeklyScheduleDayKey, interval: ScheduleIntervalDTO) -> some View {
        HStack(spacing: 10) {
            timePicker(
                value: Binding(
                    get: { Self.dateFromHHMM(interval.start) },
                    set: { newDate in updateInterval(day: day, intervalId: interval.id, start: Self.hhmmFromDate(newDate)) }
                ),
                label: "Start"
            )
            Text("–")
                .foregroundStyle(Color.lavaShellCreamSecondary)
            timePicker(
                value: Binding(
                    get: { Self.dateFromHHMM(interval.end) },
                    set: { newDate in updateInterval(day: day, intervalId: interval.id, end: Self.hhmmFromDate(newDate)) }
                ),
                label: "End"
            )
            Spacer()
            Button {
                removeInterval(day: day, intervalId: interval.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove time slot")
        }
    }

    private func timePicker(value: Binding<Date>, label: String) -> some View {
        DatePicker(label, selection: value, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
            .accessibilityLabel(label)
    }

    private var timeBlocksSection: some View {
        sectionCard(title: "Time blocks", subtitle: "Block one-off windows (vacation, off-day, lunch break, etc.).") {
            if isLoadingContent {
                sectionLoadingIndicator
            } else if let blocksError {
                Text(blocksError)
                    .font(.provider(.caption))
                    .foregroundStyle(.red)
            } else if timeBlocks.isEmpty {
                Text("No upcoming blocks.")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(timeBlocks) { block in
                        timeBlockRow(block)
                    }
                }
            }
            primaryActionButton(
                title: "Add time block",
                systemImage: "plus",
                disabled: !session.hasProviderProfile || isLoadingContent
            ) {
                showingAddBlock = true
            }
        }
    }

    private func timeBlockRow(_ block: BarberTimeBlockDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.prettyDate(block.blockDate))
                    .font(.provider(.subheadline, weight: .semibold))
                Text("\(Self.pretty12h(block.startTime)) – \(Self.pretty12h(block.endTime))")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                if let reason = block.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
            }
            Spacer()
            Button {
                Task { await deleteBlock(block) }
            } label: {
                if deletingBlockIds.contains(block.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(deletingBlockIds.contains(block.id))
            .accessibilityLabel("Delete time block")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Reusable section + buttons

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
                if let subtitle {
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

    private func primaryActionButton(
        title: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.providerOlive.opacity(disabled ? 0.18 : 0.45))
            )
            .foregroundStyle(Color.lavaShellCream)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private func secondaryActionButton(
        title: String,
        systemImage: String,
        disabled: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.lavaShellCream.opacity(disabled ? 0.18 : 0.45), lineWidth: 0.8)
            )
            .foregroundStyle(role == .destructive ? Color.red.opacity(0.92) : Color.lavaShellCream)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Mutations: weekly

    private func addInterval(day: WeeklyScheduleDayKey) {
        var current = weekly[day]
        let last = current.intervals.last
        var newStart = "09:00"
        if let last, let h = Int(last.end.split(separator: ":").first ?? "") {
            newStart = String(format: "%02d:00", min(h + 1, 23))
        }
        let startHour = Int(newStart.split(separator: ":").first ?? "9") ?? 9
        let newEnd = String(format: "%02d:00", min(startHour + 2, 23))
        current.intervals.append(ScheduleIntervalDTO(start: newStart, end: newEnd))
        current.enabled = true
        weekly[day] = current
        recomputeValidation()
    }

    private func removeInterval(day: WeeklyScheduleDayKey, intervalId: String) {
        var current = weekly[day]
        current.intervals.removeAll { $0.id == intervalId }
        if current.intervals.isEmpty { current.enabled = false }
        weekly[day] = current
        recomputeValidation()
    }

    private func updateInterval(
        day: WeeklyScheduleDayKey,
        intervalId: String,
        start: String? = nil,
        end: String? = nil
    ) {
        var current = weekly[day]
        guard let idx = current.intervals.firstIndex(where: { $0.id == intervalId }) else { return }
        if let start { current.intervals[idx].start = start }
        if let end { current.intervals[idx].end = end }
        weekly[day] = current
        recomputeValidation()
    }

    /// Mirrors the web `validateAvailability` rules: end > start, no intra-day overlaps.
    private func recomputeValidation() {
        for day in WeeklyScheduleDayKey.allCases {
            let entry = weekly[day]
            guard entry.enabled else { continue }
            let intervals = entry.intervals
            for (i, current) in intervals.enumerated() {
                let s = Self.minutesFromHHMM(current.start)
                let e = Self.minutesFromHHMM(current.end)
                if s >= e {
                    weeklyValidationError = "\(day.displayName): end time must be after start time."
                    return
                }
                for j in (i + 1) ..< intervals.count {
                    let other = intervals[j]
                    let os = Self.minutesFromHHMM(other.start)
                    let oe = Self.minutesFromHHMM(other.end)
                    if s < oe, e > os {
                        weeklyValidationError = "\(day.displayName): time slots cannot overlap."
                        return
                    }
                }
            }
        }
        weeklyValidationError = nil
    }

    // MARK: - Network

    private func loadAll(forceRefresh: Bool = false) async {
        weeklyEditorReady = false

        guard let barberId = session.barberProfile?.id else {
            isLoadingContent = false
            return
        }

        if !forceRefresh,
           let snapshot = await ProviderAvailabilityEditorPrefetch.takeSnapshot(for: barberId) {
            // `snapshot.calendarStatus` / `calendarError` are ignored while the Google Calendar
            // integration is parked. Restore the `calendar:` argument when re-enabling.
            applyLoadedContent(
                weekly: (snapshot.weekly, snapshot.weeklyError),
                blocks: (snapshot.timeBlocks, snapshot.blocksError)
            )
            await prepareWeeklyEditor()
            return
        }

        isLoadingContent = true

        // Google Calendar fetch is parked along with the rest of the integration; bringing it back
        // is a matter of restoring the `async let calendar = fetchCalendarStatus()` and threading
        // its result into `applyLoadedContent` (signature also restored under the `#if false`).
        async let weekly = fetchWeeklySchedule(barberId: barberId)
        async let blocks = fetchTimeBlocks(barberId: barberId)
        let results = await (weekly, blocks)

        applyLoadedContent(
            weekly: results.0,
            blocks: results.1
        )
        await prepareWeeklyEditor()
    }

    private func applyLoadedContent(
        weekly: (WeeklyScheduleDTO?, String?),
        blocks: ([BarberTimeBlockDTO]?, String?)
    ) {
        // calendarStatus / calendarError assignments removed while the Google Calendar
        // integration is parked. Restore alongside the `calendar:` parameter when re-enabling.

        if let schedule = weekly.0 {
            self.weekly = schedule
            originalWeekly = schedule
            weeklyError = nil
            recomputeValidation()
        } else {
            weeklyError = weekly.1
        }

        if let list = blocks.0 {
            timeBlocks = list.sorted(by: Self.blockSortOrder)
            blocksError = nil
        } else {
            timeBlocks = []
            blocksError = blocks.1
        }

        isLoadingContent = false
    }

    private func prepareWeeklyEditor() async {
        await Task.yield()
        weeklyEditorReady = true
    }

    // MARK: Google Calendar fetch helper — TEMPORARILY DISABLED.
    #if false
    private func fetchCalendarStatus() async -> (GoogleCalendarStatusDTO?, String?) {
        do {
            return (try await ProviderAvailabilityManagementService.googleCalendarStatus(), nil)
        } catch {
            return (nil, (error as? LocalizedError)?.errorDescription ?? "Could not load Google Calendar status.")
        }
    }
    #endif

    private func fetchWeeklySchedule(barberId: String) async -> (WeeklyScheduleDTO?, String?) {
        do {
            return (try await ProviderAvailabilityManagementService.fetchWeeklySchedule(barberId: barberId), nil)
        } catch {
            return (nil, (error as? LocalizedError)?.errorDescription ?? "Could not load schedule.")
        }
    }

    private func fetchTimeBlocks(barberId: String) async -> ([BarberTimeBlockDTO]?, String?) {
        do {
            let list = try await ProviderAvailabilityManagementService.listTimeBlocks(barberId: barberId)
            return (list, nil)
        } catch {
            return (nil, (error as? LocalizedError)?.errorDescription ?? "Could not load time blocks.")
        }
    }

    private func loadWeeklySchedule() async {
        guard let barberId = session.barberProfile?.id else { return }
        let result = await fetchWeeklySchedule(barberId: barberId)
        if let schedule = result.0 {
            weekly = schedule
            originalWeekly = schedule
            weeklyError = nil
            recomputeValidation()
        } else {
            weeklyError = result.1
        }
    }

    private func saveWeeklySchedule() async {
        guard let barberId = session.barberProfile?.id else { return }
        recomputeValidation()
        guard weeklyValidationError == nil else { return }
        savingWeekly = true
        weeklyError = nil
        defer { savingWeekly = false }
        do {
            try await ProviderAvailabilityManagementService.updateWeeklySchedule(barberId: barberId, schedule: weekly)
            originalWeekly = weekly
            NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
            showSavedToast("Weekly schedule saved.")
        } catch {
            weeklyError = (error as? LocalizedError)?.errorDescription ?? "Could not save schedule."
        }
    }

    // MARK: - Network: time blocks

    private func loadTimeBlocks() async {
        guard let barberId = session.barberProfile?.id else { return }
        let result = await fetchTimeBlocks(barberId: barberId)
        if let list = result.0 {
            timeBlocks = list.sorted(by: Self.blockSortOrder)
            blocksError = nil
        } else {
            timeBlocks = []
            blocksError = result.1
        }
    }

    private func deleteBlock(_ block: BarberTimeBlockDTO) async {
        guard let barberId = session.barberProfile?.id else { return }
        deletingBlockIds.insert(block.id)
        defer { deletingBlockIds.remove(block.id) }
        do {
            try await ProviderAvailabilityManagementService.deleteTimeBlock(barberId: barberId, blockId: block.id)
            timeBlocks.removeAll { $0.id == block.id }
            NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
            showSavedToast("Time block removed.")
        } catch {
            blocksError = (error as? LocalizedError)?.errorDescription ?? "Could not delete time block."
        }
    }

    // MARK: - Network: Google Calendar — TEMPORARILY DISABLED.
    //
    // The four helpers below (`loadCalendarStatus`, `connectCalendar`, `disconnectCalendar`,
    // `updateCalendarSync`) stay verbatim under the `#if false` gate so the eventual re-enable
    // is just deleting the gate. `ProviderAvailabilityManagementService.googleCalendar*` and
    // `ProviderSafariView` are still present and untouched.
    #if false
    private func loadCalendarStatus() async {
        let result = await fetchCalendarStatus()
        calendarStatus = result.0
        calendarError = result.1
    }

    private func connectCalendar() async {
        calendarBusy = true
        calendarError = nil
        defer { calendarBusy = false }
        do {
            pendingAuthURL = try await ProviderAvailabilityManagementService.googleCalendarConnectURL()
            showingSafari = true
        } catch {
            calendarError = (error as? LocalizedError)?.errorDescription ?? "Could not start Google Calendar connection."
        }
    }

    private func disconnectCalendar() async {
        calendarBusy = true
        calendarError = nil
        defer { calendarBusy = false }
        do {
            try await ProviderAvailabilityManagementService.googleCalendarDisconnect()
            await loadCalendarStatus()
            NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
            showSavedToast("Google Calendar disconnected.")
        } catch {
            calendarError = (error as? LocalizedError)?.errorDescription ?? "Could not disconnect Google Calendar."
        }
    }

    private func updateCalendarSync(_ enabled: Bool) async {
        do {
            try await ProviderAvailabilityManagementService.googleCalendarUpdateSyncEnabled(enabled)
            NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
        } catch {
            calendarError = (error as? LocalizedError)?.errorDescription ?? "Could not update sync setting."
            await loadCalendarStatus()
        }
    }
    #endif // Network: Google Calendar

    // MARK: - Toast helpers

    private func showSavedToast(_ text: String) {
        savedToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if savedToast == text { savedToast = nil }
        }
    }

    // MARK: - Formatting / sorting helpers

    static func dateFromHHMM(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 9
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        var c = DateComponents()
        c.hour = h
        c.minute = m
        return Calendar(identifier: .gregorian).date(from: c) ?? .now
    }

    static func hhmmFromDate(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }

    static func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }

    static func prettyDate(_ yyyyMMdd: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: yyyyMMdd) {
            return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        }
        return yyyyMMdd
    }

    static func pretty12h(_ hhmm: String) -> String {
        let d = dateFromHHMM(hhmm)
        return d.formatted(date: .omitted, time: .shortened)
    }

    static func blockSortOrder(_ lhs: BarberTimeBlockDTO, _ rhs: BarberTimeBlockDTO) -> Bool {
        if lhs.blockDate != rhs.blockDate { return lhs.blockDate < rhs.blockDate }
        return lhs.startTime < rhs.startTime
    }
}
