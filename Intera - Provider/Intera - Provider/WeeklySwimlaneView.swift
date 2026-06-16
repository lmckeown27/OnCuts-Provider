import SwiftUI
import UIKit

// MARK: - Data model

struct SwimlaneAppointment: Identifiable, Equatable {
    let id: String
    let booking: SimpleBookingDTO
    let startMinute: Int
    let durationMinutes: Int

    var densityWeight: Double {
        switch durationMinutes {
        case ..<30: return 0.45
        case 30 ..< 50: return 0.65
        case 50 ..< 75: return 0.82
        default: return 1.0
        }
    }

    static func from(booking: SimpleBookingDTO, calendar: Calendar) -> SwimlaneAppointment? {
        guard let canvas = ScheduleCanvasAppointment.from(booking: booking, calendar: calendar) else { return nil }
        return SwimlaneAppointment(
            id: canvas.id,
            booking: canvas.booking,
            startMinute: canvas.startMinute,
            durationMinutes: canvas.durationMinutes
        )
    }
}

private struct WeeklyPositionedAppointment: Identifiable {
    let appointment: SwimlaneAppointment
    let dayIndex: Int

    var id: String { appointment.id }
}

// MARK: - Layout constants

private enum WeeklySwimlaneLayout {
    static let timeGutterWidth: CGFloat = 56
    static let timeGutterLabelFontSize: CGFloat = 10
    static let dayHeaderHeight: CGFloat = 46
    static let outerPaddingLeading: CGFloat = 4
    static let outerPaddingTrailing: CGFloat = 10
    static let outerPaddingVertical: CGFloat = 10
    static let dayColumnWidth: CGFloat = 68
    static let dayColumnSpacing: CGFloat = 10
    static let trackCornerRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 7
    static let densityStripeWidth: CGFloat = 3.5
    static let minimumCardHeight: CGFloat = 18
    static let cardHorizontalInset: CGFloat = 4
    /// Increase to add more vertical breathing room between appointments.
    static let verticalScaleBoost: CGFloat = 1.08
    static let moveSnapStepMinutes = 15
}

private enum WeeklySwimlaneInteraction {
    static let moveHoldDuration = 0.25
    static let moveHoldMaxDistance: CGFloat = 10
    static var moveHoldHighlightDelay: Double { moveHoldDuration * 0.42 }
}

private enum WeeklySwimlaneDragLayout {
    static let viewportEdgeInset: CGFloat = 4

    /// Width of the left/right edge band where horizontal auto-scroll speed ramps with pointer depth.
    static let horizontalEdgeScrollZone: CGFloat = 96
    /// Max scroll speed (pt/s) when the pointer is flush with the viewport edge.
    static let horizontalEdgeScrollMaxPointsPerSecond: CGFloat = 120
    /// Extra speed when the pointer is pushed past the viewport edge (up to this intensity multiplier).
    static let horizontalEdgeScrollOvershootCap: CGFloat = 1.4

    /// Vertical edge band and speed (time axis).
    static let verticalEdgeScrollZone: CGFloat = 72
    static let verticalEdgeScrollMaxPointsPerSecond: CGFloat = 96
    static let verticalEdgeScrollOvershootCap: CGFloat = 1.25
    /// Smooths vertical edge speed changes only; horizontal tracks pointer depth directly.
    static let verticalEdgeScrollIntensitySmoothingRate: CGFloat = 5
}

// MARK: - Weekly swimlane

struct WeeklySwimlaneView: View {
    let calendar: Calendar
    let weekStart: Date
    let bookings: [SimpleBookingDTO]
    let viewportSize: CGSize
    let startMinute: Int
    let endMinute: Int
    let dayAvailabilityIntervals: [[BarberAvailabilityIntervalDTO]]
    let dayEntirelyBlockedOff: [Bool]
    let dayTimeBlocks: [[BarberTimeBlockDTO]]
    let onDayTap: (Date) -> Void
    let onBookingTap: (SimpleBookingDTO) -> Void

    var appointmentDragEnabled: Bool = false
    @Binding var editingMoveBookingID: String?
    @Binding var activeMoveDragBookingID: String?
    @Binding var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    var onMoveBookingRequested: (SimpleBookingDTO) -> Void = { _ in }
    var onBookingTimeChangeProposed: (SimpleBookingDTO, Date) -> Void = { _, _ in }

    private var minuteSpan: Int {
        max(1, endMinute - startMinute)
    }

    private var trackAreaHeight: CGFloat {
        max(
            120,
            viewportSize.height - WeeklySwimlaneLayout.dayHeaderHeight - (WeeklySwimlaneLayout.outerPaddingVertical * 2)
        )
    }

    private var pointsPerMinute: CGFloat {
        (trackAreaHeight / CGFloat(minuteSpan)) * WeeklySwimlaneLayout.verticalScaleBoost
    }

    private var contentTrackHeight: CGFloat {
        CGFloat(minuteSpan) * pointsPerMinute + ProviderScheduleTimelineBounds.bottomLabelClearance
    }

    private var usesVerticalScroll: Bool {
        contentTrackHeight > trackAreaHeight + 1
    }

    private var weekGridWidth: CGFloat {
        (WeeklySwimlaneLayout.timeGutterWidth * 2)
            + (WeeklySwimlaneLayout.dayColumnWidth * 7)
            + (WeeklySwimlaneLayout.dayColumnSpacing * 6)
    }

    private var layoutWidth: CGFloat {
        max(
            viewportSize.width,
            weekGridWidth
                + WeeklySwimlaneLayout.outerPaddingLeading
                + WeeklySwimlaneLayout.outerPaddingTrailing
        )
    }

    private var dayColumnStride: CGFloat {
        WeeklySwimlaneLayout.dayColumnWidth + WeeklySwimlaneLayout.dayColumnSpacing
    }

    private var timeGutterMarkers: [Int] {
        var markers = Set(
            ProviderScheduleTimelineBounds.scheduleBoundaryMarkers(
                from: startMinute,
                through: endMinute
            )
        )
        for dayIntervals in dayAvailabilityIntervals {
            for interval in dayIntervals {
                markers.insert(minutesFromHHMM(interval.start))
                markers.insert(minutesFromHHMM(interval.end))
            }
        }
        return markers.filter { $0 >= startMinute && $0 <= endMinute }.sorted()
    }

