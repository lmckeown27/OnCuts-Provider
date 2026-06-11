import SwiftUI

// MARK: - Request cancellation (SwiftUI `.task` / `refreshable` overlap)

/// `NSURLErrorCancelled` (-999) when a prior `URLSession` task is cancelled—**not** a user-visible failure.
private func providerIsBenignRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
}

// MARK: - Schedule zoom (pinch-to-zoom timeline)

/// Replaces the legacy Daily / Weekly / Monthly mode picker with a continuous zoom scale.
/// Main **dashboard** after sign-in: pinch-to-zoom schedule (minute → month).
struct ProviderScheduleDashboardView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(ProviderShellNavigator.self) private var shellNavigator

    /// Direct reference to the shared `@Observable` tracker. Accessing
    /// `awaitingPaymentTracker.requestedIds` from `body` *should* register an observation
    /// dependency, but `@Observable` tracking through a stored `let` reference to a
    /// singleton can miss updates when the mutation happens while this view is off-screen
    /// behind a pushed UIKit VC (the exact path the booking-detail screen takes). The
    /// `.onReceive(ProviderAwaitingPaymentTracker.didChangeNotification)` handler below
    /// bumps `awaitingPaymentRefreshTick` as a backstop so the banner re-renders
    /// regardless of which path delivers the change.
    private let awaitingPaymentTracker = ProviderAwaitingPaymentTracker.shared

    /// Bumped from `.onReceive(ProviderAwaitingPaymentTracker.didChangeNotification)` to
    /// force a body re-evaluation when the tracker mutates. Read once inside
    /// `awaitingPaymentBookings` so the dependency is part of the body's tracked set,
    /// but the actual integer value is otherwise unused.
    @State private var awaitingPaymentRefreshTick: Int = 0

    @State private var zoomScale: CGFloat = ProviderScheduleZoom.defaultScale
    @State private var dayOffset = 0
    @State private var weekOffset = 0
    @State private var monthOffset = 0
    @State private var bookings: [SimpleBookingDTO] = []
    @State private var isLoading = false
    @State private var errorText: String?
    /// Cached by `yyyy-MM-dd` so **adjacent days** can be pre-fetched; the visible day reads from here first.
    @State private var availabilityByDay: [String: BarberAvailabilityDayData] = [:]
    @State private var isLoadingAvailability = false
    @State private var availabilityErrorText: String?
    @State private var timeBlocksByDay: [String: [BarberTimeBlockDTO]] = [:]
    @State private var showingBlockTimeSheet = false
    @State private var blockSheetDayStart: Date = .now
    @State private var blockSheetStart: Date = .now
    @State private var blockSheetEnd: Date = .now
    @State private var deletingBlockIds: Set<String> = []

    /// When set, the user is editing **this weekday’s** weekly intervals inline (Daily mode only).
    @State private var isEditingAvailability = false
    @State private var inlineWeeklySchedule: WeeklyScheduleDTO?
    @State private var originalInlineWeeklySchedule: WeeklyScheduleDTO?
    @State private var inlineWeeklyLoading = false
    @State private var inlineWeeklyLoadError: String?
    @State private var inlineValidationError: String?
    @State private var savingInlineWeekly = false
    @State private var inlineSaveError: String?

    @State private var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    @State private var isApplyingTimeChange = false
    @State private var timeChangeErrorText: String?
    @State private var movePromptBooking: SimpleBookingDTO?
    @State private var editingMoveBookingID: String?

    private var mondayCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    private var effectiveZoomTier: ProviderScheduleZoomTier {
        ProviderScheduleZoomTier(effectiveScale: zoomScale)
    }

    private var isDayZoomTier: Bool {
        effectiveZoomTier == .day || effectiveZoomTier == .minute
    }

    /// Shared track behind the zoom preset rail and date navigation row.
    private var scheduleChromeTrackBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.providerScheduleTrackFill)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.providerScheduleTrackStroke, lineWidth: 0.6)
            )
    }

    private var scheduleControlCircleBackground: some View {
        Circle()
            .fill(Color.providerScheduleControlFill)
            .overlay(
                Circle()
                    .strokeBorder(Color.providerScheduleControlStroke, lineWidth: 0.5)
            )
    }

    private enum ScheduleCardChrome {
        case neutral
        case today
        case booked
        case completed
    }

    private func scheduleCardChrome(for booking: SimpleBookingDTO) -> ScheduleCardChrome {
        if ProviderBookingStatusDisplay.isScheduleCompleted(status: booking.status) {
            return .completed
        }
        if ProviderBookingStatusDisplay.isScheduleBooked(status: booking.status) {
            return .booked
        }
        return .neutral
    }

    @ViewBuilder
    private func scheduleCardBackground(cornerRadius: CGFloat, chrome: ScheduleCardChrome) -> some View {
        switch chrome {
        case .neutral:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.providerScheduleCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.providerScheduleCardStroke, lineWidth: 0.6)
                )
        case .today:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.providerOlive.opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.providerOlive.opacity(0.75), lineWidth: 0.6)
                )
        case .booked:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.providerOlive.opacity(0.44))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.providerOlive.opacity(0.68), lineWidth: 0.6)
                )
        case .completed:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.green.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.55), lineWidth: 0.6)
                )
        }
    }

    var body: some View {
        GeometryReader { screenProxy in
            let canvasViewerHeight = ProviderScheduleZoom.canvasViewerHeight(
                availableHeight: screenProxy.size.height
            )
            ScrollView {
                scheduleContent(canvasViewerHeight: canvasViewerHeight)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            /// Default `ScrollView` content background is an opaque system fill — hide it so the root shell background shows through.
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .refreshable {
                await loadBookings()
                await refreshDayScheduleFromNetwork()
            }
        }
        /// Stable `id` avoids cancelling in-flight `bookings-simple` on every unrelated `body` refresh (which surfaces as **-999 cancelled** and cleared the list).
        .task(id: session.barberProfile?.id) {
            availabilityByDay = [:]
            timeBlocksByDay = [:]
            await loadBookings()
        }
        /// Refetch the day's availability window any time the daily mode anchor or barber identity changes.
        .task(id: dailyAvailabilityKey) {
            await refreshDayScheduleFromNetwork()
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerBookingsChanged)) { _ in
            Task {
                await loadBookings()
                await refreshDayScheduleFromNetwork()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerAvailabilityChanged)) { _ in
            Task { await refreshDayScheduleFromNetwork() }
        }
        // Backstop for `@Observable` tracking through `awaitingPaymentTracker`. The detail
        // VC posts this notification on every `requestedIds` mutation, so when the user
        // taps Request Payment inside the pushed UIKit detail and then pops back, the
        // dashboard reliably re-evaluates `awaitingPaymentBookings` here even if SwiftUI
        // didn't pick up the change through the singleton's stored-`let` reference.
        .onReceive(NotificationCenter.default.publisher(for: ProviderAwaitingPaymentTracker.didChangeNotification)) { _ in
            awaitingPaymentRefreshTick &+= 1
        }
        .onChange(of: dayOffset) { _, _ in
            editingMoveBookingID = nil
            movePromptBooking = nil
            timeChangeProposal = nil
        }
        .onChange(of: effectiveZoomTier) { _, tier in
            if tier != .day && tier != .minute {
                editingMoveBookingID = nil
                movePromptBooking = nil
                timeChangeProposal = nil
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        /// With `providerLavaScreenChrome()` on the shell, a **material** nav bar background can still
        /// influence layout after popping UIKit chat destinations — hide the bar chrome entirely on root.
        .toolbarBackground(.hidden, for: .navigationBar)
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .sheet(isPresented: $showingBlockTimeSheet) {
            if let barberId = session.barberProfile?.id {
                ProviderTimeBlockEditorSheet(
                    barberId: barberId,
                    navigationTitle: "Block time",
                    confirmButtonTitle: "Block",
                    initialDate: blockSheetDayStart,
                    initialStart: blockSheetStart,
                    initialEnd: blockSheetEnd,
                    onSaved: { _ in
                        Task { await refreshDayScheduleFromNetwork() }
                        NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
                    }
                )
            }
        }
        .alert(
            "Couldn’t update appointment",
            isPresented: Binding(
                get: { timeChangeErrorText != nil },
                set: { if !$0 { timeChangeErrorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                timeChangeErrorText = nil
            }
        } message: {
            if let timeChangeErrorText {
                Text(timeChangeErrorText)
            }
        }
    }

    // MARK: - Schedule content (full-page, no card chrome)

    /// Full-bleed schedule under the dashboard header. Replaces the prior "card" look so the
    /// Daily / Weekly / Monthly view fills the entire page below `dashboardHeaderBar`.
    private func scheduleContent(canvasViewerHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Sits between the shell's header bar (Chats / role chip / Requests tray /
            // profile menu) and the "[x] appointments" summary line. Renders one row
            // per booking the user has locally flipped to "Awaiting Payment" via the
            // detail screen. Hidden when the tracker has nothing to surface.
            awaitingPaymentBanner
            jumpChip
            summaryLine
            zoomPresetBar
            dateNavigationRow
            if session.hasProviderProfile, isDayZoomTier {
                manageAvailabilityOrEditControls
            }
            VStack(alignment: .leading, spacing: 12) {
                zoomScheduleCanvas(canvasViewerHeight: canvasViewerHeight)
                if isDayZoomTier {
                    dayScheduleSupplement
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inlineWeeklyDirty: Bool {
        inlineWeeklySchedule != nil && inlineWeeklySchedule != originalInlineWeeklySchedule
    }

    @ViewBuilder
    private var manageAvailabilityOrEditControls: some View {
        if isEditingAvailability {
            HStack(spacing: 10) {
                Button {
                    cancelInlineAvailabilityEditing()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.providerScheduleControlFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.providerScheduleControlStroke, lineWidth: 0.65)
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Color.lavaShellCream)
                }
                .buttonStyle(.plain)
                .disabled(savingInlineWeekly)

                Button {
                    Task { await saveInlineWeeklySchedule() }
                } label: {
                    Text(savingInlineWeekly ? "Saving…" : "Save")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.providerOlive.opacity(
                                    (inlineWeeklyDirty && inlineValidationError == nil && !savingInlineWeekly) ? 0.45 : 0.18
                                ))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Color.lavaShellCream)
                }
                .buttonStyle(.plain)
                .disabled(!inlineWeeklyDirty || savingInlineWeekly || inlineValidationError != nil)
            }
        } else {
            Button {
                beginInlineAvailabilityEditing()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Manage availability")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.providerScheduleCardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.providerOlive.opacity(0.62), lineWidth: 0.65)
                        )
                )
                .foregroundStyle(Color.lavaShellCream)
            }
            .buttonStyle(.plain)
        }
    }

    private var jumpChip: some View {
        Group {
            if jumpChipVisible {
                Button(jumpChipTitle) {
                    switch effectiveZoomTier {
                    case .minute, .day: dayOffset = 0
                    case .week: weekOffset = 0
                    case .month: monthOffset = 0
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(Color.providerScheduleTrackFill)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.providerScheduleTrackStroke, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        // When off today / this week / this month, keep the jump chip centered (parent VStack is leading-aligned).
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var jumpChipVisible: Bool {
        switch effectiveZoomTier {
        case .minute, .day: dayOffset != 0
        case .week: weekOffset != 0
        case .month: monthOffset != 0
        }
    }

    private var jumpChipTitle: String {
        switch effectiveZoomTier {
        case .minute, .day: "Today"
        case .week: "This week"
        case .month: "This month"
        }
    }

    private var summaryLine: some View {
        Text(summaryText)
            .font(.subheadline)
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    // MARK: - Awaiting Payment banner

    /// One tappable row per booking the provider has marked "Request Payment" on. Each
    /// row pushes the same `ProviderBookingDetailView` destination the schedule cells
    /// already use (`path.append(booking)`), so the user lands on the live detail
    /// screen with the inert "Awaiting Payment" pill + "Undo Completion" affordance
    /// rendered exactly as they left it.
    ///
    /// The list is the intersection of three sources of truth:
    ///   - `awaitingPaymentTracker.requestedIds` — the local "we asked the customer"
    ///     marker set by the detail VC.
    ///   - `bookings` — the latest server-loaded list. Filtering here gives us the full
    ///     `SimpleBookingDTO` we need to push, and also prunes IDs whose booking has
    ///     since dropped off the dashboard's window.
    ///   - `ProviderAwaitingPaymentTracker.isAwaitingEligible(status:)` — keeps ACCEPTED
    ///     *and* COMPLETED (the backend stamps `status = COMPLETED` the moment Request
    ///     Payment succeeds — see `POST /bookings-simple/:id/request-payment`), while
    ///     dropping resolved states (PAID / CANCELLED / REJECTED) so the banner self-
    ///     heals as soon as the booking actually closes out.
    @ViewBuilder
    private var awaitingPaymentBanner: some View {
        let awaiting = awaitingPaymentBookings
        if !awaiting.isEmpty {
            VStack(spacing: 8) {
                ForEach(awaiting) { booking in
                    awaitingPaymentRow(for: booking)
                }
            }
            // Slight bottom breathing room so the jump chip / summary line don't crowd
            // the banner. The outer `VStack(spacing: 14)` adds 14pt above; nothing extra
            // needed there.
            .padding(.bottom, 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                awaiting.count == 1
                    ? "1 booking awaiting payment"
                    : "\(awaiting.count) bookings awaiting payment"
            )
        }
    }

    private var awaitingPaymentBookings: [SimpleBookingDTO] {
        // Touch the refresh tick so SwiftUI's body-time dependency tracking includes the
        // notification-driven backstop. The integer's actual value is irrelevant — every
        // mutation to `awaitingPaymentTracker.requestedIds` increments it, which is
        // enough to invalidate this computed property and re-render the banner.
        _ = awaitingPaymentRefreshTick
        let ids = awaitingPaymentTracker.requestedIds
        guard !ids.isEmpty else { return [] }
        return bookings.filter {
            ids.contains($0.id)
                && ProviderAwaitingPaymentTracker.isAwaitingEligible(status: $0.statusUpper, paidAt: $0.paidAt)
        }
    }

    private func awaitingPaymentRow(for booking: SimpleBookingDTO) -> some View {
        Button {
            shellNavigator.pushBooking(booking)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Awaiting Payment")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCream)
                    Text(booking.consumerDisplayName)
                        .font(.headline)
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.providerOlive.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.providerOlive.opacity(0.55), lineWidth: 1)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Awaiting payment for \(booking.consumerDisplayName). Tap to open booking.")
    }

    private var summaryText: String {
        let n = visibleBookingsForCurrentZoom().count
        let noun = n == 1 ? "appointment" : "appointments"
        switch effectiveZoomTier {
        case .minute, .day:
            return "\(n) \(noun) · \(dayTitleLabel)"
        case .week:
            let that = weekOffset != 0 ? "that week" : "this week"
            return "\(n) \(noun) \(that)"
        case .month:
            let that = monthOffset != 0 ? "that month" : "this month"
            return "\(n) \(noun) \(that)"
        }
    }

    private var zoomPresetBar: some View {
        HStack(spacing: 4) {
            ForEach(ProviderScheduleZoom.Preset.allCases) { preset in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        zoomScale = preset.targetScale
                    }
                } label: {
                    Text(preset.title)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(
                            isPresetActive(preset) ? Color.lavaShellCream : Color.lavaShellCream.opacity(0.88)
                        )
                        .background {
                            if isPresetActive(preset) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.providerOlive.opacity(0.62))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isPresetActive(preset) ? .isSelected : [])
            }
        }
        .padding(4)
        .background { scheduleChromeTrackBackground }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schedule zoom")
    }

    private func isPresetActive(_ preset: ProviderScheduleZoom.Preset) -> Bool {
        effectiveZoomTier == preset.tier
    }

    private func zoomScheduleCanvas(canvasViewerHeight: CGFloat) -> some View {
        Group {
            if !session.hasProviderProfile {
                Text("Link your CampusCuts barber profile on the web to load appointments here.")
                    .font(.footnote)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                let display = displayForDailyScheduleBody()
                let intervals = display?.intervals ?? []
                let bounds = ProviderScheduleTimelineBounds.range(for: intervals)
                ProviderZoomableScheduleCanvas(
                    zoomScale: $zoomScale,
                    calendar: mondayCalendar,
                    selectedDay: selectedDay,
                    weekStartMonday: weekStartMonday,
                    monthAnchor: monthAnchor,
                    bookings: visibleBookingsForCurrentZoom(),
                    timelineStartMinute: bounds.start,
                    timelineEndMinute: bounds.end,
                    availabilityIntervals: intervals,
                    timeBlocks: timeBlocksOnSelectedDay,
                    blockTimeTapsEnabled: !isEditingAvailability && (display?.available ?? false),
                    onBookingTap: { shellNavigator.pushBooking($0) },
                    onAvailableMinuteTap: { minute in
                        prepareBlockSheet(forMinute: minute)
                        showingBlockTimeSheet = true
                    },
                    onWeekDayTap: { focusDay($0) },
                    onMonthDayTap: { focusDay($0) },
                    canvasViewerHeight: isDayZoomTier ? canvasViewerHeight : nil,
                    appointmentDragEnabled: isDayZoomTier && !isEditingAvailability,
                    editingMoveBookingID: $editingMoveBookingID,
                    movePromptBooking: $movePromptBooking,
                    timeChangeProposal: $timeChangeProposal,
                    isApplyingTimeChange: isApplyingTimeChange,
                    onConfirmTimeChange: {
                        Task { await applyPendingTimeChange() }
                    },
                    onMoveBookingRequested: { movePromptBooking = $0 },
                    onCancelMoveEditing: { editingMoveBookingID = nil },
                    onBookingTimeChangeProposed: { booking, proposedTime in
                        timeChangeProposal = ScheduleAppointmentTimeChangeProposal(
                            booking: booking,
                            originalTime: booking.scheduledTime ?? proposedTime,
                            proposedTime: proposedTime
                        )
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var dayScheduleSupplement: some View {
        let dayBookings = visibleBookingsForCurrentZoom().sorted {
            ($0.scheduledTime ?? .distantFuture) < ($1.scheduledTime ?? .distantFuture)
        }
        let display = displayForDailyScheduleBody()
        let intervals = display?.intervals ?? []
        let dayEnabled = (display?.available ?? false) && !intervals.isEmpty
        let slots = dayEnabled ? generateHourlySlots(from: intervals) : []

        VStack(alignment: .leading, spacing: 10) {
            if isEditingAvailability {
                if inlineWeeklyLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading weekly schedule…")
                            .font(.footnote)
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
                    .padding(.vertical, 4)
                } else if let inlineWeeklyLoadError {
                    Text(inlineWeeklyLoadError)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                } else {
                    inlineDayScheduleEditorCard
                    if let inlineSaveError {
                        Text(inlineSaveError)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }
            }
            if session.hasProviderProfile,
               isLoadingAvailability,
               displayForDailyScheduleBody() == nil,
               !(isEditingAvailability && (inlineWeeklyLoading || inlineWeeklySchedule != nil))
            {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading availability…")
                        .font(.footnote)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                .padding(.vertical, 4)
            } else if let availabilityErrorText, isDayZoomTier {
                Text(availabilityErrorText)
                    .font(.caption)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            if dayEnabled {
                let orphans = orphanTimeBlocks(slots: slots)
                if !orphans.isEmpty {
                    Text("Other blocked times")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                    ForEach(orphans) { block in
                        blockedTimeRow(block: block)
                    }
                }
                if isEditingAvailability {
                    Text("Finish saving or cancel to block time on the calendar.")
                        .font(.caption2)
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                } else if effectiveZoomTier == .day {
                    Text("Pinch to zoom in for minute-level detail.")
                        .font(.caption2)
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                if let trailing = bookingsOutsideAvailability(slots: slots, dayBookings: dayBookings), !trailing.isEmpty {
                    Text("Outside your set availability")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .padding(.top, 4)
                    ForEach(trailing) { b in
                        Button { shellNavigator.pushBooking(b) } label: { outsideAvailabilityRow(b) }
                            .buttonStyle(.plain)
                    }
                }
            } else if display != nil {
                dayOffMessage(dayBookings: dayBookings)
            } else if let errorText, dayBookings.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
        }
    }

    private func applyPendingTimeChange() async {
        guard let pending = timeChangeProposal else { return }
        isApplyingTimeChange = true
        defer { isApplyingTimeChange = false }

        do {
            try await ProviderBookingsService.reschedule(
                id: pending.booking.id,
                scheduledTimeISO: pending.proposedTime.campusCutsISO8601String(),
                location: pending.booking.location,
                notes: pending.booking.notes
            )
            timeChangeProposal = nil
            editingMoveBookingID = nil
            NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
            await loadBookings()
            await refreshDayScheduleFromNetwork()
        } catch {
            if providerIsBenignRequestCancellation(error) { return }
            timeChangeErrorText = error.localizedDescription
        }
    }

    private func focusDay(_ day: Date) {
        let anchor = mondayCalendar.startOfDay(for: .now)
        dayOffset = mondayCalendar.dateComponents([.day], from: anchor, to: mondayCalendar.startOfDay(for: day)).day ?? 0
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            zoomScale = ProviderScheduleZoom.defaultScale
        }
    }

    // MARK: - Daily

    private var dateNavigationRow: some View {
        HStack(spacing: 10) {
            Button {
                stepDate(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(width: 40, height: 40)
                    .background { scheduleControlCircleBackground }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(periodTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                stepDate(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(width: 40, height: 40)
                    .background { scheduleControlCircleBackground }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background { scheduleChromeTrackBackground }
    }

    private var selectedDay: Date {
        mondayCalendar.date(byAdding: .day, value: dayOffset, to: mondayCalendar.startOfDay(for: .now)) ?? .now
    }

    /// Matches backend `weeklySchedule` keys (`Date.getDay()` order in JS docs).
    private var weeklyDayKeyForSelectedDay: WeeklyScheduleDayKey {
        let w = mondayCalendar.component(.weekday, from: selectedDay)
        switch w {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }

    private var dayTitleLabel: String {
        let d = selectedDay
        if mondayCalendar.isDateInToday(d) { return "Today" }
        if mondayCalendar.isDateInTomorrow(d) { return "Tomorrow" }
        if mondayCalendar.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var periodTitle: String {
        switch effectiveZoomTier {
        case .minute, .day:
            return dayTitleLabel + " · " + selectedDay.formatted(.dateTime.month(.wide).day().year())
        case .week:
            let (a, b) = weekRangeTitles()
            return "\(a) – \(b)"
        case .month:
            return monthAnchor.formatted(.dateTime.month(.wide).year())
        }
    }

    private func blockedTimeRow(block: BarberTimeBlockDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    Text("Blocked")
                        .font(.subheadline.weight(.semibold))
                }
                Text("\(pretty12hBlockTime(block.startTime)) – \(pretty12hBlockTime(block.endTime))")
                    .font(.subheadline.weight(.medium))
                if let reason = block.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
            }
            Spacer(minLength: 8)
            Button {
                Task { await deleteTimeBlock(block) }
            } label: {
                if deletingBlockIds.contains(block.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "trash")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(deletingBlockIds.contains(block.id))
            .accessibilityLabel("Remove time block")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background { scheduleCardBackground(cornerRadius: 12, chrome: .neutral) }
    }

    private func outsideAvailabilityRow(_ b: SimpleBookingDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(b.scheduledTime?.formatted(date: .omitted, time: .shortened) ?? "Time TBD")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(b.scheduleSlotTitle)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(b.statusDisplayTint, in: Capsule())
            }
            Text(b.consumerDisplayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream)
            Text(b.serviceDisplayName)
                .font(.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text(b.barberDisplayName)
                .font(.caption)
                .foregroundStyle(Color.lavaShellCreamTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background { scheduleCardBackground(cornerRadius: 14, chrome: scheduleCardChrome(for: b)) }
    }

    @ViewBuilder
    private func dayOffMessage(dayBookings: [SimpleBookingDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You're not available on \(weekdayName(for: selectedDay))s.")
                .font(.footnote)
                .foregroundStyle(Color.lavaShellCreamSecondary)
            if !timeBlocksOnSelectedDay.isEmpty {
                Text("Blocked times on this day")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                ForEach(timeBlocksOnSelectedDay) { block in
                    blockedTimeRow(block: block)
                }
                Text("You can remove blocks below. Tap an available hour to add a block when you are not editing weekly hours.")
                    .font(.caption2)
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            if !dayBookings.isEmpty {
                Text("Existing bookings on this day:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                ForEach(dayBookings) { b in
                    Button {
                        shellNavigator.pushBooking(b)
                    } label: {
                        outsideAvailabilityRow(b)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Daily slot helpers

    /// Whole-hour bookable slot derived from the provider's availability intervals.
    fileprivate struct HourlySlot: Hashable {
        let startHour: Int
        let startMinutes: Int
        let endMinutes: Int
        let start: String
        let end: String

        var displayRange: String {
            "\(Self.format12h(minutes: startMinutes)) – \(Self.format12h(minutes: endMinutes))"
        }

        private static func format12h(minutes: Int) -> String {
            var c = DateComponents()
            c.hour = minutes / 60
            c.minute = minutes % 60
            let cal = Calendar(identifier: .gregorian)
            let date = cal.date(from: c) ?? .now
            return date.formatted(date: .omitted, time: .shortened)
        }
    }

    private func generateHourlySlots(from intervals: [BarberAvailabilityIntervalDTO]) -> [HourlySlot] {
        var seen = Set<Int>()
        var slots: [HourlySlot] = []
        for interval in intervals {
            guard let startHour = parseHour(interval.start),
                  let endHour = parseHour(interval.end),
                  endHour > startHour
            else { continue }
            for h in startHour ..< endHour where !seen.contains(h) {
                seen.insert(h)
                slots.append(HourlySlot(
                    startHour: h,
                    startMinutes: h * 60,
                    endMinutes: (h + 1) * 60,
                    start: String(format: "%02d:00", h),
                    end: String(format: "%02d:00", h + 1)
                ))
            }
        }
        return slots.sorted { $0.startHour < $1.startHour }
    }

    private func parseHour(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard let first = parts.first, let h = Int(first), (0 ... 24).contains(h) else { return nil }
        return h
    }

    private func bookingsOutsideAvailability(
        slots: [HourlySlot],
        dayBookings: [SimpleBookingDTO]
    ) -> [SimpleBookingDTO]? {
        guard !dayBookings.isEmpty else { return [] }
        let covered = Set(slots.map(\.startHour))
        let cal = mondayCalendar
        let outside = dayBookings.filter { b in
            guard let st = b.scheduledTime else { return true }
            let h = cal.component(.hour, from: st)
            return !covered.contains(h)
        }
        return outside
    }

    private func weekdayName(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = mondayCalendar
        f.locale = Locale.current
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private var dailyAvailabilityKey: String {
        "\(session.barberProfile?.id ?? "none")|\(dayOffset)"
    }

    private func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = mondayCalendar
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private var selectedDayYyyyMMdd: String {
        dayKey(for: selectedDay)
    }

    /// Only use cached API day data when its `date` matches the calendar day key (avoids mismatched payloads).
    private var displayedDayAvailability: BarberAvailabilityDayData? {
        guard let data = availabilityByDay[selectedDayYyyyMMdd] else { return nil }
        if let raw = data.date?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            guard normalizedBlockDate(raw) == selectedDayYyyyMMdd else { return nil }
        }
        return data
    }

    private func displayForDailyScheduleBody() -> BarberAvailabilityDayData? {
        if isEditingAvailability,
           !inlineWeeklyLoading,
           let w = inlineWeeklySchedule
        {
            return Self.syntheticAvailabilityDay(
                dateKey: selectedDayYyyyMMdd,
                scheduleKey: weeklyDayKeyForSelectedDay,
                schedule: w
            )
        }
        return displayedDayAvailability
    }

    /// Preview + slot generation while editing: maps the in-memory weekly row to the same shape as the day API.
    private static func syntheticAvailabilityDay(
        dateKey: String,
        scheduleKey: WeeklyScheduleDayKey,
        schedule: WeeklyScheduleDTO
    ) -> BarberAvailabilityDayData {
        let entry = schedule[scheduleKey]
        let intervals = entry.intervals.map { BarberAvailabilityIntervalDTO(id: $0.id, start: $0.start, end: $0.end) }
        return BarberAvailabilityDayData(
            date: dateKey,
            dayOfWeek: nil,
            available: entry.enabled && !entry.intervals.isEmpty,
            intervals: intervals,
            bookedSlots: nil,
            slots: nil
        )
    }

    private var selectedDaySchedule: DayScheduleDTO {
        inlineWeeklySchedule.map { $0[weeklyDayKeyForSelectedDay] } ?? .empty
    }

    private func setSelectedDaySchedule(_ day: DayScheduleDTO) {
        guard var w = inlineWeeklySchedule else { return }
        w[weeklyDayKeyForSelectedDay] = day
        inlineWeeklySchedule = w
        recomputeInlineWeeklyValidation()
    }

    private var inlineDayScheduleEditorCard: some View {
        let dayName = weeklyDayKeyForSelectedDay.displayName
        let dayAvailabilityBinding = Binding(
            get: { selectedDaySchedule.enabled },
            set: { newVal in
                var d = selectedDaySchedule
                d.enabled = newVal
                if newVal, d.intervals.isEmpty {
                    d.intervals = [ScheduleIntervalDTO(start: "09:00", end: "17:00")]
                }
                setSelectedDaySchedule(d)
            }
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text("Weekly schedule")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.lavaShellCreamSecondary)

            inlineDayAvailabilityToggleRow(
                dayName: dayName,
                isEnabled: selectedDaySchedule.enabled,
                isOn: dayAvailabilityBinding
            )

            if selectedDaySchedule.enabled {
                Text("Booking hours")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)

                ForEach(selectedDaySchedule.intervals) { interval in
                    inlineIntervalRow(interval: interval)
                }
                Button {
                    addIntervalForSelectedWeekday()
                } label: {
                    Label("Add time slot", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.providerOlive.opacity(0.58))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.lavaShellCream.opacity(0.22), lineWidth: 0.6)
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let inlineValidationError {
                Text(inlineValidationError)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.92))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.providerScheduleCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.providerOlive.opacity(0.55), lineWidth: 0.65)
                )
        )
    }

    private func inlineDayAvailabilityToggleRow(
        dayName: String,
        isEnabled: Bool,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isEnabled ? "calendar.badge.checkmark" : "calendar.badge.minus")
                .font(.title3)
                .foregroundStyle(isEnabled ? Color.providerOlive : Color.lavaShellCreamTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Open for bookings every \(dayName)")
                    .font(.subheadline.weight(.semibold))
                Text(
                    isEnabled
                        ? "Clients can request appointments during the hours below."
                        : "This weekday is a day off. Turn on to set when you're available."
                )
                .font(.caption)
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.providerOlive)
                .accessibilityLabel("Open for bookings every \(dayName)")
                .accessibilityHint(
                    isEnabled
                        ? "Turn off to mark \(dayName)s as unavailable."
                        : "Turn on to add booking hours for \(dayName)s."
                )
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.providerScheduleControlFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.providerScheduleControlStroke, lineWidth: 0.65)
                )
        )
    }

    @ViewBuilder
    private func inlineIntervalRow(interval: ScheduleIntervalDTO) -> some View {
        HStack(spacing: 10) {
            DatePicker(
                "Start",
                selection: Binding(
                    get: { Self.scheduleDateFromHHMM(interval.start) },
                    set: { updateInlineInterval(intervalId: interval.id, start: Self.scheduleHHMMFromDate($0)) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .accessibilityLabel("Start")

            Text("–")
                .foregroundStyle(Color.lavaShellCreamSecondary)

            DatePicker(
                "End",
                selection: Binding(
                    get: { Self.scheduleDateFromHHMM(interval.end) },
                    set: { updateInlineInterval(intervalId: interval.id, end: Self.scheduleHHMMFromDate($0)) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .accessibilityLabel("End")

            Spacer(minLength: 0)

            Button {
                removeInlineInterval(intervalId: interval.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove time slot")
        }
    }

    private func addIntervalForSelectedWeekday() {
        var current = selectedDaySchedule
        let last = current.intervals.last
        var newStart = "09:00"
        if let last, let h = Int(last.end.split(separator: ":").first ?? "") {
            newStart = String(format: "%02d:00", min(h + 1, 23))
        }
        let startHour = Int(newStart.split(separator: ":").first ?? "9") ?? 9
        let newEnd = String(format: "%02d:00", min(startHour + 2, 23))
        current.intervals.append(ScheduleIntervalDTO(start: newStart, end: newEnd))
        current.enabled = true
        setSelectedDaySchedule(current)
    }

    private func removeInlineInterval(intervalId: String) {
        var current = selectedDaySchedule
        current.intervals.removeAll { $0.id == intervalId }
        if current.intervals.isEmpty { current.enabled = false }
        setSelectedDaySchedule(current)
    }

    private func updateInlineInterval(intervalId: String, start: String? = nil, end: String? = nil) {
        var current = selectedDaySchedule
        guard let idx = current.intervals.firstIndex(where: { $0.id == intervalId }) else { return }
        if let start { current.intervals[idx].start = start }
        if let end { current.intervals[idx].end = end }
        setSelectedDaySchedule(current)
    }

    /// Same rules as `ProviderAvailabilityEditorView.recomputeValidation`.
    private func recomputeInlineWeeklyValidation() {
        guard let weekly = inlineWeeklySchedule else {
            inlineValidationError = nil
            return
        }
        for day in WeeklyScheduleDayKey.allCases {
            let entry = weekly[day]
            guard entry.enabled else { continue }
            let intervals = entry.intervals
            for (i, current) in intervals.enumerated() {
                let s = Self.scheduleMinutesFromHHMM(current.start)
                let e = Self.scheduleMinutesFromHHMM(current.end)
                if s >= e {
                    inlineValidationError = "\(day.displayName): end time must be after start time."
                    return
                }
                for j in (i + 1) ..< intervals.count {
                    let other = intervals[j]
                    let os = Self.scheduleMinutesFromHHMM(other.start)
                    let oe = Self.scheduleMinutesFromHHMM(other.end)
                    if s < oe, e > os {
                        inlineValidationError = "\(day.displayName): time slots cannot overlap."
                        return
                    }
                }
            }
        }
        inlineValidationError = nil
    }

    private static func scheduleDateFromHHMM(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 9
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        var c = DateComponents()
        c.hour = h
        c.minute = m
        return Calendar(identifier: .gregorian).date(from: c) ?? .now
    }

    private static func scheduleHHMMFromDate(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }

    private static func scheduleMinutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }

    private func beginInlineAvailabilityEditing() {
        guard let barberId = session.barberProfile?.id, session.hasProviderProfile else { return }
        isEditingAvailability = true
        inlineWeeklyLoading = true
        inlineWeeklyLoadError = nil
        inlineSaveError = nil
        inlineValidationError = nil
        Task { @MainActor in
            do {
                let w = try await ProviderAvailabilityManagementService.fetchWeeklySchedule(barberId: barberId)
                inlineWeeklySchedule = w
                originalInlineWeeklySchedule = w
                recomputeInlineWeeklyValidation()
                inlineWeeklyLoading = false
            } catch {
                inlineWeeklyLoadError = (error as? LocalizedError)?.errorDescription ?? "Could not load schedule."
                inlineWeeklyLoading = false
                isEditingAvailability = false
                inlineWeeklySchedule = nil
                originalInlineWeeklySchedule = nil
            }
        }
    }

    private func cancelInlineAvailabilityEditing() {
        isEditingAvailability = false
        inlineWeeklySchedule = nil
        originalInlineWeeklySchedule = nil
        inlineWeeklyLoading = false
        inlineWeeklyLoadError = nil
        inlineValidationError = nil
        inlineSaveError = nil
    }

    private func saveInlineWeeklySchedule() async {
        guard let barberId = session.barberProfile?.id, let weekly = inlineWeeklySchedule else { return }
        recomputeInlineWeeklyValidation()
        guard inlineValidationError == nil else { return }
        savingInlineWeekly = true
        inlineSaveError = nil
        defer { savingInlineWeekly = false }
        do {
            try await ProviderAvailabilityManagementService.updateWeeklySchedule(barberId: barberId, schedule: weekly)
            NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
            await refreshDayScheduleFromNetwork()
            cancelInlineAvailabilityEditing()
        } catch {
            inlineSaveError = (error as? LocalizedError)?.errorDescription ?? "Could not save schedule."
        }
    }

    private var timeBlocksOnSelectedDay: [BarberTimeBlockDTO] {
        (timeBlocksByDay[selectedDayYyyyMMdd] ?? []).sorted { $0.startTime < $1.startTime }
    }

    private func normalizedBlockDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: "T").first.map(String.init) ?? trimmed
    }

    private func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }

    private func pretty12hBlockTime(_ hhmm: String) -> String {
        let mins = minutesFromHHMM(hhmm)
        let d = mondayCalendar.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: selectedDay) ?? selectedDay
        return d.formatted(date: .omitted, time: .shortened)
    }

    private func timeBlocksOverlappingSlot(_ slot: HourlySlot) -> [BarberTimeBlockDTO] {
        timeBlocksOnSelectedDay
            .filter { b in
                let bs = minutesFromHHMM(b.startTime)
                let be = minutesFromHHMM(b.endTime)
                return bs < slot.endMinutes && be > slot.startMinutes
            }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Blocks on this calendar day that do not overlap any whole-hour availability row (e.g. 12:30–1:15).
    private func orphanTimeBlocks(slots: [HourlySlot]) -> [BarberTimeBlockDTO] {
        timeBlocksOnSelectedDay
            .filter { b in
                let bs = minutesFromHHMM(b.startTime)
                let be = minutesFromHHMM(b.endTime)
                return !slots.contains { slot in bs < slot.endMinutes && be > slot.startMinutes }
            }
            .sorted { $0.startTime < $1.startTime }
    }

    private func prepareBlockSheet(forMinute minute: Int) {
        let cal = mondayCalendar
        let day = selectedDay
        blockSheetDayStart = cal.startOfDay(for: day)
        blockSheetStart = cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
        blockSheetEnd = cal.date(byAdding: .minute, value: 60, to: blockSheetStart) ?? blockSheetStart
    }

    private func refreshDayScheduleFromNetwork() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadDayAvailabilityIfNeeded() }
            group.addTask { await loadDayTimeBlocks() }
        }
        guard session.hasProviderProfile, let barberId = session.barberProfile?.id else { return }
        let center = selectedDay
        Task(priority: .utility) { @MainActor in
            await prefetchAdjacentDaysSchedule(anchoredTo: center, barberId: barberId)
        }
    }

    /// Loads **previous / next calendar day** in the background so day-to-day navigation can reuse cache.
    private func prefetchAdjacentDaysSchedule(anchoredTo centerDay: Date, barberId: String) async {
        guard session.barberProfile?.id == barberId else { return }
        let sod = mondayCalendar.startOfDay(for: centerDay)
        let prev = mondayCalendar.date(byAdding: .day, value: -1, to: sod) ?? sod
        let next = mondayCalendar.date(byAdding: .day, value: 1, to: sod) ?? sod
        async let p: Void = prefetchSingleDayScheduleIfNeeded(barberId: barberId, date: prev, dayKey: dayKey(for: prev))
        async let n: Void = prefetchSingleDayScheduleIfNeeded(barberId: barberId, date: next, dayKey: dayKey(for: next))
        _ = await (p, n)
    }

    private func prefetchSingleDayScheduleIfNeeded(barberId: String, date: Date, dayKey: String) async {
        guard session.barberProfile?.id == barberId else { return }
        let needAvailability = availabilityByDay[dayKey] == nil
        let needBlocks = timeBlocksByDay[dayKey] == nil
        if !needAvailability && !needBlocks { return }
        await withTaskGroup(of: Void.self) { group in
            if needAvailability {
                group.addTask { await prefetchDayAvailability(barberId: barberId, date: date, dayKey: dayKey) }
            }
            if needBlocks {
                group.addTask { await prefetchDayTimeBlocks(barberId: barberId, dayKey: dayKey) }
            }
        }
    }

    private func prefetchDayAvailability(barberId: String, date: Date, dayKey: String) async {
        do {
            let result = try await ProviderAvailabilityService.getDayAvailability(
                barberId: barberId,
                date: date
            )
            try Task.checkCancellation()
            guard session.barberProfile?.id == barberId else { return }
            if let raw = result.date?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                guard normalizedBlockDate(raw) == dayKey else { return }
            }
            var next = availabilityByDay
            next[dayKey] = result
            availabilityByDay = next
        } catch {}
    }

    private func prefetchDayTimeBlocks(barberId: String, dayKey: String) async {
        do {
            let list = try await ProviderAvailabilityManagementService.listTimeBlocks(
                barberId: barberId,
                startDate: dayKey,
                endDate: dayKey
            )
            try Task.checkCancellation()
            guard session.barberProfile?.id == barberId else { return }
            let filtered = list
                .filter { normalizedBlockDate($0.blockDate) == dayKey }
                .sorted { $0.startTime < $1.startTime }
            var next = timeBlocksByDay
            next[dayKey] = filtered
            timeBlocksByDay = next
        } catch {}
    }

    private func loadDayTimeBlocks() async {
        guard session.hasProviderProfile, let barberId = session.barberProfile?.id else {
            timeBlocksByDay = [:]
            return
        }
        let fetchKey = dailyAvailabilityKey
        let anchorDay = selectedDay
        let key = dayKey(for: anchorDay)
        do {
            let list = try await ProviderAvailabilityManagementService.listTimeBlocks(
                barberId: barberId,
                startDate: key,
                endDate: key
            )
            try Task.checkCancellation()
            guard fetchKey == dailyAvailabilityKey else { return }
            let filtered = list
                .filter { normalizedBlockDate($0.blockDate) == key }
                .sorted { $0.startTime < $1.startTime }
            var next = timeBlocksByDay
            next[key] = filtered
            timeBlocksByDay = next
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            guard fetchKey == dailyAvailabilityKey else { return }
            var next = timeBlocksByDay
            next.removeValue(forKey: key)
            timeBlocksByDay = next
        }
    }

    private func deleteTimeBlock(_ block: BarberTimeBlockDTO) async {
        guard let barberId = session.barberProfile?.id else { return }
        deletingBlockIds.insert(block.id)
        defer { deletingBlockIds.remove(block.id) }
        do {
            try await ProviderAvailabilityManagementService.deleteTimeBlock(barberId: barberId, blockId: block.id)
            let dayKey = selectedDayYyyyMMdd
            if var blocks = timeBlocksByDay[dayKey] {
                blocks.removeAll { $0.id == block.id }
                var next = timeBlocksByDay
                next[dayKey] = blocks
                timeBlocksByDay = next
            }
            await refreshDayScheduleFromNetwork()
            NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
        } catch {
            // Non-fatal: list will refresh on next pull.
        }
    }

    private func loadDayAvailabilityIfNeeded() async {
        guard session.hasProviderProfile, let barberId = session.barberProfile?.id else {
            availabilityByDay = [:]
            timeBlocksByDay = [:]
            availabilityErrorText = nil
            isLoadingAvailability = false
            return
        }
        let fetchKey = dailyAvailabilityKey
        let dayToFetch = selectedDay
        let requestKey = dayKey(for: dayToFetch)
        isLoadingAvailability = true
        availabilityErrorText = nil
        defer {
            if fetchKey == dailyAvailabilityKey {
                isLoadingAvailability = false
            }
        }
        do {
            let result = try await ProviderAvailabilityService.getDayAvailability(
                barberId: barberId,
                date: dayToFetch
            )
            try Task.checkCancellation()
            guard fetchKey == dailyAvailabilityKey else { return }
            var next = availabilityByDay
            next[requestKey] = result
            availabilityByDay = next
        } catch is CancellationError {
            // Swift task cancelled (overlapping refresh / navigation).
        } catch let error as URLError where error.code == .cancelled {
            // `NSURLErrorDomain` -999
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            guard fetchKey == dailyAvailabilityKey else { return }
            availabilityErrorText = (error as? LocalizedError)?.errorDescription ?? "Could not load availability."
            var next = availabilityByDay
            next.removeValue(forKey: requestKey)
            availabilityByDay = next
        }
    }

    // MARK: - Weekly (list of 7 days, mobile-style)

    private var weekStartMonday: Date {
        let today = mondayCalendar.startOfDay(for: .now)
        let weekday = mondayCalendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let thisMonday = mondayCalendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
        return mondayCalendar.date(byAdding: .weekOfYear, value: weekOffset, to: thisMonday) ?? thisMonday
    }

    private func weekRangeTitles() -> (String, String) {
        let start = weekStartMonday
        let end = mondayCalendar.date(byAdding: .day, value: 6, to: start) ?? start
        let y1 = mondayCalendar.component(.year, from: start)
        let y2 = mondayCalendar.component(.year, from: end)
        if y1 != y2 {
            return (
                start.formatted(.dateTime.month(.abbreviated).day().year()),
                end.formatted(.dateTime.month(.abbreviated).day().year())
            )
        }
        return (
            start.formatted(.dateTime.month(.abbreviated).day()),
            end.formatted(.dateTime.month(.abbreviated).day().year())
        )
    }

    private var monthAnchor: Date {
        mondayCalendar.date(byAdding: .month, value: monthOffset, to: mondayCalendar.startOfDay(for: .now)) ?? .now
    }

    // MARK: - Data

    /// Bookings shown anywhere on the main schedule (daily slots, weekly rows, monthly counts, summary).
    private var scheduleBookings: [SimpleBookingDTO] {
        bookings.filter(\.isVisibleOnMainSchedule)
    }

    private func visibleBookingsForCurrentZoom() -> [SimpleBookingDTO] {
        switch effectiveZoomTier {
        case .minute, .day:
            return scheduleBookings.filter { $0.isSameCalendarDay(as: selectedDay, calendar: mondayCalendar) }
        case .week:
            return scheduleBookings.filter { $0.isInWeek(containing: weekStartMonday, calendar: mondayCalendar) }
        case .month:
            return scheduleBookings.filter { $0.isInMonth(containing: monthAnchor, calendar: mondayCalendar) }
        }
    }

    private func loadBookings() async {
        guard session.hasProviderProfile else {
            bookings = []
            errorText = nil
            awaitingPaymentTracker.reconcile(with: [])
            return
        }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let list = try await ProviderBookingsService.listBookings(role: "barber")
            try Task.checkCancellation()
            bookings = list
            // Prune any locally-tracked "Awaiting Payment" IDs whose underlying booking
            // has since changed status server-side (paid, completed, cancelled, …) or
            // dropped out of the barber's window entirely. Without this, the banner can
            // outlive its meaning — e.g. if the customer pays, the booking flips to
            // PAID/COMPLETED on the server but the local tracker would still try to
            // render a stale row.
            awaitingPaymentTracker.reconcile(with: list)
        } catch is CancellationError {
            // Swift task cancelled (e.g. overlapping refresh / navigation).
        } catch let error as URLError where error.code == .cancelled {
            // `NSURLErrorDomain` -999
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            bookings = []
        }
    }

    private func stepDate(_ delta: Int) {
        switch effectiveZoomTier {
        case .minute, .day: dayOffset += delta
        case .week: weekOffset += delta
        case .month: monthOffset += delta
        }
    }
}
