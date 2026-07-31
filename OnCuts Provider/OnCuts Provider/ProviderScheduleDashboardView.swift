import SwiftUI
import MapKit
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

/// `NSURLErrorCancelled` (-999) when a prior `URLSession` task is cancelled—**not** a user-visible failure.
private func providerIsBenignRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
}

/// Provider schedule hub: Monday-start weekly grid with 5-minute slots (parity with web `ProviderWeeklyScheduleGrid`).
struct ProviderScheduleDashboardView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(ProviderShellNavigator.self) private var shellNavigator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private let awaitingPaymentTracker = ProviderAwaitingPaymentTracker.shared

    @State private var awaitingPaymentRefreshTick: Int = 0
    @State private var weekOffset = 0
    @State private var bookings: [SimpleBookingDTO] = []
    @State private var weeklySchedule = WeeklyScheduleDTO()
    @State private var weeklyTimeBlocks: [BarberTimeBlockDTO] = []
    @State private var googleBusyTimes: [ProviderWeeklyScheduleBusyInterval] = []
    @State private var googleCalendarConnected = false

    @State private var isLoadingBookings = false
    @State private var isLoadingSchedule = false
    @State private var isLoadingBlocks = false
    @State private var errorText: String?

    @State private var showingBlockTimeSheet = false
    @State private var showingEditScheduleSheet = false
    @State private var showingPayoutSettingsSheet = false
    @State private var showingServicesOfferedSheet = false
    @State private var blockSheetDayStart: Date = .now
    @State private var blockSheetStart: Date = .now
    @State private var blockSheetEnd: Date = .now
    @State private var blockSheetBlocksEntireDay = false
    @State private var blockSheetPresentationID = UUID()
    @State private var deletingBlockIds: Set<String> = []
    @State private var scheduleChromeHeight: CGFloat = 0
    @State private var editingMoveBookingID: String?
    @State private var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    @State private var isSavingBookingMove = false
    @State private var discoveryLocationPin: BarberServiceLocationDTO?
    @State private var discoveryLocationLoadFailed = false
    /// Remaining commission-free card bookings for this operator (`GET /barbers/user/:id`).
    @State private var commissionFreeBookingsRemaining = 0
    /// Toggle On = device GPS tracking; Off = manual place input (`web_only`).
    @State private var shareDeviceLocation = true
    @State private var isTogglingDiscoveryLocation = false
    @State private var manualPlaceQuery = ""
    @State private var isSavingManualPlace = false
    @State private var placeSearch = ProviderPlaceSearchCompleter()
    @FocusState private var isManualPlaceFieldFocused: Bool

    private let scheduleVerticalPadding: CGFloat = 36

    private var mondayCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    private var todayAnchor: Date {
        mondayCalendar.startOfDay(for: .now)
    }

    private var weekStartMonday: Date {
        ProviderWeeklyScheduleGridEngine.weekStartMonday(
            from: todayAnchor,
            weekOffset: weekOffset,
            calendar: mondayCalendar
        )
    }

    private var scheduleBookings: [SimpleBookingDTO] {
        bookings.filter(\.isVisibleOnMainSchedule)
    }

    private var weekUpcomingBookings: [SimpleBookingDTO] {
        let weekEnd = mondayCalendar.date(byAdding: .day, value: 7, to: weekStartMonday) ?? weekStartMonday
        return scheduleBookings.filter { booking in
            guard ProviderBookingStatusDisplay.isUpcomingScheduleAppointment(booking) else { return false }
            guard let scheduled = booking.providerEffectiveScheduledTime else { return false }
            return scheduled >= weekStartMonday && scheduled < weekEnd
        }
    }

    private var weekEndExclusive: Date {
        mondayCalendar.date(byAdding: .day, value: 7, to: weekStartMonday) ?? weekStartMonday
    }

    private var bookingsBeforeViewedWeekCount: Int {
        scheduleBookings.filter { booking in
            guard ProviderBookingStatusDisplay.countsForWeekNavigationTicker(booking) else { return false }
            guard let scheduled = booking.providerEffectiveScheduledTime else { return false }
            return scheduled < weekStartMonday
        }.count
    }

    private var bookingsAfterViewedWeekCount: Int {
        scheduleBookings.filter { booking in
            guard ProviderBookingStatusDisplay.countsForWeekNavigationTicker(booking) else { return false }
            guard let scheduled = booking.providerEffectiveScheduledTime else { return false }
            return scheduled >= weekEndExclusive
        }.count
    }

    private var gridModel: ProviderWeeklyScheduleGridModel {
        ProviderWeeklyScheduleGridEngine.buildModel(
            weekOffset: weekOffset,
            today: todayAnchor,
            calendar: mondayCalendar,
            weeklySchedule: weeklySchedule,
            weeklyTimeBlocks: weeklyTimeBlocks,
            bookings: scheduleBookings,
            googleBusyTimes: googleBusyTimes
        )
    }

    private var isGridLoading: Bool {
        isLoadingSchedule || isLoadingBlocks
    }

    private func scheduleGridViewportHeight(in geometry: GeometryProxy) -> CGFloat {
        let dayHeaderHeight = ProviderWeeklyScheduleGridMetrics.dayHeaderRowHeight
        let available = geometry.size.height
            - scheduleChromeHeight
            - scheduleVerticalPadding
            - dayHeaderHeight
            - 12
        return max(ProviderWeeklyScheduleGridMetrics.minimumGridHeight, available)
    }

    var body: some View {
        GeometryReader { geometry in
            scheduleContent(gridViewportHeight: scheduleGridViewportHeight(in: geometry))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: session.barberProfile?.id) {
            await reloadAll()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await loadCommissionFreeRemaining() }
        }
        .task(id: weekOffset) {
            cancelBookingMove()
            await loadWeekTimeBlocks()
            await loadGoogleBusyTimes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerBookingsChanged)) { _ in
            Task {
                await loadBookings()
                await loadCommissionFreeRemaining()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerCommissionFreeQuotaChanged)) { _ in
            Task { await loadCommissionFreeRemaining() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerAvailabilityChanged)) { _ in
            Task {
                await loadWeeklySchedule()
                await loadWeekTimeBlocks()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProviderAwaitingPaymentTracker.didChangeNotification)) { _ in
            awaitingPaymentRefreshTick &+= 1
        }
        .toolbar(.hidden, for: .navigationBar)
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
                    initialEnd: blockSheetBlocksEntireDay ? nil : blockSheetEnd,
                    bookings: ProviderScheduleBookingConflicts.upcomingBookings(
                        from: scheduleBookings,
                        calendar: mondayCalendar
                    ),
                    calendar: mondayCalendar,
                    onSaved: { _ in
                        Task {
                            await loadWeekTimeBlocks()
                            NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
                        }
                    }
                )
                .id(blockSheetPresentationID)
            }
        }
        .sheet(isPresented: $showingEditScheduleSheet) {
            hubPullUpSheet(close: { showingEditScheduleSheet = false }) {
                ProviderAvailabilityEditorView(presentation: .weeklyEditorOnly)
            }
        }
        .sheet(isPresented: $showingPayoutSettingsSheet) {
            hubPullUpSheet(close: { showingPayoutSettingsSheet = false }) {
                ProviderPayoutSettingsView()
            }
        }
        .sheet(isPresented: $showingServicesOfferedSheet) {
            hubPullUpSheet(close: { showingServicesOfferedSheet = false }) {
                ProviderBarberServicesView()
            }
        }
    }

    /// Shared pull-up chrome for hub actions (Edit Schedule / Payouts / Services Offered).
    private func hubPullUpSheet<Content: View>(
        close: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", action: close)
                            .font(.provider(.body, weight: .semibold))
                    }
                }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
        .presentationBackground(OnCutsLavaMidnight.color)
    }

    // MARK: - Content

    private func scheduleContent(gridViewportHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                awaitingPaymentBanner
                    .simultaneousGesture(manualPlaceKeyboardDismissTap)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 12) {
                        if session.hasProviderProfile {
                            discoveryLocationStatusLine
                        }
                        weekNavigationRow
                            .simultaneousGesture(manualPlaceKeyboardDismissTap)
                        if session.hasProviderProfile {
                            scheduleAvailabilityActionsRow
                                .simultaneousGesture(manualPlaceKeyboardDismissTap)
                        }
                        summaryLine
                            .simultaneousGesture(manualPlaceKeyboardDismissTap)
                    }
                    .opacity(editingMoveBookingID == nil ? 1 : 0)
                    .allowsHitTesting(editingMoveBookingID == nil)
                    .accessibilityHidden(editingMoveBookingID != nil)

                    if editingMoveBookingID != nil {
                        bookingMoveChromeRow
                            .simultaneousGesture(manualPlaceKeyboardDismissTap)
                    }
                }
                if let errorText {
                    Text(errorText)
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .simultaneousGesture(manualPlaceKeyboardDismissTap)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ProviderScheduleChromeHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            }

            ProviderWeeklyScheduleGrid(
                model: gridModel,
                weekOffset: weekOffset,
                isLoading: isGridLoading,
                viewportHeight: gridViewportHeight,
                appointmentDragEnabled: session.hasProviderProfile,
                onPullToRefresh: { await reloadAll() },
                editingMoveBookingID: $editingMoveBookingID,
                onUnblockTime: { blockId in
                    Task { await deleteTimeBlock(blockId: blockId) }
                },
                onViewBooking: { booking in
                    // Leave move mode so the booking is interactive again after a drag.
                    editingMoveBookingID = nil
                    timeChangeProposal = nil
                    shellNavigator.pushBooking(booking)
                },
                onMoveBookingRequested: { booking in
                    editingMoveBookingID = booking.id
                    timeChangeProposal = nil
                },
                onBookingTimeChangeProposed: { booking, proposedDate, targetsPast in
                    timeChangeProposal = ScheduleAppointmentTimeChangeProposal(
                        booking: booking,
                        originalTime: booking.providerEffectiveScheduledTime ?? proposedDate,
                        proposedTime: proposedDate,
                        targetsPastTime: targetsPast
                    )
                },
                onBookingMoveProposalCleared: {
                    timeChangeProposal = nil
                }
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, -ProviderWeeklyScheduleGridMetrics.scheduleOuterHorizontalInset)
            .simultaneousGesture(manualPlaceKeyboardDismissTap)
        }
        .onPreferenceChange(ProviderScheduleChromeHeightPreferenceKey.self) { scheduleChromeHeight = $0 }
    }

    private var manualPlaceKeyboardDismissTap: some Gesture {
        TapGesture().onEnded {
            guard isManualPlaceFieldFocused else { return }
            dismissManualPlaceKeyboard()
        }
    }

    private func dismissManualPlaceKeyboard() {
        isManualPlaceFieldFocused = false
        placeSearch.clearResults()
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    // MARK: - Chrome

    private var canSaveBookingMove: Bool {
        guard let proposal = timeChangeProposal else { return false }
        return ScheduleAppointmentDrag.isSaveEligibleMove(
            proposed: proposal.proposedTime,
            original: proposal.originalTime,
            targetsPast: proposal.targetsPastTime
        )
    }

    private var bookingMoveChromeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let proposal = timeChangeProposal {
                Text("Move to \(proposal.proposedTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(maxWidth: .infinity, alignment: .center)

                if proposal.targetsPastTime {
                    Text("You can't place this booking at a date and time that has already passed. Choose a future slot or tap Cancel.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if let bookingID = editingMoveBookingID,
                      let booking = scheduleBookings.first(where: { $0.id == bookingID }) {
                Text("Moving \(booking.consumerDisplayName)")
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 10) {
                Button(action: cancelBookingMove) {
                    Text("Cancel")
                        .font(.provider(size: 14, weight: .medium))
                        .foregroundStyle(Color.providerScheduleActionForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.providerScheduleActionBackground)
                                .shadow(color: Color.providerScheduleActionShadow, radius: 1, x: 0, y: 1)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.providerScheduleActionBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isSavingBookingMove)

                Button {
                    guard let proposal = timeChangeProposal else { return }
                    Task { await confirmBookingMove(proposal) }
                } label: {
                    Group {
                        if isSavingBookingMove {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save Change")
                                .font(.provider(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(canSaveBookingMove ? Color.providerOlive : Color.providerOlive.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSaveBookingMove || isSavingBookingMove)
            }
            .padding(.top, 8)
            .frame(maxWidth: 448)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background { scheduleChromeTrackBackground }
    }

    private var discoveryLocationStatusLine: some View {
        VStack(spacing: 8) {
            if commissionFreeBookingsRemaining > 0 {
                (
                    Text("Commissionless Bookings left: ")
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    + Text("\(commissionFreeBookingsRemaining)")
                        .fontWeight(.bold)
                        .foregroundStyle(Color.lavaShellCream)
                )
                .font(.provider(.caption))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            }

            if shareDeviceLocation {
                HStack(spacing: 6) {
                    Text(discoveryLocationPlaceText)
                        .lineLimit(1)
                    if isTogglingDiscoveryLocation {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.lavaShellCreamSecondary)
                    }
                }
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                manualDiscoveryPlaceSearch
            }

            ZStack {
                Text(shareDeviceLocation
                      ? "Toggle off to turn off device tracking"
                      : "Toggle on to track your device")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 52)

                HStack {
                    Spacer(minLength: 0)
                    Toggle("", isOn: $shareDeviceLocation)
                        .labelsHidden()
                        .tint(.providerOlive)
                        .disabled(isTogglingDiscoveryLocation || isSavingManualPlace || discoveryLocationPin == nil)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(manualPlaceKeyboardDismissTap)
            .onChange(of: shareDeviceLocation) { oldValue, newValue in
                guard oldValue != newValue else { return }
                guard !isTogglingDiscoveryLocation else { return }
                // Server `web_only` is the inverse of sharing device location.
                let expectedWebOnly = !newValue
                guard discoveryLocationPin?.serviceLocationWebOnly != expectedWebOnly else { return }
                Task { await setShareDeviceLocation(newValue) }
            }
            .padding(.horizontal, 8)
        }
        .task(id: session.barberProfile?.id) {
            await loadDiscoveryLocationStatus(seedManualField: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerDiscoveryLocationChanged)) { _ in
            Task { await loadDiscoveryLocationStatus(seedManualField: false) }
        }
        .onChange(of: shareDeviceLocation) { _, sharingDevice in
            if sharingDevice {
                placeSearch.clearResults()
                isManualPlaceFieldFocused = false
            } else {
                manualPlaceQuery = ""
                placeSearch.clearResults()
                isManualPlaceFieldFocused = true
            }
        }
    }

    private var manualDiscoveryPlaceSearch: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $manualPlaceQuery,
                    prompt: Text("Manually enter a location where you conduct service")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                )
                .font(.provider(.subheadline))
                .foregroundStyle(Color.lavaShellCream)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isManualPlaceFieldFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await saveManualPlaceFromTypedQuery() }
                }
                .onChange(of: manualPlaceQuery) { _, newValue in
                    placeSearch.queryFragment = newValue
                }

                if isSavingManualPlace || placeSearch.isSearching {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.lavaShellCreamSecondary)
                } else if !manualPlaceQuery.isEmpty {
                    Button {
                        manualPlaceQuery = ""
                        placeSearch.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear place search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color.providerScheduleActionBackground,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.providerScheduleActionBorder, lineWidth: 0.8)
            )

            if isManualPlaceFieldFocused, !placeSearch.suggestionsSuppressed, !placeSearch.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(placeSearch.results.enumerated()), id: \.offset) { index, completion in
                        Button {
                            Task { await selectManualPlace(completion) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(.provider(.subheadline, weight: .semibold))
                                    .foregroundStyle(Color.lavaShellCream)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.provider(.caption))
                                        .foregroundStyle(Color.lavaShellCreamSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSavingManualPlace)

                        if index < placeSearch.results.count - 1 {
                            Divider()
                                .overlay(Color.providerElevatedSurfaceStroke)
                        }
                    }
                }
                .background(
                    Color.providerElevatedSurface,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.providerElevatedSurfaceStroke, lineWidth: 0.8)
                )
            }
        }
        .padding(.horizontal, 4)
    }

    private var discoveryLocationPlaceText: String {
        if discoveryLocationLoadFailed {
            return "Location unavailable"
        }
        guard let pin = discoveryLocationPin else {
            return "Loading location…"
        }
        let label = pin.serviceLocationLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            return label
        }
        if pin.hasCoordinates {
            return "Public pin set · \(pin.sourceDisplayName)"
        }
        return "No public pin yet"
    }

    private func seedManualPlaceQueryFromPin() {
        let label = discoveryLocationPin?.serviceLocationLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            manualPlaceQuery = label
            placeSearch.dismissSuggestions(keepingQuery: label)
        } else {
            placeSearch.clearResults()
        }
    }

    private var summaryLine: some View {
        Text(summaryText)
            .font(.provider(.subheadline))
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private var summaryText: String {
        let n = weekUpcomingBookings.count
        let noun = n == 1 ? "appointment" : "appointments"
        if weekOffset == 0 {
            return "\(n) \(noun) this week"
        }
        return "\(n) \(noun) that week"
    }

    private var weekNavigationRow: some View {
        HStack(spacing: 10) {
            Button { weekOffset -= 1 } label: {
                Image(systemName: "chevron.left")
                    .font(.provider(.body, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(width: 40, height: 40)
                    .background { scheduleControlCircleBackground }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if bookingsBeforeViewedWeekCount > 0 {
                    weekNavigationTickerBadge(bookingsBeforeViewedWeekCount)
                        .offset(x: 5, y: -5)
                }
            }
            .accessibilityLabel(
                bookingsBeforeViewedWeekCount > 0
                    ? "Previous week, \(bookingsBeforeViewedWeekCount) booking\(bookingsBeforeViewedWeekCount == 1 ? "" : "s")"
                    : "Previous week"
            )

            Spacer()

            VStack(spacing: 2) {
                Text(weekRangeTitle)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                if weekOffset != 0 {
                    Button("This Week") {
                        withAnimation(.easeInOut(duration: 0.2)) { weekOffset = 0 }
                    }
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.providerOlive)
                }
            }

            Spacer()

            Button { weekOffset += 1 } label: {
                Image(systemName: "chevron.right")
                    .font(.provider(.body, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(width: 40, height: 40)
                    .background { scheduleControlCircleBackground }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if bookingsAfterViewedWeekCount > 0 {
                    weekNavigationTickerBadge(bookingsAfterViewedWeekCount)
                        .offset(x: 5, y: -5)
                }
            }
            .accessibilityLabel(
                bookingsAfterViewedWeekCount > 0
                    ? "Next week, \(bookingsAfterViewedWeekCount) booking\(bookingsAfterViewedWeekCount == 1 ? "" : "s")"
                    : "Next week"
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background { scheduleChromeTrackBackground }
    }

    @ViewBuilder
    private func weekNavigationTickerBadge(_ count: Int) -> some View {
        let label = count > 99 ? "99+" : "\(count)"
        let text = Text(label)
            .font(.provider(size: 11, weight: .bold))
            .foregroundStyle(.white)

        if count > 9 {
            text
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.92), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.lavaShellCream.opacity(0.85), lineWidth: 1.5)
                )
        } else {
            text
                .frame(minWidth: 18, minHeight: 18)
                .background(Color.red.opacity(0.92), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.lavaShellCream.opacity(0.85), lineWidth: 1.5)
                )
        }
    }

    private var scheduleAvailabilityActionsRow: some View {
        HStack(spacing: 8) {
            scheduleActionButton(title: "Edit Schedule") {
                if let barberId = session.barberProfile?.id {
                    ProviderAvailabilityEditorPrefetch.begin(barberId: barberId)
                }
                showingEditScheduleSheet = true
            }
            schedulePayoutsActionButton {
                showingPayoutSettingsSheet = true
            }
            scheduleActionButton(title: "Services Offered") {
                showingServicesOfferedSheet = true
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func scheduleActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.provider(size: 14, weight: .medium))
                .foregroundStyle(Color.providerScheduleActionForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.providerScheduleActionBackground)
                        .shadow(color: Color.providerScheduleActionShadow, radius: 1, x: 0, y: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.providerScheduleActionBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    /// Stripe-branded hub CTA (web `#635BFF`) — opens Payout Settings.
    private func schedulePayoutsActionButton(action: @escaping () -> Void) -> some View {
        let stripePurple = Color(red: 99 / 255, green: 91 / 255, blue: 255 / 255)
        return Button(action: action) {
            Text("Payouts")
                .font(.provider(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(stripePurple)
                        .shadow(color: stripePurple.opacity(0.35), radius: 2, x: 0, y: 1)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Payouts")
    }

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
            .overlay(Circle().strokeBorder(Color.providerScheduleControlStroke, lineWidth: 0.6))
    }

    private var weekRangeTitle: String {
        let start = weekStartMonday
        let end = mondayCalendar.date(byAdding: .day, value: 6, to: start) ?? start
        let startFmt = start.formatted(.dateTime.month(.abbreviated).day())
        let endFmt = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(startFmt) – \(endFmt)"
    }

    // MARK: - Awaiting payment

    @ViewBuilder
    private var awaitingPaymentBanner: some View {
        let awaiting = awaitingPaymentBookings
        if !awaiting.isEmpty {
            VStack(spacing: 8) {
                ForEach(awaiting) { booking in
                    awaitingPaymentRow(for: booking)
                }
            }
            .padding(.bottom, 2)
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
                    Text(booking.consumerDisplayName)
                        .font(.provider(.headline))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.providerOlive.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.providerOlive.opacity(0.55), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Block time sheet prep

    private func prepareBlockSheet(dateKey: String, startHHMM: String, endHHMM: String) {
        blockSheetBlocksEntireDay = false
        let day = dateFromKey(dateKey)
        blockSheetDayStart = day
        blockSheetStart = dateTime(on: day, hhmm: startHHMM)
        blockSheetEnd = dateTime(on: day, hhmm: endHHMM)
        blockSheetPresentationID = UUID()
    }

    private func dateFromKey(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return todayAnchor }
        return mondayCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            ?? todayAnchor
    }

    private func dateTime(on day: Date, hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":")
        let hour = parts.first.flatMap { Int($0) } ?? 0
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return mondayCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    // MARK: - Data loading

    private func reloadAll() async {
        await loadBookings()
        await loadWeeklySchedule()
        await loadWeekTimeBlocks()
        await loadGoogleCalendarStatusAndBusyTimes()
        await loadDiscoveryLocationStatus(seedManualField: false)
        await loadCommissionFreeRemaining()
    }

    private func loadCommissionFreeRemaining() async {
        guard session.hasProviderProfile,
              let userId = session.authUser?.id.trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty else {
            commissionFreeBookingsRemaining = 0
            return
        }
        do {
            let remaining = try await ProviderBarberServicesService.fetchCommissionFreeBookingsRemaining(
                userId: userId
            )
            try Task.checkCancellation()
            commissionFreeBookingsRemaining = remaining
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            // Keep last known count; missing field / transient errors should not blank the hub.
        }
    }

    private func loadDiscoveryLocationStatus(seedManualField: Bool) async {
        guard session.hasProviderProfile else {
            discoveryLocationPin = nil
            discoveryLocationLoadFailed = false
            shareDeviceLocation = true
            return
        }
        do {
            let pin = try await ProviderBarberServiceLocationService.fetch()
            discoveryLocationPin = pin
            shareDeviceLocation = !pin.serviceLocationWebOnly
            discoveryLocationLoadFailed = false
            // Only seed on initial profile load — never after a toggle, or the prior pin refills the cleared field.
            if seedManualField, pin.serviceLocationWebOnly {
                seedManualPlaceQueryFromPin()
            }
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            discoveryLocationLoadFailed = true
        }
    }

    private func setShareDeviceLocation(_ enabled: Bool) async {
        guard session.hasProviderProfile, !isTogglingDiscoveryLocation else { return }
        let previousPin = discoveryLocationPin
        let previousShare = !(previousPin?.serviceLocationWebOnly ?? false)
        isTogglingDiscoveryLocation = true
        defer { isTogglingDiscoveryLocation = false }
        do {
            // Manual lock is the inverse of sharing device location.
            let updated = try await ProviderServiceLocationSync.setUseManualLocation(!enabled)
            discoveryLocationPin = updated
            shareDeviceLocation = !updated.serviceLocationWebOnly
            discoveryLocationLoadFailed = false
            if updated.serviceLocationWebOnly {
                manualPlaceQuery = ""
                placeSearch.clearResults()
            }
            NotificationCenter.default.post(name: .providerDiscoveryLocationChanged, object: nil)
        } catch {
            discoveryLocationPin = previousPin
            shareDeviceLocation = previousShare
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func selectManualPlace(_ completion: MKLocalSearchCompletion) async {
        guard session.hasProviderProfile, !isSavingManualPlace else { return }
        isSavingManualPlace = true
        defer { isSavingManualPlace = false }
        do {
            let resolved = try await placeSearch.resolveCoordinates(for: completion)
            let updated = try await ProviderBarberServiceLocationService.update(
                latitude: resolved.coordinate.latitude,
                longitude: resolved.coordinate.longitude,
                label: resolved.label,
                source: "manual",
                webOnly: true
            )
            discoveryLocationPin = updated
            shareDeviceLocation = false
            manualPlaceQuery = resolved.label
            placeSearch.dismissSuggestions(keepingQuery: resolved.label)
            isManualPlaceFieldFocused = false
            discoveryLocationLoadFailed = false
            NotificationCenter.default.post(name: .providerDiscoveryLocationChanged, object: nil)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveManualPlaceFromTypedQuery() async {
        let query = manualPlaceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, session.hasProviderProfile, !isSavingManualPlace else { return }
        if let first = placeSearch.results.first {
            await selectManualPlace(first)
            return
        }
        isSavingManualPlace = true
        defer { isSavingManualPlace = false }
        do {
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.geocodeAddressString(query)
            guard let place = placemarks.first, let location = place.location else {
                errorText = "Couldn’t find that place. Try selecting a suggestion."
                return
            }
            let label = [
                place.name,
                place.locality,
                place.administrativeArea,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: ", ")

            let updated = try await ProviderBarberServiceLocationService.update(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                label: label.isEmpty ? query : label,
                source: "manual",
                webOnly: true
            )
            discoveryLocationPin = updated
            shareDeviceLocation = false
            manualPlaceQuery = updated.serviceLocationLabel ?? query
            placeSearch.dismissSuggestions(keepingQuery: manualPlaceQuery)
            isManualPlaceFieldFocused = false
            discoveryLocationLoadFailed = false
            NotificationCenter.default.post(name: .providerDiscoveryLocationChanged, object: nil)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadBookings() async {
        guard session.hasProviderProfile else {
            bookings = []
            errorText = nil
            awaitingPaymentTracker.reconcile(with: [])
            return
        }
        isLoadingBookings = true
        defer { isLoadingBookings = false }
        do {
            let list = try await ProviderBookingsService.listBookings(role: "barber")
            try Task.checkCancellation()
            bookings = list
            awaitingPaymentTracker.reconcile(with: list)
            errorText = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func loadWeeklySchedule() async {
        guard let barberId = session.barberProfile?.id else {
            weeklySchedule = WeeklyScheduleDTO()
            return
        }
        isLoadingSchedule = true
        defer { isLoadingSchedule = false }
        do {
            weeklySchedule = try await ProviderAvailabilityManagementService.fetchWeeklySchedule(barberId: barberId)
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            weeklySchedule = WeeklyScheduleDTO()
        }
    }

    private func loadWeekTimeBlocks() async {
        guard let barberId = session.barberProfile?.id else {
            weeklyTimeBlocks = []
            return
        }
        isLoadingBlocks = true
        defer { isLoadingBlocks = false }
        let start = weekStartMonday
        let end = mondayCalendar.date(byAdding: .day, value: 6, to: start) ?? start
        let startKey = dateKey(for: start)
        let endKey = dateKey(for: end)
        do {
            weeklyTimeBlocks = try await ProviderAvailabilityManagementService.listTimeBlocks(
                barberId: barberId,
                startDate: startKey,
                endDate: endKey
            )
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            weeklyTimeBlocks = []
        }
    }

    private func loadGoogleCalendarStatusAndBusyTimes() async {
        do {
            let status = try await ProviderAvailabilityManagementService.googleCalendarStatus()
            googleCalendarConnected = status.connected
            if status.connected {
                await loadGoogleBusyTimes()
            } else {
                googleBusyTimes = []
            }
        } catch {
            googleCalendarConnected = false
            googleBusyTimes = []
        }
    }

    private func loadGoogleBusyTimes() async {
        guard googleCalendarConnected else {
            googleBusyTimes = []
            return
        }
        let start = weekStartMonday
        let end = mondayCalendar.date(byAdding: .day, value: 21, to: start) ?? start
        do {
            googleBusyTimes = try await ProviderAvailabilityManagementService.googleCalendarBusyTimes(
                startDate: start,
                endDate: end
            )
        } catch {
            googleBusyTimes = []
        }
    }

    private func deleteTimeBlock(blockId: String) async {
        guard let barberId = session.barberProfile?.id else { return }
        guard !deletingBlockIds.contains(blockId) else { return }
        deletingBlockIds.insert(blockId)
        defer { deletingBlockIds.remove(blockId) }
        do {
            try await ProviderAvailabilityManagementService.deleteTimeBlock(barberId: barberId, blockId: blockId)
            await loadWeekTimeBlocks()
            NotificationCenter.default.post(name: .providerAvailabilityChanged, object: nil)
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? "Couldn’t unblock that time."
        }
    }

    private func cancelBookingMove() {
        editingMoveBookingID = nil
        timeChangeProposal = nil
    }

    private func confirmBookingMove(_ proposal: ScheduleAppointmentTimeChangeProposal) async {
        guard !isSavingBookingMove else { return }
        isSavingBookingMove = true
        defer { isSavingBookingMove = false }
        do {
            try await ProviderBookingsService.reschedule(
                id: proposal.booking.id,
                scheduledTimeISO: proposal.proposedTime.campusCutsISO8601String(),
                location: proposal.booking.location,
                notes: proposal.booking.notes
            )
            cancelBookingMove()
            await loadBookings()
            NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
        } catch {
            guard !providerIsBenignRequestCancellation(error) else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? "Couldn’t move that appointment."
        }
    }

    private func dateKey(for date: Date) -> String {
        let c = mondayCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

private enum ProviderScheduleChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