    private func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }

    private var positionedAppointments: [WeeklyPositionedAppointment] {
        (0 ..< 7).flatMap { offset in
            let day = dayDate(offset: offset)
            return appointments(for: day).map {
                WeeklyPositionedAppointment(appointment: $0, dayIndex: offset)
            }
        }
    }

    private var moveResolver: WeeklySwimlaneMoveResolver {
        WeeklySwimlaneMoveResolver(
            calendar: calendar,
            weekStart: weekStart,
            startMinute: startMinute,
            endMinute: endMinute,
            pointsPerMinute: pointsPerMinute,
            dayColumnStride: dayColumnStride,
            dayAvailabilityIntervals: dayAvailabilityIntervals,
            dayTimeBlocks: dayTimeBlocks,
            positionedAppointments: positionedAppointments
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            dayHeaderRow
                .padding(.top, WeeklySwimlaneLayout.outerPaddingVertical)

            trackScrollRegion
                .padding(.bottom, WeeklySwimlaneLayout.outerPaddingVertical)
        }
        .frame(width: layoutWidth, height: viewportSize.height, alignment: .top)
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: WeeklySwimlaneLayout.outerPaddingLeading)

            HStack(spacing: WeeklySwimlaneLayout.dayColumnSpacing) {
                Color.clear
                    .frame(width: WeeklySwimlaneLayout.timeGutterWidth)

                ForEach(0 ..< 7, id: \.self) { offset in
                    dayHeader(
                        for: dayDate(offset: offset),
                        isBlockedOff: isEntireDayBlockedOff(for: offset)
                    )
                    .frame(width: WeeklySwimlaneLayout.dayColumnWidth)
                }

                Color.clear
                    .frame(width: WeeklySwimlaneLayout.timeGutterWidth)
            }
            .frame(width: weekGridWidth, alignment: .leading)

            Color.clear
                .frame(width: WeeklySwimlaneLayout.outerPaddingTrailing)
        }
        .frame(width: layoutWidth, height: WeeklySwimlaneLayout.dayHeaderHeight, alignment: .leading)
    }

    @ViewBuilder
    private var trackScrollRegion: some View {
        let tracks = AnyView(
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: WeeklySwimlaneLayout.outerPaddingLeading)

                    HStack(alignment: .top, spacing: WeeklySwimlaneLayout.dayColumnSpacing) {
                        WeeklySwimlaneTimeGutterView(
                            calendar: calendar,
                            labeledMinutes: timeGutterMarkers,
                            startMinute: startMinute,
                            pointsPerMinute: pointsPerMinute,
                            trackHeight: contentTrackHeight,
                            labelPlacement: .leadingEdge
                        )
                        .frame(width: WeeklySwimlaneLayout.timeGutterWidth)

                        ForEach(0 ..< 7, id: \.self) { offset in
                            WeeklySwimlaneDayTrackView(
                                day: dayDate(offset: offset),
                                availabilityIntervals: availabilityIntervals(for: offset),
                                isEntireDayBlockedOff: isEntireDayBlockedOff(for: offset),
                                timeBlocks: dayTimeBlocks.indices.contains(offset) ? dayTimeBlocks[offset] : [],
                                startMinute: startMinute,
                                endMinute: endMinute,
                                pointsPerMinute: pointsPerMinute,
                                trackHeight: contentTrackHeight,
                                moveEditingActive: editingMoveBookingID != nil,
                                onDayTap: onDayTap
                            )
                            .frame(width: WeeklySwimlaneLayout.dayColumnWidth)
                        }

                        WeeklySwimlaneTimeGutterView(
                            calendar: calendar,
                            labeledMinutes: timeGutterMarkers,
                            startMinute: startMinute,
                            pointsPerMinute: pointsPerMinute,
                            trackHeight: contentTrackHeight,
                            labelPlacement: .trailingEdge
                        )
                        .frame(width: WeeklySwimlaneLayout.timeGutterWidth)
                    }
                    .frame(width: weekGridWidth, alignment: .leading)

                    Color.clear
                        .frame(width: WeeklySwimlaneLayout.outerPaddingTrailing)
                }
                .frame(width: layoutWidth, alignment: .leading)

                WeeklySwimlaneAppointmentsLayer(
                    positionedAppointments: positionedAppointments,
                    moveResolver: moveResolver,
                    startMinute: startMinute,
                    pointsPerMinute: pointsPerMinute,
                    dayColumnStride: dayColumnStride,
                    trackHeight: contentTrackHeight,
                    viewportWidth: viewportSize.width,
                    viewportHeight: trackAreaHeight,
                    appointmentDragEnabled: appointmentDragEnabled,
                    editingMoveBookingID: $editingMoveBookingID,
                    activeMoveDragBookingID: $activeMoveDragBookingID,
                    timeChangeProposal: $timeChangeProposal,
                    onMoveBookingRequested: onMoveBookingRequested,
                    onBookingTap: onBookingTap,
                    onBookingTimeChangeProposed: onBookingTimeChangeProposed
                )
                .offset(x: WeeklySwimlaneLayout.outerPaddingLeading)
                .frame(width: weekGridWidth, height: contentTrackHeight, alignment: .topLeading)
            }
            .frame(width: layoutWidth, alignment: .leading)
        )

        if usesVerticalScroll {
            ScrollView(.vertical, showsIndicators: false) {
                tracks
            }
            .frame(height: trackAreaHeight)
        } else {
            tracks
                .frame(height: trackAreaHeight, alignment: .top)
        }
    }

    @ViewBuilder
    private func dayHeader(for day: Date, isBlockedOff: Bool) -> some View {
        let isToday = calendar.isDateInToday(day)

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                onDayTap(day)
            }
        } label: {
            ZStack {
                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(isToday ? Color.lavaShellCream : Color.lavaShellCreamSecondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.provider(.subheadline, weight: isToday ? .bold : .semibold))
                        .foregroundStyle(isToday ? Color.providerOlive : Color.lavaShellCream)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isToday {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.providerOlive.opacity(0.14))
                    }
                }

                if isBlockedOff {
                    ProviderScheduleEntireDayCrossOutOverlay(cornerRadius: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func dayDate(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
    }

    private func availabilityIntervals(for offset: Int) -> [BarberAvailabilityIntervalDTO] {
        dayAvailabilityIntervals.indices.contains(offset) ? dayAvailabilityIntervals[offset] : []
    }

    private func isEntireDayBlockedOff(for offset: Int) -> Bool {
        dayEntirelyBlockedOff.indices.contains(offset) ? dayEntirelyBlockedOff[offset] : false
    }

    private func appointments(for day: Date) -> [SwimlaneAppointment] {
        bookings
            .filter { $0.isSameCalendarDay(as: day, calendar: calendar) }
            .compactMap { SwimlaneAppointment.from(booking: $0, calendar: calendar) }
            .sorted { $0.startMinute < $1.startMinute }
    }

    fileprivate static func dayColumnOriginX(dayIndex: Int) -> CGFloat {
        WeeklySwimlaneLayout.timeGutterWidth + CGFloat(dayIndex) * (
            WeeklySwimlaneLayout.dayColumnWidth + WeeklySwimlaneLayout.dayColumnSpacing
        )
    }
}

// MARK: - Move resolver

private struct WeeklySwimlaneMoveResolver {
    let calendar: Calendar
    let weekStart: Date
    let startMinute: Int
    let endMinute: Int
    let pointsPerMinute: CGFloat
    let dayColumnStride: CGFloat
    let dayAvailabilityIntervals: [[BarberAvailabilityIntervalDTO]]
    let dayTimeBlocks: [[BarberTimeBlockDTO]]
    let positionedAppointments: [WeeklyPositionedAppointment]

    func dayDate(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
    }

    func clampedDragOffset(
        for positioned: WeeklyPositionedAppointment,
        totalOffsetX: CGFloat,
        totalOffsetY: CGFloat
    ) -> CGPoint {
        let proposed = proposedPosition(
            for: positioned,
            totalOffsetX: totalOffsetX,
            totalOffsetY: totalOffsetY
        )
        let offsetX = CGFloat(proposed.dayIndex - positioned.dayIndex) * dayColumnStride
        let offsetY = CGFloat(proposed.startMinute - positioned.appointment.startMinute) * pointsPerMinute
        return CGPoint(x: offsetX, y: offsetY)
    }

    /// Resolves the snapped drag offset from the finger position in week-grid coordinates.
    /// Grid origin is the top-leading corner of the appointments layer (not the scroll view).
    func clampedDragOffsetFromGridPoint(
        for positioned: WeeklyPositionedAppointment,
        gridX: CGFloat,
        gridY: CGFloat
    ) -> CGPoint {
        let rawDayIndex = Int(
            round(
                (gridX - WeeklySwimlaneLayout.timeGutterWidth - WeeklySwimlaneLayout.dayColumnWidth * 0.5)
                    / dayColumnStride
            )
        )
        let rawMinute = startMinute + Int(round(gridY / pointsPerMinute))
        let resolved = resolvedOpenStart(
            dayIndex: rawDayIndex,
            proposedMinute: rawMinute,
            durationMinutes: positioned.appointment.durationMinutes,
            excludingAppointmentID: positioned.appointment.id
        )
        let offsetX = CGFloat(resolved.dayIndex - positioned.dayIndex) * dayColumnStride
        let offsetY = CGFloat(resolved.startMinute - positioned.appointment.startMinute) * pointsPerMinute
        return CGPoint(x: offsetX, y: offsetY)
    }

    @discardableResult
    func handleDragEndedFromGridPoint(
        for positioned: WeeklyPositionedAppointment,
        gridX: CGFloat,
        gridY: CGFloat,
        onProposed: (SimpleBookingDTO, Date) -> Void
    ) -> Bool {
        let offset = clampedDragOffsetFromGridPoint(for: positioned, gridX: gridX, gridY: gridY)
        return handleDragEnded(
            for: positioned,
            totalOffsetX: offset.x,
            totalOffsetY: offset.y,
            onProposed: onProposed
        )
    }

    @discardableResult
    func handleDragEnded(
        for positioned: WeeklyPositionedAppointment,
        totalOffsetX: CGFloat,
        totalOffsetY: CGFloat,
        onProposed: (SimpleBookingDTO, Date) -> Void
    ) -> Bool {
        let proposed = proposedPosition(
            for: positioned,
            totalOffsetX: totalOffsetX,
            totalOffsetY: totalOffsetY
        )
        guard proposed.dayIndex != positioned.dayIndex || proposed.startMinute != positioned.appointment.startMinute else {
            return false
        }
        guard let proposedDate = scheduledDate(dayIndex: proposed.dayIndex, totalMinutes: proposed.startMinute) else {
            return false
        }
        onProposed(positioned.appointment.booking, proposedDate)
        return true
    }

    private func proposedPosition(
        for positioned: WeeklyPositionedAppointment,
        totalOffsetX: CGFloat,
        totalOffsetY: CGFloat
    ) -> (dayIndex: Int, startMinute: Int) {
        let rawDayIndex = positioned.dayIndex + Int(round(totalOffsetX / dayColumnStride))
        let rawMinute = positioned.appointment.startMinute + Int(round(totalOffsetY / pointsPerMinute))
        let resolved = resolvedOpenStart(
            dayIndex: rawDayIndex,
            proposedMinute: rawMinute,
            durationMinutes: positioned.appointment.durationMinutes,
            excludingAppointmentID: positioned.appointment.id
        )
        return resolved
    }

    private func resolvedOpenStart(
        dayIndex: Int,
        proposedMinute: Int,
        durationMinutes: Int,
        excludingAppointmentID: String
    ) -> (dayIndex: Int, startMinute: Int) {
        let clampedDay = min(max(dayIndex, 0), 6)
        let snapped = ScheduleAppointmentDrag.snapMinute(proposedMinute, step: WeeklySwimlaneLayout.moveSnapStepMinutes)

        if isOpenSlot(
            dayIndex: clampedDay,
            startMinute: snapped,
            durationMinutes: durationMinutes,
            excludingAppointmentID: excludingAppointmentID,
            allowBlockedTime: true
        ) {
            return (clampedDay, snapped)
        }

        let nearest = nearestOpenStart(
            aroundDayIndex: clampedDay,
            aroundMinute: snapped,
            durationMinutes: durationMinutes,
            excludingAppointmentID: excludingAppointmentID
        )
        return nearest ?? (clampedDay, snapped)
    }

    private func nearestOpenStart(
        aroundDayIndex dayIndex: Int,
        aroundMinute minute: Int,
        durationMinutes: Int,
        excludingAppointmentID: String
    ) -> (dayIndex: Int, startMinute: Int)? {
        let step = WeeklySwimlaneLayout.moveSnapStepMinutes
        for radius in 0 ... 6 {
            for dayDelta in -radius ... radius {
                let candidateDay = dayIndex + dayDelta
                guard (0 ... 6).contains(candidateDay) else { continue }

                let minuteRadius = max(radius - abs(dayDelta), 0)
                if minuteRadius == 0 {
                    let snapped = ScheduleAppointmentDrag.snapMinute(minute, step: step)
                    if isOpenSlot(
                        dayIndex: candidateDay,
                        startMinute: snapped,
                        durationMinutes: durationMinutes,
                        excludingAppointmentID: excludingAppointmentID,
                        allowBlockedTime: true
                    ) {
                        return (candidateDay, snapped)
                    }
                    continue
                }

                for minuteDelta in stride(from: step, through: minuteRadius * step * 4, by: step) {
                    for candidateMinute in [minute - minuteDelta, minute + minuteDelta] {
                        let snapped = ScheduleAppointmentDrag.snapMinute(candidateMinute, step: step)
                        if isOpenSlot(
                            dayIndex: candidateDay,
                            startMinute: snapped,
                            durationMinutes: durationMinutes,
                            excludingAppointmentID: excludingAppointmentID,
                            allowBlockedTime: true
                        ) {
                            return (candidateDay, snapped)
                        }
                    }
                }
            }
        }
        return nil
    }

    private func isOpenSlot(
        dayIndex: Int,
        startMinute: Int,
        durationMinutes: Int,
        excludingAppointmentID: String,
        allowBlockedTime: Bool = false
    ) -> Bool {
        let endMinute = startMinute + durationMinutes
        guard startMinute >= self.startMinute, endMinute <= self.endMinute else { return false }

        for other in positionedAppointments where other.appointment.id != excludingAppointmentID && other.dayIndex == dayIndex {
            let otherEnd = other.appointment.startMinute + other.appointment.durationMinutes
            if startMinute < otherEnd && endMinute > other.appointment.startMinute {
                return false
            }
        }

        if !allowBlockedTime {
            let blocks = dayTimeBlocks.indices.contains(dayIndex) ? dayTimeBlocks[dayIndex] : []
            for block in blocks {
                let blockStart = minutesFromHHMM(block.startTime)
                let blockEnd = minutesFromHHMM(block.endTime)
                if startMinute < blockEnd && endMinute > blockStart {
                    return false
                }
            }
        }

        let intervals = dayAvailabilityIntervals.indices.contains(dayIndex) ? dayAvailabilityIntervals[dayIndex] : []
        guard !intervals.isEmpty else { return true }
        return intervals.contains { interval in
            let intervalStart = minutesFromHHMM(interval.start)
            let intervalEnd = minutesFromHHMM(interval.end)
            return startMinute >= intervalStart && endMinute <= intervalEnd
        }
    }

    private func scheduledDate(dayIndex: Int, totalMinutes: Int) -> Date? {
        let day = dayDate(offset: dayIndex)
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: totalMinutes, to: dayStart)
    }

    private func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }
}

