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
    @Environment(\.colorScheme) private var colorScheme

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
    /// False while a day/minute pinch is adjusting scale — blocks accidental week/month drift.
    @State private var scheduleZoomChangedViaPreset = true
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
    @State private var blockSheetBlocksEntireDay = true
    @State private var blockSheetPresentationID = UUID()
    @State private var deletingBlockIds: Set<String> = []

    /// When set, the user is editing **this weekday’s** weekly intervals inline (Daily mode only).
    @State private var isEditingAvailability = false
    @State private var inlineWeeklySchedule: WeeklyScheduleDTO?
    @State private var originalInlineWeeklySchedule: WeeklyScheduleDTO?
    /// Recurring weekly hours — used for the week-view grid without waiting on per-day availability fetches.
    @State private var cachedWeeklySchedule: WeeklyScheduleDTO?
    @State private var inlineWeeklyLoading = false
    @State private var inlineWeeklyLoadError: String?
    @State private var inlineValidationError: String?
    @State private var savingInlineWeekly = false
    @State private var inlineSaveError: String?

    @State private var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    @State private var blockedTimeChangeConfirmationPending = false
    @State private var isApplyingTimeChange = false
    @State private var timeChangeErrorText: String?
    @State private var movePromptBooking: SimpleBookingDTO?
    @State private var editingMoveBookingID: String?
    /// While rescheduling, the booking being moved is only draggable when this matches `editingMoveBookingID`.
    @State private var activeMoveDragBookingID: String?
    /// When set, the day timeline scrolls to this booking after focusing a day from week/month view.
    @State private var pendingScrollToBookingID: String?

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

    /// Day, minute, and week share the taller schedule viewer; month stays compact.
    private var usesTallScheduleViewer: Bool {
        isDayZoomTier || effectiveZoomTier == .week
    }

    private var supportsManageAvailability: Bool {
        switch effectiveZoomTier {
        case .month, .week, .day, .minute:
            return true
        }
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
            ZStack(alignment: .top) {
                ScrollView {
                    scheduleContent(canvasViewerHeight: canvasViewerHeight)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDisabled(isEditingAvailability || (effectiveZoomTier == .month && !isEditingAvailability))
                /// Default `ScrollView` content background is an opaque system fill — hide it so the root shell background shows through.
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .refreshable {
                    await loadBookings()
                    await refreshDayScheduleFromNetwork()
                }

                if isEditingAvailability {
                    availabilityEditorFullScreenOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        /// Stable `id` avoids cancelling in-flight `bookings-simple` on every unrelated `body` refresh (which surfaces as **-999 cancelled** and cleared the list).
        .task(id: session.barberProfile?.id) {
            availabilityByDay = [:]
            timeBlocksByDay = [:]
            cachedWeeklySchedule = nil
            await loadBookings()
            await loadCachedWeeklyScheduleIfNeeded()
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
            Task {
                await refreshDayScheduleFromNetwork()
                await loadCachedWeeklyScheduleIfNeeded()
            }
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
            activeMoveDragBookingID = nil
            movePromptBooking = nil
            timeChangeProposal = nil
            blockedTimeChangeConfirmationPending = false
        }
        .onChange(of: effectiveZoomTier) { _, tier in
            if tier == .month {
                editingMoveBookingID = nil
                activeMoveDragBookingID = nil
                movePromptBooking = nil
                timeChangeProposal = nil
                blockedTimeChangeConfirmationPending = false
            }
        }
        .onChange(of: zoomScale) { _, newScale in
            enforcePinchOnlyScheduleZoom(newScale)
        }
        .task(id: weekTimeBlocksPrefetchToken) {
            await prefetchVisibleWeekTimeBlocksIfNeeded()
        }
        .onChange(of: timeChangeProposal?.id) { _, _ in
            blockedTimeChangeConfirmationPending = false
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
                    navigationTitle: "Block Time",
                    confirmButtonTitle: "Block",
                    initialDate: blockSheetDayStart,
                    initialBlocksEntireDay: blockSheetBlocksEntireDay,
                    initialStart: blockSheetBlocksEntireDay ? nil : blockSheetStart,
                    bookings: ProviderScheduleBookingConflicts.upcomingBookings(
                        from: scheduleBookings,
                        calendar: mondayCalendar
                    ),
                    calendar: mondayCalendar,
                    onSaved: { _ in
                        Task { await refreshDayScheduleFromNetwork() }
                        NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
                    }
                )
                .id(blockSheetPresentationID)
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
            if isScheduleBookingMoveFlowActive {
                scheduleBookingMoveActionPanel
            } else {
                summaryLine
                zoomPresetBar
                dateNavigationRow
                if session.hasProviderProfile, supportsManageAvailability, !isEditingAvailability {
                    scheduleAvailabilityActionsRow
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                scheduleCanvasRegion(canvasViewerHeight: canvasViewerHeight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func scheduleCanvasRegion(canvasViewerHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            zoomScheduleCanvas(canvasViewerHeight: canvasViewerHeight)

            if isDayZoomTier {
                dayScheduleSupplement
            } else if effectiveZoomTier == .week {
                weekScheduleSupplement
            }
        }
    }

    private var availabilityEditorFullScreenOverlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            availabilityEditorActionBar

            ScrollView(.vertical, showsIndicators: false) {
                availabilityEditorOverlayContent
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaPadding(.bottom, 8)
        .background {
            Color(uiColor: ProviderAppearance.shellBase)
                .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Availability editor")
    }

    private var availabilityEditorActionBar: some View {
        HStack(spacing: 10) {
            Button {
                cancelInlineAvailabilityEditing()
            } label: {
                Text("Cancel")
                    .font(.provider(.subheadline, weight: .semibold))
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
                    .font(.provider(.subheadline, weight: .semibold))
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
    }

    @ViewBuilder
    private var availabilityEditorOverlayContent: some View {
        if inlineWeeklyLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading weekly schedule…")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else if let inlineWeeklyLoadError {
            Text(inlineWeeklyLoadError)
                .font(.provider(.footnote))
                .foregroundStyle(.red.opacity(0.9))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(WeeklyScheduleDayKey.allCases) { day in
                    inlineWeeklyDayEditorCard(for: day)
                }

                if let inlineValidationError {
                    Text(inlineValidationError)
                        .font(.provider(.caption))
                        .foregroundStyle(.red.opacity(0.92))
                }
                if let inlineSaveError {
                    Text(inlineSaveError)
                        .font(.provider(.caption))
                        .foregroundStyle(.red.opacity(0.9))
                }
            }
        }
    }

    private var inlineWeeklyDirty: Bool {
        inlineWeeklySchedule != nil && inlineWeeklySchedule != originalInlineWeeklySchedule
    }

    private var scheduleAvailabilityActionsRow: some View {
        HStack(spacing: 10) {
            scheduleActionButton(
                title: "Edit Schedule",
                action: beginInlineAvailabilityEditing
            )
            scheduleActionButton(
                title: "Block Time",
                action: {
                    prepareBlockSheetForSelectedDay()
                    showingBlockTimeSheet = true
                }
            )
        }
    }

    private func scheduleActionButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.provider(.subheadline, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .providerOliveOutlined()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.providerScheduleCardFill)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.providerOlive.opacity(0.62), lineWidth: 0.65)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var summaryLine: some View {
        Text(summaryText)
            .font(.provider(.subheadline))
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private var isScheduleBookingMoveFlowActive: Bool {
        movePromptBooking != nil || timeChangeProposal != nil || editingMoveBookingID != nil
    }

    @ViewBuilder
    private var scheduleBookingMoveActionPanel: some View {
        if blockedTimeChangeConfirmationPending, let proposal = timeChangeProposal {
            scheduleMoveActionCard(
                title: "Blocked time",
                bullets: blockedTimeChangeConfirmBullets(for: proposal),
                primaryTitle: isApplyingTimeChange ? "Saving…" : "Move anyway",
                secondaryTitle: "Cancel",
                isPrimaryDisabled: isApplyingTimeChange,
                onPrimary: {
                    Task { await applyPendingTimeChange() }
                },
                onSecondary: {
                    blockedTimeChangeConfirmationPending = false
                }
            )
        } else if let proposal = timeChangeProposal {
            scheduleMoveActionCard(
                title: "Confirm time change",
                bullets: confirmTimeChangeBullets(for: proposal),
                primaryTitle: isApplyingTimeChange ? "Saving…" : "Confirm",
                secondaryTitle: "Cancel",
                isPrimaryDisabled: isApplyingTimeChange,
                onPrimary: {
                    if requiresBlockedTimeMoveConfirmation(for: proposal) {
                        blockedTimeChangeConfirmationPending = true
                    } else {
                        Task { await applyPendingTimeChange() }
                    }
                },
                onSecondary: {
                    timeChangeProposal = nil
                    blockedTimeChangeConfirmationPending = false
                    editingMoveBookingID = nil
                    activeMoveDragBookingID = nil
                }
            )
        } else if let booking = movePromptBooking {
            scheduleMoveActionCard(
                title: "Change appointment time?",
                bullets: [
                    "Tap Change time to start rescheduling",
                    "Drag to an open slot",
                    "Confirm the new time"
                ],
                primaryTitle: "Change time",
                secondaryTitle: "Cancel",
                isPrimaryDisabled: false,
                onPrimary: {
                    timeChangeProposal = nil
                    editingMoveBookingID = booking.id
                    activeMoveDragBookingID = booking.id
                    movePromptBooking = nil
                },
                onSecondary: {
                    movePromptBooking = nil
                }
            )
        } else if editingMoveBookingID != nil {
            scheduleMoveActionCard(
                title: "Moving appointment",
                bullets: [
                    "Drag to an open slot",
                    "After dropping, tap the booking again to drag elsewhere"
                ],
                primaryTitle: nil,
                secondaryTitle: "Cancel",
                isPrimaryDisabled: false,
                onPrimary: {},
                onSecondary: {
                    editingMoveBookingID = nil
                    activeMoveDragBookingID = nil
                }
            )
        }
    }

    private func confirmTimeChangeBullets(for proposal: ScheduleAppointmentTimeChangeProposal) -> [String] {
        let fromTime = proposal.originalTime.formatted(date: .omitted, time: .shortened)
        let toTime = proposal.proposedTime.formatted(date: .omitted, time: .shortened)
        return [
            "\(proposal.booking.consumerDisplayName) · \(proposal.booking.serviceDisplayName): \(fromTime) → \(toTime)",
            "Tap the booking again to drag to a different slot"
        ]
    }

    private func blockedTimeChangeConfirmBullets(for proposal: ScheduleAppointmentTimeChangeProposal) -> [String] {
        let toDate = proposal.proposedTime.formatted(date: .abbreviated, time: .omitted)
        let toTime = proposal.proposedTime.formatted(date: .omitted, time: .shortened)
        let bookingLabel = "\(proposal.booking.consumerDisplayName) · \(proposal.booking.serviceDisplayName)"

        if isEntireDayBlockedOff(for: proposal.proposedTime) {
            return [
                "That day is blocked off (\(toDate))",
                "Move \(bookingLabel) to a blocked day anyway?"
            ]
        }

        return [
            "That date and time is blocked off (\(toDate) · \(toTime))",
            "Move \(bookingLabel) to blocked time anyway?"
        ]
    }

    private func requiresBlockedTimeMoveConfirmation(for proposal: ScheduleAppointmentTimeChangeProposal) -> Bool {
        if overlappingTimeBlock(for: proposal) != nil { return true }
        return isEntireDayBlockedOff(for: proposal.proposedTime)
    }

    private func overlappingTimeBlock(for proposal: ScheduleAppointmentTimeChangeProposal) -> BarberTimeBlockDTO? {
        let key = dayKey(for: proposal.proposedTime)
        let blocks = timeBlocksByDay[key] ?? []
        guard let appointment = ScheduleCanvasAppointment.from(booking: proposal.booking, calendar: mondayCalendar) else {
            return nil
        }

        let proposedComponents = mondayCalendar.dateComponents([.hour, .minute], from: proposal.proposedTime)
        let startMinute = (proposedComponents.hour ?? 0) * 60 + (proposedComponents.minute ?? 0)
        let endMinute = startMinute + appointment.durationMinutes

        return blocks.first { block in
            let blockStart = minutesFromHHMM(block.startTime)
            let blockEnd = minutesFromHHMM(block.endTime)
            return startMinute < blockEnd && endMinute > blockStart
        }
    }

    private func scheduleMoveActionCard(
        title: String,
        bullets: [String],
        primaryTitle: String?,
        secondaryTitle: String,
        isPrimaryDisabled: Bool,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void
    ) -> some View {
        let secondaryButton = Button(action: onSecondary) {
            Text(secondaryTitle)
                .font(.provider(.subheadline, weight: .semibold))
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

        func primaryButton(_ title: String) -> some View {
            Button(action: onPrimary) {
                Text(title)
                    .font(.provider(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.providerOlive.opacity(isPrimaryDisabled ? 0.25 : 0.55))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Color.lavaShellCream)
            }
            .buttonStyle(.plain)
            .disabled(isPrimaryDisabled)
        }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lavaShellCream)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.provider(.caption, weight: .bold))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                            Text(bullet)
                                .font(.provider(.caption))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let primaryTitle {
                HStack(spacing: 10) {
                    secondaryButton
                    primaryButton(primaryTitle)
                }
            } else {
                secondaryButton
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.providerSchedulePromptCardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.providerOlive.opacity(0.55), lineWidth: 1)
                }
        }
        .animation(.easeInOut(duration: 0.2), value: movePromptBooking?.id)
        .animation(.easeInOut(duration: 0.2), value: timeChangeProposal?.id)
        .animation(.easeInOut(duration: 0.2), value: editingMoveBookingID)
        .animation(.easeInOut(duration: 0.2), value: blockedTimeChangeConfirmationPending)
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
            // Slight bottom breathing room so the summary line doesn't crowd the banner.
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
        _ = awaitingPaymentRefreshTick
        return bookings.filter { booking in
            ProviderAwaitingPaymentTracker.isAwaitingEligible(status: booking.statusUpper, paidAt: booking.paidAt)
                && (booking.isCompletedAwaitingConsumerPayment
                    || awaitingPaymentTracker.requestedIds.contains(booking.id))
        }
    }

    private func awaitingPaymentRow(for booking: SimpleBookingDTO) -> some View {
        Button {
            shellNavigator.pushBooking(booking)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Awaiting Payment")
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                    Text(booking.consumerDisplayName)
                        .font(.provider(.headline))
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.provider(.subheadline, weight: .semibold))
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
                    scheduleZoomChangedViaPreset = true
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        zoomScale = preset.targetScale
                    }
                } label: {
                    Text(preset.title)
                        .font(.provider(.caption, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(
                            isPresetActive(preset)
                                ? ProviderOliveChromeStyle.zoomSegmentActiveForeground(colorScheme)
                                : ProviderOliveChromeStyle.zoomSegmentInactiveForeground(colorScheme)
                        )
                        .background {
                            if isPresetActive(preset) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(ProviderOliveChromeStyle.zoomSegmentActiveFill(colorScheme))
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
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                let display = displayForDailyScheduleBody()
                let intervals = display?.intervals ?? []
                let bounds = timelineBoundsForCurrentZoom(displayIntervals: intervals)
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
                    weekDayAvailabilityIntervals: availabilityIntervalsForVisibleWeek(),
                    weekDayEntirelyBlockedOff: entireDaysBlockedOffForVisibleWeek(),
                    isDayEntirelyBlockedOff: isEntireDayBlockedOff(for:),
                    weekDayTimeBlocks: timeBlocksForVisibleWeek(),
                    timeBlocks: timeBlocksOnSelectedDay,
                    blockTimeTapsEnabled: !isEditingAvailability && (display?.available ?? false),
                    onBookingTap: { shellNavigator.pushBooking($0) },
                    onAvailableMinuteTap: { minute in
                        prepareBlockSheet(forMinute: minute)
                        showingBlockTimeSheet = true
                    },
                    onWeekDayTap: { focusDay($0, scrollToFirstBooking: true) },
                    onMonthDayTap: { focusDay($0, scrollToFirstBooking: true) },
                    pendingScrollToBookingID: $pendingScrollToBookingID,
                    canvasViewerHeight: usesTallScheduleViewer ? canvasViewerHeight : nil,
                    appointmentDragEnabled: usesTallScheduleViewer && !isEditingAvailability,
                    editingMoveBookingID: $editingMoveBookingID,
                    activeMoveDragBookingID: $activeMoveDragBookingID,
                    timeChangeProposal: $timeChangeProposal,
                    onMoveBookingRequested: { movePromptBooking = $0 },
                    onBookingTimeChangeProposed: { booking, proposedTime in
                        timeChangeProposal = ScheduleAppointmentTimeChangeProposal(
                            booking: booking,
                            originalTime: booking.scheduledTime ?? proposedTime,
                            proposedTime: proposedTime
                        )
                    },
                    onPinchZoomSessionBegan: {
                        scheduleZoomChangedViaPreset = false
                    }
                )
            }
        }
    }

    private func inlineWeeklyDayEditorCard(for day: WeeklyScheduleDayKey) -> some View {
        let schedule = daySchedule(for: day)
        let dayAvailabilityBinding = Binding(
            get: { daySchedule(for: day).enabled },
            set: { newVal in
                var updated = daySchedule(for: day)
                updated.enabled = newVal
                if newVal, updated.intervals.isEmpty {
                    updated.intervals = [ScheduleIntervalDTO(start: "09:00", end: "17:00")]
                }
                setDaySchedule(updated, for: day)
            }
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(day.displayName)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)

                Spacer(minLength: 8)

                Toggle("Available", isOn: dayAvailabilityBinding)
                    .labelsHidden()
                    .tint(.providerOlive)
                    .accessibilityLabel("\(day.displayName) available for bookings")
            }

            if schedule.enabled {
                ForEach(schedule.intervals) { interval in
                    inlineIntervalRow(day: day, interval: interval)
                }

                Button {
                    addInterval(for: day)
                } label: {
                    Text("Add hours")
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(Color.providerOlive)
                }
                .buttonStyle(.plain)
            } else {
                Text("Unavailable")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
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
            if session.hasProviderProfile,
               isLoadingAvailability,
               displayForDailyScheduleBody() == nil
            {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading availability…")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                .padding(.vertical, 4)
            } else if let availabilityErrorText, isDayZoomTier {
                Text(availabilityErrorText)
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            if dayEnabled {
                let orphans = orphanTimeBlocks(slots: slots)
                if !orphans.isEmpty {
                    Text("Other blocked times")
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                    ForEach(orphans) { block in
                        blockedTimeRow(block: block)
                    }
                }
                if effectiveZoomTier == .day {
                    Text("Tap a booking for details. Hold to change its time. Pinch to zoom in for minute-level detail.")
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                if let trailing = bookingsOutsideAvailability(slots: slots, dayBookings: dayBookings), !trailing.isEmpty {
                    Text("Outside your set availability")
                        .font(.provider(.caption, weight: .semibold))
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
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
        }
    }

    @ViewBuilder
    private var weekScheduleSupplement: some View {
        Text("Swipe left or right to view the rest of your week. Hold a booking to drag it to a new time or day, or tap for details.")
            .font(.provider(.caption2))
            .foregroundStyle(Color.lavaShellCreamTertiary)
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
            blockedTimeChangeConfirmationPending = false
            editingMoveBookingID = nil
            activeMoveDragBookingID = nil
            NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
            await loadBookings()
            await refreshDayScheduleFromNetwork()
        } catch {
            if providerIsBenignRequestCancellation(error) { return }
            timeChangeErrorText = error.localizedDescription
        }
    }

    private func focusDay(_ day: Date, scrollToFirstBooking: Bool = false) {
        let anchor = mondayCalendar.startOfDay(for: .now)
        dayOffset = mondayCalendar.dateComponents([.day], from: anchor, to: mondayCalendar.startOfDay(for: day)).day ?? 0

        if scrollToFirstBooking {
            let firstAppointment = scheduleBookings
                .filter { $0.isSameCalendarDay(as: day, calendar: mondayCalendar) }
                .compactMap { ScheduleCanvasAppointment.from(booking: $0, calendar: mondayCalendar) }
                .sorted { $0.startMinute < $1.startMinute }
                .first
            pendingScrollToBookingID = firstAppointment?.id
        } else {
            pendingScrollToBookingID = nil
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            scheduleZoomChangedViaPreset = true
            zoomScale = ProviderScheduleZoom.defaultScale
        }
    }

    private func openMonthViewForSelectedDay() {
        syncMonthOffset(to: selectedDay)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            scheduleZoomChangedViaPreset = true
            zoomScale = ProviderScheduleZoom.Preset.month.targetScale
        }
    }

    /// Pinch only moves between day and minute; snap back if spring/rounding lands in week/month.
    private func enforcePinchOnlyScheduleZoom(_ newScale: CGFloat) {
        guard !scheduleZoomChangedViaPreset else { return }
        let corrected = ProviderScheduleZoom.clampedForPinch(newScale)
        guard abs(corrected - newScale) > 0.0001 else { return }
        zoomScale = corrected
    }

    private func syncMonthOffset(to day: Date) {
        let nowMonthStart = mondayCalendar.date(
            from: mondayCalendar.dateComponents([.year, .month], from: .now)
        ) ?? mondayCalendar.startOfDay(for: .now)
        let dayMonthStart = mondayCalendar.date(
            from: mondayCalendar.dateComponents([.year, .month], from: day)
        ) ?? mondayCalendar.startOfDay(for: day)
        monthOffset = mondayCalendar.dateComponents([.month], from: nowMonthStart, to: dayMonthStart).month ?? 0
    }

    // MARK: - Daily

    private var dateNavigationRow: some View {
        HStack(spacing: 10) {
            Button {
                stepDate(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.provider(.body, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(width: 40, height: 40)
                    .background { scheduleControlCircleBackground }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            if isDayZoomTier {
                Button(action: openMonthViewForSelectedDay) {
                    Text(periodTitle)
                        .font(.provider(.headline))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.lavaShellCream)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show month view")
                .accessibilityHint("Opens the monthly schedule for \(periodTitle)")
            } else {
                Text(periodTitle)
                    .font(.provider(.headline))
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                stepDate(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.provider(.body, weight: .semibold))
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
    private func weeklyDayKey(for date: Date) -> WeeklyScheduleDayKey {
        let w = mondayCalendar.component(.weekday, from: date)
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

    private var weeklyDayKeyForSelectedDay: WeeklyScheduleDayKey {
        weeklyDayKey(for: selectedDay)
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
            let d = selectedDay
            if mondayCalendar.isDateInToday(d)
                || mondayCalendar.isDateInTomorrow(d)
                || mondayCalendar.isDateInYesterday(d)
            {
                return dayTitleLabel + " · " + d.formatted(.dateTime.month(.wide).day().year())
            }
            return d.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
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
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    Text("Blocked")
                        .font(.provider(.subheadline, weight: .semibold))
                }
                Text(ProviderTimeBlockEditorSheet.displayTimeRange(startTime: block.startTime, endTime: block.endTime))
                    .font(.provider(.subheadline, weight: .medium))
                if let reason = block.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.provider(.caption))
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
                        .font(.provider(.body, weight: .medium))
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
                    .font(.provider(.subheadline, weight: .semibold))
                Spacer()
                Text(b.scheduleSlotTitle)
                    .font(.provider(.caption2, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(b.statusDisplayTint, in: Capsule())
            }
            Text(b.consumerDisplayName)
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
            Text(b.serviceDisplayName)
                .font(.provider(.subheadline))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text(b.barberDisplayName)
                .font(.provider(.caption))
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
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            if !timeBlocksOnSelectedDay.isEmpty {
                Text("Blocked times on this day")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                ForEach(timeBlocksOnSelectedDay) { block in
                    blockedTimeRow(block: block)
                }
                Text("You can remove blocks below. Tap an available hour to add a block when you are not editing weekly hours.")
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            if !dayBookings.isEmpty {
                Text("Existing bookings on this day:")
                    .font(.provider(.caption, weight: .semibold))
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

    private func daySchedule(for day: WeeklyScheduleDayKey) -> DayScheduleDTO {
        inlineWeeklySchedule.map { $0[day] } ?? .empty
    }

    private func setDaySchedule(_ day: DayScheduleDTO, for key: WeeklyScheduleDayKey) {
        guard var w = inlineWeeklySchedule else { return }
        w[key] = day
        inlineWeeklySchedule = w
        recomputeInlineWeeklyValidation()
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

    @ViewBuilder
    private func inlineIntervalRow(day: WeeklyScheduleDayKey, interval: ScheduleIntervalDTO) -> some View {
        HStack(spacing: 8) {
            inlineScheduleTimePicker(
                day: day,
                intervalId: interval.id,
                hhmm: interval.start,
                label: "Start",
                isStart: true
            )

            Text("–")
                .foregroundStyle(Color.lavaShellCreamSecondary)

            inlineScheduleTimePicker(
                day: day,
                intervalId: interval.id,
                hhmm: interval.end,
                label: "End",
                isStart: false
            )

            Spacer(minLength: 0)

            Button {
                removeInlineInterval(day: day, intervalId: interval.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove hours")
        }
    }

    private func inlineScheduleTimePicker(
        day: WeeklyScheduleDayKey,
        intervalId: String,
        hhmm: String,
        label: String,
        isStart: Bool
    ) -> some View {
        DatePicker(
            label,
            selection: Binding(
                get: { Self.scheduleDateFromHHMM(hhmm) },
                set: { newDate in
                    let value = Self.scheduleHHMMFromDate(newDate)
                    if isStart {
                        updateInlineInterval(day: day, intervalId: intervalId, start: value)
                    } else {
                        updateInlineInterval(day: day, intervalId: intervalId, end: value)
                    }
                }
            ),
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .accessibilityLabel(label)
    }

    private func addInterval(for day: WeeklyScheduleDayKey) {
        var current = daySchedule(for: day)
        let last = current.intervals.last
        var newStart = "09:00"
        if let last, let h = Int(last.end.split(separator: ":").first ?? "") {
            newStart = String(format: "%02d:00", min(h + 1, 23))
        }
        let startHour = Int(newStart.split(separator: ":").first ?? "9") ?? 9
        let newEnd = String(format: "%02d:00", min(startHour + 2, 23))
        current.intervals.append(ScheduleIntervalDTO(start: newStart, end: newEnd))
        current.enabled = true
        setDaySchedule(current, for: day)
    }

    private func removeInlineInterval(day: WeeklyScheduleDayKey, intervalId: String) {
        var current = daySchedule(for: day)
        current.intervals.removeAll { $0.id == intervalId }
        if current.intervals.isEmpty { current.enabled = false }
        setDaySchedule(current, for: day)
    }

    private func updateInlineInterval(
        day: WeeklyScheduleDayKey,
        intervalId: String,
        start: String? = nil,
        end: String? = nil
    ) {
        var current = daySchedule(for: day)
        guard let idx = current.intervals.firstIndex(where: { $0.id == intervalId }) else { return }
        if let start { current.intervals[idx].start = start }
        if let end { current.intervals[idx].end = end }
        setDaySchedule(current, for: day)
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
        let original = originalInlineWeeklySchedule ?? weekly
        let bookingConflicts = ProviderScheduleBookingConflicts.bookingsNewlyExcludedByScheduleChange(
            proposed: weekly,
            original: original,
            bookings: scheduleBookings,
            calendar: mondayCalendar
        )
        if !bookingConflicts.isEmpty {
            inlineSaveError = ProviderScheduleBookingConflicts.moveBookingsMessage(
                bookings: bookingConflicts,
                calendar: mondayCalendar,
                action: "saving this schedule"
            )
            return
        }
        savingInlineWeekly = true
        inlineSaveError = nil
        defer { savingInlineWeekly = false }
        do {
            try await ProviderAvailabilityManagementService.updateWeeklySchedule(barberId: barberId, schedule: weekly)
            cachedWeeklySchedule = weekly
            purgeStaleAvailabilityCacheAfterWeeklyScheduleSave(from: original, to: weekly)
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
        prepareBlockSheetForSelectedDay(startMinute: minute)
    }

    /// Opens the one-off block editor prefilled from the schedule's selected day.
    private func prepareBlockSheetForSelectedDay(startMinute: Int? = nil) {
        let cal = mondayCalendar
        let day = selectedDay
        let start: Date
        if let startMinute {
            blockSheetBlocksEntireDay = false
            start = cal.date(
                bySettingHour: startMinute / 60,
                minute: startMinute % 60,
                second: 0,
                of: day
            ) ?? day
        } else {
            blockSheetBlocksEntireDay = true
            let defaultStart = ProviderTimeBlockEditorSheet.defaultBlockStart(from: Date(), calendar: cal)
            start = ProviderTimeBlockEditorSheet.blockStart(
                on: day,
                defaultStartFromNow: defaultStart,
                calendar: cal
            )
        }
        blockSheetStart = start
        blockSheetDayStart = cal.startOfDay(for: start)
        blockSheetPresentationID = UUID()
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

    private func timelineBoundsForCurrentZoom(displayIntervals: [BarberAvailabilityIntervalDTO]) -> (start: Int, end: Int) {
        switch effectiveZoomTier {
        case .week:
            let weekIntervals = availabilityIntervalsForVisibleWeek().flatMap { $0 }
            return ProviderScheduleTimelineBounds.weekRange(
                intervals: weekIntervals,
                bookings: visibleBookingsForCurrentZoom(),
                calendar: mondayCalendar
            )
        case .day, .minute:
            if let exact = ProviderScheduleTimelineBounds.exactRange(for: displayIntervals) {
                return exact
            }
            return (0, 1)
        default:
            return ProviderScheduleTimelineBounds.range(for: displayIntervals)
        }
    }

    private func availabilityIntervalsForVisibleWeek() -> [[BarberAvailabilityIntervalDTO]] {
        (0 ..< 7).map { offset in
            guard let day = mondayCalendar.date(byAdding: .day, value: offset, to: weekStartMonday) else {
                return []
            }
            let apiIntervals = cachedAvailabilityIntervals(for: day)
            if !apiIntervals.isEmpty { return apiIntervals }
            return weeklyTemplateIntervals(for: day)
        }
    }

    private func entireDaysBlockedOffForVisibleWeek() -> [Bool] {
        (0 ..< 7).map { offset in
            guard let day = mondayCalendar.date(byAdding: .day, value: offset, to: weekStartMonday) else {
                return false
            }
            return isEntireDayBlockedOff(for: day)
        }
    }

    /// True only when a day is explicitly off — disabled in the weekly schedule or marked unavailable for that date.
    private func isEntireDayBlockedOff(for day: Date) -> Bool {
        let weekdayKey = weeklyDayKey(for: day)

        if isEditingAvailability, let schedule = inlineWeeklySchedule {
            return !schedule[weekdayKey].enabled
        }

        if let schedule = cachedWeeklySchedule {
            if !schedule[weekdayKey].enabled { return true }
            let key = dayKey(for: day)
            if let data = availabilityByDay[key],
               let raw = data.date?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
               normalizedBlockDate(raw) == key,
               data.available == false
            {
                return true
            }
            return false
        }

        let key = dayKey(for: day)
        if let data = availabilityByDay[key],
           let raw = data.date?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
           normalizedBlockDate(raw) == key
        {
            if data.available == false { return true }
            if (data.intervals ?? []).isEmpty { return true }
        }
        return false
    }

    private func purgeStaleAvailabilityCacheAfterWeeklyScheduleSave(from original: WeeklyScheduleDTO, to saved: WeeklyScheduleDTO) {
        var next = availabilityByDay
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = mondayCalendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        for dateKey in availabilityByDay.keys {
            guard let date = formatter.date(from: dateKey) else { continue }
            let weekdayKey = weeklyDayKey(for: date)
            if !original[weekdayKey].enabled, saved[weekdayKey].enabled {
                next.removeValue(forKey: dateKey)
            }
        }
        availabilityByDay = next
    }

    private func timeBlocksForVisibleWeek() -> [[BarberTimeBlockDTO]] {
        (0 ..< 7).map { offset in
            guard let day = mondayCalendar.date(byAdding: .day, value: offset, to: weekStartMonday) else {
                return []
            }
            return (timeBlocksByDay[dayKey(for: day)] ?? []).sorted { $0.startTime < $1.startTime }
        }
    }

    private var weekTimeBlocksPrefetchToken: String {
        "\(weekOffset)|\(session.barberProfile?.id ?? "none")|\(effectiveZoomTier == .week)"
    }

    private func prefetchVisibleWeekTimeBlocksIfNeeded() async {
        guard session.hasProviderProfile, let barberId = session.barberProfile?.id else { return }
        guard effectiveZoomTier == .week else { return }

        await withTaskGroup(of: Void.self) { group in
            for offset in 0 ..< 7 {
                guard let day = mondayCalendar.date(byAdding: .day, value: offset, to: weekStartMonday) else {
                    continue
                }
                let key = dayKey(for: day)
                group.addTask {
                    await prefetchSingleDayScheduleIfNeeded(barberId: barberId, date: day, dayKey: key)
                }
            }
        }
    }

    private func weeklyTemplateIntervals(for day: Date) -> [BarberAvailabilityIntervalDTO] {
        let schedule = isEditingAvailability ? inlineWeeklySchedule : cachedWeeklySchedule
        guard let schedule else { return [] }
        let entry = schedule[weeklyDayKey(for: day)]
        guard entry.enabled else { return [] }
        return entry.intervals.map {
            BarberAvailabilityIntervalDTO(id: $0.id, start: $0.start, end: $0.end)
        }
    }

    private func loadCachedWeeklyScheduleIfNeeded() async {
        guard session.hasProviderProfile, let barberId = session.barberProfile?.id else {
            cachedWeeklySchedule = nil
            return
        }
        do {
            cachedWeeklySchedule = try await ProviderAvailabilityManagementService.fetchWeeklySchedule(barberId: barberId)
        } catch {
            cachedWeeklySchedule = nil
        }
    }

    private func cachedAvailabilityIntervals(for day: Date) -> [BarberAvailabilityIntervalDTO] {
        let key = dayKey(for: day)
        guard let data = availabilityByDay[key] else { return [] }
        if let raw = data.date?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            guard normalizedBlockDate(raw) == key else { return [] }
        }
        return data.intervals ?? []
    }

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
