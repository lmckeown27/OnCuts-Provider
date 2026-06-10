import SwiftUI

// MARK: - Request cancellation (SwiftUI `.task` / `refreshable` overlap)

/// `NSURLErrorCancelled` (-999) when a prior `URLSession` task is cancelled—**not** a user-visible failure.
private func providerIsBenignRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
}

// MARK: - Schedule modes (BarberPage-style)

private enum ProviderScheduleMode: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    var id: String { rawValue }
}

/// Main **dashboard** after sign-in: schedule card with Daily / Weekly / Monthly (web `DashboardView` analogue).
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

    @State private var mode: ProviderScheduleMode = .daily
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

    private var mondayCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    /// Shared track behind the **Daily / Weekly / Monthly** rail and date navigation row.
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
        ScrollView {
            scheduleContent
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
    }

    // MARK: - Schedule content (full-page, no card chrome)

    /// Full-bleed schedule under the dashboard header. Replaces the prior "card" look so the
    /// Daily / Weekly / Monthly view fills the entire page below `dashboardHeaderBar`.
    private var scheduleContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Sits between the shell's header bar (Chats / role chip / Requests tray /
            // profile menu) and the "[x] appointments" summary line. Renders one row
            // per booking the user has locally flipped to "Awaiting Payment" via the
            // detail screen. Hidden when the tracker has nothing to surface.
            awaitingPaymentBanner
            jumpChip
            summaryLine
            modePicker
            dateNavigationRow
            if session.hasProviderProfile, mode == .daily {
                manageAvailabilityOrEditControls
            }
            // Swipe-to-change-mode only on this region so it never steals taps from the picker / chevrons.
            // `highPriorityGesture` (vs `simultaneousGesture`) is critical: the Weekly rows and Monthly cells
            // are `Button`s that reset `mode = .daily` on tap. With a *simultaneous* drag, a horizontal swipe
            // could fail the dominance check and still register as a child tap — sending the user from Weekly
            // (or Monthly) back to Daily instead of advancing to Monthly. High-priority swipes claim the touch
            // once movement crosses `minimumDistance`, cancelling those child taps cleanly.
            VStack(alignment: .leading, spacing: 12) {
                modeContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .highPriorityGesture(scheduleSwipeGesture)
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
                    switch mode {
                    case .daily: dayOffset = 0
                    case .weekly: weekOffset = 0
                    case .monthly: monthOffset = 0
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
        switch mode {
        case .daily: dayOffset != 0
        case .weekly: weekOffset != 0
        case .monthly: monthOffset != 0
        }
    }

    private var jumpChipTitle: String {
        switch mode {
        case .daily: "Today"
        case .weekly: "This week"
        case .monthly: "This month"
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
        let n = visibleBookingsForCurrentMode().count
        let noun = n == 1 ? "appointment" : "appointments"
        switch mode {
        case .daily:
            return "\(n) \(noun) · \(dayTitleLabel)"
        case .weekly:
            let that = weekOffset != 0 ? "that week" : "this week"
            return "\(n) \(noun) \(that)"
        case .monthly:
            let that = monthOffset != 0 ? "that month" : "this month"
            return "\(n) \(noun) \(that)"
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(ProviderScheduleMode.allCases) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(
                            mode == m ? Color.lavaShellCream : Color.lavaShellCream.opacity(0.88)
                        )
                        .background {
                            if mode == m {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.providerOlive.opacity(0.62))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .padding(4)
        .background { scheduleChromeTrackBackground }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schedule view")
    }

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

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .daily:
            dailyBody
        case .weekly:
            weeklyBody
        case .monthly:
            monthlyBody
        }
    }

    /// Lowered `minimumDistance` (30) so the gesture engages before a slow swipe gets misclassified as a tap
    /// on a `weeklyRow` / `monthlyCell` / `dailySlotRow` button. The dominance check uses a proportional ratio
    /// (`> abs(dy) * 1.3`) instead of the previous `+20` literal so honest, slightly-diagonal swipes still
    /// register reliably — fixing the "Weekly → swipe → Daily" regression.
    private var scheduleSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                let dx = v.translation.width
                let dy = v.translation.height
                guard abs(dx) > 50, abs(dx) > abs(dy) * 1.3 else { return }
                advanceMode(dx > 0 ? -1 : 1)
            }
    }

    // MARK: - Daily

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
        switch mode {
        case .daily:
            return dayTitleLabel + " · " + selectedDay.formatted(.dateTime.month(.wide).day().year())
        case .weekly:
            let (a, b) = weekRangeTitles()
            return "\(a) – \(b)"
        case .monthly:
            return monthAnchor.formatted(.dateTime.month(.wide).year())
        }
    }

    private var dailyBody: some View {
        let dayBookings = visibleBookingsForCurrentMode().sorted {
            ($0.scheduledTime ?? .distantFuture) < ($1.scheduledTime ?? .distantFuture)
        }
        let display = displayForDailyScheduleBody()
        let intervals = display?.intervals ?? []
        let dayEnabled = (display?.available ?? false) && !intervals.isEmpty
        let slots = dayEnabled ? generateHourlySlots(from: intervals) : []
        return VStack(alignment: .leading, spacing: 10) {
            if !session.hasProviderProfile {
                Text("Link your CampusCuts barber profile on the web to load appointments here.")
                    .font(.footnote)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            } else if isEditingAvailability {
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
            } else if dayEnabled {
                if let availabilityErrorText {
                    Text(availabilityErrorText)
                        .font(.caption)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                ForEach(slots, id: \.start) { slot in
                    dailySlotRow(slot: slot, booking: booking(for: slot, in: dayBookings), blockTimeTapsEnabled: !isEditingAvailability)
                }
                let orphans = orphanTimeBlocks(slots: slots)
                if !orphans.isEmpty {
                    Text("Other blocked times")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .padding(.top, 4)
                    ForEach(orphans) { block in
                        blockedTimeRow(block: block)
                    }
                }
                if isEditingAvailability {
                    Text("Finish saving or cancel to tap an hour and block time on the calendar.")
                        .font(.caption2)
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .padding(.top, 2)
                } else {
                    Text("Tap an available hour to block it.")
                        .font(.caption2)
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .padding(.top, 2)
                }
                if let trailing = bookingsOutsideAvailability(slots: slots, dayBookings: dayBookings), !trailing.isEmpty {
                    Text("Outside your set availability")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .padding(.top, 6)
                    ForEach(trailing) { b in
                        Button {
                            shellNavigator.pushBooking(b)
                        } label: {
                            outsideAvailabilityRow(b)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if display != nil {
                dayOffMessage(dayBookings: dayBookings)
            } else if let availabilityErrorText {
                Text(availabilityErrorText)
                    .font(.footnote)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                if !dayBookings.isEmpty {
                    ForEach(dayBookings) { b in
                        Button {
                            shellNavigator.pushBooking(b)
                        } label: {
                            outsideAvailabilityRow(b)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let errorText, dayBookings.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
        }
    }

    @ViewBuilder
    private func dailySlotRow(slot: HourlySlot, booking: SimpleBookingDTO?, blockTimeTapsEnabled: Bool) -> some View {
        let overlaps = timeBlocksOverlappingSlot(slot)
        if let booking {
            Button {
                shellNavigator.pushBooking(booking)
            } label: {
                bookedSlotCard(slot: slot, booking: booking)
            }
            .buttonStyle(.plain)
        } else if !overlaps.isEmpty {
            ForEach(overlaps) { block in
                blockedTimeRow(block: block)
            }
        } else if blockTimeTapsEnabled {
            Button {
                prepareBlockSheet(for: slot)
                showingBlockTimeSheet = true
            } label: {
                availableSlotCard(slot: slot)
            }
            .buttonStyle(.plain)
        } else {
            availableSlotCard(slot: slot)
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

    private func bookedSlotCard(slot: HourlySlot, booking: SimpleBookingDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(slot.displayRange)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(booking.scheduleSlotTitle)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(booking.statusDisplayTint, in: Capsule())
            }
            Text(booking.consumerDisplayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream)
            Text(booking.serviceDisplayName)
                .font(.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text(booking.barberDisplayName)
                .font(.caption)
                .foregroundStyle(Color.lavaShellCreamTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background { scheduleCardBackground(cornerRadius: 14, chrome: scheduleCardChrome(for: booking)) }
    }

    private func availableSlotCard(slot: HourlySlot) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.providerOlive)
                .frame(width: 8, height: 8)
            Text(slot.displayRange)
                .font(.subheadline.weight(.medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Available")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                Text("Tap to block")
                    .font(.caption2)
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
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

    private func weeklyDayAppointmentSummary(_ dayBookings: [SimpleBookingDTO]) -> String {
        let booked = dayBookings.filter { ProviderBookingStatusDisplay.isScheduleBooked(status: $0.status) }.count
        let completed = dayBookings.filter { ProviderBookingStatusDisplay.isScheduleCompleted(status: $0.status) }.count
        var parts: [String] = []
        if booked > 0 { parts.append("\(booked) booked") }
        if completed > 0 { parts.append("\(completed) completed") }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        let other = dayBookings.count
        return other == 1 ? "1 appointment" : "\(other) appointments"
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

    /// Hour-bucketed lookup mirroring the web Daily view: a booking belongs to a slot when its
    /// `scheduledTime` minute-of-day lies in `[startMinutes, endMinutes)`.
    private func booking(for slot: HourlySlot, in dayBookings: [SimpleBookingDTO]) -> SimpleBookingDTO? {
        let cal = mondayCalendar
        return dayBookings.first { b in
            guard let st = b.scheduledTime else { return false }
            let comps = cal.dateComponents([.hour, .minute], from: st)
            let mins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            return mins >= slot.startMinutes && mins < slot.endMinutes
        }
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

    private func prepareBlockSheet(for slot: HourlySlot) {
        let cal = mondayCalendar
        let day = selectedDay
        blockSheetDayStart = cal.startOfDay(for: day)
        blockSheetStart = cal.date(bySettingHour: slot.startHour, minute: 0, second: 0, of: day) ?? day
        let endHour = min(slot.startHour + 1, 23)
        blockSheetEnd = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: day) ?? day
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

    private var weeklyBody: some View {
        VStack(spacing: 10) {
            ForEach(0 ..< 7, id: \.self) { i in
                let day = mondayCalendar.date(byAdding: .day, value: i, to: weekStartMonday) ?? weekStartMonday
                weeklyRow(day: day)
            }
        }
    }

    private func weeklyRow(day: Date) -> some View {
        let dayBookings = scheduleBookings.filter { $0.isSameCalendarDay(as: day, calendar: mondayCalendar) }
        let isToday = mondayCalendar.isDateInToday(day)
        return Button {
            dayOffset = mondayCalendar.dateComponents([.day], from: mondayCalendar.startOfDay(for: .now), to: day).day ?? 0
            mode = .daily
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.wide)))
                        .font(.subheadline.weight(isToday ? .bold : .medium))
                    Text(day.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                .frame(width: 120, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    if dayBookings.isEmpty {
                        Text("No appointments")
                            .font(.caption)
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    } else {
                        Text(weeklyDayAppointmentSummary(dayBookings))
                            .font(.caption.weight(.semibold))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background { scheduleCardBackground(cornerRadius: 14, chrome: isToday ? .today : .neutral) }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monthly (compact grid)

    private var monthAnchor: Date {
        mondayCalendar.date(byAdding: .month, value: monthOffset, to: mondayCalendar.startOfDay(for: .now)) ?? .now
    }

    private var monthlyBody: some View {
        let grid = monthGridDays()
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, w in
                    Text(w)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(grid.indices, id: \.self) { idx in
                    if let d = grid[idx] {
                        monthlyCell(date: d)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }

    private func monthGridDays() -> [Date?] {
        let range = mondayCalendar.range(of: .day, in: .month, for: monthAnchor) ?? 1 ..< 29
        let first = mondayCalendar.date(from: mondayCalendar.dateComponents([.year, .month], from: monthAnchor)) ?? monthAnchor
        let weekday = mondayCalendar.component(.weekday, from: first)
        let pad = (weekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: pad)
        for d in range {
            if let date = mondayCalendar.date(byAdding: .day, value: d - 1, to: first) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func monthlyCell(date: Date) -> some View {
        let count = scheduleBookings.filter { $0.isSameCalendarDay(as: date, calendar: mondayCalendar) }.count
        let isToday = mondayCalendar.isDateInToday(date)
        return Button {
            dayOffset = mondayCalendar.dateComponents([.day], from: mondayCalendar.startOfDay(for: .now), to: date).day ?? 0
            mode = .daily
        } label: {
            ZStack {
                scheduleCardBackground(cornerRadius: 8, chrome: isToday ? .today : .neutral)
                VStack(spacing: 2) {
                    Text("\(mondayCalendar.component(.day, from: date))")
                        .font(.caption.weight(isToday ? .bold : .medium))
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
                }
            }
            .frame(height: 36)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    /// Bookings shown anywhere on the main schedule (daily slots, weekly rows, monthly counts, summary).
    private var scheduleBookings: [SimpleBookingDTO] {
        bookings.filter(\.isVisibleOnMainSchedule)
    }

    private func visibleBookingsForCurrentMode() -> [SimpleBookingDTO] {
        switch mode {
        case .daily:
            return scheduleBookings.filter { $0.isSameCalendarDay(as: selectedDay, calendar: mondayCalendar) }
        case .weekly:
            return scheduleBookings.filter { $0.isInWeek(containing: weekStartMonday, calendar: mondayCalendar) }
        case .monthly:
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
        switch mode {
        case .daily: dayOffset += delta
        case .weekly: weekOffset += delta
        case .monthly: monthOffset += delta
        }
    }

    private func advanceMode(_ delta: Int) {
        let all = ProviderScheduleMode.allCases
        guard let i = all.firstIndex(of: mode) else { return }
        let next = (i + delta + all.count) % all.count
        mode = all[next]
    }
}