// MARK: - Appointments layer

private struct WeeklySwimlaneAppointmentsLayer: View {
    let positionedAppointments: [WeeklyPositionedAppointment]
    let moveResolver: WeeklySwimlaneMoveResolver
    let startMinute: Int
    let pointsPerMinute: CGFloat
    let dayColumnStride: CGFloat
    let trackHeight: CGFloat
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    let appointmentDragEnabled: Bool
    @Binding var editingMoveBookingID: String?
    @Binding var activeMoveDragBookingID: String?
    @Binding var timeChangeProposal: ScheduleAppointmentTimeChangeProposal?
    let onMoveBookingRequested: (SimpleBookingDTO) -> Void
    let onBookingTap: (SimpleBookingDTO) -> Void
    let onBookingTimeChangeProposed: (SimpleBookingDTO, Date) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(positionedAppointments) { positioned in
                weeklyAppointmentCard(for: positioned)
            }
        }
        .frame(height: trackHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func weeklyAppointmentCard(for positioned: WeeklyPositionedAppointment) -> some View {
        let appointment = positioned.appointment
        let cardTop = CGFloat(appointment.startMinute - startMinute) * pointsPerMinute
        let cardHeight = max(
            WeeklySwimlaneLayout.minimumCardHeight,
            CGFloat(appointment.durationMinutes) * pointsPerMinute
        )
        let originX = WeeklySwimlaneView.dayColumnOriginX(dayIndex: positioned.dayIndex)
        let canMove = appointmentDragEnabled && ScheduleAppointmentDrag.isDraggable(appointment.booking)
        let isMoveSession = editingMoveBookingID == appointment.id
        let isDragActive = activeMoveDragBookingID == appointment.id

        WeeklyDraggableSwimlaneAppointmentCard(
            originX: originX,
            top: cardTop,
            height: cardHeight,
            columnWidth: WeeklySwimlaneLayout.dayColumnWidth,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            isMoveSession: isMoveSession,
            isDragActive: isDragActive,
            canRequestMove: canMove && editingMoveBookingID == nil,
            snapDragOffsetFromGridPoint: { gridPoint in
                moveResolver.clampedDragOffsetFromGridPoint(
                    for: positioned,
                    gridX: gridPoint.x,
                    gridY: gridPoint.y
                )
            },
            onTap: {
                if let editingID = editingMoveBookingID {
                    if appointment.id == editingID {
                        timeChangeProposal = nil
                        activeMoveDragBookingID = appointment.id
                    } else {
                        activeMoveDragBookingID = nil
                    }
                    return
                }
                onBookingTap(appointment.booking)
            },
            onMoveRequested: { onMoveBookingRequested(appointment.booking) },
            onDragEndedAtGridPoint: { gridPoint in
                let moved = moveResolver.handleDragEndedFromGridPoint(
                    for: positioned,
                    gridX: gridPoint.x,
                    gridY: gridPoint.y,
                    onProposed: onBookingTimeChangeProposed
                )
                if moved {
                    activeMoveDragBookingID = nil
                }
                return moved
            }
        ) {
            WeeklySwimlaneAppointmentCardContent(
                appointment: appointment,
                cardHeight: cardHeight,
                isMoveSession: isMoveSession,
                isDragActive: isDragActive
            )
        }
    }
}

