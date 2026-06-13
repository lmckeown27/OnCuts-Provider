import SwiftUI
import UIKit

// MARK: - Zoom tiers & presets

enum ProviderScheduleZoom {
    static let scaleMin: CGFloat = 0.15
    static let scaleMax: CGFloat = 5.0
    static let defaultScale: CGFloat = 1.5

    /// Fixed viewer height for month/week schedule boxes.
    static let canvasMinHeightDefault: CGFloat = 360

    /// Taller scrollable viewer for day/minute — timeline content may extend beyond and scroll inside.
    static let timelineVerticalScaleBoost: CGFloat = 1.4

    /// Target height for the day/minute schedule viewer box (timeline scrolls inside).
    static let dayMinuteViewerPreferredHeight: CGFloat = 440
    static let dayMinuteViewerMinHeight: CGFloat = 360
    static let dayMinuteViewerScreenMargin: CGFloat = 24

    /// Height of the day/minute schedule **viewer** area inside the card (below the tier header).
    /// Chrome above/below the card lives in the page `ScrollView` and is not subtracted here.
    static func canvasViewerHeight(availableHeight: CGFloat) -> CGFloat {
        let capped = max(dayMinuteViewerMinHeight, availableHeight - dayMinuteViewerScreenMargin)
        return min(dayMinuteViewerPreferredHeight, capped)
    }

    /// Tier boundaries — pinch scale crosses these to change Month / Week / Day / Minute.
    static let weekLower: CGFloat = 0.4
    static let dayLower: CGFloat = 1.5
    static let minuteLower: CGFloat = 3.5

