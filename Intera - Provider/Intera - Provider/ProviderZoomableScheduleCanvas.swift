import SwiftUI

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

    static func from(booking: SimpleBookingDTO, calendar: Calendar, defaultDurationMinutes: Int = 60) -> ScheduleCanvasAppointment? {
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
    let timeBlocks: [BarberTimeBlockDTO]
    let blockTimeTapsEnabled: Bool
    let onBookingTap: (SimpleBookingDTO) -> Void
    let onAvailableMinuteTap: (Int) -> Void
    let onWeekDayTap: (Date) -> Void
    let onMonthDayTap: (Date) -> Void
    /// Height of the day/minute **viewer box**; timeline content scrolls vertically inside it.
    var canvasViewerHeight: CGFloat?
    var appointmentDragEnabled: Bool = false
    @Binding var editingMoveBookingID: String?
    @Binding var movePromptBooking: SimpleBookingDTO?
    @Binding var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    var isApplyingTimeChange: Bool = false
    var onConfirmTimeChange: () -> Void = {}
    var onMoveBookingRequested: (SimpleBookingDTO) -> Void = { _ in }
    var onCancelMoveEditing: () -> Void = {}
    var onBookingTimeChangeProposed: (SimpleBookingDTO, Date) -> Void = { _, _ in }

    @GestureState private var dynamicGestureScale: CGFloat = 1.0

    private var effectiveScale: CGFloat {
        ProviderScheduleZoom.clamped(zoomScale * dynamicGestureScale)
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
            .sorted { $0.startMinute < $1.startMinute }
    }

    private var resolvedViewerBoxHeight: CGFloat {
        if tier.supportsPinchZoom {
            return canvasViewerHeight ?? ProviderScheduleZoom.dayMinuteViewerPreferredHeight
        }
        return ProviderScheduleZoom.canvasMinHeightDefault
    }

    var body: some View {
        VStack(spacing: 0) {
            zoomContextHeader

            Divider()
                .overlay(Color.providerScheduleTrackStroke)

            GeometryReader { proxy in
                weekAwareScrollView(viewportSize: proxy.size)
                    .modifier(PinchZoomGestureModifier(
                        isEnabled: pinchZoomEnabled && editingMoveBookingID == nil,
                        gesture: magnificationGesture
                    ))
            }
            .frame(height: resolvedViewerBoxHeight)
        }
        .background(Color.providerScheduleCardFill.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.providerScheduleTrackStroke, lineWidth: 0.6)
        )
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
                    Text(tier.headerLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.lavaShellCream)
                    Spacer()
                    if tier.supportsPinchZoom {
                        Text(String(format: "%.1fx", effectiveScale))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.lavaShellCreamSecondary)
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
            .scrollDisabled(editingMoveBookingID != nil)
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
                    startMinute: timelineStartMinute,
                    endMinute: timelineEndMinute,
                    availabilityIntervals: availabilityIntervals,
                    timeBlocks: timeBlocks,
                    blockTimeTapsEnabled: blockTimeTapsEnabled,
                    appointmentDragEnabled: appointmentDragEnabled,
                    editingMoveBookingID: $editingMoveBookingID,
                    movePromptBooking: $movePromptBooking,
                    timeChangeProposal: $timeChangeProposal,
                    isApplyingTimeChange: isApplyingTimeChange,
                    onConfirmTimeChange: onConfirmTimeChange,
                    onMoveBookingRequested: onMoveBookingRequested,
                    onBookingTap: onBookingTap,
                    onAvailableMinuteTap: onAvailableMinuteTap,
                    onBookingTimeChangeProposed: onBookingTimeChangeProposed
                )
                .frame(width: size.width)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tier)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($dynamicGestureScale) { value, state, _ in
                guard pinchZoomEnabled else { return }
                let clamped = Self.clampToPinchZoomRange(zoomScale * value)
                state = clamped / zoomScale
            }
            .onEnded { value in
                guard pinchZoomEnabled else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    zoomScale = Self.clampToPinchZoomRange(zoomScale * value)
                }
            }
    }

    /// Keeps pinch zoom within day and minute tiers only.
    private static func clampToPinchZoomRange(_ scale: CGFloat) -> CGFloat {
        ProviderScheduleZoom.clamped(
            min(ProviderScheduleZoom.scaleMax, max(ProviderScheduleZoom.dayLower, scale))
        )
    }
}