// MARK: - Time gutter

private struct WeeklySwimlaneTimeGutterView: View {
    enum LabelPlacement {
        /// Left gutter — labels align toward the day columns.
        case leadingEdge
        /// Right gutter — labels align toward the day columns.
        case trailingEdge
    }

    let calendar: Calendar
    let labeledMinutes: [Int]
    let startMinute: Int
    let pointsPerMinute: CGFloat
    let trackHeight: CGFloat
    var labelPlacement: LabelPlacement = .leadingEdge

    /// Anchor labels toward the day columns; allow overflow into outer padding so AM/PM isn't clipped.
    private var gutterAlignment: Alignment {
        switch labelPlacement {
        case .leadingEdge: .topTrailing
        case .trailingEdge: .topLeading
        }
    }

    var body: some View {
        ZStack(alignment: gutterAlignment) {
            Color.clear
                .frame(height: trackHeight)

            ForEach(labeledMinutes, id: \.self) { minute in
                Text(formatHour(minute))
                    .font(.provider(size: WeeklySwimlaneLayout.timeGutterLabelFontSize, weight: .medium))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(y: CGFloat(minute - startMinute) * pointsPerMinute)
            }
        }
        .frame(width: WeeklySwimlaneLayout.timeGutterWidth, height: trackHeight, alignment: .top)
    }

    private func formatHour(_ totalMinutes: Int) -> String {
        let hour = totalMinutes / 60
        let minute = totalMinutes % 60
        if minute == 0 {
            let displayHour = hour % 12 == 0 ? 12 : hour % 12
            let meridiem = hour < 12 ? "AM" : "PM"
            return "\(displayHour) \(meridiem)"
        }
        let date = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: .now
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Day track

private struct WeeklySwimlaneDayTrackView: View {
    let day: Date
    let availabilityIntervals: [BarberAvailabilityIntervalDTO]
    let isEntireDayBlockedOff: Bool
    let timeBlocks: [BarberTimeBlockDTO]
    let startMinute: Int
    let endMinute: Int
    let pointsPerMinute: CGFloat
    let trackHeight: CGFloat
    let moveEditingActive: Bool
    let onDayTap: (Date) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: WeeklySwimlaneLayout.trackCornerRadius, style: .continuous)
                .fill(Color.providerScheduleControlFill.opacity(0.55))

            if isEntireDayBlockedOff {
                ProviderScheduleEntireDayCrossOutOverlay(cornerRadius: WeeklySwimlaneLayout.trackCornerRadius)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, trackHeight))
                    .padding(.horizontal, 4)
            } else {
                ForEach(availabilityIntervals.indices, id: \.self) { index in
                    let interval = availabilityIntervals[index]
                    let intervalStart = minutesFromHHMM(interval.start)
                    let intervalEnd = minutesFromHHMM(interval.end)
                    if intervalEnd > intervalStart {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.providerOlive.opacity(0.07))
                            .frame(height: CGFloat(intervalEnd - intervalStart) * pointsPerMinute)
                            .offset(y: CGFloat(intervalStart - startMinute) * pointsPerMinute)
                            .padding(.horizontal, 4)
                    }
                }

                ForEach(timeBlocks) { block in
                    let blockStart = minutesFromHHMM(block.startTime)
                    let blockEnd = minutesFromHHMM(block.endTime)
                    if blockEnd > blockStart {
                        WeeklySwimlaneBlockedTimeOverlay(
                            height: CGFloat(blockEnd - blockStart) * pointsPerMinute
                        )
                        .offset(y: CGFloat(blockStart - startMinute) * pointsPerMinute)
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: trackHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !moveEditingActive else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                onDayTap(day)
            }
        }
    }

    private func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }
}

// MARK: - Blocked time overlay

private struct WeeklySwimlaneBlockedTimeOverlay: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.lavaShellCreamSecondary.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.lavaShellCreamSecondary.opacity(0.32), lineWidth: 0.5)
            }
            .overlay {
                ProviderScheduleDiagonalCrossOut()
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(height: max(4, height))
            .accessibilityLabel("Blocked time")
    }
}

// MARK: - Appointment card

private struct WeeklySwimlaneAppointmentCardContent: View {
    let appointment: SwimlaneAppointment
    let cardHeight: CGFloat
    var isMoveSession: Bool = false
    var isDragActive: Bool = false

    private var usesCompactInitialsLabel: Bool {
        cardHeight <= 44
    }

    private var bookingPrimaryLabel: String {
        usesCompactInitialsLabel
            ? appointment.booking.consumerInitials
            : appointment.booking.consumerDisplayName
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    isMoveSession
                        ? Color.lavaShellCreamSecondary.opacity(isDragActive ? 0.35 : appointment.densityWeight * 0.5)
                        : Color.providerOlive.opacity(appointment.densityWeight)
                )
                .frame(width: WeeklySwimlaneLayout.densityStripeWidth)

