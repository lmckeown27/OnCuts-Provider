import SwiftUI
import UIKit

// MARK: - Zoom tiers & presets

enum ProviderScheduleZoom {
    static let scaleMin: CGFloat = 0.15
    static let scaleMax: CGFloat = 5.0
    static let defaultScale: CGFloat = 1.5

    /// Fixed viewer height for month schedule box; week/day/minute use `canvasViewerHeight`.
    static let canvasMinHeightDefault: CGFloat = 340

    /// Taller scrollable viewer for day/minute — timeline content may extend beyond and scroll inside.
    static let timelineVerticalScaleBoost: CGFloat = 1.4

    /// Target height for the day/minute/weekly schedule viewer box (timeline scrolls inside).
    static let dayMinuteViewerPreferredHeight: CGFloat = 400
    static let dayMinuteViewerMinHeight: CGFloat = 340
    static let dayMinuteViewerScreenMargin: CGFloat = 24
    /// Shell header, summary, controls above the canvas, and supplement text below it.
    static let schedulePageChromeReserve: CGFloat = 180

    /// Height of the schedule **viewer** area inside the card.
    static func canvasViewerHeight(availableHeight: CGFloat) -> CGFloat {
        let budget = availableHeight - schedulePageChromeReserve - dayMinuteViewerScreenMargin
        return min(dayMinuteViewerPreferredHeight, max(dayMinuteViewerMinHeight, budget))
    }

    /// Tier boundaries — pinch scale crosses these to change Month / Week / Day / Minute.
    static let weekLower: CGFloat = 0.4
    static let dayLower: CGFloat = 1.5
    static let minuteLower: CGFloat = 3.5

    static func clamped(_ scale: CGFloat) -> CGFloat {
        Swift.max(scaleMin, Swift.min(scaleMax, scale))
    }

    /// Pinch may only move between day and minute — never into week or month.
    static func clampedForPinch(_ scale: CGFloat) -> CGFloat {
        clamped(min(scaleMax, max(dayLower, scale)))
    }

    enum Preset: CaseIterable, Identifiable {
        case month
        case week
        case day
        case minute

        var id: String { title }

        var title: String {
            switch self {
            case .month: return "Month"
            case .week: return "Week"
            case .day: return "Day"
            case .minute: return "Minute"
            }
        }

        var targetScale: CGFloat {
            switch self {
            case .month: return 0.25
            case .week: return 0.9
            case .day: return 1.5
            case .minute: return 4.0
            }
        }

        var tier: ProviderScheduleZoomTier {
            switch self {
            case .month: return .month
            case .week: return .week
            case .day: return .day
            case .minute: return .minute
            }
        }
    }
}

enum ProviderScheduleZoomTier: Equatable {
    case minute
    case day
    case week
    case month

    init(effectiveScale: CGFloat) {
        let scale = ProviderScheduleZoom.clamped(effectiveScale)
        // Small epsilon so spring / pinch rounding at 1.5 stays in day, not week.
        let dayThreshold = ProviderScheduleZoom.dayLower - 0.001
        if scale >= ProviderScheduleZoom.minuteLower {
            self = .minute
        } else if scale >= dayThreshold {
            self = .day
        } else if scale >= ProviderScheduleZoom.weekLower {
            self = .week
        } else {
            self = .month
        }
    }

    var headerLabel: String {
        switch self {
        case .minute: return "Minute-by-minute"
        case .day: return "Daily Schedule"
        case .week: return "Weekly Schedule"
        case .month: return "Monthly Schedule"
        }
    }

    var supportsPinchZoom: Bool {
        switch self {
        case .day, .minute: return true
        case .week, .month: return false
        }
    }
}

// MARK: - Timeline appointment model

struct ScheduleCanvasAppointment: Identifiable {
    let id: String
    let booking: SimpleBookingDTO
    let startMinute: Int
    let durationMinutes: Int

    static func from(booking: SimpleBookingDTO, calendar: Calendar, defaultDurationMinutes: Int = ProviderScheduleHourlySlot.bookableSlotMinutes) -> ScheduleCanvasAppointment? {
        guard let scheduled = booking.providerEffectiveScheduledTime else { return nil }
        let comps = calendar.dateComponents([.hour, .minute], from: scheduled)
        let start = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return ScheduleCanvasAppointment(
            id: booking.id,
            booking: booking,
            startMinute: start,
            durationMinutes: defaultDurationMinutes
        )
    }
}

// MARK: - Main canvas

struct ProviderZoomableScheduleCanvas: View {
    @Binding var zoomScale: CGFloat

    let calendar: Calendar
    let selectedDay: Date
    let weekStartMonday: Date
    let monthAnchor: Date
    let bookings: [SimpleBookingDTO]
    let timelineStartMinute: Int
    let timelineEndMinute: Int
    let availabilityIntervals: [BarberAvailabilityIntervalDTO]
    /// Per-day availability intervals for the visible week (Mon–Sun), used for bookable-slot grid lines.
    let weekDayAvailabilityIntervals: [[BarberAvailabilityIntervalDTO]]
    /// Per-day flags for weekdays explicitly turned off in the weekly schedule (or date overrides).
    let weekDayEntirelyBlockedOff: [Bool]
    let isDayEntirelyBlockedOff: (Date) -> Bool
    /// Per-day time blocks for the visible week (Mon–Sun), used when validating weekly drag moves.
    let weekDayTimeBlocks: [[BarberTimeBlockDTO]]
    let timeBlocks: [BarberTimeBlockDTO]
    let blockTimeTapsEnabled: Bool
    let onBookingTap: (SimpleBookingDTO) -> Void
    let onAvailableMinuteTap: (Int) -> Void
    let onWeekDayTap: (Date) -> Void
    let onMonthDayTap: (Date) -> Void
    @Binding var pendingScrollToBookingID: String?
    /// Height of the day/minute **viewer box**; timeline content scrolls vertically inside it.
    var canvasViewerHeight: CGFloat?
    var appointmentDragEnabled: Bool = false
    @Binding var editingMoveBookingID: String?
    @Binding var activeMoveDragBookingID: String?
    @Binding var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    var onMoveBookingRequested: (SimpleBookingDTO) -> Void = { _ in }
    var onBookingTimeChangeProposed: (SimpleBookingDTO, Date, Bool) -> Void = { _, _, _ in }
    /// Called when a day/minute pinch session starts (used to block week/month scale drift).
    var onPinchZoomSessionBegan: () -> Void = {}

    @State private var pinchZoomMultiplier: CGFloat = 1.0
    @State private var isPinchZoomActive = false
    @State private var pinchSessionScrollY: CGFloat = 0
    @State private var pinchSessionAnchorY: CGFloat = 0
    @State private var pinchSessionLastEffectiveScale: CGFloat = 1
    @State private var pinchSessionKeepDayMinuteTier = false
    @State private var timelineScrollPosition = ScrollPosition()
    @State private var timelineScrollOffsetY: CGFloat = 0
    @State private var isPerformingDayScroll = false

    private var effectiveScale: CGFloat {
        let raw = ProviderScheduleZoom.clamped(zoomScale * pinchZoomMultiplier)
        if isPinchZoomActive || pinchSessionKeepDayMinuteTier {
            return ProviderScheduleZoom.clampedForPinch(raw)
        }
        return raw
    }

    private var tier: ProviderScheduleZoomTier {
        ProviderScheduleZoomTier(effectiveScale: effectiveScale)
    }

    /// Pinch zoom is only available in day and minute tiers (preset buttons switch month/week).
    private var pinchZoomEnabled: Bool {
        if isPinchZoomActive { return pinchSessionKeepDayMinuteTier }
        return ProviderScheduleZoomTier(effectiveScale: zoomScale).supportsPinchZoom
    }

    private var appointments: [ScheduleCanvasAppointment] {
        bookings.compactMap { ScheduleCanvasAppointment.from(booking: $0, calendar: calendar) }
            .filter { calendar.isDate($0.booking.scheduledTime ?? selectedDay, inSameDayAs: selectedDay) }
            .sorted { $0.startMinute < $1.startMinute }
    }

    private var dayTimelineVerticalScale: CGFloat {
        effectiveScale * ProviderScheduleZoom.timelineVerticalScaleBoost
    }

    private var resolvedViewerBoxHeight: CGFloat {
        if let canvasViewerHeight {
            return canvasViewerHeight
        }
        if tier.supportsPinchZoom || tier == .week {
            return ProviderScheduleZoom.dayMinuteViewerPreferredHeight
        }
        return ProviderScheduleZoom.canvasMinHeightDefault
    }

    /// Scrollable timeline content height (timeline + vertical padding in day/minute canvas).
    private var dayMinuteTimelineLayout: ScheduleAvailabilityTimelineLayout {
        ScheduleAvailabilityTimelineLayout(
            intervals: availabilityIntervals,
            verticalScale: dayTimelineVerticalScale
        )
    }

    private var timelineScrollContentHeight: CGFloat {
        let bookedHoursHeight = dayMinuteTimelineLayout.contentHeight
        if bookedHoursHeight > 0 {
            return bookedHoursHeight + ScheduleTimelineDragLayout.timelineVerticalChromeHeight
        }
        return ScheduleTimelineDragLayout.timelineVerticalChromeHeight
    }

    private var maxTimelineScrollOffsetY: CGFloat {
        maxTimelineScrollOffsetY(forEffectiveScale: effectiveScale)
    }

    private func maxTimelineScrollOffsetY(forEffectiveScale scale: CGFloat) -> CGFloat {
        let verticalScale = scale * ProviderScheduleZoom.timelineVerticalScaleBoost
        let layout = ScheduleAvailabilityTimelineLayout(
            intervals: availabilityIntervals,
            verticalScale: verticalScale
        )
        let contentHeight = layout.contentHeight + ScheduleTimelineDragLayout.timelineVerticalChromeHeight
        return max(0, contentHeight - resolvedViewerBoxHeight)
    }

    /// Keeps the timeline point under the pinch centroid fixed while scale changes.
    private func scrollOffsetAfterPinchIncrement(
        incrementalRatio: CGFloat,
        proposedEffectiveScale: CGFloat
    ) -> CGFloat {
        let padding = ScheduleTimelineDragLayout.contentTopPadding
        let rawScroll = padding * (1 - incrementalRatio)
            + pinchSessionScrollY * incrementalRatio
            + pinchSessionAnchorY * (incrementalRatio - 1)
        let maxScroll = maxTimelineScrollOffsetY(forEffectiveScale: proposedEffectiveScale)
        return min(max(rawScroll, 0), maxScroll)
    }

