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
    static let timeGutterWidth: CGFloat = 52
    static let timeGutterLabelFontSize: CGFloat = 10
    static let dayHeaderHeight: CGFloat = 46
    static let outerPadding: CGFloat = 10
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

// MARK: - Weekly swimlane

struct WeeklySwimlaneView: View {
    let calendar: Calendar
    let weekStart: Date
    let bookings: [SimpleBookingDTO]
    let viewportSize: CGSize
    let startMinute: Int
    let endMinute: Int
    let dayAvailabilityIntervals: [[BarberAvailabilityIntervalDTO]]
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
            viewportSize.height - WeeklySwimlaneLayout.dayHeaderHeight - (WeeklySwimlaneLayout.outerPadding * 2)
        )
    }

    private var pointsPerMinute: CGFloat {
        (trackAreaHeight / CGFloat(minuteSpan)) * WeeklySwimlaneLayout.verticalScaleBoost
    }

    private var contentTrackHeight: CGFloat {
        CGFloat(minuteSpan) * pointsPerMinute
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
        max(viewportSize.width, weekGridWidth + (WeeklySwimlaneLayout.outerPadding * 2))
    }

    private var dayColumnStride: CGFloat {
        WeeklySwimlaneLayout.dayColumnWidth + WeeklySwimlaneLayout.dayColumnSpacing
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
                .padding(.horizontal, WeeklySwimlaneLayout.outerPadding)
                .padding(.top, WeeklySwimlaneLayout.outerPadding)

            trackScrollRegion
                .padding(.horizontal, WeeklySwimlaneLayout.outerPadding)
                .padding(.bottom, WeeklySwimlaneLayout.outerPadding)
        }
        .frame(width: layoutWidth, height: viewportSize.height, alignment: .top)
    }

    private var dayHeaderRow: some View {
        HStack(spacing: WeeklySwimlaneLayout.dayColumnSpacing) {
            Color.clear
                .frame(width: WeeklySwimlaneLayout.timeGutterWidth)

            ForEach(0 ..< 7, id: \.self) { offset in
                dayHeader(for: dayDate(offset: offset))
                    .frame(width: WeeklySwimlaneLayout.dayColumnWidth)
            }

            Color.clear
                .frame(width: WeeklySwimlaneLayout.timeGutterWidth)
        }
        .frame(width: weekGridWidth, height: WeeklySwimlaneLayout.dayHeaderHeight, alignment: .leading)
    }

    @ViewBuilder
    private var trackScrollRegion: some View {
        let tracks = AnyView(
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: WeeklySwimlaneLayout.dayColumnSpacing) {
                    WeeklySwimlaneTimeGutterView(
                        startMinute: startMinute,
                        endMinute: endMinute,
                        pointsPerMinute: pointsPerMinute,
                        trackHeight: contentTrackHeight,
                        labelPlacement: .leadingEdge
                    )
                    .frame(width: WeeklySwimlaneLayout.timeGutterWidth)

                    ForEach(0 ..< 7, id: \.self) { offset in
                        WeeklySwimlaneDayTrackView(
                            day: dayDate(offset: offset),
                            availabilityIntervals: availabilityIntervals(for: offset),
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
                        startMinute: startMinute,
                        endMinute: endMinute,
                        pointsPerMinute: pointsPerMinute,
                        trackHeight: contentTrackHeight,
                        labelPlacement: .trailingEdge
                    )
                    .frame(width: WeeklySwimlaneLayout.timeGutterWidth)
                }
                .frame(width: weekGridWidth, alignment: .leading)

                WeeklySwimlaneAppointmentsLayer(
                    positionedAppointments: positionedAppointments,
                    moveResolver: moveResolver,
                    startMinute: startMinute,
                    pointsPerMinute: pointsPerMinute,
                    dayColumnStride: dayColumnStride,
                    trackHeight: contentTrackHeight,
                    appointmentDragEnabled: appointmentDragEnabled,
                    editingMoveBookingID: $editingMoveBookingID,
                    activeMoveDragBookingID: $activeMoveDragBookingID,
                    timeChangeProposal: $timeChangeProposal,
                    onMoveBookingRequested: onMoveBookingRequested,
                    onBookingTap: onBookingTap,
                    onBookingTimeChangeProposed: onBookingTimeChangeProposed
                )
                .frame(width: weekGridWidth, height: contentTrackHeight, alignment: .topLeading)
            }
            .frame(width: weekGridWidth, alignment: .leading)
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
    private func dayHeader(for day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                onDayTap(day)
            }
        } label: {
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
        }
        .buttonStyle(.plain)
    }

    private func dayDate(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
    }

    private func availabilityIntervals(for offset: Int) -> [BarberAvailabilityIntervalDTO] {
        dayAvailabilityIntervals.indices.contains(offset) ? dayAvailabilityIntervals[offset] : []
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
            excludingAppointmentID: excludingAppointmentID
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
                        excludingAppointmentID: excludingAppointmentID
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
                            excludingAppointmentID: excludingAppointmentID
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
        excludingAppointmentID: String
    ) -> Bool {
        let endMinute = startMinute + durationMinutes
        guard startMinute >= self.startMinute, endMinute <= self.endMinute else { return false }

        for other in positionedAppointments where other.appointment.id != excludingAppointmentID && other.dayIndex == dayIndex {
            let otherEnd = other.appointment.startMinute + other.appointment.durationMinutes
            if startMinute < otherEnd && endMinute > other.appointment.startMinute {
                return false
            }
        }

        let blocks = dayTimeBlocks.indices.contains(dayIndex) ? dayTimeBlocks[dayIndex] : []
        for block in blocks {
            let blockStart = minutesFromHHMM(block.startTime)
            let blockEnd = minutesFromHHMM(block.endTime)
            if startMinute < blockEnd && endMinute > blockStart {
                return false
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
            isMoveSession: isMoveSession,
            isDragActive: isDragActive,
            canRequestMove: canMove && editingMoveBookingID == nil,
            snapDragOffset: { offset in
                moveResolver.clampedDragOffset(
                    for: positioned,
                    totalOffsetX: offset.x,
                    totalOffsetY: offset.y
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
            onDragEnded: { offset in
                let moved = moveResolver.handleDragEnded(
                    for: positioned,
                    totalOffsetX: offset.x,
                    totalOffsetY: offset.y,
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
                isInMoveMode: isMoveSession
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

    let startMinute: Int
    let endMinute: Int
    let pointsPerMinute: CGFloat
    let trackHeight: CGFloat
    var labelPlacement: LabelPlacement = .leadingEdge

    private var hourMarkers: [Int] {
        let firstHour = (startMinute / 60) * 60
        return stride(from: max(firstHour, startMinute), to: endMinute, by: 60).map { $0 }
    }

    private var labelAlignment: Alignment {
        labelPlacement == .leadingEdge ? .trailing : .leading
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: trackHeight)

            ForEach(hourMarkers, id: \.self) { minute in
                Text(formatHour(minute))
                    .font(.provider(size: WeeklySwimlaneLayout.timeGutterLabelFontSize, weight: .medium))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: WeeklySwimlaneLayout.timeGutterWidth, alignment: labelAlignment)
                    .offset(y: CGFloat(minute - startMinute) * pointsPerMinute)
                    .padding(labelPlacement == .leadingEdge ? .trailing : .leading, 2)
            }
        }
        .frame(height: trackHeight, alignment: .top)
    }

    private func formatHour(_ totalMinutes: Int) -> String {
        var components = DateComponents()
        components.hour = totalMinutes / 60
        components.minute = 0
        let date = Calendar(identifier: .gregorian).date(from: components) ?? .now
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }
}

// MARK: - Day track

private struct WeeklySwimlaneDayTrackView: View {
    let day: Date
    let availabilityIntervals: [BarberAvailabilityIntervalDTO]
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

// MARK: - Appointment card

private struct WeeklySwimlaneAppointmentCardContent: View {
    let appointment: SwimlaneAppointment
    let cardHeight: CGFloat
    var isInMoveMode: Bool = false

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
            if !isInMoveMode {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.providerOlive.opacity(appointment.densityWeight))
                    .frame(width: WeeklySwimlaneLayout.densityStripeWidth)
            }

            Group {
                if isInMoveMode {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.provider(size: moveModeIconSize(for: cardHeight), weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamSecondary.opacity(0.88))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                .fill(
                    isInMoveMode
                        ? Color.lavaShellCreamSecondary.opacity(0.22)
                        : Color.providerOlive.opacity(0.26)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: WeeklySwimlaneLayout.cardCornerRadius, style: .continuous))
        .overlay {
            if isInMoveMode {
                RoundedRectangle(cornerRadius: WeeklySwimlaneLayout.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.lavaShellCreamSecondary.opacity(0.45), lineWidth: 1.5)
            }
        }
        .padding(.horizontal, WeeklySwimlaneLayout.cardHorizontalInset)
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
    let isMoveSession: Bool
    let isDragActive: Bool
    let canRequestMove: Bool
    let snapDragOffset: (CGPoint) -> CGPoint
    let onTap: () -> Void
    let onMoveRequested: () -> Void
    let onDragEnded: (CGPoint) -> Bool
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
                        onEnded: handleDragEnded
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
            .scaleEffect(isDragActive ? 1.03 : (isPressingForMove ? 0.98 : 1))
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
                    persistedOffset = .zero
                    liveDragOffset = .zero
                    isPanActive = false
                }
            }
    }

    private func handleDragChanged(_ translation: CGPoint) {
        if !isPanActive {
            isPanActive = true
        }
        let total = CGPoint(
            x: persistedOffset.x + translation.x,
            y: persistedOffset.y + translation.y
        )
        let clamped = snapDragOffset(total)
        liveDragOffset = CGPoint(
            x: clamped.x - persistedOffset.x,
            y: clamped.y - persistedOffset.y
        )
    }

    private func handleDragEnded(_ translation: CGPoint) {
        isPanActive = false
        let total = CGPoint(
            x: persistedOffset.x + translation.x,
            y: persistedOffset.y + translation.y
        )
        liveDragOffset = .zero
        let snapped = snapDragOffset(total)
        if onDragEnded(snapped) {
            persistedOffset = snapped
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
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
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
        context.coordinator.configureScrollViewInteraction(for: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardownScrollViewInteraction()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGPoint) -> Void
        var onEnded: (CGPoint) -> Void
        weak var panRecognizer: UIPanGestureRecognizer?
        weak var wiredScrollView: UIScrollView?
        private var scrollOffsetObservation: NSKeyValueObservation?
        private var dragStartTranslation: CGPoint = .zero
        private var dragStartScrollOffset: CGPoint = .zero

        init(onChanged: @escaping (CGPoint) -> Void, onEnded: @escaping (CGPoint) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        deinit {
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
            guard let pan = panRecognizer else { return }
            switch pan.state {
            case .began, .changed:
                onChanged(currentTranslation(recognizer: pan))
            default:
                break
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                dragStartTranslation = .zero
                if let scrollView = recognizer.view?.enclosingScrollView {
                    dragStartScrollOffset = scrollView.contentOffset
                } else {
                    dragStartScrollOffset = .zero
                }
                onChanged(.zero)
            case .changed:
                onChanged(currentTranslation(recognizer: recognizer))
            case .ended, .cancelled, .failed:
                onEnded(currentTranslation(recognizer: recognizer))
                dragStartScrollOffset = .zero
            default:
                break
            }
        }

        private func currentTranslation(recognizer: UIPanGestureRecognizer) -> CGPoint {
            let fingerDelta = recognizer.translation(in: recognizer.view)
            guard let scrollView = recognizer.view?.enclosingScrollView else {
                return fingerDelta
            }
            let scrollDelta = CGPoint(
                x: scrollView.contentOffset.x - dragStartScrollOffset.x,
                y: scrollView.contentOffset.y - dragStartScrollOffset.y
            )
            return CGPoint(
                x: fingerDelta.x + scrollDelta.x,
                y: fingerDelta.y + scrollDelta.y
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
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