            Group {
                if isMoveSession {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.provider(size: moveModeIconSize(for: cardHeight), weight: .semibold))
                        .foregroundStyle(
                            isDragActive
                                ? Color.lavaShellCreamSecondary.opacity(0.88)
                                : Color.lavaShellCream.opacity(0.92)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: usesCompactInitialsLabel ? .center : .leading, spacing: 2) {
                        Text(bookingPrimaryLabel)
                            .font(.provider(
                                size: usesCompactInitialsLabel
                                    ? initialsFontSize(for: cardHeight)
                                    : consumerFontSize(for: cardHeight),
                                weight: .semibold
                            ))
                            .foregroundStyle(Color.lavaShellCream)
                            .lineLimit(usesCompactInitialsLabel ? 1 : (cardHeight > 44 ? 2 : 1))
                            .minimumScaleFactor(usesCompactInitialsLabel ? 1 : 0.85)
                            .frame(maxWidth: .infinity, alignment: usesCompactInitialsLabel ? .center : .leading)

                        if cardHeight > 40 {
                            Text(appointment.booking.serviceDisplayName)
                                .font(.provider(size: serviceFontSize(for: cardHeight), weight: .medium))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: cardHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: WeeklySwimlaneLayout.cardCornerRadius, style: .continuous)
                .fill(moveModeBackgroundColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: WeeklySwimlaneLayout.cardCornerRadius, style: .continuous))
        .overlay {
            if isMoveSession {
                RoundedRectangle(cornerRadius: WeeklySwimlaneLayout.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isDragActive
                            ? Color.lavaShellCreamSecondary.opacity(0.45)
                            : Color.providerOlive.opacity(0.95),
                        lineWidth: 2
                    )
            }
        }
        .padding(.horizontal, WeeklySwimlaneLayout.cardHorizontalInset)
    }

    private var moveModeBackgroundColor: Color {
        if isDragActive {
            return Color.lavaShellCreamSecondary.opacity(0.22)
        }
        return Color.providerOlive.opacity(0.26)
    }

    private func moveModeIconSize(for cardHeight: CGFloat) -> CGFloat {
        min(18, max(11, cardHeight * 0.42))
    }

    private func consumerFontSize(for cardHeight: CGFloat) -> CGFloat {
        min(14, max(11, cardHeight * 0.22))
    }

    private func initialsFontSize(for cardHeight: CGFloat) -> CGFloat {
        min(13, max(11, cardHeight * 0.42))
    }

    private func serviceFontSize(for cardHeight: CGFloat) -> CGFloat {
        min(12, max(10, cardHeight * 0.16))
    }
}

// MARK: - Draggable appointment card

private struct WeeklyDraggableSwimlaneAppointmentCard<Content: View>: View {
    let originX: CGFloat
    let top: CGFloat
    let height: CGFloat
    let columnWidth: CGFloat
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    let isMoveSession: Bool
    let isDragActive: Bool
    let canRequestMove: Bool
    let snapDragOffsetFromGridPoint: (CGPoint) -> CGPoint
    let onTap: () -> Void
    let onMoveRequested: () -> Void
    let onDragEndedAtGridPoint: (CGPoint) -> Bool
    @ViewBuilder let content: () -> Content

    @State private var liveDragOffset: CGPoint = .zero
    @State private var persistedOffset: CGPoint = .zero
    @State private var isPanActive = false
    @State private var isPressingForMove = false
    @State private var suppressNextTap = false
    @State private var pressBeganAt: Date?

    private var dragDelta: CGPoint {
        CGPoint(
            x: persistedOffset.x + liveDragOffset.x,
            y: persistedOffset.y + liveDragOffset.y
        )
    }