private struct PinchZoomGestureModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(gesture)
        } else {
            content
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

private enum ScheduleTimelineCoordinateSpace {
    static let name = "scheduleTimelineCanvas"
}

private struct ScheduleAppointmentFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
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

private struct SchedulePreciseTimelineCanvas: View {
    let calendar: Calendar
    let day: Date
    let appointments: [ScheduleCanvasAppointment]
    let scale: CGFloat
    let startMinute: Int
    let endMinute: Int
    let availabilityIntervals: [BarberAvailabilityIntervalDTO]
    let timeBlocks: [BarberTimeBlockDTO]
    let blockTimeTapsEnabled: Bool
    let appointmentDragEnabled: Bool
    @Binding var editingMoveBookingID: String?
    @Binding var movePromptBooking: SimpleBookingDTO?
    @Binding var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    let isApplyingTimeChange: Bool
    let onConfirmTimeChange: () -> Void
    let onMoveBookingRequested: (SimpleBookingDTO) -> Void
    let onBookingTap: (SimpleBookingDTO) -> Void
    let onAvailableMinuteTap: (Int) -> Void
    let onBookingTimeChangeProposed: (SimpleBookingDTO, Date) -> Void

    private var tickStep: Int {
        scale >= 3.5 ? 5 : (scale >= 2.0 ? 15 : 30)
    }

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
            availabilityBackground
            timeBlockOverlays
            tickMarks
            appointmentBlocks
        }
        .coordinateSpace(name: ScheduleTimelineCoordinateSpace.name)
        .frame(height: timelineHeight)
        .padding(.vertical, 8)
        .overlayPreferenceValue(ScheduleAppointmentFrameKey.self) { frames in
            GeometryReader { proxy in
                if let booking = movePromptBooking, let frame = frames[booking.id] {
                    anchoredPrompt(
                        title: "Move booking?",
                        message: "Move \(booking.consumerDisplayName)'s \(booking.serviceDisplayName) to a different open time slot?",
                        primaryTitle: "Move",
                        secondaryTitle: "Cancel",
                        isPrimaryDisabled: false,
                        targetFrame: frame,
                        in: proxy.size
                    ) {
                        editingMoveBookingID = booking.id
                        movePromptBooking = nil
                    } onSecondary: {
                        movePromptBooking = nil
                    }
                }

                if let proposal = timeChangeProposal, let frame = frames[proposal.booking.id] {
                    let fromTime = proposal.originalTime.formatted(date: .omitted, time: .shortened)
                    let toTime = proposal.proposedTime.formatted(date: .omitted, time: .shortened)
                    anchoredPrompt(
                        title: "Confirm time change",
                        message: "Move \(proposal.booking.consumerDisplayName)'s \(proposal.booking.serviceDisplayName) from \(fromTime) to \(toTime)?",
                        primaryTitle: isApplyingTimeChange ? "Saving…" : "Confirm",
                        secondaryTitle: "Cancel",
                        isPrimaryDisabled: isApplyingTimeChange,
                        targetFrame: frame,
                        in: proxy.size
                    ) {
                        onConfirmTimeChange()
                    } onSecondary: {
                        timeChangeProposal = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func anchoredPrompt(
        title: String,
        message: String,
        primaryTitle: String,
        secondaryTitle: String,
        isPrimaryDisabled: Bool,
        targetFrame: CGRect,
        in containerSize: CGSize,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void
    ) -> some View {
        let cardWidth = min(280, max(180, containerSize.width - 72))
        let showAbove = targetFrame.minY > 118
        let anchorX = min(max(targetFrame.midX, cardWidth / 2 + 12), containerSize.width - cardWidth / 2 - 12)

        VStack(spacing: 0) {
            if !showAbove {
                ScheduleAppointmentPromptArrow(pointingUp: true)
            }

            ScheduleAnchoredAppointmentPromptCard(
                title: title,
                message: message,
                primaryTitle: primaryTitle,
                secondaryTitle: secondaryTitle,
                isPrimaryDisabled: isPrimaryDisabled,
                onPrimary: onPrimary,
                onSecondary: onSecondary
            )
            .frame(width: cardWidth)

            if showAbove {
                ScheduleAppointmentPromptArrow(pointingUp: false)
            }
        }
        .position(
            x: anchorX,
            y: showAbove
                ? targetFrame.minY - 58
                : targetFrame.maxY + 58
        )
        .zIndex(20)
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
            ForEach(Array(stride(from: startMinute, to: endMinute, by: tickStep)), id: \.self) { minute in
                HStack(alignment: .top, spacing: 6) {
                    Text(formatMinuteLabel(minute))
                        .font(.system(size: scale >= 3.5 ? 9 : 10))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .frame(width: 52, alignment: .trailing)
                    Rectangle()
                        .fill(Color.lavaShellCreamTertiary.opacity(0.35))
                        .frame(height: 0.5)
                }
                .frame(height: CGFloat(tickStep) * verticalScale, alignment: .top)
            }
        }
    }

    private var appointmentBlocks: some View {
        ForEach(appointments) { app in
            let top = CGFloat(app.startMinute - startMinute) * verticalScale
            let height = max(4, CGFloat(app.durationMinutes) * verticalScale)
            let canMove = appointmentDragEnabled && ScheduleAppointmentDrag.isDraggable(app.booking)
            let isEditing = editingMoveBookingID == app.id

            ScheduleDraggableAppointmentBlock(
                top: top,
                height: height,
                isEditing: isEditing,
                canRequestMove: canMove && editingMoveBookingID == nil,
                onTap: {
                    guard editingMoveBookingID == nil else { return }
                    onBookingTap(app.booking)
                },
                onMoveRequested: { onMoveBookingRequested(app.booking) },
                onDragEnded: { translationY in
                    handleAppointmentDragEnded(app: app, translationY: translationY)
                }
            ) {
                HStack(spacing: 0) {
                    Spacer().frame(width: 52)
                    appointmentBlockContent(for: app, blockHeight: height, isEditing: isEditing)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .background(appointmentColor(for: app.booking, isEditing: isEditing))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            if isEditing {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.providerOlive.opacity(0.95), lineWidth: 2)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScheduleAppointmentFrameKey.self,
                                    value: [
                                        app.id: geo.frame(in: .named(ScheduleTimelineCoordinateSpace.name))
                                    ]
                                )
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func handleAppointmentDragEnded(app: ScheduleCanvasAppointment, translationY: CGFloat) {
        guard abs(translationY) > 4 else { return }

        let deltaMinutes = Int((translationY / verticalScale).rounded())
        let rawProposed = app.startMinute + deltaMinutes
        let snapped = ScheduleAppointmentDrag.snapMinute(rawProposed, step: dragSnapStep)
        let clampedStart = min(
            max(snapped, startMinute),
            max(startMinute, endMinute - app.durationMinutes)
        )

        guard clampedStart != app.startMinute else { return }
        guard isOpenSlot(
            startMinute: clampedStart,
            durationMinutes: app.durationMinutes,
            excludingAppointmentID: app.id
        ) else { return }
        guard let proposedDate = scheduledDate(on: day, totalMinutes: clampedStart) else { return }

        onBookingTimeChangeProposed(app.booking, proposedDate)
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
        isEditing: Bool
    ) -> some View {
        let booking = app.booking
        let detailLevel = appointmentDetailLevel(for: blockHeight)

        VStack(alignment: .center, spacing: detailLineSpacing(for: detailLevel)) {
            if isEditing {
                Label("Drag to move", systemImage: "arrow.up.and.down")
                    .font(.system(size: min(12, detailFontSize(for: blockHeight) + 1), weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .allowsHitTesting(false)
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

    private func appointmentColor(for booking: SimpleBookingDTO, isEditing: Bool) -> Color {
        let base: Color
        if ProviderBookingStatusDisplay.isScheduleCompleted(status: booking.status) {
            base = Color.green.opacity(0.32)
        } else if ProviderBookingStatusDisplay.isScheduleBooked(status: booking.status) {
            base = Color.providerOlive.opacity(0.44)
        } else {
            base = Color.providerScheduleCardFill
        }
        if isEditing {
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
                .fill(Color.providerScheduleCardFill)
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
            .foregroundStyle(Color.providerScheduleCardFill)
            .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

private struct ScheduleDraggableAppointmentBlock<Content: View>: View {
    let top: CGFloat
    let height: CGFloat
    let isEditing: Bool
    let canRequestMove: Bool
    let onTap: () -> Void
    let onMoveRequested: () -> Void
    let onDragEnded: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    @GestureState private var dragTranslationY: CGFloat = 0

    private var displayTop: CGFloat {
        top + (isEditing ? dragTranslationY : 0)
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isEditing else { return }
                        onTap()
                    }
                    .gesture(isEditing ? editingDragGesture : nil)
                    .simultaneousGesture(canRequestMove ? moveRequestGesture : nil)
            }
            .offset(y: displayTop)
            .zIndex(isEditing ? 3 : 0)
            .scaleEffect(isEditing ? 1.03 : 1)
            .shadow(
                color: Color.black.opacity(isEditing ? 0.32 : 0),
                radius: isEditing ? 10 : 0,
                y: isEditing ? 5 : 0
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isEditing)
    }

    /// Static mode: long-press anywhere on the box to ask whether to enter move mode.
    private var moveRequestGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                onMoveRequested()
            }
    }

    /// Editing mode: simple vertical drag without fighting the scroll view.
    private var editingDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragTranslationY) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                onDragEnded(value.translation.height)
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