    static func clamped(_ scale: CGFloat) -> CGFloat {
        Swift.max(scaleMin, Swift.min(scaleMax, scale))
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
        if scale >= ProviderScheduleZoom.minuteLower {
            self = .minute
        } else if scale >= ProviderScheduleZoom.dayLower {
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
        case .day: return "Daily schedule"
        case .week: return "Weekly overview"
        case .month: return "Monthly overview"
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
        guard let scheduled = booking.scheduledTime else { return nil }
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
    @Binding var movePromptBooking: SimpleBookingDTO?
    @Binding var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    var isApplyingTimeChange: Bool = false
    var onConfirmTimeChange: () -> Void = {}
    var onMoveBookingRequested: (SimpleBookingDTO) -> Void = { _ in }
    var onCancelMoveEditing: () -> Void = {}
    var onBookingTimeChangeProposed: (SimpleBookingDTO, Date) -> Void = { _, _ in }

    @State private var pinchZoomMultiplier: CGFloat = 1.0
    @State private var isPinchZoomActive = false
    @State private var pinchSessionScrollY: CGFloat = 0
    @State private var pinchSessionAnchorY: CGFloat = 0
    @State private var pinchSessionLastEffectiveScale: CGFloat = 1
    @State private var timelineScrollPosition = ScrollPosition()
    @State private var timelineScrollOffsetY: CGFloat = 0
    @State private var isPerformingDayScroll = false

    private var effectiveScale: CGFloat {
        ProviderScheduleZoom.clamped(zoomScale * pinchZoomMultiplier)
    }

    private var tier: ProviderScheduleZoomTier {
        ProviderScheduleZoomTier(effectiveScale: effectiveScale)
    }

    /// Pinch zoom is only available in day and minute tiers (preset buttons switch month/week).
    private var pinchZoomEnabled: Bool {
        ProviderScheduleZoomTier(effectiveScale: zoomScale).supportsPinchZoom
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
        if tier.supportsPinchZoom {
            return canvasViewerHeight ?? ProviderScheduleZoom.dayMinuteViewerPreferredHeight
        }
        return ProviderScheduleZoom.canvasMinHeightDefault
    }

    /// Scrollable timeline content height (timeline + vertical padding in day/minute canvas).
    private var timelineScrollContentHeight: CGFloat {
        CGFloat(timelineEndMinute - timelineStartMinute) * dayTimelineVerticalScale + 16
    }

    private var maxTimelineScrollOffsetY: CGFloat {
        maxTimelineScrollOffsetY(forEffectiveScale: effectiveScale)
    }

    private func maxTimelineScrollOffsetY(forEffectiveScale scale: CGFloat) -> CGFloat {
        let verticalScale = scale * ProviderScheduleZoom.timelineVerticalScaleBoost
        let contentHeight = CGFloat(timelineEndMinute - timelineStartMinute) * verticalScale + 16
        return max(0, contentHeight - resolvedViewerBoxHeight)
    }

    /// Keeps the timeline point under the pinch centroid fixed while scale changes.
    private func scrollOffsetAfterPinchIncrement(
        incrementalRatio: CGFloat,
        proposedEffectiveScale: CGFloat
    ) -> CGFloat {
        let padding = ScheduleTimelineDragLayout.contentVerticalPadding
        let rawScroll = padding * (1 - incrementalRatio)
            + pinchSessionScrollY * incrementalRatio
            + pinchSessionAnchorY * (incrementalRatio - 1)
        let maxScroll = maxTimelineScrollOffsetY(forEffectiveScale: proposedEffectiveScale)
        return min(max(rawScroll, 0), maxScroll)
    }

    private func handlePinchZoomBegan(anchorYInViewport: CGFloat) {
        isPinchZoomActive = true
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

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            zoomScale = proposedEffectiveScale
            pinchZoomMultiplier = 1.0
            isPinchZoomActive = false
        }
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

        let top = CGFloat(app.startMinute - timelineStartMinute) * dayTimelineVerticalScale
        let height = max(4, CGFloat(app.durationMinutes) * dayTimelineVerticalScale)
        let bookingContentTop = ScheduleTimelineDragLayout.contentVerticalPadding + top + clampedOffsetY
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

    private func scrollToRevealConfirmPrompt(
        for app: ScheduleCanvasAppointment,
        clampedOffsetY: CGFloat
    ) {
        scrollToShowBooking(for: app, clampedOffsetY: clampedOffsetY, reservePromptSpace: true)
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
        .onChange(of: editingMoveBookingID) { oldID, newID in
            guard oldID == nil, let newID, let app = appointments.first(where: { $0.id == newID }) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                scrollToFocusedBooking(for: app)
            }
        }
        .onChange(of: movePromptBooking) { oldValue, newValue in
            guard oldValue == nil,
                  let booking = newValue,
                  let app = appointments.first(where: { $0.id == booking.id }) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                scrollToRevealConfirmPrompt(for: app, clampedOffsetY: 0)
            }
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
        Group {
            if let editingID = editingMoveBookingID,
               let moving = appointments.first(where: { $0.id == editingID }) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Moving appointment")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.lavaShellCream)
                        Text("Drag \(moving.booking.consumerDisplayName) to a new open slot")
                            .font(.caption)
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button("Cancel") {
                        onCancelMoveEditing()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        Capsule()
                            .fill(Color.providerScheduleControlFill)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        Text("Daily schedule")
                            .opacity(dailyTierHeaderOpacity)
                        Text("Minute-by-minute")
                            .opacity(minuteTierHeaderOpacity)
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.lavaShellCream)
                    .animation(isPinchZoomActive ? nil : .smooth(duration: 0.28), value: effectiveScale)
                    Spacer()
                    if tier.supportsPinchZoom {
                        Text(String(format: "%.1fx", effectiveScale))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .contentTransition(.numericText())
                            .animation(isPinchZoomActive ? nil : .smooth(duration: 0.28), value: effectiveScale)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.2), value: editingMoveBookingID)
    }

    @ViewBuilder
    private func weekAwareScrollView(viewportSize: CGSize) -> some View {
        switch tier {
        case .week:
            ScrollView(.horizontal, showsIndicators: false) {
                canvasContent(in: viewportSize)
                    .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .contentShape(Rectangle())
        case .month:
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                canvasContent(in: viewportSize)
                    .frame(minWidth: viewportSize.width, alignment: .topLeading)
            }
            .contentShape(Rectangle())
        case .day, .minute:
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                canvasContent(in: viewportSize)
                    .frame(minWidth: viewportSize.width, alignment: .topLeading)
            }
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
                ScheduleMonthHeatmapGrid(
                    calendar: calendar,
                    monthAnchor: monthAnchor,
                    bookings: bookings,
                    onDayTap: onMonthDayTap
                )
                .frame(width: size.width)
            case .week:
                ScheduleWeekColumnsCanvas(
                    calendar: calendar,
                    weekStart: weekStartMonday,
                    bookings: bookings,
                    viewportSize: size,
                    startMinute: timelineStartMinute,
                    endMinute: timelineEndMinute,
                    dayAvailabilityIntervals: weekDayAvailabilityIntervals,
                    onDayTap: onWeekDayTap,
                    onBookingTap: onBookingTap
                )
                .frame(width: size.width, height: size.height, alignment: .top)
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
                    movePromptBooking: $movePromptBooking,
                    timeChangeProposal: $timeChangeProposal,
                    isApplyingTimeChange: isApplyingTimeChange,
                    onConfirmTimeChange: onConfirmTimeChange,
                    onMoveBookingRequested: onMoveBookingRequested,
                    onBookingTap: onBookingTap,
                    onAvailableMinuteTap: { minute in
                        if editingMoveBookingID != nil {
                            activeMoveDragBookingID = nil
                        }
                        onAvailableMinuteTap(minute)
                    },
                    onBookingTimeChangeProposed: onBookingTimeChangeProposed,
                    onBookingDropScroll: scrollToRevealConfirmPrompt,
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
        ProviderScheduleZoom.clamped(
            min(ProviderScheduleZoom.scaleMax, max(ProviderScheduleZoom.dayLower, scale))
        )
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
            let targetY = CGFloat(minute - timelineStartMinute) * dayTimelineVerticalScale + 8
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
}

private enum ScheduleTimelineDragLayout {
    static let contentVerticalPadding: CGFloat = 8
    static let viewportEdgeInset: CGFloat = 4
    /// Space reserved above a dropped booking so the confirm prompt stays visible.
    static let confirmPromptClearance: CGFloat = 152
}

enum ScheduleAppointmentDrag {
    static func isDraggable(_ booking: SimpleBookingDTO) -> Bool {
        switch ProviderBookingStatusDisplay.normalized(booking.status) {
        case "pending", "accepted":
            return booking.scheduledTime != nil
        default:
            return false
        }
    }

    static func snapMinute(_ minute: Int, step: Int) -> Int {
        guard step > 1 else { return minute }
        return ((minute + step / 2) / step) * step
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
    @Binding var movePromptBooking: SimpleBookingDTO?
    @Binding var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    let isApplyingTimeChange: Bool
    let onConfirmTimeChange: () -> Void
    let onMoveBookingRequested: (SimpleBookingDTO) -> Void
    let onBookingTap: (SimpleBookingDTO) -> Void
    let onAvailableMinuteTap: (Int) -> Void
    let onBookingTimeChangeProposed: (SimpleBookingDTO, Date) -> Void
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

    private var dragSnapStep: Int {
        scale >= ProviderScheduleZoom.minuteLower ? 5 : 15
    }

    private var timelineHeight: CGFloat {
        CGFloat(endMinute - startMinute) * verticalScale
    }

    private var detailTextOpacity: Double {
        if scale >= 1.2 { return 1 }
        if scale >= 0.7 { return Double((scale - 0.7) / 0.5) }
        return 0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if editingMoveBookingID != nil, activeMoveDragBookingID != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .frame(height: timelineHeight + 16)
                    .onTapGesture {
                        activeMoveDragBookingID = nil
                    }
            }
            availabilityBackground
            timeBlockOverlays
            tickMarks
            appointmentBlocks
        }
        .frame(height: timelineHeight)
        .padding(.vertical, 8)
    }

    private var availabilityBackground: some View {
        ForEach(availabilityIntervals.indices, id: \.self) { index in
            let interval = availabilityIntervals[index]
            let start = minutesFromHHMM(interval.start)
            let end = minutesFromHHMM(interval.end)
            if end > start {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.providerOlive.opacity(0.08))
                    .frame(height: CGFloat(end - start) * verticalScale)
                    .offset(x: 52, y: CGFloat(start - startMinute) * verticalScale)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var timeBlockOverlays: some View {
        ForEach(timeBlocks) { block in
            let start = minutesFromHHMM(block.startTime)
            let end = minutesFromHHMM(block.endTime)
            if end > start {
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
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.lavaShellCreamSecondary)
                                    .padding(.horizontal, 6)
                                    .opacity(detailTextOpacity)
                            }
                        }
                        .frame(height: max(4, CGFloat(end - start) * verticalScale))
                }
                .offset(y: CGFloat(start - startMinute) * verticalScale)
            }
        }
    }

    private var tickMarks: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(stride(from: startMinute, to: endMinute, by: ScheduleTimelineZoomVisuals.fineTickStep)),
                id: \.self
            ) { minute in
                tickRow(for: minute)
            }
        }
        .animation(isPinchZoomActive ? nil : .smooth(duration: 0.28), value: scale)
    }

    private func tickRow(for minute: Int) -> some View {
        let presentation = tickPresentation(for: minute)
        let rowHeight = CGFloat(ScheduleTimelineZoomVisuals.fineTickStep) * verticalScale

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
            .font(.system(size: ScheduleTimelineZoomVisuals.tickLabelFontSize(scale: scale)))
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

        if minute % 30 == 0, majorOpacity > 0.04 {
            return TickPresentation(
                label: formatMinuteLabel(minute),
                labelOpacity: majorOpacity,
                lineOpacity: 0.16 + 0.24 * majorOpacity
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
            appointmentBlock(for: app)
        }
    }

    @ViewBuilder
    private func appointmentBlock(for app: ScheduleCanvasAppointment) -> some View {
        let top = CGFloat(app.startMinute - startMinute) * verticalScale
        let height = max(4, CGFloat(app.durationMinutes) * verticalScale)
        let canMove = appointmentDragEnabled && ScheduleAppointmentDrag.isDraggable(app.booking)
        let isMoveSession = editingMoveBookingID == app.id
        let isDragActive = activeMoveDragBookingID == app.id
        let isParked = isMoveSession && !isDragActive
        let allowedStart = allowedDragStartMinuteRange(for: app)
        let minDragOffsetY = CGFloat(allowedStart.minStart - app.startMinute) * verticalScale
        let maxDragOffsetY = CGFloat(allowedStart.maxStart - app.startMinute) * verticalScale

        ScheduleDraggableAppointmentBlock(
            top: top,
            height: height,
            appointmentID: app.booking.id,
            isMoveSession: isMoveSession,
            isDragActive: isDragActive,
            canRequestMove: canMove && editingMoveBookingID == nil,
            hasActivePrompt: movePromptBooking?.id == app.booking.id
                || timeChangeProposal?.booking.id == app.booking.id,
            minDragOffsetY: minDragOffsetY,
            maxDragOffsetY: maxDragOffsetY,
            snapDragOffset: { totalOffsetY in
                clampedDragOffsetY(for: app, totalOffsetY: totalOffsetY, snapToGrid: true)
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
                    .background(appointmentColor(for: app.booking, isDragActive: isDragActive, isParked: isParked))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        if isDragActive {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.providerOlive.opacity(0.95), lineWidth: 2)
                        } else if isParked {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.lavaShellCreamSecondary.opacity(0.55), lineWidth: 2)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } promptOverlay: {
            if let booking = movePromptBooking, booking.id == app.booking.id {
                ScheduleBookingAbovePromptAnchor {
                    ScheduleAnchoredAppointmentPromptCard(
                        title: "Change appointment time?",
                        message: "You held this booking to reschedule. Drag it to an open slot, then confirm the new time.",
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
                }
            } else if let proposal = timeChangeProposal, proposal.booking.id == app.booking.id {
                let fromTime = proposal.originalTime.formatted(date: .omitted, time: .shortened)
                let toTime = proposal.proposedTime.formatted(date: .omitted, time: .shortened)
                ScheduleBookingAbovePromptAnchor {
                    ScheduleAnchoredAppointmentPromptCard(
                        title: "Confirm time change",
                        message: "Move \(proposal.booking.consumerDisplayName)'s \(proposal.booking.serviceDisplayName) from \(fromTime) to \(toTime)?",
                        primaryTitle: isApplyingTimeChange ? "Saving…" : "Confirm",
                        secondaryTitle: "Cancel",
                        isPrimaryDisabled: isApplyingTimeChange,
                        onPrimary: onConfirmTimeChange,
                        onSecondary: {
                            timeChangeProposal = nil
                            editingMoveBookingID = nil
                            activeMoveDragBookingID = nil
                        }
                    )
                }
            }
        }
    }

    /// Latest/earliest start times derived from the provider's availability windows.
    private func allowedDragStartMinuteRange(for app: ScheduleCanvasAppointment) -> (minStart: Int, maxStart: Int) {
        let timelineMin = startMinute
        let timelineMax = max(startMinute, endMinute - app.durationMinutes)

        guard !availabilityIntervals.isEmpty else {
            return (timelineMin, timelineMax)
        }

        var minStart = Int.max
        var maxStart = Int.min
        for interval in availabilityIntervals {
            let intervalStart = minutesFromHHMM(interval.start)
            let intervalEnd = minutesFromHHMM(interval.end)
            guard intervalEnd - intervalStart >= app.durationMinutes else { continue }
            minStart = min(minStart, intervalStart)
            maxStart = max(maxStart, intervalEnd - app.durationMinutes)
        }

        guard minStart <= maxStart else {
            return (timelineMin, timelineMax)
        }

        return (max(minStart, timelineMin), min(maxStart, timelineMax))
    }

    private func visibleDragOffsetRange(top: CGFloat, height: CGFloat) -> (min: CGFloat, max: CGFloat) {
        let scrollY = currentScrollOffsetY()
        let padding = ScheduleTimelineDragLayout.contentVerticalPadding
        let inset = ScheduleTimelineDragLayout.viewportEdgeInset
        let minOffset = scrollY - padding - top + inset
        let maxOffset = scrollY + viewportHeight - height - padding - top - inset
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
            totalOffsetY: totalOffsetY,
            snapToGrid: false
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
            totalOffsetY: totalOffsetY,
            snapToGrid: false
        )
        let scrollY = currentScrollOffsetY()
        let padding = ScheduleTimelineDragLayout.contentVerticalPadding
        let inset = ScheduleTimelineDragLayout.viewportEdgeInset

        if direction > 0, availabilityClamped >= maxDragOffsetY - 1 {
            let viewportTop = padding + top + availabilityClamped - scrollY
            if viewportTop <= padding + inset + 1 {
                return false
            }
        }

        if direction < 0, availabilityClamped <= minDragOffsetY + 1 {
            let viewportBottom = padding + top + availabilityClamped - scrollY + height
            if viewportBottom >= viewportHeight - padding - inset - 1 {
                return false
            }
        }

        return true
    }

    private func clampedDragOffsetY(
        for app: ScheduleCanvasAppointment,
        totalOffsetY: CGFloat,
        snapToGrid: Bool
    ) -> CGFloat {
        let rawProposedMinute = CGFloat(app.startMinute) + (totalOffsetY / verticalScale)
        let proposedMinute: CGFloat
        if snapToGrid {
            let snapped = ScheduleAppointmentDrag.snapMinute(
                Int(rawProposedMinute.rounded()),
                step: dragSnapStep
            )
            proposedMinute = CGFloat(snapped)
        } else {
            proposedMinute = rawProposedMinute
        }

        let allowed = allowedDragStartMinuteRange(for: app)
        let clampedStart = min(
            max(proposedMinute, CGFloat(allowed.minStart)),
            CGFloat(allowed.maxStart)
        )
        return (clampedStart - CGFloat(app.startMinute)) * verticalScale
    }

    @discardableResult
    private func handleAppointmentDragEnded(app: ScheduleCanvasAppointment, totalOffsetY: CGFloat) -> Bool {
        let clampedOffsetY = clampedDragOffsetY(for: app, totalOffsetY: totalOffsetY, snapToGrid: true)
        let clampedStart = app.startMinute + Int((clampedOffsetY / verticalScale).rounded())
        guard let proposedDate = scheduledDate(on: day, totalMinutes: clampedStart) else { return false }

        activeMoveDragBookingID = nil
        onBookingDropScroll(app, clampedOffsetY)
        onBookingTimeChangeProposed(app.booking, proposedDate)
        return true
    }

    private func isOpenSlot(startMinute: Int, durationMinutes: Int, excludingAppointmentID: String) -> Bool {
        let endMinute = startMinute + durationMinutes

        for other in appointments where other.id != excludingAppointmentID {
            let otherEnd = other.startMinute + other.durationMinutes
            if startMinute < otherEnd && endMinute > other.startMinute {
                return false
            }
        }

        for block in timeBlocks {
            let blockStart = minutesFromHHMM(block.startTime)
            let blockEnd = minutesFromHHMM(block.endTime)
            if startMinute < blockEnd && endMinute > blockStart {
                return false
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
        let booking = app.booking
        let detailLevel = appointmentDetailLevel(for: blockHeight)

        VStack(alignment: .center, spacing: detailLineSpacing(for: detailLevel)) {
            if isDragActive {
                Label("Drag to move", systemImage: "arrow.up.and.down")
                    .font(.system(size: min(12, detailFontSize(for: blockHeight) + 1), weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .allowsHitTesting(false)
            } else if isMoveSession {
                Label("Tap to drag again", systemImage: "hand.tap")
                    .font(.system(size: min(12, detailFontSize(for: blockHeight) + 1), weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .allowsHitTesting(false)
            } else if canRequestMove, blockHeight >= 34 {
                appointmentInteractionHint(blockHeight: blockHeight)
            }

            if detailTextOpacity > 0.05 {
                Text(booking.consumerDisplayName)
                    .font(.system(size: consumerFontSize(for: blockHeight, level: detailLevel), weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit(for: detailLevel, primary: true))
                    .minimumScaleFactor(0.85)
                    .opacity(detailTextOpacity)
                    .allowsHitTesting(false)

                Text(booking.serviceDisplayName)
                    .font(.system(size: serviceFontSize(for: blockHeight, level: detailLevel), weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit(for: detailLevel, primary: false))
                    .minimumScaleFactor(0.85)
                    .opacity(detailTextOpacity * 0.9)
                    .allowsHitTesting(false)

                if detailLevel >= .standard {
                    Text(appointmentTimeRange(for: app))
                        .font(.system(size: detailFontSize(for: blockHeight), weight: .medium))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .multilineTextAlignment(.center)
                        .allowsHitTesting(false)

                    Text(ProviderBookingStatusDisplay.title(for: booking.status))
                        .font(.system(size: detailFontSize(for: blockHeight) - 1, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .multilineTextAlignment(.center)
                        .allowsHitTesting(false)
                }

                if detailLevel >= .detailed {
                    if let price = formattedPrice(for: booking) {
                        Text(price)
                            .font(.system(size: detailFontSize(for: blockHeight), weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream)
                            .multilineTextAlignment(.center)
                            .allowsHitTesting(false)
                    }

                    if let duration = formattedDuration(minutes: app.durationMinutes) {
                        Text(duration)
                            .font(.system(size: detailFontSize(for: blockHeight) - 1, weight: .medium))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                            .multilineTextAlignment(.center)
                            .allowsHitTesting(false)
                    }

                    if booking.hasPendingRescheduleRequest {
                        Text("Reschedule requested")
                            .font(.system(size: detailFontSize(for: blockHeight) - 1, weight: .semibold))
                            .foregroundStyle(Color.orange.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .allowsHitTesting(false)
                    }

                    if let location = trimmedNonEmpty(booking.location) {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: detailFontSize(for: blockHeight) - 2))
                            Text(location)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        .font(.system(size: detailFontSize(for: blockHeight) - 1, weight: .medium))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                    }

                    if let notes = trimmedNonEmpty(booking.notes) {
                        Text(notes)
                            .font(.system(size: detailFontSize(for: blockHeight) - 1, weight: .regular))
                            .italic()
                            .foregroundStyle(Color.lavaShellCreamTertiary)
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

    @ViewBuilder
    private func appointmentInteractionHint(blockHeight: CGFloat) -> some View {
        let fontSize = max(8, detailFontSize(for: blockHeight) - 2)
        HStack(spacing: 8) {
            Label("Tap for details", systemImage: "hand.tap")
            Label("Hold to move time", systemImage: "clock.arrow.circlepath")
        }
        .font(.system(size: fontSize, weight: .medium))
        .foregroundStyle(Color.lavaShellCream.opacity(0.72))
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

    private func appointmentColor(for booking: SimpleBookingDTO, isDragActive: Bool, isParked: Bool) -> Color {
        if isParked {
            return Color.lavaShellCreamSecondary.opacity(0.24)
        }

        let base: Color
        if ProviderBookingStatusDisplay.isScheduleCompleted(status: booking.status) {
            base = Color.green.opacity(0.32)
        } else if ProviderBookingStatusDisplay.isScheduleBooked(status: booking.status) {
            base = Color.providerOlive.opacity(0.44)
        } else {
            base = Color.providerScheduleCardFill
        }
        if isDragActive {
            return base.opacity(0.92)
        }
        return base
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

private struct ScheduleAnchoredAppointmentPromptCard: View {
    let title: String
    let message: String
    let primaryTitle: String
    let secondaryTitle: String
    let isPrimaryDisabled: Bool
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.lavaShellCream)

            Text(message)
                .font(.caption)
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onSecondary) {
                    Text(secondaryTitle)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.lavaShellCream)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.providerScheduleControlFill)
                }

                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.lavaShellCream)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.providerOlive.opacity(isPrimaryDisabled ? 0.25 : 0.55))
                }
                .disabled(isPrimaryDisabled)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.providerSchedulePromptCardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.providerOlive.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.28), radius: 10, y: 4)
        }
    }
}

private struct ScheduleAppointmentPromptArrow: View {
    let pointingUp: Bool

    var body: some View {
        Image(systemName: pointingUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.providerSchedulePromptCardFill)
            .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

// MARK: - Appointment move / confirm prompts (anchored on booking)

/// Positions a prompt card directly above its booking block in local coordinates.
private struct ScheduleBookingAbovePromptAnchor<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(280, max(180, geo.size.width + 120))
            VStack(spacing: 0) {
                content()
                    .frame(width: cardWidth)
                ScheduleAppointmentPromptArrow(pointingUp: false)
            }
            .fixedSize(horizontal: false, vertical: true)
            .position(x: geo.size.width / 2, y: 0)
            .offset(y: -72)
        }
        .allowsHitTesting(true)
    }
}

private enum ScheduleAppointmentInteraction {
    static let moveHoldDuration = 0.25
    static let moveHoldMaxDistance: CGFloat = 10
    /// Delay before hold feedback appears so quick taps stay visually neutral.
    static var moveHoldHighlightDelay: Double { moveHoldDuration * 0.42 }
}

private struct ScheduleDraggableAppointmentBlock<Content: View, PromptOverlay: View>: View {
    let top: CGFloat
    let height: CGFloat
    let appointmentID: String
    let isMoveSession: Bool
    let isDragActive: Bool
    let canRequestMove: Bool
    let hasActivePrompt: Bool
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
    @ViewBuilder let promptOverlay: () -> PromptOverlay

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
            .overlay {
                if hasActivePrompt {
                    promptOverlay()
                }
            }
            .offset(y: displayTop)
            .zIndex(hasActivePrompt ? 50 : (isDragActive ? 3 : (isMoveSession ? 2 : (isPressingForMove ? 2 : 0))))
            .scaleEffect(scaleForInteractionState)
            .shadow(
                color: Color.black.opacity(isDragActive ? 0.32 : (isPressingForMove ? 0.18 : 0)),
                radius: isDragActive ? 10 : (isPressingForMove ? 6 : 0),
                y: isDragActive ? 5 : (isPressingForMove ? 3 : 0)
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
        if isDragActive { return 1.03 }
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

// MARK: - Week columns

private struct ScheduleWeekColumnsCanvas: View {
    let calendar: Calendar
    let weekStart: Date
    let bookings: [SimpleBookingDTO]
    let viewportSize: CGSize
    let startMinute: Int
    let endMinute: Int
    let dayAvailabilityIntervals: [[BarberAvailabilityIntervalDTO]]
    let onDayTap: (Date) -> Void
    let onBookingTap: (SimpleBookingDTO) -> Void

    private let columnSpacing: CGFloat = 8

    /// Weekday + date labels and padding above the timeline track.
    private var columnHeaderHeight: CGFloat { 36 }

    /// Outer canvas padding (`.padding(10)`) plus per-column button padding.
    private var verticalChrome: CGFloat { 32 }

    /// Fits the full availability window into the viewer — no vertical scroll.
    private var timelineHeight: CGFloat {
        max(48, viewportSize.height - columnHeaderHeight - verticalChrome)
    }

    /// Points per minute so the day column ends at the bottom of the schedule viewer.
    private var columnScale: CGFloat {
        let minuteSpan = CGFloat(max(1, endMinute - startMinute))
        return timelineHeight / minuteSpan
    }

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(0 ..< 7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                let dayBookings = bookings.filter { $0.isSameCalendarDay(as: day, calendar: calendar) }
                let apps = dayBookings.compactMap { ScheduleCanvasAppointment.from(booking: $0, calendar: calendar) }
                let intervals = dayAvailabilityIntervals.indices.contains(offset)
                    ? dayAvailabilityIntervals[offset]
                    : []

                Button {
                    onDayTap(day)
                } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                calendar.isDateInToday(day) ? Color.lavaShellCream : Color.lavaShellCreamSecondary
                            )
                        Text(day.formatted(.dateTime.day()))
                            .font(.caption2)
                            .foregroundStyle(Color.lavaShellCreamTertiary)

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.providerScheduleControlFill)
                            bookableSlotGrid(intervals: intervals)
                            ForEach(apps) { app in
                                let top = CGFloat(app.startMinute - startMinute) * columnScale
                                let height = max(3, CGFloat(app.durationMinutes) * columnScale)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.providerOlive.opacity(0.55))
                                    .frame(height: height)
                                    .offset(y: top)
                                    .padding(.horizontal, 2)
                            }
                        }
                        .frame(height: timelineHeight)
                        .clipped()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(calendar.isDateInToday(day) ? Color.providerOlive.opacity(0.22) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: viewportSize.height, alignment: .top)
        .padding(10)
    }

    @ViewBuilder
    private func bookableSlotGrid(intervals: [BarberAvailabilityIntervalDTO]) -> some View {
        let slots = resolvedBookableSlots(intervals: intervals)
        ForEach(slots, id: \.startMinutes) { slot in
            let top = CGFloat(slot.startMinutes - startMinute) * columnScale
            let height = max(1, CGFloat(slot.endMinutes - slot.startMinutes) * columnScale)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.providerOlive.opacity(0.07))
                .frame(height: height)
                .offset(y: top)
                .padding(.horizontal, 2)

            Rectangle()
                .fill(Color.lavaShellCreamTertiary.opacity(0.32))
                .frame(height: 0.5)
                .offset(y: top)
                .padding(.horizontal, 2)

            Rectangle()
                .fill(Color.lavaShellCreamTertiary.opacity(0.22))
                .frame(height: 0.5)
                .offset(y: top + height)
                .padding(.horizontal, 2)
        }
    }

    private func resolvedBookableSlots(intervals: [BarberAvailabilityIntervalDTO]) -> [ProviderScheduleHourlySlot] {
        let bookable = ProviderScheduleHourlySlot.generateBookableSlots(from: intervals)
        if !bookable.isEmpty { return bookable }
        return ProviderScheduleHourlySlot.generateBookableSlots(from: [timelineSpanInterval])
    }

    private var timelineSpanInterval: BarberAvailabilityIntervalDTO {
        BarberAvailabilityIntervalDTO(
            id: "timeline-span",
            start: Self.hhmm(from: startMinute),
            end: Self.hhmm(from: endMinute)
        )
    }

    private static func hhmm(from totalMinutes: Int) -> String {
        String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}

// MARK: - Month heatmap

private struct ScheduleMonthHeatmapGrid: View {
    let calendar: Calendar
    let monthAnchor: Date
    let bookings: [SimpleBookingDTO]
    let onDayTap: (Date) -> Void

    private let cellHeight: CGFloat = 34
    private let gridSpacing: CGFloat = 5
    private let dayFontSize: CGFloat = 11

    private var gridDays: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: monthAnchor) ?? 1 ..< 29
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor)) ?? monthAnchor
        let weekday = calendar.component(.weekday, from: first)
        let pad = (weekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: pad)
        for d in range {
            if let date = calendar.date(byAdding: .day, value: d - 1, to: first) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 7), spacing: gridSpacing) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                ForEach(gridDays.indices, id: \.self) { index in
                    if let date = gridDays[index] {
                        monthDayCell(date: date)
                    } else {
                        Color.clear.frame(height: cellHeight)
                    }
                }
            }
            .padding(12)
        }
    }

    private func monthDayCell(date: Date) -> some View {
        let dayBookings = bookings.filter { $0.isSameCalendarDay(as: date, calendar: calendar) }
        let count = dayBookings.count
        let booked = dayBookings.filter { ProviderBookingStatusDisplay.isScheduleBooked(status: $0.status) }.count
        let completed = dayBookings.filter { ProviderBookingStatusDisplay.isScheduleCompleted(status: $0.status) }.count
        let intensity = min(1.0, Double(count) / 4.0)
        let isToday = calendar.isDateInToday(date)

        return Button {
            onDayTap(date)
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: dayFontSize, weight: isToday ? .bold : .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                HStack(spacing: 3) {
                    if booked > 0 {
                        Circle()
                            .fill(Color.providerOlive)
                            .frame(width: 6, height: 6)
                    }
                    if completed > 0 {
                        Circle()
                            .fill(Color.green.opacity(0.85))
                            .frame(width: 6, height: 6)
                    }
                    if count == 0 {
                        Circle()
                            .fill(Color.lavaShellCreamTertiary.opacity(0.25))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.providerOlive.opacity(intensity * 0.35 + (isToday ? 0.12 : 0)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isToday ? Color.providerOlive.opacity(0.7) : Color.providerScheduleCardStroke,
                                lineWidth: isToday ? 1 : 0.5
                            )
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline bounds helper

enum ProviderScheduleTimelineBounds {
    static let defaultStartMinute = 8 * 60
    static let defaultEndMinute = 19 * 60

    static func range(for intervals: [BarberAvailabilityIntervalDTO]) -> (start: Int, end: Int) {
        guard !intervals.isEmpty else {
            return (defaultStartMinute, defaultEndMinute)
        }
        var start = defaultEndMinute
        var end = defaultStartMinute
        for interval in intervals {
            let s = minutesFromHHMM(interval.start)
            let e = minutesFromHHMM(interval.end)
            start = min(start, s)
            end = max(end, e)
        }
        return (max(0, start - 30), min(24 * 60, end + 30))
    }

    private static func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }
}