    private func handlePinchZoomBegan(anchorYInViewport: CGFloat) {
        isPinchZoomActive = true
        pinchSessionKeepDayMinuteTier = ProviderScheduleZoomTier(effectiveScale: zoomScale).supportsPinchZoom
        onPinchZoomSessionBegan()
        pinchSessionAnchorY = anchorYInViewport
        pinchSessionScrollY = timelineScrollOffsetY
        pinchSessionLastEffectiveScale = effectiveScale
    }

    private func handlePinchZoomChanged(proposedEffectiveScale: CGFloat) {
        guard abs(proposedEffectiveScale - pinchSessionLastEffectiveScale) > 0.0001 else { return }

        let incrementalRatio = proposedEffectiveScale / pinchSessionLastEffectiveScale
        pinchSessionScrollY = scrollOffsetAfterPinchIncrement(
            incrementalRatio: incrementalRatio,
            proposedEffectiveScale: proposedEffectiveScale
        )
        pinchSessionLastEffectiveScale = proposedEffectiveScale
        pinchZoomMultiplier = proposedEffectiveScale / zoomScale
        applyPinchZoomScroll(to: pinchSessionScrollY)
    }

    private func handlePinchZoomEnded(proposedEffectiveScale: CGFloat) {
        handlePinchZoomChanged(proposedEffectiveScale: proposedEffectiveScale)

        let resolved = pinchSessionKeepDayMinuteTier
            ? ProviderScheduleZoom.clampedForPinch(proposedEffectiveScale)
            : ProviderScheduleZoom.clamped(proposedEffectiveScale)

        pinchZoomMultiplier = 1.0
        isPinchZoomActive = false
        zoomScale = resolved
        pinchSessionKeepDayMinuteTier = false
    }