    var body: some View {
        content()
            .frame(width: columnWidth, height: height, alignment: .topLeading)
            .overlay {
                if isDragActive {
                    WeeklyUIKitPlaneDragOverlay(
                        onChanged: handleDragChanged,
                        onEnded: handleDragEnded,
                        onInteractionReset: handleDragInteractionReset,
                        viewportWidth: viewportWidth,
                        viewportHeight: viewportHeight,
                        shouldAllowHorizontalEdgeScroll: { intensity, gridPoint, _ in
                            allowsHorizontalEdgeScroll(intensity: intensity, gridPoint: gridPoint)
                        },
                        shouldAllowVerticalEdgeScroll: { intensity, gridPoint, scrollOffset in
                            allowsVerticalEdgeScroll(
                                intensity: intensity,
                                gridPoint: gridPoint,
                                scrollOffset: scrollOffset
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
                    RoundedRectangle(cornerRadius: WeeklySwimlaneLayout.cardCornerRadius, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.92), lineWidth: 2.5)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: originX + dragDelta.x, y: top + dragDelta.y)
            .zIndex(isDragActive ? 3 : (isMoveSession ? 2 : (isPressingForMove ? 2 : 0)))
            .scaleEffect(isPressingForMove ? 0.98 : 1)
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
                    persistedOffset = .zero
                    liveDragOffset = .zero
                    isPanActive = false
                }
            }
    }

    private var startDayIndex: Int {
        Int(
            round(
                (originX - WeeklySwimlaneLayout.timeGutterWidth)
                    / (WeeklySwimlaneLayout.dayColumnWidth + WeeklySwimlaneLayout.dayColumnSpacing)
            )
        )
    }

    private var dayColumnStride: CGFloat {
        WeeklySwimlaneLayout.dayColumnWidth + WeeklySwimlaneLayout.dayColumnSpacing
    }

    private var maxDayOffsetX: CGFloat {
        CGFloat(max(0, 6 - startDayIndex)) * dayColumnStride
    }

    private var minDayOffsetX: CGFloat {
        CGFloat(-startDayIndex) * dayColumnStride
    }

    /// Weekly horizontal drag follows the finger freely between day columns; only Y uses day-view-style clamping.
    private func freeHorizontalDragOffset(gridX: CGFloat) -> CGFloat {
        let raw = gridX - columnWidth * 0.5 - originX
        return min(max(raw, minDayOffsetX), maxDayOffsetX)
    }

    private func clampVerticalDragOffset(_ offsetY: CGFloat, scrollOffset: CGPoint) -> CGFloat {
        let visible = visibleVerticalDragOffsetRange(scrollOffset: scrollOffset)
        return min(max(offsetY, visible.minY), visible.maxY)
    }

    private func handleDragChanged(_ gridPoint: CGPoint, scrollOffset: CGPoint) {
        if !isPanActive {
            isPanActive = true
        }
        let slotOffset = snapDragOffsetFromGridPoint(gridPoint)
        liveDragOffset = CGPoint(
            x: freeHorizontalDragOffset(gridX: gridPoint.x) - persistedOffset.x,
            y: clampVerticalDragOffset(slotOffset.y, scrollOffset: scrollOffset) - persistedOffset.y
        )
    }

    private func visibleVerticalDragOffsetRange(scrollOffset: CGPoint) -> (minY: CGFloat, maxY: CGFloat) {
        let inset = WeeklySwimlaneDragLayout.viewportEdgeInset
        let minY = scrollOffset.y + inset - top
        let maxY = scrollOffset.y + viewportHeight - inset - top - height
        return (minY, max(maxY, minY))
    }

    /// At Monday/Sunday the booking stays on that column (`freeHorizontalDragOffset`); the week grid may still pan.
    private func allowsHorizontalEdgeScroll(intensity: CGFloat, gridPoint: CGPoint) -> Bool {
        _ = intensity
        _ = gridPoint
        return true
    }

    private func allowsVerticalEdgeScroll(
        intensity: CGFloat,
        gridPoint: CGPoint,
        scrollOffset: CGPoint
    ) -> Bool {
        let slotClamped = snapDragOffsetFromGridPoint(gridPoint)
        let clampedY = clampVerticalDragOffset(slotClamped.y, scrollOffset: scrollOffset)
        let inset = WeeklySwimlaneDragLayout.viewportEdgeInset

        if intensity > 0, slotClamped.y >= clampedY - 0.5 {
            let cardBottom = top + clampedY - scrollOffset.y + height
            if cardBottom >= viewportHeight - inset - 1 {
                return false
            }
        }
        if intensity < 0, slotClamped.y <= clampedY + 0.5 {
            let cardTop = top + clampedY - scrollOffset.y
            if cardTop <= inset + 1 {
                return false
            }
        }
        return true
    }

    private func handleDragInteractionReset() {
        guard !isPanActive else { return }
        liveDragOffset = .zero
    }

    private func handleDragEnded(_ gridPoint: CGPoint, scrollOffset: CGPoint) {
        isPanActive = false
        liveDragOffset = .zero
        let snapped = snapDragOffsetFromGridPoint(gridPoint)
        let clampedX = min(max(snapped.x, minDayOffsetX), maxDayOffsetX)
        let finalOffset = CGPoint(
            x: clampedX,
            y: clampVerticalDragOffset(snapped.y, scrollOffset: scrollOffset)
        )
        if onDragEndedAtGridPoint(gridPoint) {
            persistedOffset = finalOffset
        }
    }

    @ViewBuilder
    private var interactionOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .modifier(WeeklyAppointmentInteractionModifier(
                isEnabled: !isMoveSession,
                canRequestMove: canRequestMove,
                moveHoldDuration: WeeklySwimlaneInteraction.moveHoldDuration,
                moveHoldMaxDistance: WeeklySwimlaneInteraction.moveHoldMaxDistance,
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

// MARK: - UIKit plane drag

private struct WeeklyUIKitPlaneDragOverlay: UIViewRepresentable {
    var onChanged: (CGPoint, CGPoint) -> Void
    var onEnded: (CGPoint, CGPoint) -> Void
    var onInteractionReset: () -> Void
    var viewportWidth: CGFloat
    var viewportHeight: CGFloat
    var shouldAllowHorizontalEdgeScroll: (CGFloat, CGPoint, CGPoint) -> Bool
    var shouldAllowVerticalEdgeScroll: (CGFloat, CGPoint, CGPoint) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onChanged: onChanged,
            onEnded: onEnded,
            onInteractionReset: onInteractionReset,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            shouldAllowHorizontalEdgeScroll: shouldAllowHorizontalEdgeScroll,
            shouldAllowVerticalEdgeScroll: shouldAllowVerticalEdgeScroll
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
        context.coordinator.viewportWidth = viewportWidth
        context.coordinator.viewportHeight = viewportHeight
        context.coordinator.shouldAllowHorizontalEdgeScroll = shouldAllowHorizontalEdgeScroll
        context.coordinator.shouldAllowVerticalEdgeScroll = shouldAllowVerticalEdgeScroll
        context.coordinator.configureScrollViewInteraction(for: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardownScrollViewInteraction()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGPoint, CGPoint) -> Void
        var onEnded: (CGPoint, CGPoint) -> Void
        var onInteractionReset: () -> Void
        var viewportWidth: CGFloat
        var viewportHeight: CGFloat
        var shouldAllowHorizontalEdgeScroll: (CGFloat, CGPoint, CGPoint) -> Bool
        var shouldAllowVerticalEdgeScroll: (CGFloat, CGPoint, CGPoint) -> Bool
        weak var panRecognizer: UIPanGestureRecognizer?

        private var scrollOffsetObservations: [NSKeyValueObservation] = []
        /// Scroll views used for edge-scroll physics (only views that can actually scroll).
        private weak var horizontalScrollView: UIScrollView?
        private weak var verticalScrollView: UIScrollView?
        /// Scroll views used to map finger location into week-grid coordinates.
        private weak var horizontalCoordinateScrollView: UIScrollView?
        private weak var verticalCoordinateScrollView: UIScrollView?
        private var lastValidGridPoint: CGPoint?

        private var edgeScrollDisplayLink: CADisplayLink?
        private var targetHorizontalEdgeIntensity: CGFloat = 0
        private var targetVerticalEdgeIntensity: CGFloat = 0
        private var smoothedVerticalEdgeIntensity: CGFloat = 0
        private weak var edgeScrollRecognizer: UIPanGestureRecognizer?

        init(
            onChanged: @escaping (CGPoint, CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint) -> Void,
            onInteractionReset: @escaping () -> Void,
            viewportWidth: CGFloat,
            viewportHeight: CGFloat,
            shouldAllowHorizontalEdgeScroll: @escaping (CGFloat, CGPoint, CGPoint) -> Bool,
            shouldAllowVerticalEdgeScroll: @escaping (CGFloat, CGPoint, CGPoint) -> Bool
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onInteractionReset = onInteractionReset
            self.viewportWidth = viewportWidth
            self.viewportHeight = viewportHeight
            self.shouldAllowHorizontalEdgeScroll = shouldAllowHorizontalEdgeScroll
            self.shouldAllowVerticalEdgeScroll = shouldAllowVerticalEdgeScroll
        }

        deinit {
            stopEdgeScroll()
            teardownScrollViewInteraction()
        }

        func configureScrollViewInteraction(for view: UIView) {
            guard let pan = panRecognizer else { return }

            let scrollViews = view.enclosingScrollViews
            guard !scrollViews.isEmpty else { return }

            let horizontal = scrollViews.first(where: Self.canScrollHorizontally)
            let vertical = scrollViews.first(where: Self.canScrollVertically)
            let horizontalForCoordinates = horizontal ?? scrollViews.last
            let verticalForCoordinates = vertical ?? scrollViews.first

            let needsRewire = scrollOffsetObservations.isEmpty
                || horizontalScrollView !== horizontal
                || verticalScrollView !== vertical
                || horizontalCoordinateScrollView !== horizontalForCoordinates
                || verticalCoordinateScrollView !== verticalForCoordinates

            guard needsRewire else { return }

            teardownScrollViewInteraction()
            horizontalScrollView = horizontal
            verticalScrollView = vertical
            horizontalCoordinateScrollView = horizontalForCoordinates
            verticalCoordinateScrollView = verticalForCoordinates

            for scrollView in scrollViews {
                scrollView.panGestureRecognizer.require(toFail: pan)
                let observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    self?.handleExternalScroll()
                }
                scrollOffsetObservations.append(observation)
            }
        }

        func teardownScrollViewInteraction() {
            scrollOffsetObservations.forEach { $0.invalidate() }
            scrollOffsetObservations.removeAll()
            horizontalScrollView = nil
            verticalScrollView = nil
            horizontalCoordinateScrollView = nil
            verticalCoordinateScrollView = nil
        }

        private static func canScrollHorizontally(_ scrollView: UIScrollView) -> Bool {
            scrollView.contentSize.width > scrollView.bounds.width + 1
        }

        private static func canScrollVertically(_ scrollView: UIScrollView) -> Bool {
            scrollView.contentSize.height > scrollView.bounds.height + 1
        }

        private func currentScrollOffset() -> CGPoint {
            CGPoint(
                x: horizontalScrollView?.contentOffset.x ?? 0,
                y: verticalScrollView?.contentOffset.y ?? 0
            )
        }

        private func handleExternalScroll() {
            guard let pan = panRecognizer else { return }
            switch pan.state {
            case .began, .changed:
                notifyDragChange(recognizer: pan)
            default:
                onInteractionReset()
            }
        }

        private func fingerGridPoint(recognizer: UIPanGestureRecognizer) -> CGPoint? {
            guard let host = recognizer.view else { return nil }

            if horizontalCoordinateScrollView == nil, verticalCoordinateScrollView == nil {
                configureScrollViewInteraction(for: host)
            }

            let scrollViews = host.enclosingScrollViews
            guard !scrollViews.isEmpty else { return nil }

            let hScroll = horizontalCoordinateScrollView
                ?? scrollViews.first(where: Self.canScrollHorizontally)
                ?? scrollViews.last
            let vScroll = verticalCoordinateScrollView
                ?? scrollViews.first(where: Self.canScrollVertically)
                ?? scrollViews.first

            guard let hScroll else { return nil }

            let fingerInHorizontal = recognizer.location(in: hScroll)
            let x = fingerInHorizontal.x - WeeklySwimlaneLayout.outerPaddingLeading
            let y: CGFloat
            if let vScroll {
                y = recognizer.location(in: vScroll).y
            } else {
                y = fingerInHorizontal.y
                    - WeeklySwimlaneLayout.dayHeaderHeight
                    - WeeklySwimlaneLayout.outerPaddingVertical
            }

            return CGPoint(x: x, y: y)
        }

        private func notifyDragChange(recognizer: UIPanGestureRecognizer) {
            guard let gridPoint = fingerGridPoint(recognizer: recognizer) else { return }
            lastValidGridPoint = gridPoint
            onChanged(gridPoint, currentScrollOffset())
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            if let host = recognizer.view {
                configureScrollViewInteraction(for: host)
            }

            switch recognizer.state {
            case .began:
                notifyDragChange(recognizer: recognizer)
            case .changed:
                notifyDragChange(recognizer: recognizer)
                updateEdgeScroll(recognizer: recognizer)
            case .ended, .cancelled, .failed:
                stopEdgeScroll()
                let gridPoint = fingerGridPoint(recognizer: recognizer) ?? lastValidGridPoint
                if let gridPoint {
                    onEnded(gridPoint, currentScrollOffset())
                }
                lastValidGridPoint = nil
            default:
                break
            }
        }

        private func fingerPositionInHorizontalViewport(_ recognizer: UIPanGestureRecognizer) -> CGPoint? {
            guard let scrollView = horizontalScrollView else { return nil }
            let fingerInWindow = recognizer.location(in: nil)
            let viewportFrame = scrollView.convert(scrollView.bounds, to: nil)
            return CGPoint(
                x: fingerInWindow.x - viewportFrame.minX,
                y: fingerInWindow.y - viewportFrame.minY
            )
        }

        private func fingerPositionInVerticalViewport(_ recognizer: UIPanGestureRecognizer) -> CGPoint? {
            guard let scrollView = verticalScrollView else { return nil }
            let fingerInWindow = recognizer.location(in: nil)
            let viewportFrame = scrollView.convert(scrollView.bounds, to: nil)
            return CGPoint(
                x: fingerInWindow.x - viewportFrame.minX,
                y: fingerInWindow.y - viewportFrame.minY
            )
        }

        private func fingerPositionInViewport(_ recognizer: UIPanGestureRecognizer) -> CGPoint? {
            fingerPositionInHorizontalViewport(recognizer)
                ?? fingerPositionInVerticalViewport(recognizer)
        }

        /// Linear ramp: deeper into the left/right edge band = higher intensity (faster pan).
        private func horizontalEdgeScrollIntensity(
            fingerX: CGFloat,
            viewportWidth: CGFloat,
            canScrollLeft: () -> Bool,
            canScrollRight: () -> Bool
        ) -> CGFloat {
            let zone = WeeklySwimlaneDragLayout.horizontalEdgeScrollZone
            let overshootCap = WeeklySwimlaneDragLayout.horizontalEdgeScrollOvershootCap

            if fingerX < zone {
                guard canScrollLeft() else { return 0 }
                let depthIntoEdge = zone - fingerX
                guard depthIntoEdge > 0 else { return 0 }
                let normalized = depthIntoEdge / zone
                return -min(normalized, overshootCap)
            }

            if fingerX > viewportWidth - zone {
                guard canScrollRight() else { return 0 }
                let depthIntoEdge = fingerX - (viewportWidth - zone)
                guard depthIntoEdge > 0 else { return 0 }
                let normalized = depthIntoEdge / zone
                return min(normalized, overshootCap)
            }

            return 0
        }

        private func verticalEdgeScrollIntensity(
            fingerY: CGFloat,
            viewportHeight: CGFloat,
            canScrollUp: () -> Bool,
            canScrollDown: () -> Bool
        ) -> CGFloat {
            let zone = WeeklySwimlaneDragLayout.verticalEdgeScrollZone
            let overshootCap = WeeklySwimlaneDragLayout.verticalEdgeScrollOvershootCap

            if fingerY < zone {
                guard canScrollUp() else { return 0 }
                let depthIntoEdge = zone - fingerY
                guard depthIntoEdge > 0 else { return 0 }
                let normalized = depthIntoEdge / zone
                return -min(normalized, overshootCap)
            }

            if fingerY > viewportHeight - zone {
                guard canScrollDown() else { return 0 }
                let depthIntoEdge = fingerY - (viewportHeight - zone)
                guard depthIntoEdge > 0 else { return 0 }
                let normalized = depthIntoEdge / zone
                return min(normalized, overshootCap)
            }

            return 0
        }

        private func refreshTargetEdgeIntensities(recognizer: UIPanGestureRecognizer) {
            if let finger = fingerPositionInHorizontalViewport(recognizer),
               let hScroll = horizontalScrollView {
                let zone = WeeklySwimlaneDragLayout.horizontalEdgeScrollZone
                guard hScroll.bounds.width > zone * 2 else {
                    targetHorizontalEdgeIntensity = 0
                    return
                }
                targetHorizontalEdgeIntensity = horizontalEdgeScrollIntensity(
                    fingerX: finger.x,
                    viewportWidth: hScroll.bounds.width,
                    canScrollLeft: canScrollHorizontallyLeft,
                    canScrollRight: canScrollHorizontallyRight
                )
            } else {
                targetHorizontalEdgeIntensity = 0
            }

            if let finger = fingerPositionInVerticalViewport(recognizer),
               let vScroll = verticalScrollView {
                let zone = WeeklySwimlaneDragLayout.verticalEdgeScrollZone
                guard vScroll.bounds.height > zone * 2 else {
                    targetVerticalEdgeIntensity = 0
                    return
                }
                targetVerticalEdgeIntensity = verticalEdgeScrollIntensity(
                    fingerY: finger.y,
                    viewportHeight: vScroll.bounds.height,
                    canScrollUp: canScrollVerticallyUp,
                    canScrollDown: canScrollVerticallyDown
                )
            } else {
                targetVerticalEdgeIntensity = 0
            }
        }

        private func smoothVerticalEdgeIntensity(current: CGFloat, target: CGFloat, deltaTime: CGFloat) -> CGFloat {
            let rate = WeeklySwimlaneDragLayout.verticalEdgeScrollIntensitySmoothingRate
            let alpha = min(1, rate * deltaTime)
            return current + ((target - current) * alpha)
        }

        private func canScrollHorizontallyLeft() -> Bool {
            guard let scrollView = horizontalScrollView else { return false }
            let minX = -scrollView.adjustedContentInset.left
            return scrollView.contentOffset.x > minX + 0.5
        }

        private func canScrollHorizontallyRight() -> Bool {
            guard let scrollView = horizontalScrollView else { return false }
            let minX = -scrollView.adjustedContentInset.left
            let maxX = max(
                minX,
                scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
            )
            return scrollView.contentOffset.x < maxX - 0.5
        }

        private func canScrollVerticallyUp() -> Bool {
            guard let scrollView = verticalScrollView else { return false }
            let minY = -scrollView.adjustedContentInset.top
            return scrollView.contentOffset.y > minY + 0.5
        }

        private func canScrollVerticallyDown() -> Bool {
            guard let scrollView = verticalScrollView else { return false }
            let minY = -scrollView.adjustedContentInset.top
            let maxY = max(
                minY,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )
            return scrollView.contentOffset.y < maxY - 0.5
        }

        private func updateEdgeScroll(recognizer: UIPanGestureRecognizer) {
            refreshTargetEdgeIntensities(recognizer: recognizer)

            if abs(targetHorizontalEdgeIntensity) <= 0.02, abs(targetVerticalEdgeIntensity) <= 0.02 {
                stopEdgeScroll()
                return
            }

            guard let gridPoint = fingerGridPoint(recognizer: recognizer) else { return }
            let scrollOffset = currentScrollOffset()

            if abs(targetHorizontalEdgeIntensity) > 0.02,
               !shouldAllowHorizontalEdgeScroll(targetHorizontalEdgeIntensity, gridPoint, scrollOffset) {
                targetHorizontalEdgeIntensity = 0
            }
            if abs(targetVerticalEdgeIntensity) > 0.02,
               !shouldAllowVerticalEdgeScroll(targetVerticalEdgeIntensity, gridPoint, scrollOffset) {
                targetVerticalEdgeIntensity = 0
            }

            if abs(targetHorizontalEdgeIntensity) > 0.02 || abs(targetVerticalEdgeIntensity) > 0.02 {
                startEdgeScroll(recognizer: recognizer)
            } else {
                stopEdgeScroll()
            }
        }

        private func startEdgeScroll(recognizer: UIPanGestureRecognizer) {
            edgeScrollRecognizer = recognizer
            guard edgeScrollDisplayLink == nil else { return }

            let link = CADisplayLink(target: self, selector: #selector(edgeScrollTick(_:)))
            link.add(to: .main, forMode: .common)
            edgeScrollDisplayLink = link
        }

        private func stopEdgeScroll() {
            edgeScrollDisplayLink?.invalidate()
            edgeScrollDisplayLink = nil
            targetHorizontalEdgeIntensity = 0
            targetVerticalEdgeIntensity = 0
            smoothedVerticalEdgeIntensity = 0
            edgeScrollRecognizer = nil
        }

        @objc private func edgeScrollTick(_ link: CADisplayLink) {
            guard let recognizer = edgeScrollRecognizer else {
                stopEdgeScroll()
                return
            }

            refreshTargetEdgeIntensities(recognizer: recognizer)

            let deltaTime = max(link.duration, 1.0 / 120.0)
            smoothedVerticalEdgeIntensity = smoothVerticalEdgeIntensity(
                current: smoothedVerticalEdgeIntensity,
                target: targetVerticalEdgeIntensity,
                deltaTime: deltaTime
            )

            let horizontalIntensity = targetHorizontalEdgeIntensity
            let verticalIntensity = smoothedVerticalEdgeIntensity

            guard abs(horizontalIntensity) > 0.01 || abs(verticalIntensity) > 0.01 else {
                stopEdgeScroll()
                return
            }

            guard let gridPoint = fingerGridPoint(recognizer: recognizer) else {
                stopEdgeScroll()
                return
            }
            let scrollOffset = currentScrollOffset()
            var didScroll = false

            if abs(horizontalIntensity) > 0.01,
               shouldAllowHorizontalEdgeScroll(horizontalIntensity, gridPoint, scrollOffset),
               let scrollView = horizontalScrollView {
                if horizontalIntensity < 0, !canScrollHorizontallyLeft() {
                    targetHorizontalEdgeIntensity = 0
                } else if horizontalIntensity > 0, !canScrollHorizontallyRight() {
                    targetHorizontalEdgeIntensity = 0
                } else {
                    let speed = WeeklySwimlaneDragLayout.horizontalEdgeScrollMaxPointsPerSecond * abs(horizontalIntensity)
                    let scrollDelta = (horizontalIntensity < 0 ? -speed : speed) * CGFloat(deltaTime)
                    didScroll = abs(applyHorizontalScroll(scrollDelta, on: scrollView)) > 0.01 || didScroll
                }
            }

            if abs(verticalIntensity) > 0.01,
               shouldAllowVerticalEdgeScroll(verticalIntensity, gridPoint, scrollOffset),
               let scrollView = verticalScrollView {
                if verticalIntensity < 0, !canScrollVerticallyUp() {
                    smoothedVerticalEdgeIntensity = 0
                    targetVerticalEdgeIntensity = 0
                } else if verticalIntensity > 0, !canScrollVerticallyDown() {
                    smoothedVerticalEdgeIntensity = 0
                    targetVerticalEdgeIntensity = 0
                } else {
                    let speed = WeeklySwimlaneDragLayout.verticalEdgeScrollMaxPointsPerSecond * abs(verticalIntensity)
                    let scrollDelta = (verticalIntensity < 0 ? -speed : speed) * CGFloat(deltaTime)
                    didScroll = abs(applyVerticalScroll(scrollDelta, on: scrollView)) > 0.01 || didScroll
                }
            }

            if didScroll {
                notifyDragChange(recognizer: recognizer)
            } else if abs(targetHorizontalEdgeIntensity) <= 0.02,
                      abs(targetVerticalEdgeIntensity) <= 0.02,
                      abs(verticalIntensity) <= 0.01 {
                stopEdgeScroll()
            }
        }

        private func applyHorizontalScroll(_ delta: CGFloat, on scrollView: UIScrollView) -> CGFloat {
            let minX = -scrollView.adjustedContentInset.left
            let maxX = max(
                minX,
                scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
            )
            let proposed = scrollView.contentOffset.x + delta
            let clamped = min(max(proposed, minX), maxX)
            let applied = clamped - scrollView.contentOffset.x
            if abs(applied) > 0.01 {
                scrollView.contentOffset.x = clamped
            }
            return applied
        }

        private func applyVerticalScroll(_ delta: CGFloat, on scrollView: UIScrollView) -> CGFloat {
            let minY = -scrollView.adjustedContentInset.top
            let maxY = max(
                minY,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )
            let proposed = scrollView.contentOffset.y + delta
            let clamped = min(max(proposed, minY), maxY)
            let applied = clamped - scrollView.contentOffset.y
            if abs(applied) > 0.01 {
                scrollView.contentOffset.y = clamped
            }
            return applied
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let scrollView = otherGestureRecognizer.view as? UIScrollView else { return false }
            return horizontalScrollView === scrollView || verticalScrollView === scrollView
        }
    }
}

private extension UIView {
    var enclosingScrollViews: [UIScrollView] {
        sequence(first: self, next: { $0.superview })
            .compactMap { $0 as? UIScrollView }
            .reduce(into: [UIScrollView]()) { result, scrollView in
                if !result.contains(where: { $0 === scrollView }) {
                    result.append(scrollView)
                }
            }
    }

    var enclosingScrollView: UIScrollView? {
        enclosingScrollViews.first
    }
}

private struct WeeklyAppointmentInteractionModifier: ViewModifier {
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
                deadline: .now() + WeeklySwimlaneInteraction.moveHoldHighlightDelay,
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