    private func applyPinchZoomScroll(to offsetY: CGFloat) {
        timelineScrollOffsetY = offsetY
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineScrollPosition.scrollTo(y: offsetY)
        }
    }

    private func canScrollTimelineUp() -> Bool {
        timelineScrollOffsetY > 0.5
    }

    private func canScrollTimelineDown() -> Bool {
        timelineScrollOffsetY < maxTimelineScrollOffsetY - 0.5
    }

    @discardableResult
    private func applyTimelineEdgeScroll(deltaY: CGFloat) -> CGFloat {
        let next = min(max(timelineScrollOffsetY + deltaY, 0), maxTimelineScrollOffsetY)
        let applied = next - timelineScrollOffsetY
        guard abs(applied) > 0.01 else { return 0 }

        timelineScrollOffsetY = next
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineScrollPosition.scrollTo(y: next)
        }
        return applied
    }

    private func scrollToShowBooking(
        for app: ScheduleCanvasAppointment,
        clampedOffsetY: CGFloat,
        reservePromptSpace: Bool
    ) {
        guard tier == .day || tier == .minute else { return }
        guard let top = dayMinuteTimelineLayout.contentY(forMinute: app.startMinute) else { return }

        let height = max(4, CGFloat(app.durationMinutes) * dayTimelineVerticalScale)
        let bookingContentTop = ScheduleTimelineDragLayout.contentTopPadding + top + clampedOffsetY
        let bottomMargin: CGFloat = 14

        let targetY: CGFloat
        if reservePromptSpace {
            let topMargin: CGFloat = 14
            var promptTarget = bookingContentTop - ScheduleTimelineDragLayout.confirmPromptClearance - topMargin
            let minScrollForBottom = bookingContentTop + height - resolvedViewerBoxHeight + bottomMargin
            if minScrollForBottom > 0, promptTarget < minScrollForBottom {
                promptTarget = minScrollForBottom
            }
            targetY = min(max(promptTarget, 0), maxTimelineScrollOffsetY)
        } else {
            let centeredY = max(0, bookingContentTop - resolvedViewerBoxHeight * 0.35)
            targetY = min(centeredY, maxTimelineScrollOffsetY)
        }

        guard abs(targetY - timelineScrollOffsetY) > 1 else { return }

        timelineScrollOffsetY = targetY
        withAnimation(.easeInOut(duration: 0.28)) {
            timelineScrollPosition.scrollTo(y: targetY)
        }
    }

    private func scrollToFocusedBookingAfterDrop(
        for app: ScheduleCanvasAppointment,
        clampedOffsetY: CGFloat
    ) {
        scrollToShowBooking(for: app, clampedOffsetY: clampedOffsetY, reservePromptSpace: false)
    }

    private func scrollToFocusedBooking(for app: ScheduleCanvasAppointment) {
        scrollToShowBooking(for: app, clampedOffsetY: 0, reservePromptSpace: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            zoomContextHeader

            Divider()
                .overlay(Color.providerScheduleTrackStroke)

            GeometryReader { proxy in
                weekAwareScrollView(viewportSize: proxy.size)
                    .background {
                        if pinchZoomEnabled && activeMoveDragBookingID == nil {
                            ScheduleTimelinePinchZoomAttachment(
                                isEnabled: true,
                                currentZoomScale: zoomScale,
                                clampZoom: Self.clampToPinchZoomRange,
                                onPinchBegan: handlePinchZoomBegan,
                                onPinchChanged: handlePinchZoomChanged,
                                onPinchEnded: handlePinchZoomEnded
                            )
                        }
                    }
            }
            .frame(height: resolvedViewerBoxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .background(Color.providerScheduleCardFill.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.providerScheduleTrackStroke, lineWidth: 0.6)
        )
        .onChange(of: pendingScrollToBookingID) { _, bookingID in
            guard bookingID != nil else { return }
            Task { await performPendingDayScroll() }
        }
        .onChange(of: tier) { _, newTier in
            guard newTier == .day || newTier == .minute else { return }
            guard pendingScrollToBookingID != nil else { return }
            Task { await performPendingDayScroll() }
        }
        .onChange(of: selectedDay) { _, _ in
            guard pendingScrollToBookingID != nil else { return }
            Task { await performPendingDayScroll() }
        }
    }

    private var minuteTierHeaderOpacity: Double {
        if effectiveScale <= 3.0 { return 0 }
        if effectiveScale >= 3.5 { return 1 }
        return Double((effectiveScale - 3.0) / 0.5)
    }

    private var dailyTierHeaderOpacity: Double {
        1 - minuteTierHeaderOpacity
    }

    private var zoomContextHeader: some View {
        HStack(spacing: 8) {
            Group {
                if tier == .week || tier == .month {
                    Text(tier.headerLabel)
                } else {
                    ZStack(alignment: .leading) {
                        Text("Daily Schedule")
                            .opacity(dailyTierHeaderOpacity)
                        Text("Minute-by-minute")
                            .opacity(minuteTierHeaderOpacity)
                    }
                }
            }
            .font(.provider(.subheadline, weight: .bold))
            .foregroundStyle(Color.lavaShellCream)
            .animation(isPinchZoomActive ? nil : .smooth(duration: 0.28), value: effectiveScale)
            Spacer()
            if tier.supportsPinchZoom {
                Text(String(format: "%.1fx", effectiveScale))
                    .font(.provider(.caption2)).monospacedDigit()
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .contentTransition(.numericText())
                    .animation(isPinchZoomActive ? nil : .smooth(duration: 0.28), value: effectiveScale)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func weekAwareScrollView(viewportSize: CGSize) -> some View {
        switch tier {
        case .week:
            ScrollView(.horizontal, showsIndicators: false) {
                canvasContent(in: viewportSize)
                    .frame(height: viewportSize.height, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .contentShape(Rectangle())
        case .month:
            canvasContent(in: viewportSize)
                .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
                .clipped()
        case .day, .minute:
            ScrollView(.vertical, showsIndicators: false) {
                canvasContent(in: viewportSize)
                    .frame(width: viewportSize.width, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollPosition($timelineScrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                guard !isPinchZoomActive else { return }
                timelineScrollOffsetY = newValue
            }
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func canvasContent(in size: CGSize) -> some View {
        Group {
            switch tier {
            case .month:
                BarberMonthlyDensityView(
                    calendar: calendar,
                    monthAnchor: monthAnchor,
                    workloads: BarberMonthlyDensityView.workloads(
                        monthAnchor: monthAnchor,
                        bookings: bookings,
                        calendar: calendar
                    ),
                    selectedDate: selectedDay,
                    availableHeight: size.height,
                    isDayBlockedOff: isDayEntirelyBlockedOff,
                    onDayTap: onMonthDayTap
                )
                .frame(width: size.width, height: size.height, alignment: .top)
            case .week:
                WeeklySwimlaneView(
                    calendar: calendar,
                    weekStart: weekStartMonday,
                    bookings: bookings,
                    viewportSize: size,
                    startMinute: timelineStartMinute,
                    endMinute: timelineEndMinute,
                    dayAvailabilityIntervals: weekDayAvailabilityIntervals,
                    dayEntirelyBlockedOff: weekDayEntirelyBlockedOff,
                    dayTimeBlocks: weekDayTimeBlocks,
                    onDayTap: onWeekDayTap,
                    onBookingTap: onBookingTap,
                    appointmentDragEnabled: appointmentDragEnabled,
                    editingMoveBookingID: $editingMoveBookingID,
                    activeMoveDragBookingID: $activeMoveDragBookingID,
                    timeChangeProposal: $timeChangeProposal,
                    onMoveBookingRequested: onMoveBookingRequested,
                    onBookingTimeChangeProposed: onBookingTimeChangeProposed
                )
                .frame(height: size.height, alignment: .top)
            case .day, .minute:
                SchedulePreciseTimelineCanvas(
                    calendar: calendar,
                    day: selectedDay,
                    appointments: appointments,
                    scale: effectiveScale,
                    isPinchZoomActive: isPinchZoomActive,
                    startMinute: timelineStartMinute,
                    endMinute: timelineEndMinute,
                    availabilityIntervals: availabilityIntervals,
                    timeBlocks: timeBlocks,
                    blockTimeTapsEnabled: blockTimeTapsEnabled,
                    appointmentDragEnabled: appointmentDragEnabled,
                    editingMoveBookingID: $editingMoveBookingID,
                    activeMoveDragBookingID: $activeMoveDragBookingID,
                    timeChangeProposal: $timeChangeProposal,
                    onMoveBookingRequested: onMoveBookingRequested,
                    onBookingTap: onBookingTap,
                    onAvailableMinuteTap: { minute in
                        if editingMoveBookingID != nil {
                            activeMoveDragBookingID = nil
                        }
                        onAvailableMinuteTap(minute)
                    },
                    onBookingTimeChangeProposed: onBookingTimeChangeProposed,
                    onBookingDropScroll: scrollToFocusedBookingAfterDrop,
                    viewportHeight: resolvedViewerBoxHeight,
                    canScrollTimelineUp: canScrollTimelineUp,
                    canScrollTimelineDown: canScrollTimelineDown,
                    onScrollTimelineBy: applyTimelineEdgeScroll,
                    currentScrollOffsetY: { timelineScrollOffsetY }
                )
                .frame(width: size.width)
            }
        }
        .animation(isPinchZoomActive ? nil : .smooth(duration: 0.28), value: effectiveScale)
    }

    /// Keeps pinch zoom within day and minute tiers only.
    private static func clampToPinchZoomRange(_ scale: CGFloat) -> CGFloat {
        ProviderScheduleZoom.clampedForPinch(scale)
    }

    private func clampedScrollMinute(_ minute: Int) -> Int {
        min(max(minute, timelineStartMinute), max(timelineStartMinute, timelineEndMinute - 1))
    }

    private func performPendingDayScroll() async {
        guard !isPerformingDayScroll else { return }
        guard let bookingID = pendingScrollToBookingID else { return }
        guard tier == .day || tier == .minute else { return }

        isPerformingDayScroll = true
        defer { isPerformingDayScroll = false }

        for attempt in 0 ..< 8 {
            let delayMs = attempt == 0 ? 450 : 120
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            guard tier == .day || tier == .minute else { return }
            guard pendingScrollToBookingID == bookingID else { return }

            guard let appointment = appointments.first(where: { $0.id == bookingID }) else {
                continue
            }

            let minute = clampedScrollMinute(appointment.startMinute)
            guard let top = dayMinuteTimelineLayout.contentY(forMinute: minute) else {
                continue
            }
            let targetY = top + 8
            let centeredY = max(0, targetY - resolvedViewerBoxHeight * 0.35)

            withAnimation(.easeInOut(duration: 0.28)) {
                timelineScrollPosition.scrollTo(y: centeredY)
            }
            pendingScrollToBookingID = nil
            return
        }

        pendingScrollToBookingID = nil
    }
}

/// Attaches a UIKit pinch recognizer to the timeline scroll view without blocking taps or scroll.
private struct ScheduleTimelinePinchZoomAttachment: UIViewRepresentable {
    var isEnabled: Bool
    var currentZoomScale: CGFloat
    var clampZoom: (CGFloat) -> CGFloat
    var onPinchBegan: (_ anchorYInViewport: CGFloat) -> Void
    var onPinchChanged: (_ proposedEffectiveScale: CGFloat) -> Void
    var onPinchEnded: (_ proposedEffectiveScale: CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attachIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ScheduleTimelinePinchZoomAttachment
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var wiredScrollView: UIScrollView?

        private var pinchStartZoomScale: CGFloat = 1

        init(parent: ScheduleTimelinePinchZoomAttachment) {
            self.parent = parent
        }

        deinit {
            detach()
        }

        func attachIfNeeded(from view: UIView) {
            guard let scrollView = view.enclosingScrollView else { return }

            if wiredScrollView !== scrollView {
                detach()
                let pinch = UIPinchGestureRecognizer(
                    target: self,
                    action: #selector(handlePinch(_:))
                )
                pinch.cancelsTouchesInView = false
                pinch.delegate = self
                scrollView.addGestureRecognizer(pinch)
                pinchRecognizer = pinch
                wiredScrollView = scrollView
            }

            pinchRecognizer?.isEnabled = parent.isEnabled
        }

        func detach() {
            if let pinch = pinchRecognizer, let scrollView = wiredScrollView {
                scrollView.removeGestureRecognizer(pinch)
            }
            pinchRecognizer = nil
            wiredScrollView = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer === wiredScrollView?.panGestureRecognizer
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard parent.isEnabled else { return }
            guard let scrollView = recognizer.view as? UIScrollView ?? recognizer.view?.enclosingScrollView else { return }

            switch recognizer.state {
            case .began:
                pinchStartZoomScale = parent.currentZoomScale
                parent.onPinchBegan(recognizer.location(in: scrollView).y)
            case .changed:
                let proposed = parent.clampZoom(pinchStartZoomScale * recognizer.scale)
                parent.onPinchChanged(proposed)
            case .ended, .cancelled:
                let proposed = parent.clampZoom(pinchStartZoomScale * recognizer.scale)
                parent.onPinchEnded(proposed)
            default:
                break
            }
        }
    }
}

// MARK: - Appointment drag helpers

struct ScheduleAppointmentTimeChangeProposal: Identifiable {
    let id = UUID()
    let booking: SimpleBookingDTO
    let originalTime: Date
    let proposedTime: Date
    /// True when the user's finger is over a slot before the current date/time (card may snap forward visually).
    var targetsPastTime: Bool = false
}

private enum ScheduleTimelineDragLayout {
    static let contentTopPadding: CGFloat = 24
    static let contentBottomPadding: CGFloat = 8
    static let contentBottomLabelClearance: CGFloat = 32

    static var timelineVerticalChromeHeight: CGFloat {
        contentTopPadding + contentBottomPadding + contentBottomLabelClearance
    }

    static var contentBottomInset: CGFloat {
        contentBottomPadding + contentBottomLabelClearance
    }

    static let viewportEdgeInset: CGFloat = 4
    /// Space reserved above a dropped booking so the confirm prompt stays visible.
    static let confirmPromptClearance: CGFloat = 152
}

enum ScheduleAppointmentDrag {
    static func isDraggable(_ booking: SimpleBookingDTO) -> Bool {
        guard booking.scheduledTime != nil else { return false }
        switch ProviderBookingStatusDisplay.normalized(booking.status) {
        case "pending", "accepted":
            return true
        case "paid":
            // Upcoming paid appointments move like accepted; legacy finished PAID stays fixed.
            return booking.isUpcomingPaidAppointment
        default:
            return false
        }
    }

    static func snapMinute(_ minute: Int, step: Int) -> Int {
        guard step > 1 else { return minute }
        return ((minute + step / 2) / step) * step
    }

    /// Whether a dragged appointment may be saved at the proposed time.
    static func isSaveEligibleMove(
        proposed: Date,
        original: Date,
        targetsPast: Bool = false,
        now: Date = .now
    ) -> Bool {
        guard !targetsPast else { return false }
        guard proposed.timeIntervalSince(now) > -30 else { return false }
        return abs(proposed.timeIntervalSince(original)) > 30
    }
}

// MARK: - Minute / day timeline

private enum ScheduleTimelineZoomVisuals {
    static let fineTickStep = 5

    /// 30-minute labels — strongest at day zoom, fade out as minute detail appears.
    static func majorTickLabelOpacity(scale: CGFloat) -> Double {
        if scale <= 2.0 { return 1 }
        if scale >= 3.4 { return 0 }
        return Double(1 - (scale - 2.0) / 1.4)
    }

    /// 15-minute labels — bridge between coarse and fine ticks.
    static func midTickLabelOpacity(scale: CGFloat) -> Double {
        if scale <= 1.6 { return 0 }
        if scale >= 2.2, scale <= 3.0 { return 1 }
        if scale < 2.2 { return Double((scale - 1.6) / 0.6) }
        return Double(1 - (scale - 3.0) / 0.8)
    }

    /// 5-minute labels — fade in for minute-by-minute density.
    static func fineTickLabelOpacity(scale: CGFloat) -> Double {
        if scale <= 2.6 { return 0 }
        if scale >= 3.8 { return 1 }
        return Double((scale - 2.6) / 1.2)
    }

    static func minorGridLineOpacity(scale: CGFloat) -> Double {
        0.05 + 0.1 * fineTickLabelOpacity(scale: scale)
    }

    static func tickLabelFontSize(scale: CGFloat) -> CGFloat {
        let t = min(1, max(0, (scale - 2.0) / 2.0))
        return 10 - t
    }

    /// Smallest time division the user can target at this zoom — matches visible tick labels.
    static func visibleSnapStepMinutes(scale: CGFloat) -> Int {
        if scale >= ProviderScheduleZoom.minuteLower { return 1 }
        if fineTickLabelOpacity(scale: scale) > 0.45 { return fineTickStep }
        if midTickLabelOpacity(scale: scale) > 0.45 { return 15 }
        return 30
    }
}

private struct SchedulePreciseTimelineCanvas: View {
    let calendar: Calendar
    let day: Date
    let appointments: [ScheduleCanvasAppointment]
    let scale: CGFloat
    var isPinchZoomActive: Bool = false
    let startMinute: Int
    let endMinute: Int
    let availabilityIntervals: [BarberAvailabilityIntervalDTO]
    let timeBlocks: [BarberTimeBlockDTO]
    let blockTimeTapsEnabled: Bool
    let appointmentDragEnabled: Bool
    @Binding var editingMoveBookingID: String?
    @Binding var activeMoveDragBookingID: String?
    @Binding var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    let onMoveBookingRequested: (SimpleBookingDTO) -> Void
    let onBookingTap: (SimpleBookingDTO) -> Void
    let onAvailableMinuteTap: (Int) -> Void
    let onBookingTimeChangeProposed: (SimpleBookingDTO, Date, Bool) -> Void
    let onBookingDropScroll: (ScheduleCanvasAppointment, CGFloat) -> Void
    let viewportHeight: CGFloat
    let canScrollTimelineUp: () -> Bool
    let canScrollTimelineDown: () -> Bool
    let onScrollTimelineBy: (CGFloat) -> CGFloat
    let currentScrollOffsetY: () -> CGFloat

    /// Points per minute for timeline layout; grows with pinch zoom and may exceed the viewer box height.
    private var verticalScale: CGFloat {
        scale * ProviderScheduleZoom.timelineVerticalScaleBoost
    }

    private var timelineLayout: ScheduleAvailabilityTimelineLayout {
        ScheduleAvailabilityTimelineLayout(intervals: availabilityIntervals, verticalScale: verticalScale)
    }

    private var timelineHeight: CGFloat {
        timelineLayout.contentHeight
    }

    private var detailTextOpacity: Double {
        if scale >= 1.2 { return 1 }
        if scale >= 0.7 { return Double((scale - 0.7) / 0.5) }
        return 0
    }

    var body: some View {
        Group {
            if timelineLayout.isEmpty {
                Text("No booking hours for this day")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .padding(.vertical, 8)
            } else {
                timelineBody
            }
        }
    }

    private var timelineBody: some View {
        ZStack(alignment: .topLeading) {
            availabilityBackground
                .allowsHitTesting(false)
            timeBlockOverlays
                .allowsHitTesting(false)
            tickMarks
                .allowsHitTesting(editingMoveBookingID == nil)
            if let movingID = editingMoveBookingID,
               appointments.contains(where: { $0.id == movingID }) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .frame(height: timelineHeight + ScheduleTimelineDragLayout.timelineVerticalChromeHeight)
                    .onTapGesture(coordinateSpace: .local) { location in
                        guard let app = appointments.first(where: { $0.id == movingID }) else { return }
                        if activeMoveDragBookingID != nil {
                            activeMoveDragBookingID = nil
                            return
                        }
                        proposeMoveToTimelinePoint(location, for: app)
                    }
            }
            appointmentBlocks
        }
        .frame(height: timelineHeight)
        .padding(.top, ScheduleTimelineDragLayout.contentTopPadding)
        .padding(.bottom, ScheduleTimelineDragLayout.contentBottomInset)
    }

    private var availabilityBackground: some View {
        ForEach(availabilityIntervals.indices, id: \.self) { index in
            let interval = availabilityIntervals[index]
            let start = minutesFromHHMM(interval.start)
            let end = minutesFromHHMM(interval.end)
            if end > start, let y = timelineLayout.contentY(forMinute: start) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.providerScheduleTodayColumnHighlight)
                    .frame(height: CGFloat(end - start) * verticalScale)
                    .offset(x: 52, y: y)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var timeBlockOverlays: some View {
        ForEach(timeBlocks) { block in
            let start = minutesFromHHMM(block.startTime)
            let end = minutesFromHHMM(block.endTime)
            if end > start, let y = timelineLayout.contentY(forMinute: start) {
                HStack(spacing: 6) {
                    Spacer().frame(width: 52)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.lavaShellCreamSecondary.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.lavaShellCreamSecondary.opacity(0.35), lineWidth: 0.5)
                        )
                        .overlay(alignment: .leading) {
                            if detailTextOpacity > 0.3 {
                                Text("Blocked")
                                    .font(.provider(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.lavaShellCreamSecondary)
                                    .padding(.horizontal, 6)
                                    .opacity(detailTextOpacity)
                            }
                        }
                        .frame(height: max(4, CGFloat(end - start) * verticalScale))
                }
                .offset(y: y)
            }
        }
    }

    private var tickMarks: some View {
        VStack(spacing: 0) {
            ForEach(timelineLayout.segments.indices, id: \.self) { segmentIndex in
                let segment = timelineLayout.segments[segmentIndex]
                let minutes = tickMinutes(for: segment)
                ForEach(minutes.indices, id: \.self) { index in
                    let minute = minutes[index]
                    let spanMinutes = (index + 1 < minutes.count ? minutes[index + 1] : minute + ScheduleTimelineZoomVisuals.fineTickStep) - minute
                    tickRow(for: minute, rowSpanMinutes: max(1, spanMinutes))
                }
            }
        }
        .animation(isPinchZoomActive ? nil : .smooth(duration: 0.28), value: scale)
    }

    private func tickMinutes(for segment: ScheduleAvailabilityTimelineLayout.Segment) -> [Int] {
        let step = ScheduleTimelineZoomVisuals.fineTickStep
        guard segment.end > segment.start else { return [] }

        var minutes: [Int] = []
        var minute = segment.start
        while minute < segment.end {
            minutes.append(minute)
            minute += step
        }
        if minutes.last != segment.end {
            minutes.append(segment.end)
        }
        return minutes
    }

    private func tickRow(for minute: Int, rowSpanMinutes: Int) -> some View {
        let presentation = tickPresentation(for: minute)
        let rowHeight = CGFloat(rowSpanMinutes) * verticalScale

        return HStack(alignment: .top, spacing: 6) {
            Group {
                if let label = presentation.label {
                    Text(label)
                        .opacity(presentation.labelOpacity)
                } else {
                    Text(" ")
                        .opacity(0)
                }
            }
            .font(.provider(size: ScheduleTimelineZoomVisuals.tickLabelFontSize(scale: scale)))
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .frame(width: 52, alignment: .trailing)

            Rectangle()
                .fill(Color.lavaShellCreamTertiary.opacity(presentation.lineOpacity))
                .frame(height: 0.5)
        }
        .frame(height: rowHeight, alignment: .top)
    }

    private struct TickPresentation {
        let label: String?
        let labelOpacity: Double
        let lineOpacity: Double
    }

    private func tickPresentation(for minute: Int) -> TickPresentation {
        let majorOpacity = ScheduleTimelineZoomVisuals.majorTickLabelOpacity(scale: scale)
        let midOpacity = ScheduleTimelineZoomVisuals.midTickLabelOpacity(scale: scale)
        let fineOpacity = ScheduleTimelineZoomVisuals.fineTickLabelOpacity(scale: scale)
        let minorLine = ScheduleTimelineZoomVisuals.minorGridLineOpacity(scale: scale)
        let isScheduleBoundary = timelineLayout.segments.contains { $0.start == minute || $0.end == minute }

        if isScheduleBoundary || (minute % 30 == 0 && majorOpacity > 0.04) {
            return TickPresentation(
                label: formatMinuteLabel(minute),
                labelOpacity: isScheduleBoundary ? max(majorOpacity, 0.85) : majorOpacity,
                lineOpacity: isScheduleBoundary ? 0.28 : 0.16 + 0.24 * majorOpacity
            )
        }

        if minute % 15 == 0, midOpacity > 0.04 {
            return TickPresentation(
                label: formatMinuteLabel(minute),
                labelOpacity: midOpacity,
                lineOpacity: 0.12 + 0.2 * midOpacity
            )
        }

        if minute % 5 == 0, fineOpacity > 0.04 {
            return TickPresentation(
                label: formatMinuteLabel(minute),
                labelOpacity: fineOpacity,
                lineOpacity: 0.08 + 0.16 * fineOpacity
            )
        }

        return TickPresentation(label: nil, labelOpacity: 0, lineOpacity: minorLine)
    }

    private var appointmentBlocks: some View {
        ForEach(appointments) { app in
            if timelineLayout.contentY(forMinute: app.startMinute) != nil {
                appointmentBlock(for: app)
            }
        }
    }

    @ViewBuilder
    private func appointmentBlock(for app: ScheduleCanvasAppointment) -> some View {
        let top = timelineLayout.contentY(forMinute: app.startMinute) ?? 0
        let height = max(4, CGFloat(app.durationMinutes) * verticalScale)
        let canMove = appointmentDragEnabled && ScheduleAppointmentDrag.isDraggable(app.booking)
        let isMoveSession = editingMoveBookingID == app.id
        let isDragActive = activeMoveDragBookingID == app.id
        let allowedStart = allowedDragStartMinuteRange(for: app)
        let minDragOffsetY = (timelineLayout.contentY(forMinute: allowedStart.minStart) ?? top) - top
        let maxDragOffsetY = (timelineLayout.contentY(forMinute: allowedStart.maxStart) ?? top) - top

        ZStack(alignment: .topLeading) {
            if isMoveSession {
                HStack(spacing: 0) {
                    Spacer().frame(width: 52)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(app.booking.scheduleAppointmentMoveOriginFillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.lavaShellCream.opacity(0.12), lineWidth: 0.6)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .padding(.horizontal, 10)
                }
                .offset(y: top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            ScheduleDraggableAppointmentBlock(
                top: top,
                height: height,
                appointmentID: app.booking.id,
                isMoveSession: isMoveSession,
                isDragActive: isDragActive,
                canRequestMove: canMove && editingMoveBookingID == nil,
                minDragOffsetY: minDragOffsetY,
                maxDragOffsetY: maxDragOffsetY,
                snapDragOffset: { totalOffsetY in
                    clampedDragOffsetY(for: app, totalOffsetY: totalOffsetY)
                },
                liveClampDragOffset: { totalOffsetY in
                    liveClampedDragOffsetY(
                        for: app,
                        top: top,
                        height: height,
                        totalOffsetY: totalOffsetY
                    )
                },
                shouldAllowEdgeScroll: { direction, totalOffsetY in
                    shouldAllowEdgeScroll(
                        direction: direction,
                        for: app,
                        top: top,
                        height: height,
                        minDragOffsetY: minDragOffsetY,
                        maxDragOffsetY: maxDragOffsetY,
                        totalOffsetY: totalOffsetY
                    )
                },
                viewportHeight: viewportHeight,
                canScrollTimelineUp: canScrollTimelineUp,
                canScrollTimelineDown: canScrollTimelineDown,
                onScrollTimelineBy: onScrollTimelineBy,
                currentScrollOffsetY: currentScrollOffsetY,
                onTap: {
                    if let editingID = editingMoveBookingID {
                        if app.id == editingID {
                            timeChangeProposal = nil
                            activeMoveDragBookingID = app.id
                        } else {
                            activeMoveDragBookingID = nil
                        }
                        return
                    }
                    onBookingTap(app.booking)
                },
                onMoveRequested: { onMoveBookingRequested(app.booking) },
                onDragEnded: { totalOffsetY in
                    handleAppointmentDragEnded(app: app, totalOffsetY: totalOffsetY)
                }
            ) {
                HStack(spacing: 0) {
                    Spacer().frame(width: 52)
                    appointmentBlockContent(
                        for: app,
                        blockHeight: height,
                        isMoveSession: isMoveSession,
                        isDragActive: isDragActive,
                        canRequestMove: canMove && editingMoveBookingID == nil
                    )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .background(appointmentColor(for: app.booking))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            if isMoveSession {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        isDragActive
                                            ? Color.lavaShellCreamSecondary.opacity(0.45)
                                            : Color.providerOlive.opacity(0.95),
                                        lineWidth: 2
                                    )
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var visibleSnapStepMinutes: Int {
        ScheduleTimelineZoomVisuals.visibleSnapStepMinutes(scale: scale)
    }

    private func snappedVisibleMinute(_ minute: Int) -> Int {
        ScheduleAppointmentDrag.snapMinute(minute, step: visibleSnapStepMinutes)
    }

    /// Latest/earliest open start minutes where the appointment fits without overlap.
    private func allowedDragStartMinuteRange(for app: ScheduleCanvasAppointment) -> (minStart: Int, maxStart: Int) {
        let openStarts = openStartMinutes(for: app)
        if openStarts.isEmpty {
            return (app.startMinute, app.startMinute)
        }
        return (openStarts.min() ?? app.startMinute, openStarts.max() ?? app.startMinute)
    }

    private func openStartMinutes(for app: ScheduleCanvasAppointment) -> [Int] {
        timelineLayout.segments.flatMap { segment in
            let latestStart = segment.end - app.durationMinutes
            guard latestStart >= segment.start else { return [Int]() }
            return (segment.start ... latestStart).filter { minute in
                isOpenSlot(
                    startMinute: minute,
                    durationMinutes: app.durationMinutes,
                    excludingAppointmentID: app.id,
                    allowBlockedTime: true
                )
            }
        }
    }

    private func clampMinuteToBookingHours(_ minute: Int) -> Int {
        if timelineLayout.contains(minute: minute) { return minute }

        var bestMinute = minute
        var bestDistance = Int.max
        for segment in timelineLayout.segments {
            if minute < segment.start {
                let distance = segment.start - minute
                if distance < bestDistance {
                    bestDistance = distance
                    bestMinute = segment.start
                }
            } else if minute >= segment.end {
                let distance = minute - (segment.end - 1)
                if distance < bestDistance {
                    bestDistance = distance
                    bestMinute = segment.end - 1
                }
            }
        }
        return bestMinute
    }

    private func resolvedOpenStartMinute(for app: ScheduleCanvasAppointment, proposedMinute: Int) -> Int {
        let openStarts = openStartMinutes(for: app)
        guard !openStarts.isEmpty else { return app.startMinute }

        let minStart = openStarts.min() ?? app.startMinute
        let maxStart = openStarts.max() ?? app.startMinute
        let clamped = min(
            max(clampMinuteToBookingHours(proposedMinute), minStart),
            maxStart
        )
        let snapped = snappedVisibleMinute(clamped)

        if isOpenSlot(
            startMinute: snapped,
            durationMinutes: app.durationMinutes,
            excludingAppointmentID: app.id,
            allowBlockedTime: true
        ) {
            return snapped
        }

        return nearestOpenStartMinute(for: app, around: snapped, step: visibleSnapStepMinutes) ?? app.startMinute
    }

    private func nearestOpenStartMinute(
        for app: ScheduleCanvasAppointment,
        around target: Int,
        step: Int
    ) -> Int? {
        let openStarts = openStartMinutes(for: app)
        guard !openStarts.isEmpty else { return nil }

        let snapStride = max(step, 1)
        let snappedTarget = ScheduleAppointmentDrag.snapMinute(target, step: snapStride)
        let minStart = openStarts.min() ?? snappedTarget
        let maxStart = openStarts.max() ?? snappedTarget
        let maxSteps = max(
            (snappedTarget - minStart) / snapStride,
            (maxStart - snappedTarget) / snapStride
        )

        for stepIndex in 0 ... maxSteps {
            let delta = stepIndex * snapStride
            if stepIndex == 0 {
                if openStarts.contains(snappedTarget) {
                    return snappedTarget
                }
                continue
            }

            let later = snappedTarget + delta
            if later <= maxStart, openStarts.contains(later) {
                return later
            }

            let earlier = snappedTarget - delta
            if earlier >= minStart, openStarts.contains(earlier) {
                return earlier
            }
        }

        return nil
    }

    private func startMinute(atTimelineY locationY: CGFloat) -> Int {
        timelineLayout.minute(atContentY: max(0, locationY)) ?? startMinute
    }

    private func proposeMoveToTimelinePoint(_ location: CGPoint, for app: ScheduleCanvasAppointment) {
        guard location.x >= 48 else { return }

        let proposedStart = startMinute(atTimelineY: location.y)
        let resolvedStart = resolvedOpenStartMinute(for: app, proposedMinute: proposedStart)
        guard resolvedStart != app.startMinute else { return }

        guard let baseTop = timelineLayout.contentY(forMinute: app.startMinute),
              let resolvedTop = timelineLayout.contentY(forMinute: resolvedStart)
        else { return }

        let offsetY = resolvedTop - baseTop
        _ = handleAppointmentDragEnded(app: app, totalOffsetY: offsetY)
    }

    private func visibleDragOffsetRange(top: CGFloat, height: CGFloat) -> (min: CGFloat, max: CGFloat) {
        let scrollY = currentScrollOffsetY()
        let topPadding = ScheduleTimelineDragLayout.contentTopPadding
        let bottomPadding = ScheduleTimelineDragLayout.contentBottomInset
        let inset = ScheduleTimelineDragLayout.viewportEdgeInset
        let minOffset = scrollY - topPadding - top + inset
        let maxOffset = scrollY + viewportHeight - height - bottomPadding - top - inset
        return (minOffset, max(maxOffset, minOffset))
    }

    private func liveClampedDragOffsetY(
        for app: ScheduleCanvasAppointment,
        top: CGFloat,
        height: CGFloat,
        totalOffsetY: CGFloat
    ) -> CGFloat {
        let availabilityClamped = clampedDragOffsetY(
            for: app,
            totalOffsetY: totalOffsetY
        )
        let visible = visibleDragOffsetRange(top: top, height: height)
        return min(max(availabilityClamped, visible.min), visible.max)
    }

    private func shouldAllowEdgeScroll(
        direction: CGFloat,
        for app: ScheduleCanvasAppointment,
        top: CGFloat,
        height: CGFloat,
        minDragOffsetY: CGFloat,
        maxDragOffsetY: CGFloat,
        totalOffsetY: CGFloat
    ) -> Bool {
        let availabilityClamped = clampedDragOffsetY(
            for: app,
            totalOffsetY: totalOffsetY
        )
        let scrollY = currentScrollOffsetY()
        let topPadding = ScheduleTimelineDragLayout.contentTopPadding
        let bottomPadding = ScheduleTimelineDragLayout.contentBottomInset
        let inset = ScheduleTimelineDragLayout.viewportEdgeInset

        if direction > 0, availabilityClamped >= maxDragOffsetY - 1 {
            let viewportTop = topPadding + top + availabilityClamped - scrollY
            if viewportTop <= topPadding + inset + 1 {
                return false
            }
        }

        if direction < 0, availabilityClamped <= minDragOffsetY + 1 {
            let viewportBottom = topPadding + top + availabilityClamped - scrollY + height
            if viewportBottom >= viewportHeight - bottomPadding - inset - 1 {
                return false
            }
        }

        return true
    }

    private func clampedDragOffsetY(
        for app: ScheduleCanvasAppointment,
        totalOffsetY: CGFloat
    ) -> CGFloat {
        guard let baseTop = timelineLayout.contentY(forMinute: app.startMinute) else { return 0 }

        let proposedY = baseTop + totalOffsetY
        let proposedMinute = timelineLayout.minute(atContentY: max(0, proposedY)) ?? app.startMinute
        let resolvedStart = resolvedOpenStartMinute(for: app, proposedMinute: proposedMinute)
        let resolvedTop = timelineLayout.contentY(forMinute: resolvedStart) ?? baseTop
        return resolvedTop - baseTop
    }

    @discardableResult
    private func handleAppointmentDragEnded(app: ScheduleCanvasAppointment, totalOffsetY: CGFloat) -> Bool {
        let clampedOffsetY = clampedDragOffsetY(for: app, totalOffsetY: totalOffsetY)
        guard let baseTop = timelineLayout.contentY(forMinute: app.startMinute) else { return false }

        let resolvedTop = baseTop + clampedOffsetY
        let clampedStart = timelineLayout.minute(atContentY: max(0, resolvedTop)) ?? app.startMinute
        guard clampedStart != app.startMinute else { return false }
        guard let proposedDate = scheduledDate(on: day, totalMinutes: clampedStart) else { return false }

        activeMoveDragBookingID = nil
        onBookingDropScroll(app, clampedOffsetY)
        onBookingTimeChangeProposed(app.booking, proposedDate, false)
        return true
    }

    private func isOpenSlot(
        startMinute: Int,
        durationMinutes: Int,
        excludingAppointmentID: String,
        allowBlockedTime: Bool = false
    ) -> Bool {
        let endMinute = startMinute + durationMinutes

        for other in appointments where other.id != excludingAppointmentID {
            let otherEnd = other.startMinute + other.durationMinutes
            if startMinute < otherEnd && endMinute > other.startMinute {
                return false
            }
        }

        if !allowBlockedTime {
            for block in timeBlocks {
                let blockStart = minutesFromHHMM(block.startTime)
                let blockEnd = minutesFromHHMM(block.endTime)
                if startMinute < blockEnd && endMinute > blockStart {
                    return false
                }
            }
        }

        guard !availabilityIntervals.isEmpty else { return true }
        return availabilityIntervals.contains { interval in
            let intervalStart = minutesFromHHMM(interval.start)
            let intervalEnd = minutesFromHHMM(interval.end)
            return startMinute >= intervalStart && endMinute <= intervalEnd
        }
    }

    private func scheduledDate(on day: Date, totalMinutes: Int) -> Date? {
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: totalMinutes, to: dayStart)
    }

    @ViewBuilder
    private func appointmentBlockContent(
        for app: ScheduleCanvasAppointment,
        blockHeight: CGFloat,
        isMoveSession: Bool,
        isDragActive: Bool,
        canRequestMove: Bool
    ) -> some View {
        if isMoveSession {
            Image(systemName: "arrow.up.and.down")
                .font(.provider(size: moveModeIconSize(for: blockHeight), weight: .semibold))
                .foregroundStyle(
                    isDragActive
                        ? Color.providerScheduleAppointmentSecondaryLabel
                        : Color.providerScheduleAppointmentPrimaryLabel
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)
        } else {
            appointmentBlockDetailContent(
                for: app,
                blockHeight: blockHeight,
                canRequestMove: canRequestMove
            )
        }
    }

    @ViewBuilder
    private func appointmentBlockDetailContent(
        for app: ScheduleCanvasAppointment,
        blockHeight: CGFloat,
        canRequestMove: Bool
    ) -> some View {
        let booking = app.booking
        let detailLevel = appointmentDetailLevel(for: blockHeight)

        VStack(alignment: .center, spacing: detailLineSpacing(for: detailLevel)) {
            if canRequestMove, blockHeight >= 34 {
                appointmentInteractionHint(blockHeight: blockHeight)
            }

            if detailTextOpacity > 0.05 {
                Text(booking.consumerDisplayName)
                    .font(.provider(size: consumerFontSize(for: blockHeight, level: detailLevel), weight: .bold))
                    .foregroundStyle(Color.providerScheduleAppointmentPrimaryLabel)
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit(for: detailLevel, primary: true))
                    .minimumScaleFactor(0.85)
                    .opacity(detailTextOpacity)
                    .allowsHitTesting(false)

                Text(booking.serviceDisplayName)
                    .font(.provider(size: serviceFontSize(for: blockHeight, level: detailLevel), weight: .semibold))
                    .foregroundStyle(Color.providerScheduleAppointmentSecondaryLabel)
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit(for: detailLevel, primary: false))
                    .minimumScaleFactor(0.85)
                    .opacity(detailTextOpacity * 0.9)
                    .allowsHitTesting(false)

                if detailLevel >= .standard {
                    Text(appointmentTimeRange(for: app))
                        .font(.provider(size: detailFontSize(for: blockHeight), weight: .medium))
                        .foregroundStyle(Color.providerScheduleAppointmentTertiaryLabel)
                        .multilineTextAlignment(.center)
                        .allowsHitTesting(false)

                    Text(booking.scheduleCardTitle)
                        .font(.provider(size: detailFontSize(for: blockHeight) - 1, weight: .semibold))
                        .foregroundStyle(Color.providerScheduleAppointmentSecondaryLabel)
                        .multilineTextAlignment(.center)
                        .allowsHitTesting(false)
                }

                if detailLevel >= .detailed {
                    if let price = formattedPrice(for: booking) {
                        Text(price)
                            .font(.provider(size: detailFontSize(for: blockHeight), weight: .semibold))
                            .foregroundStyle(Color.providerScheduleAppointmentPrimaryLabel)
                            .multilineTextAlignment(.center)
                            .allowsHitTesting(false)
                    }

                    if let duration = formattedDuration(minutes: app.durationMinutes) {
                        Text(duration)
                            .font(.provider(size: detailFontSize(for: blockHeight) - 1, weight: .medium))
                            .foregroundStyle(Color.providerScheduleAppointmentTertiaryLabel)
                            .multilineTextAlignment(.center)
                            .allowsHitTesting(false)
                    }

                    if booking.hasPendingRescheduleRequest {
                        Text("Reschedule requested")
                            .font(.provider(size: detailFontSize(for: blockHeight) - 1, weight: .semibold))
                            .foregroundStyle(Color.orange.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .allowsHitTesting(false)
                    }

                    if let location = trimmedNonEmpty(booking.location) {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.provider(size: detailFontSize(for: blockHeight) - 2))
                            Text(location)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        .font(.provider(size: detailFontSize(for: blockHeight) - 1, weight: .medium))
                        .foregroundStyle(Color.providerScheduleAppointmentTertiaryLabel)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                    }

                    if let notes = trimmedNonEmpty(booking.notes) {
                        Text(notes)
                            .font(.provider(size: detailFontSize(for: blockHeight) - 1, weight: .regular))
                            .italic()
                            .foregroundStyle(Color.providerScheduleAppointmentTertiaryLabel)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    private func moveModeIconSize(for blockHeight: CGFloat) -> CGFloat {
        min(22, max(12, blockHeight * 0.38))
    }

    @ViewBuilder
    private func appointmentInteractionHint(blockHeight: CGFloat) -> some View {
        let fontSize = max(8, detailFontSize(for: blockHeight) - 2)
        HStack(spacing: 8) {
            Label("Tap for details", systemImage: "hand.tap")
            Label("Hold to move time", systemImage: "clock.arrow.circlepath")
        }
        .font(.provider(size: fontSize, weight: .medium))
        .foregroundStyle(Color.providerScheduleAppointmentSecondaryLabel)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .allowsHitTesting(false)
    }

    private enum AppointmentDetailLevel: Comparable {
        case compact
        case standard
        case detailed

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }

        private var sortOrder: Int {
            switch self {
            case .compact: return 0
            case .standard: return 1
            case .detailed: return 2
            }
        }
    }

    private func appointmentDetailLevel(for blockHeight: CGFloat) -> AppointmentDetailLevel {
        if scale >= ProviderScheduleZoom.minuteLower, blockHeight >= 96 {
            return .detailed
        }
        if scale >= 2.0, blockHeight >= 72 {
            return .standard
        }
        return .compact
    }

    private func detailLineSpacing(for level: AppointmentDetailLevel) -> CGFloat {
        switch level {
        case .compact: return 4
        case .standard: return 3
        case .detailed: return 2
        }
    }

    private func lineLimit(for level: AppointmentDetailLevel, primary: Bool) -> Int {
        switch level {
        case .compact: return primary ? 2 : 2
        case .standard: return primary ? 2 : 2
        case .detailed: return primary ? 2 : 1
        }
    }

    private func consumerFontSize(for blockHeight: CGFloat, level: AppointmentDetailLevel) -> CGFloat {
        let base = min(18, max(14, blockHeight * 0.24))
        switch level {
        case .compact: return base
        case .standard: return min(17, base)
        case .detailed: return min(16, max(13, blockHeight * 0.16))
        }
    }

    private func serviceFontSize(for blockHeight: CGFloat, level: AppointmentDetailLevel) -> CGFloat {
        let base = min(15, max(12, blockHeight * 0.18))
        switch level {
        case .compact: return base
        case .standard: return min(14, base)
        case .detailed: return min(13, max(11, blockHeight * 0.12))
        }
    }

    private func detailFontSize(for blockHeight: CGFloat) -> CGFloat {
        min(12, max(10, blockHeight * 0.1))
    }

    private func appointmentTimeRange(for app: ScheduleCanvasAppointment) -> String {
        let endMinute = app.startMinute + app.durationMinutes
        return "\(formatMinuteLabel(app.startMinute)) – \(formatMinuteLabel(endMinute))"
    }

    private func formattedPrice(for booking: SimpleBookingDTO) -> String? {
        guard let cents = booking.priceUsdCents else { return nil }
        return (Double(cents) / 100).formatted(.currency(code: "USD"))
    }

    private func formattedDuration(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        if minutes == 1 { return "1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "1 hr" : "\(hours) hr" }
        return "\(hours) hr \(remainder) min"
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func appointmentColor(for booking: SimpleBookingDTO) -> Color {
        // Moving card keeps status fill; original slot uses `scheduleAppointmentMoveOriginFillColor`.
        switch ProviderBookingStatusDisplay.normalized(booking.status) {
        case "pending", "accepted", "booked", "in_progress", "completed":
            return booking.scheduleAppointmentFillColor
        default:
            return Color.providerScheduleCardFill
        }
    }

    private func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }

    private func formatMinuteLabel(_ totalMinutes: Int) -> String {
        var components = DateComponents()
        components.hour = totalMinutes / 60
        components.minute = totalMinutes % 60
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Draggable appointment block

private enum ScheduleAppointmentInteraction {
    static let moveHoldDuration = 0.25
    static let moveHoldMaxDistance: CGFloat = 10
    /// Delay before hold feedback appears so quick taps stay visually neutral.
    static var moveHoldHighlightDelay: Double { moveHoldDuration * 0.42 }
}

private struct ScheduleDraggableAppointmentBlock<Content: View>: View {
    let top: CGFloat
    let height: CGFloat
    let appointmentID: String
    let isMoveSession: Bool
    let isDragActive: Bool
    let canRequestMove: Bool
    let minDragOffsetY: CGFloat
    let maxDragOffsetY: CGFloat
    let snapDragOffset: (CGFloat) -> CGFloat
    let liveClampDragOffset: (CGFloat) -> CGFloat
    let shouldAllowEdgeScroll: (CGFloat, CGFloat) -> Bool
    let viewportHeight: CGFloat
    let canScrollTimelineUp: () -> Bool
    let canScrollTimelineDown: () -> Bool
    let onScrollTimelineBy: (CGFloat) -> CGFloat
    let currentScrollOffsetY: () -> CGFloat
    let onTap: () -> Void
    let onMoveRequested: () -> Void
    let onDragEnded: (CGFloat) -> Bool
    @ViewBuilder let content: () -> Content

    @State private var liveDragOffsetY: CGFloat = 0
    @State private var persistedOffsetY: CGFloat = 0
    @State private var isPanActive = false
    @State private var isPressingForMove = false
    @State private var suppressNextTap = false
    @State private var pressBeganAt: Date?

    private var dragDeltaY: CGFloat {
        persistedOffsetY + liveDragOffsetY
    }

    private var displayTop: CGFloat {
        top + dragDeltaY
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .overlay {
                if isDragActive {
                    ScheduleUIKitVerticalDragOverlay(
                        onChanged: handleDragChanged,
                        onEnded: handleDragEnded,
                        onInteractionReset: handleDragInteractionReset,
                        viewportHeight: viewportHeight,
                        canScrollTimelineUp: canScrollTimelineUp,
                        canScrollTimelineDown: canScrollTimelineDown,
                        onScrollTimelineBy: onScrollTimelineBy,
                        currentScrollOffsetY: currentScrollOffsetY,
                        shouldAllowEdgeScroll: { direction, translationY in
                            shouldAllowEdgeScroll(
                                direction,
                                persistedOffsetY + translationY
                            )
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isMoveSession {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onTap)
                } else {
                    interactionOverlay
                }
            }
            .overlay {
                if isPressingForMove {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.92), lineWidth: 2.5)
                        .allowsHitTesting(false)
                }
            }
            .offset(y: displayTop)
            .zIndex(isDragActive ? 3 : (isMoveSession ? 2 : (isPressingForMove ? 2 : 0)))
            .scaleEffect(scaleForInteractionState)
            .shadow(
                color: Color.black.opacity(isPressingForMove ? 0.18 : 0),
                radius: isPressingForMove ? 6 : 0,
                y: isPressingForMove ? 3 : 0
            )
            .transaction { transaction in
                if isPanActive {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .animation(isMoveSession || isPanActive ? nil : .spring(response: 0.26, dampingFraction: 0.84), value: isMoveSession)
            .animation(isMoveSession ? nil : .easeInOut(duration: 0.12), value: isPressingForMove)
            .onChange(of: isMoveSession) { _, inSession in
                if !inSession {
                    persistedOffsetY = 0
                    liveDragOffsetY = 0
                    isPanActive = false
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(isMoveSession ? .isSelected : .isButton)
    }

    private func handleDragChanged(_ translationY: CGFloat) {
        if !isPanActive {
            isPanActive = true
        }
        let totalOffsetY = persistedOffsetY + translationY
        let clampedTotal = liveClampDragOffset(totalOffsetY)
        liveDragOffsetY = clampedTotal - persistedOffsetY
    }

    private func handleDragInteractionReset() {
        guard !isPanActive else { return }
        liveDragOffsetY = 0
    }

    private func handleDragEnded(_ translationY: CGFloat) {
        isPanActive = false
        let totalOffsetY = persistedOffsetY + translationY
        liveDragOffsetY = 0

        let snappedTotal = snapDragOffset(totalOffsetY)
        if onDragEnded(snappedTotal) {
            persistedOffsetY = snappedTotal
        }
    }

    private var scaleForInteractionState: CGFloat {
        if isPressingForMove { return 0.98 }
        return 1
    }

    private var accessibilityLabel: String {
        if isDragActive { return "Moving appointment. Drag to a new time." }
        if isMoveSession { return "Appointment selected for rescheduling. Tap to drag again." }
        return "Appointment"
    }

    private var accessibilityHint: String {
        if isDragActive { return "Drag vertically to choose a new time slot." }
        if isMoveSession { return "Tap this booking to drag it again, or tap elsewhere on the schedule to inspect other times." }
        if canRequestMove { return "Tap for booking details. Hold to change the appointment time." }
        return "Tap for booking details."
    }

    @ViewBuilder
    private var interactionOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .modifier(StaticAppointmentInteractionModifier(
                isEnabled: !isMoveSession,
                canRequestMove: canRequestMove,
                moveHoldDuration: ScheduleAppointmentInteraction.moveHoldDuration,
                moveHoldMaxDistance: ScheduleAppointmentInteraction.moveHoldMaxDistance,
                isPressingForMove: $isPressingForMove,
                suppressNextTap: $suppressNextTap,
                pressBeganAt: $pressBeganAt,
                onTap: onTap,
                onMoveRequested: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onMoveRequested()
                }
            ))
    }
}

/// UIKit pan avoids SwiftUI `DragGesture` fighting `ScrollView` + `.offset` during reschedule drags.
private struct ScheduleUIKitVerticalDragOverlay: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onInteractionReset: () -> Void
    var viewportHeight: CGFloat
    var canScrollTimelineUp: () -> Bool
    var canScrollTimelineDown: () -> Bool
    var onScrollTimelineBy: (CGFloat) -> CGFloat
    var currentScrollOffsetY: () -> CGFloat
    var shouldAllowEdgeScroll: (CGFloat, CGFloat) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onChanged: onChanged,
            onEnded: onEnded,
            onInteractionReset: onInteractionReset,
            viewportHeight: viewportHeight,
            canScrollTimelineUp: canScrollTimelineUp,
            canScrollTimelineDown: canScrollTimelineDown,
            onScrollTimelineBy: onScrollTimelineBy,
            currentScrollOffsetY: currentScrollOffsetY,
            shouldAllowEdgeScroll: shouldAllowEdgeScroll
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.panRecognizer = pan
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onInteractionReset = onInteractionReset
        context.coordinator.viewportHeight = viewportHeight
        context.coordinator.canScrollTimelineUp = canScrollTimelineUp
        context.coordinator.canScrollTimelineDown = canScrollTimelineDown
        context.coordinator.onScrollTimelineBy = onScrollTimelineBy
        context.coordinator.currentScrollOffsetY = currentScrollOffsetY
        context.coordinator.shouldAllowEdgeScroll = shouldAllowEdgeScroll
        context.coordinator.configureScrollViewInteraction(for: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardownScrollViewInteraction()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void
        var onInteractionReset: () -> Void
        var viewportHeight: CGFloat
        var canScrollTimelineUp: () -> Bool
        var canScrollTimelineDown: () -> Bool
        var onScrollTimelineBy: (CGFloat) -> CGFloat
        var currentScrollOffsetY: () -> CGFloat
        var shouldAllowEdgeScroll: (CGFloat, CGFloat) -> Bool
        weak var panRecognizer: UIPanGestureRecognizer?

        private var edgeScrollDisplayLink: CADisplayLink?
        private var edgeScrollIntensity: CGFloat = 0
        private weak var edgeScrollTarget: UIScrollView?
        private weak var edgeScrollRecognizer: UIPanGestureRecognizer?
        private weak var wiredScrollView: UIScrollView?
        private var scrollOffsetObservation: NSKeyValueObservation?
        private var dragStartFingerViewportY: CGFloat?
        private var dragStartScrollOffsetY: CGFloat?

        private let edgeThreshold: CGFloat = 72
        /// Points per second at intensity 1.0 — scales up as the finger pushes further into the edge.
        private let maxEdgeScrollPointsPerSecond: CGFloat = 160
        /// Up to ~2.25× base speed when the finger is pushed well past the viewport edge.
        private let maxEdgeScrollIntensity: CGFloat = 2.25

        private func edgeScrollIntensity(fingerY: CGFloat, visibleHeight: CGFloat) -> CGFloat {
            if fingerY < edgeThreshold, canScrollTimelineUp() {
                let penetration = edgeThreshold - fingerY
                guard penetration > 0 else { return 0 }
                let normalized = penetration / edgeThreshold
                return -min(normalized, maxEdgeScrollIntensity)
            }

            if fingerY > visibleHeight - edgeThreshold, canScrollTimelineDown() {
                let penetration = fingerY - (visibleHeight - edgeThreshold)
                guard penetration > 0 else { return 0 }
                let normalized = penetration / edgeThreshold
                return min(normalized, maxEdgeScrollIntensity)
            }

            return 0
        }

        init(
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping (CGFloat) -> Void,
            onInteractionReset: @escaping () -> Void,
            viewportHeight: CGFloat,
            canScrollTimelineUp: @escaping () -> Bool,
            canScrollTimelineDown: @escaping () -> Bool,
            onScrollTimelineBy: @escaping (CGFloat) -> CGFloat,
            currentScrollOffsetY: @escaping () -> CGFloat,
            shouldAllowEdgeScroll: @escaping (CGFloat, CGFloat) -> Bool
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onInteractionReset = onInteractionReset
            self.viewportHeight = viewportHeight
            self.canScrollTimelineUp = canScrollTimelineUp
            self.canScrollTimelineDown = canScrollTimelineDown
            self.onScrollTimelineBy = onScrollTimelineBy
            self.currentScrollOffsetY = currentScrollOffsetY
            self.shouldAllowEdgeScroll = shouldAllowEdgeScroll
        }

        deinit {
            stopEdgeScroll()
            teardownScrollViewInteraction()
        }

        func configureScrollViewInteraction(for view: UIView) {
            guard let pan = panRecognizer,
                  let scrollView = view.enclosingScrollView else { return }

            if wiredScrollView !== scrollView {
                teardownScrollViewInteraction()
                scrollView.panGestureRecognizer.require(toFail: pan)
                wiredScrollView = scrollView
                scrollOffsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    self?.handleExternalScroll()
                }
            }
        }

        func teardownScrollViewInteraction() {
            scrollOffsetObservation?.invalidate()
            scrollOffsetObservation = nil
            wiredScrollView = nil
        }

        private func handleExternalScroll() {
            guard let pan = panRecognizer,
                  let scrollView = pan.view?.enclosingScrollView else { return }
            switch pan.state {
            case .began, .changed:
                onChanged(currentTranslation(recognizer: pan, scrollView: scrollView))
            default:
                onInteractionReset()
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let hostView = recognizer.view,
                  let scrollView = hostView.enclosingScrollView else { return }

            switch recognizer.state {
            case .began:
                dragStartFingerViewportY = fingerYInViewport(recognizer, scrollView: scrollView)
                dragStartScrollOffsetY = currentScrollOffsetY()
                onChanged(0)
            case .changed:
                onChanged(currentTranslation(recognizer: recognizer, scrollView: scrollView))
                let fingerY = fingerYInViewport(recognizer, scrollView: scrollView)
                updateEdgeScroll(fingerY: fingerY, scrollView: scrollView, recognizer: recognizer)
            case .ended, .cancelled, .failed:
                stopEdgeScroll()
                onEnded(currentTranslation(recognizer: recognizer, scrollView: scrollView))
                dragStartFingerViewportY = nil
                dragStartScrollOffsetY = nil
            default:
                break
            }
        }

        private func fingerYInViewport(_ recognizer: UIPanGestureRecognizer, scrollView: UIScrollView) -> CGFloat {
            let fingerInWindow = recognizer.location(in: nil)
            let viewportFrame = scrollView.convert(scrollView.bounds, to: nil)
            return fingerInWindow.y - viewportFrame.minY
        }

        private func currentTranslation(
            recognizer: UIPanGestureRecognizer,
            scrollView: UIScrollView
        ) -> CGFloat {
            guard let startFinger = dragStartFingerViewportY,
                  let startScroll = dragStartScrollOffsetY else { return 0 }
            let fingerDelta = fingerYInViewport(recognizer, scrollView: scrollView) - startFinger
            let scrollDelta = currentScrollOffsetY() - startScroll
            return fingerDelta + scrollDelta
        }

        private func updateEdgeScroll(
            fingerY: CGFloat,
            scrollView: UIScrollView,
            recognizer: UIPanGestureRecognizer
        ) {
            let visibleHeight = max(viewportHeight, scrollView.bounds.height)
            guard visibleHeight > edgeThreshold * 2 else {
                stopEdgeScroll()
                return
            }

            var intensity: CGFloat = 0
            intensity = edgeScrollIntensity(fingerY: fingerY, visibleHeight: visibleHeight)

            if abs(intensity) > 0.02 {
                let translation = currentTranslation(recognizer: recognizer, scrollView: scrollView)
                guard shouldAllowEdgeScroll(intensity, translation) else {
                    stopEdgeScroll()
                    return
                }
                startEdgeScroll(intensity: intensity, scrollView: scrollView, recognizer: recognizer)
            } else {
                stopEdgeScroll()
            }
        }

        private func startEdgeScroll(
            intensity: CGFloat,
            scrollView: UIScrollView,
            recognizer: UIPanGestureRecognizer
        ) {
            edgeScrollIntensity = intensity
            edgeScrollTarget = scrollView
            edgeScrollRecognizer = recognizer
            guard edgeScrollDisplayLink == nil else { return }

            let link = CADisplayLink(target: self, selector: #selector(edgeScrollTick(_:)))
            link.add(to: .main, forMode: .common)
            edgeScrollDisplayLink = link
        }

        private func stopEdgeScroll() {
            edgeScrollDisplayLink?.invalidate()
            edgeScrollDisplayLink = nil
            edgeScrollIntensity = 0
            edgeScrollTarget = nil
            edgeScrollRecognizer = nil
        }

        @objc private func edgeScrollTick(_ link: CADisplayLink) {
            guard let scrollView = edgeScrollTarget,
                  let recognizer = edgeScrollRecognizer else {
                stopEdgeScroll()
                return
            }

            let visibleHeight = max(viewportHeight, scrollView.bounds.height)
            let fingerY = fingerYInViewport(recognizer, scrollView: scrollView)
            let intensity = edgeScrollIntensity(fingerY: fingerY, visibleHeight: visibleHeight)
            edgeScrollIntensity = intensity

            guard abs(intensity) > 0.02 else {
                stopEdgeScroll()
                return
            }

            if intensity < 0, !canScrollTimelineUp() {
                stopEdgeScroll()
                return
            }
            if edgeScrollIntensity > 0, !canScrollTimelineDown() {
                stopEdgeScroll()
                return
            }

            let translation = currentTranslation(recognizer: recognizer, scrollView: scrollView)
            guard shouldAllowEdgeScroll(edgeScrollIntensity, translation) else {
                stopEdgeScroll()
                return
            }

            let deltaTime = max(link.duration, 1.0 / 120.0)
            let scrollDelta = edgeScrollIntensity * maxEdgeScrollPointsPerSecond * CGFloat(deltaTime)
            let appliedDelta = onScrollTimelineBy(scrollDelta)
            guard abs(appliedDelta) > 0.01 else {
                stopEdgeScroll()
                return
            }

            onChanged(currentTranslation(recognizer: recognizer, scrollView: scrollView))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer === wiredScrollView?.panGestureRecognizer
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        sequence(first: self, next: { $0.superview })
            .compactMap { $0 as? UIScrollView }
            .first
    }
}

/// Separates tap (details) from hold (reschedule) so they never fire together.
private struct StaticAppointmentInteractionModifier: ViewModifier {
    let isEnabled: Bool
    let canRequestMove: Bool
    let moveHoldDuration: Double
    let moveHoldMaxDistance: CGFloat
    @Binding var isPressingForMove: Bool
    @Binding var suppressNextTap: Bool
    @Binding var pressBeganAt: Date?
    let onTap: () -> Void
    let onMoveRequested: () -> Void

    @State private var pendingMoveHighlight: DispatchWorkItem?

    func body(content: Content) -> some View {
        if isEnabled, canRequestMove {
            content
                .onLongPressGesture(
                    minimumDuration: moveHoldDuration,
                    maximumDistance: moveHoldMaxDistance,
                    pressing: handlePressingChanged,
                    perform: handleMoveHoldRecognized
                )
                .onTapGesture(perform: handleTap)
        } else if isEnabled {
            content.onTapGesture(perform: onTap)
        } else {
            content
        }
    }

    private func handlePressingChanged(_ pressing: Bool) {
        if pressing {
            pressBeganAt = Date()
            pendingMoveHighlight?.cancel()
            let work = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isPressingForMove = true
                }
            }
            pendingMoveHighlight = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + ScheduleAppointmentInteraction.moveHoldHighlightDelay,
                execute: work
            )
            return
        }

        pendingMoveHighlight?.cancel()
        pendingMoveHighlight = nil
        withAnimation(.easeInOut(duration: 0.12)) {
            isPressingForMove = false
        }

        guard let began = pressBeganAt else { return }
        pressBeganAt = nil
        let heldDuration = Date().timeIntervalSince(began)
        // A partial hold should not open details when the user meant to reschedule.
        if heldDuration >= moveHoldDuration * 0.45 {
            suppressTapBriefly()
        }
    }

    private func handleMoveHoldRecognized() {
        suppressTapBriefly()
        onMoveRequested()
    }

    private func handleTap() {
        guard !suppressNextTap, !isPressingForMove else { return }
        onTap()
    }

    private func suppressTapBriefly() {
        suppressNextTap = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            suppressNextTap = false
        }
    }
}

// MARK: - Timeline bounds helper

enum ProviderScheduleTimelineBounds {
    static let defaultStartMinute = 8 * 60
    static let defaultEndMinute = 19 * 60
    /// Extra space below the timeline so the last time label is not clipped.
    static let bottomLabelClearance: CGFloat = 32

    /// Exact booking-hour envelope with no padding — day/minute views use this.
    static func exactRange(for intervals: [BarberAvailabilityIntervalDTO]) -> (start: Int, end: Int)? {
        guard !intervals.isEmpty else { return nil }
        var start = defaultEndMinute
        var end = defaultStartMinute
        for interval in intervals {
            let s = minutesFromHHMM(interval.start)
            let e = minutesFromHHMM(interval.end)
            start = min(start, s)
            end = max(end, e)
        }
        guard end > start else { return nil }
        return (start, end)
    }

    /// Week view: no padding on availability hours; extend one hour past the latest slot when a booking ends there.
    static func weekRange(
        intervals: [BarberAvailabilityIntervalDTO],
        bookings: [SimpleBookingDTO],
        calendar: Calendar,
        durationMinutes: Int = ProviderScheduleHourlySlot.bookableSlotMinutes
    ) -> (start: Int, end: Int) {
        guard let envelope = exactRange(for: intervals) else {
            return (defaultStartMinute, defaultEndMinute)
        }

        var start = envelope.start
        var end = envelope.end
        let availabilityEnd = envelope.end
        var bookingTouchesLatestAvailability = false

        for booking in bookings {
            guard let appointment = ScheduleCanvasAppointment.from(
                booking: booking,
                calendar: calendar,
                defaultDurationMinutes: durationMinutes
            ) else { continue }
            start = min(start, appointment.startMinute)
            let bookingEnd = appointment.startMinute + appointment.durationMinutes
            end = max(end, bookingEnd)
            if bookingEnd >= availabilityEnd || appointment.startMinute >= availabilityEnd {
                bookingTouchesLatestAvailability = true
            }
        }

        if bookingTouchesLatestAvailability {
            end = min(24 * 60, max(end, availabilityEnd + 60))
        }

        guard end > start else { return (defaultStartMinute, defaultEndMinute) }
        return (start, end)
    }

    /// Padded outer range — used where extra breathing room is still desired.
    static func range(for intervals: [BarberAvailabilityIntervalDTO], paddingMinutes: Int = 30) -> (start: Int, end: Int) {
        guard let exact = exactRange(for: intervals) else {
            return (defaultStartMinute, defaultEndMinute)
        }
        return (
            max(0, exact.start - paddingMinutes),
            min(24 * 60, exact.end + paddingMinutes)
        )
    }

    /// Hour labels plus exact schedule start/end when they fall between whole hours.
    static func scheduleBoundaryMarkers(from startMinute: Int, through endMinute: Int) -> [Int] {
        guard endMinute > startMinute else { return [] }

        var markers = Set<Int>([startMinute, endMinute])
        var minute = (startMinute / 60) * 60
        if minute < startMinute {
            minute += 60
        }
        while minute < endMinute {
            markers.insert(minute)
            minute += 60
        }
        return markers.sorted()
    }

    /// Total minutes of availability (excludes gaps between intervals).
    static func visibleMinuteSpan(for intervals: [BarberAvailabilityIntervalDTO]) -> Int {
        intervals.reduce(0) { total, interval in
            let s = minutesFromHHMM(interval.start)
            let e = minutesFromHHMM(interval.end)
            return total + max(0, e - s)
        }
    }

    private static func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }
}

/// Maps clock minutes into stacked availability segments (gaps between booking hours are omitted).
private struct ScheduleAvailabilityTimelineLayout {
    struct Segment: Equatable {
        let start: Int
        let end: Int
    }

    let segments: [Segment]
    let verticalScale: CGFloat

    init(intervals: [BarberAvailabilityIntervalDTO], verticalScale: CGFloat) {
        self.verticalScale = verticalScale
        self.segments = intervals
            .map { Segment(start: Self.minutesFromHHMM($0.start), end: Self.minutesFromHHMM($0.end)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }

    var isEmpty: Bool { segments.isEmpty }

    var contentHeight: CGFloat {
        segments.reduce(0) { $0 + CGFloat($1.end - $1.start) * verticalScale }
    }

    func contentY(forMinute minute: Int) -> CGFloat? {
        var offset: CGFloat = 0
        for segment in segments {
            if minute < segment.start { return nil }
            if minute < segment.end {
                return offset + CGFloat(minute - segment.start) * verticalScale
            }
            offset += CGFloat(segment.end - segment.start) * verticalScale
        }
        return nil
    }

    func minute(atContentY y: CGFloat) -> Int? {
        var offset: CGFloat = 0
        for segment in segments {
            let segmentHeight = CGFloat(segment.end - segment.start) * verticalScale
            if y < offset + segmentHeight {
                let minute = segment.start + Int(((y - offset) / verticalScale).rounded())
                return min(max(minute, segment.start), segment.end - 1)
            }
            offset += segmentHeight
        }
        return nil
    }

    func contains(minute: Int) -> Bool {
        segments.contains { minute >= $0.start && minute < $0.end }
    }

    private static func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }
}
