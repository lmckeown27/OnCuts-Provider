import SwiftUI
import UIKit

// MARK: - Layout

private enum ProviderWeeklyScheduleGridDragLayout {
    /// Full hold before move mode activates.
    static let moveHoldDuration = 0.55
    /// Early feedback once the user is clearly holding (not a quick tap).
    static let moveHoldHighlightDelay = 0.14
    static let moveHoldMaxDistance: CGFloat = 14
    static var moveHoldCommitDuration: Double { moveHoldDuration - moveHoldHighlightDelay }
    static let viewportEdgeInset: CGFloat = 4
    static let horizontalEdgeScrollZone: CGFloat = 72
    static let horizontalEdgeScrollMaxPointsPerSecond: CGFloat = 120
    static let horizontalEdgeScrollOvershootCap: CGFloat = 2.0
    static let verticalEdgeScrollZone: CGFloat = 72
    static let verticalEdgeScrollMaxPointsPerSecond: CGFloat = 96
    static let verticalEdgeScrollOvershootCap: CGFloat = 2.0

    /// Maps edge penetration (pt past the inner edge of the scroll zone) to scroll speed multiplier.
    static func edgeScrollIntensity(penetration: CGFloat, zone: CGFloat, overshootCap: CGFloat) -> CGFloat {
        guard penetration > 0, zone > 0 else { return 0 }
        return min(penetration / zone, overshootCap)
    }
}

// MARK: - Move resolver

struct ProviderWeeklyScheduleGridMoveResolver {
    let model: ProviderWeeklyScheduleGridModel
    let calendar: Calendar
    let dayColumnWidth: CGFloat
    let positionedBookings: [ProviderWeeklyScheduleGridPositionedBooking]
    var earliestBookableDate: Date = .now

    private var rowHeight: CGFloat { ProviderWeeklyScheduleGridMetrics.rowHeight }
    private var slotMinutes: Int { ProviderWeeklyScheduleGridMetrics.slotMinutes }

    func clampedDragOffsetFromGridPoint(
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
        gridX: CGFloat,
        gridY: CGFloat
    ) -> CGPoint {
        let resolved = resolvedPosition(
            dayIndex: dayIndex(atGridX: gridX),
            rowIndex: rowIndex(atGridY: gridY),
            rowSpan: positioned.rowSpan,
            excludingBookingID: positioned.booking.id,
            enforceEarliestBookable: false
        )
        let offsetX = CGFloat(resolved.dayIndex - positioned.dayIndex) * dayColumnWidth
        let offsetY = CGFloat(resolved.startRowIndex - positioned.startRowIndex) * rowHeight
        return CGPoint(x: offsetX, y: offsetY)
    }

    func isTargetingPastTime(
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
        gridX: CGFloat,
        gridY: CGFloat
    ) -> Bool {
        guard let rawDate = rawProposedDate(for: positioned, gridX: gridX, gridY: gridY) else {
            return true
        }
        return rawDate.timeIntervalSince(earliestBookableDate) < -30
    }

    func rawProposedDate(
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
        gridX: CGFloat,
        gridY: CGFloat
    ) -> Date? {
        let dayIdx = dayIndex(atGridX: gridX)
        let rowIdx = rowIndex(atGridY: gridY)
        let resolved = resolvedPosition(
            dayIndex: dayIdx,
            rowIndex: rowIdx,
            rowSpan: positioned.rowSpan,
            excludingBookingID: positioned.booking.id,
            enforceEarliestBookable: false
        )
        return scheduledDate(dayIndex: resolved.dayIndex, startRowIndex: resolved.startRowIndex)
    }

    func proposedDate(
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
        gridX: CGFloat,
        gridY: CGFloat
    ) -> Date? {
        rawProposedDate(for: positioned, gridX: gridX, gridY: gridY)
    }

    @discardableResult
    func handleDragEndedFromGridPoint(
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
        gridX: CGFloat,
        gridY: CGFloat,
        onProposed: (SimpleBookingDTO, Date, Bool) -> Void
    ) -> Bool {
        let offset = clampedDragOffsetFromGridPoint(for: positioned, gridX: gridX, gridY: gridY)
        return handleDragEnded(
            for: positioned,
            totalOffsetX: offset.x,
            totalOffsetY: offset.y,
            gridX: gridX,
            gridY: gridY,
            onProposed: onProposed
        )
    }

    @discardableResult
    func handleDragEnded(
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
        totalOffsetX: CGFloat,
        totalOffsetY: CGFloat,
        gridX: CGFloat? = nil,
        gridY: CGFloat? = nil,
        onProposed: (SimpleBookingDTO, Date, Bool) -> Void
    ) -> Bool {
        let proposed = proposedPosition(
            for: positioned,
            totalOffsetX: totalOffsetX,
            totalOffsetY: totalOffsetY,
            enforceEarliestBookable: false
        )
        guard proposed.dayIndex != positioned.dayIndex || proposed.startRowIndex != positioned.startRowIndex else {
            return false
        }
        let proposedDate: Date?
        let targetsPast: Bool
        if let gridX, let gridY {
            proposedDate = rawProposedDate(for: positioned, gridX: gridX, gridY: gridY)
            targetsPast = isTargetingPastTime(for: positioned, gridX: gridX, gridY: gridY)
        } else {
            proposedDate = scheduledDate(
                dayIndex: proposed.dayIndex,
                startRowIndex: proposed.startRowIndex
            )
            targetsPast = proposedDate.map { $0.timeIntervalSince(earliestBookableDate) < -30 } ?? true
        }
        guard let proposedDate else { return false }
        onProposed(positioned.booking, proposedDate, targetsPast)
        return true
    }

    private func proposedPosition(
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
        totalOffsetX: CGFloat,
        totalOffsetY: CGFloat,
        enforceEarliestBookable: Bool = true
    ) -> (dayIndex: Int, startRowIndex: Int) {
        let dayDelta = Int(round(totalOffsetX / dayColumnWidth))
        let rowDelta = Int(round(totalOffsetY / rowHeight))
        return resolvedPosition(
            dayIndex: positioned.dayIndex + dayDelta,
            rowIndex: positioned.startRowIndex + rowDelta,
            rowSpan: positioned.rowSpan,
            excludingBookingID: positioned.booking.id,
            enforceEarliestBookable: enforceEarliestBookable
        )
    }

    private func dayIndex(atGridX gridX: CGFloat) -> Int {
        Int(round((gridX - dayColumnWidth * 0.5) / dayColumnWidth))
    }

    private func rowIndex(atGridY gridY: CGFloat) -> Int {
        let contentY = gridY - ProviderWeeklyScheduleGridMetrics.timeGutterTopPadding
        return Int(round(contentY / rowHeight))
    }

    private func resolvedPosition(
        dayIndex: Int,
        rowIndex: Int,
        rowSpan: Int,
        excludingBookingID: String,
        enforceEarliestBookable: Bool = true
    ) -> (dayIndex: Int, startRowIndex: Int) {
        let clampedDay = min(max(dayIndex, 0), model.weekDays.count - 1)
        let snappedRow = snappedRowIndex(from: rowIndex)

        let corePosition: (dayIndex: Int, startRowIndex: Int)
        if isOpenSlot(
            dayIndex: clampedDay,
            startRowIndex: snappedRow,
            rowSpan: rowSpan,
            excludingBookingID: excludingBookingID
        ) {
            corePosition = (clampedDay, snappedRow)
        } else if let nearest = nearestOpenStart(
            aroundDayIndex: clampedDay,
            aroundRowIndex: snappedRow,
            rowSpan: rowSpan,
            excludingBookingID: excludingBookingID
        ) {
            corePosition = (nearest.dayIndex, nearest.startRowIndex)
        } else {
            corePosition = (clampedDay, snappedRow)
        }

        guard enforceEarliestBookable else { return corePosition }

        return clampPositionToEarliestBookable(
            dayIndex: corePosition.dayIndex,
            startRowIndex: corePosition.startRowIndex,
            rowSpan: rowSpan,
            excludingBookingID: excludingBookingID
        )
    }

    private func clampPositionToEarliestBookable(
        dayIndex: Int,
        startRowIndex: Int,
        rowSpan: Int,
        excludingBookingID: String
    ) -> (dayIndex: Int, startRowIndex: Int) {
        var clampedDay = min(max(dayIndex, 0), model.weekDays.count - 1)
        var clampedRow = min(max(startRowIndex, 0), max(0, model.timeRows.count - 1))

        if let earliestDayIndex = earliestBookableDayIndex(), clampedDay < earliestDayIndex {
            clampedDay = earliestDayIndex
        }

        let minimumRow = minimumStartRowIndex(forDayIndex: clampedDay)
        if clampedRow < minimumRow {
            clampedRow = minimumRow
        }

        if isOpenSlot(
            dayIndex: clampedDay,
            startRowIndex: clampedRow,
            rowSpan: rowSpan,
            excludingBookingID: excludingBookingID
        ) {
            return (clampedDay, clampedRow)
        }

        if let nearest = nearestOpenStartAtOrAfter(
            dayIndex: clampedDay,
            minRowIndex: minimumRow,
            rowSpan: rowSpan,
            excludingBookingID: excludingBookingID
        ) {
            return nearest
        }

        return (clampedDay, clampedRow)
    }

    private func earliestBookableDayIndex() -> Int? {
        let earliestDay = calendar.startOfDay(for: earliestBookableDate)
        return model.weekDays.firstIndex { calendar.startOfDay(for: $0.date) >= earliestDay }
    }

    private func minimumStartRowIndex(forDayIndex dayIndex: Int) -> Int {
        guard model.weekDays.indices.contains(dayIndex), !model.timeRows.isEmpty else { return 0 }

        let dayStart = calendar.startOfDay(for: model.weekDays[dayIndex].date)
        let earliestDay = calendar.startOfDay(for: earliestBookableDate)

        if dayStart < earliestDay {
            return model.timeRows.count
        }
        if dayStart > earliestDay {
            return 0
        }

        let earliestMinutes =
            calendar.component(.hour, from: earliestBookableDate) * 60
            + calendar.component(.minute, from: earliestBookableDate)
        let snappedMinute = ScheduleAppointmentDrag.snapMinute(
            earliestMinutes,
            step: ProviderWeeklyScheduleGridMetrics.moveSnapStepMinutes
        )
        let row = (snappedMinute - model.gridStartMin) / slotMinutes
        return min(max(row, 0), max(0, model.timeRows.count - 1))
    }

    private func nearestOpenStartAtOrAfter(
        dayIndex: Int,
        minRowIndex: Int,
        rowSpan: Int,
        excludingBookingID: String
    ) -> (dayIndex: Int, startRowIndex: Int)? {
        let stepRows = max(1, ProviderWeeklyScheduleGridMetrics.moveSnapStepMinutes / slotMinutes)

        for candidateDay in dayIndex ..< model.weekDays.count {
            let rowStart = candidateDay == dayIndex
                ? max(minRowIndex, 0)
                : minimumStartRowIndex(forDayIndex: candidateDay)
            guard rowStart < model.timeRows.count else { continue }

            var candidateRow = snappedRowIndex(from: rowStart)
            while candidateRow < model.timeRows.count {
                if isOpenSlot(
                    dayIndex: candidateDay,
                    startRowIndex: candidateRow,
                    rowSpan: rowSpan,
                    excludingBookingID: excludingBookingID
                ) {
                    return (candidateDay, candidateRow)
                }
                candidateRow += stepRows
            }
        }
        return nil
    }

    private func snappedRowIndex(from rowIndex: Int) -> Int {
        guard !model.timeRows.isEmpty else { return 0 }
        let clamped = min(max(rowIndex, 0), model.timeRows.count - 1)
        let minute = model.timeRows[clamped]
        let snappedMinute = ScheduleAppointmentDrag.snapMinute(
            minute,
            step: ProviderWeeklyScheduleGridMetrics.moveSnapStepMinutes
        )
        let snappedRow = (snappedMinute - model.gridStartMin) / slotMinutes
        return min(max(snappedRow, 0), max(0, model.timeRows.count - 1))
    }

    private func nearestOpenStart(
        aroundDayIndex dayIndex: Int,
        aroundRowIndex rowIndex: Int,
        rowSpan: Int,
        excludingBookingID: String
    ) -> (dayIndex: Int, startRowIndex: Int)? {
        let stepRows = max(1, ProviderWeeklyScheduleGridMetrics.moveSnapStepMinutes / slotMinutes)
        for radius in 0 ... 6 {
            for dayDelta in -radius ... radius {
                let candidateDay = dayIndex + dayDelta
                guard (0 ..< model.weekDays.count).contains(candidateDay) else { continue }

                let rowRadius = max(radius - abs(dayDelta), 0)
                if rowRadius == 0 {
                    let snapped = snappedRowIndex(from: rowIndex)
                    if isOpenSlot(
                        dayIndex: candidateDay,
                        startRowIndex: snapped,
                        rowSpan: rowSpan,
                        excludingBookingID: excludingBookingID
                    ) {
                        return (candidateDay, snapped)
                    }
                    continue
                }

                for rowDelta in stride(from: stepRows, through: rowRadius * stepRows * 4, by: stepRows) {
                    for candidateRow in [rowIndex - rowDelta, rowIndex + rowDelta] {
                        let snapped = snappedRowIndex(from: candidateRow)
                        if isOpenSlot(
                            dayIndex: candidateDay,
                            startRowIndex: snapped,
                            rowSpan: rowSpan,
                            excludingBookingID: excludingBookingID
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
        startRowIndex: Int,
        rowSpan: Int,
        excludingBookingID: String
    ) -> Bool {
        guard model.weekDays[dayIndex].isDaySelected else { return false }
        guard startRowIndex >= 0, startRowIndex + rowSpan <= model.timeRows.count else { return false }

        for row in startRowIndex ..< (startRowIndex + rowSpan) {
            let cell = model.cells[row][dayIndex]
            switch cell.status {
            case .open:
                continue
            case .booked:
                if cell.booking?.id == excludingBookingID { continue }
                return false
            case .blocked, .google, .unavailable:
                return false
            }
        }
        return true
    }

    private func scheduledDate(dayIndex: Int, startRowIndex: Int) -> Date? {
        guard model.timeRows.indices.contains(startRowIndex) else { return nil }
        let day = model.weekDays[dayIndex].date
        let minute = model.timeRows[startRowIndex]
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minute, to: dayStart)
    }
}

// MARK: - Appointments layer

struct ProviderWeeklyScheduleGridAppointmentsLayer: View {
    let model: ProviderWeeklyScheduleGridModel
    let positionedBookings: [ProviderWeeklyScheduleGridPositionedBooking]
    let moveResolver: ProviderWeeklyScheduleGridMoveResolver
    let dayColumnWidth: CGFloat
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    let appointmentDragEnabled: Bool
    @Binding var editingMoveBookingID: String?
    let onMoveBookingRequested: (SimpleBookingDTO) -> Void
    let onViewBooking: (SimpleBookingDTO) -> Void
    let onBookingTimeChangeProposed: (SimpleBookingDTO, Date, Bool) -> Void
    let onBookingMoveProposalCleared: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(positionedBookings) { positioned in
                gridAppointmentCard(for: positioned)
            }
        }
        .frame(width: dayColumnWidth * 7, height: model.totalContentHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func gridAppointmentCard(for positioned: ProviderWeeklyScheduleGridPositionedBooking) -> some View {
        let originX = CGFloat(positioned.dayIndex) * dayColumnWidth
        let canMove = appointmentDragEnabled && ScheduleAppointmentDrag.isDraggable(positioned.booking)
        let isMoveSession = editingMoveBookingID == positioned.booking.id
        let cornerRadius = ProviderWeeklyScheduleGridMetrics.bookingCardCornerRadius(height: positioned.height)

        ZStack(alignment: .topLeading) {
            if isMoveSession {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(positioned.booking.scheduleAppointmentMoveOriginFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.lavaShellCream.opacity(0.12), lineWidth: 0.6)
                    )
                    .frame(width: dayColumnWidth, height: positioned.height, alignment: .topLeading)
                    .offset(x: originX, y: positioned.yOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            ProviderWeeklyScheduleGridDraggableBookingCard(
                originX: originX,
                top: positioned.yOffset,
                height: positioned.height,
                columnWidth: dayColumnWidth,
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight,
                isMoveSession: isMoveSession,
                canRequestMove: canMove && editingMoveBookingID == nil,
                snapDragOffsetFromGridPoint: { gridPoint in
                    moveResolver.clampedDragOffsetFromGridPoint(
                        for: positioned,
                        gridX: gridPoint.x,
                        gridY: gridPoint.y
                    )
                },
                onTap: {
                    onViewBooking(positioned.booking)
                },
                onMoveRequested: { onMoveBookingRequested(positioned.booking) },
                reportMoveAtGridPoint: { gridPoint in
                    guard let proposedDate = moveResolver.proposedDate(
                        for: positioned,
                        gridX: gridPoint.x,
                        gridY: gridPoint.y
                    ) else {
                        onBookingMoveProposalCleared()
                        return
                    }
                    let targetsPast = moveResolver.isTargetingPastTime(
                        for: positioned,
                        gridX: gridPoint.x,
                        gridY: gridPoint.y
                    )
                    onBookingTimeChangeProposed(positioned.booking, proposedDate, targetsPast)
                },
                onMoveProposalCleared: onBookingMoveProposalCleared,
                onDragEndedAtGridPoint: { gridPoint in
                    moveResolver.handleDragEndedFromGridPoint(
                        for: positioned,
                        gridX: gridPoint.x,
                        gridY: gridPoint.y,
                        onProposed: onBookingTimeChangeProposed
                    )
                },
                accessibilityName: positioned.booking.consumerDisplayName
            ) {
                ProviderWeeklyScheduleGridBookingCardContent(
                    booking: positioned.booking,
                    cardHeight: positioned.height,
                    isMoveSession: isMoveSession
                )
            }
        }
    }
}

// MARK: - Booking card content

struct ProviderWeeklyScheduleGridBookingCardContent: View {
    let booking: SimpleBookingDTO
    let cardHeight: CGFloat
    var isMoveSession: Bool = false

    var body: some View {
        let cornerRadius = ProviderWeeklyScheduleGridMetrics.bookingCardCornerRadius(height: cardHeight)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(booking.scheduleAppointmentFillColor)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.lavaShellCream.opacity(0.22),
                    lineWidth: max(0.5, min(1, cardHeight * 0.04))
                )

            if isMoveSession {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.provider(size: moveModeIconSize, weight: .semibold))
                    .foregroundStyle(Color.providerScheduleAppointmentPrimaryLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cardHeight >= 20 {
                Text(booking.scheduleCardTitle)
                    .font(.provider(size: statusFontSize, weight: .bold))
                    .foregroundStyle(Color.providerScheduleAppointmentPrimaryLabel)
                    .multilineTextAlignment(.center)
                    .lineLimit(cardHeight >= 36 ? 2 : 1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var statusFontSize: CGFloat {
        if cardHeight >= 48 { return 11 }
        if cardHeight >= 32 { return 10 }
        return 9
    }

    private var moveModeIconSize: CGFloat {
        cardHeight >= 36 ? 14 : 11
    }
}

// MARK: - Hold-to-move indicator

private struct ProviderWeeklyScheduleGridMoveHoldIndicator: View {
    let startedAt: Date
    let commitDuration: TimeInterval

    var body: some View {
        let cornerRadius = ProviderWeeklyScheduleGridMetrics.bookingCardCornerRadius(height: 12)

        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let progress = min(1, max(0, elapsed / commitDuration))

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.orange.opacity(0.10 + 0.10 * progress))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.orange.opacity(0.35 + 0.45 * progress),
                        style: StrokeStyle(lineWidth: 2, dash: progress < 1 ? [5, 4] : [])
                    )

                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.provider(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.45 + 0.45 * progress))
                    .scaleEffect(0.88 + 0.12 * progress)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Draggable booking card

private struct ProviderWeeklyScheduleGridDraggableBookingCard<Content: View>: View {
    let originX: CGFloat
    let top: CGFloat
    let height: CGFloat
    let columnWidth: CGFloat
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    let isMoveSession: Bool
    let canRequestMove: Bool
    let snapDragOffsetFromGridPoint: (CGPoint) -> CGPoint
    let onTap: () -> Void
    let onMoveRequested: () -> Void
    let reportMoveAtGridPoint: (CGPoint) -> Void
    let onMoveProposalCleared: () -> Void
    let onDragEndedAtGridPoint: (CGPoint) -> Bool
    let accessibilityName: String
    @ViewBuilder let content: () -> Content

    @State private var liveDragOffset: CGPoint = .zero
    @State private var persistedOffset: CGPoint = .zero
    @State private var isPanActive = false
    @State private var isPressingForMove = false
    @State private var pressBeganAt: Date?
    @State private var suppressNextTap = false

    private var showsMoveInteractionOverlay: Bool {
        canRequestMove || isMoveSession
    }

    private var dragDelta: CGPoint {
        CGPoint(
            x: persistedOffset.x + liveDragOffset.x,
            y: persistedOffset.y + liveDragOffset.y
        )
    }

    var body: some View {
        content()
            .frame(width: columnWidth, height: height, alignment: .topLeading)
            .contentShape(Rectangle())
            .overlay {
                if showsMoveInteractionOverlay {
                    ProviderWeeklyScheduleGridPlaneDragOverlay(
                        allowsImmediateDrag: isMoveSession,
                        onHoldIndicationBegan: {
                            pressBeganAt = Date()
                            withAnimation(.easeInOut(duration: 0.12)) {
                                isPressingForMove = true
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        },
                        onHoldIndicationEnded: {
                            pressBeganAt = nil
                            withAnimation(.easeInOut(duration: 0.12)) {
                                isPressingForMove = false
                            }
                        },
                        onMoveBegan: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if !isMoveSession {
                                onMoveRequested()
                            }
                            isPanActive = true
                        },
                        onTap: {
                            guard !suppressNextTap else { return }
                            onTap()
                        },
                        onChanged: handleDragChanged,
                        onEnded: handleDragEnded,
                        onInteractionReset: handleDragInteractionReset,
                        viewportWidth: viewportWidth,
                        viewportHeight: viewportHeight,
                        shouldAllowHorizontalEdgeScroll: { _, _, _ in true },
                        shouldAllowVerticalEdgeScroll: { _, _, _ in true },
                        cardContentLeft: originX + dragDelta.x,
                        cardContentTop: top + dragDelta.y,
                        cardContentWidth: columnWidth,
                        cardContentHeight: height,
                        useCardViewportForEdgeScroll: isMoveSession && isPanActive
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onTap)
                }
            }
            .overlay {
                if isPressingForMove, !isMoveSession, let startedAt = pressBeganAt {
                    ProviderWeeklyScheduleGridMoveHoldIndicator(
                        startedAt: startedAt,
                        commitDuration: ProviderWeeklyScheduleGridDragLayout.moveHoldCommitDuration
                    )
                } else if isMoveSession {
                    let cornerRadius = ProviderWeeklyScheduleGridMetrics.bookingCardCornerRadius(height: height)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: 1)
                        .stroke(Color.orange.opacity(0.92), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: originX + dragDelta.x, y: top + dragDelta.y)
            .zIndex(isMoveSession ? 3 : (isPressingForMove ? 2 : 1))
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
                    isPressingForMove = false
                    pressBeganAt = nil
                }
            }
            .accessibilityLabel("\(accessibilityName), tap for booking details")
            .accessibilityHint(
                isMoveSession
                    ? "Drag to a new time, then save the change."
                    : canRequestMove
                        ? "Tap for booking details. Press and hold to move this booking."
                        : "Tap for booking details."
            )
            .accessibilityAddTraits(isMoveSession ? .allowsDirectInteraction : [])
    }

    private var startDayIndex: Int {
        Int(round(originX / columnWidth))
    }

    private var minDayOffsetX: CGFloat {
        CGFloat(-startDayIndex) * columnWidth
    }

    private var maxDayOffsetX: CGFloat {
        CGFloat(max(0, 6 - startDayIndex)) * columnWidth
    }

    private func handleDragChanged(_ gridPoint: CGPoint, scrollOffset: CGPoint) {
        guard isMoveSession || isPanActive else { return }
        if !isPanActive {
            isPanActive = true
        }
        let snapped = snapDragOffsetFromGridPoint(gridPoint)
        liveDragOffset = CGPoint(
            x: min(max(snapped.x, minDayOffsetX), maxDayOffsetX) - persistedOffset.x,
            y: snapped.y - persistedOffset.y
        )
        reportMoveAtGridPoint(gridPoint)
    }

    private func handleDragInteractionReset() {
        guard !isPanActive else { return }
        liveDragOffset = .zero
    }

    private func handleDragEnded(_ gridPoint: CGPoint, scrollOffset: CGPoint) {
        guard isMoveSession || isPanActive else { return }
        isPanActive = false
        isPressingForMove = false
        pressBeganAt = nil
        liveDragOffset = .zero
        suppressTapBriefly()
        guard isMoveSession else { return }
        let snapped = snapDragOffsetFromGridPoint(gridPoint)
        let finalOffset = CGPoint(
            x: min(max(snapped.x, minDayOffsetX), maxDayOffsetX),
            y: snapped.y
        )
        if onDragEndedAtGridPoint(gridPoint) {
            persistedOffset = finalOffset
        } else {
            onMoveProposalCleared()
        }
    }

    private func suppressTapBriefly() {
        suppressNextTap = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            suppressNextTap = false
        }
    }
}

// MARK: - UIKit plane drag overlay

private struct ProviderWeeklyScheduleGridPlaneDragOverlay: UIViewRepresentable {
    /// When `true`, pan begins immediately (booking is already in move mode).
    var allowsImmediateDrag: Bool = false
    var onHoldIndicationBegan: () -> Void
    var onHoldIndicationEnded: () -> Void
    var onMoveBegan: () -> Void
    var onTap: () -> Void
    var onChanged: (CGPoint, CGPoint) -> Void
    var onEnded: (CGPoint, CGPoint) -> Void
    var onInteractionReset: () -> Void
    var viewportWidth: CGFloat
    var viewportHeight: CGFloat
    var shouldAllowHorizontalEdgeScroll: (CGFloat, CGPoint, CGPoint) -> Bool
    var shouldAllowVerticalEdgeScroll: (CGFloat, CGPoint, CGPoint) -> Bool
    var cardContentLeft: CGFloat
    var cardContentTop: CGFloat
    var cardContentWidth: CGFloat
    var cardContentHeight: CGFloat
    var useCardViewportForEdgeScroll: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            allowsImmediateDrag: allowsImmediateDrag,
            onHoldIndicationBegan: onHoldIndicationBegan,
            onHoldIndicationEnded: onHoldIndicationEnded,
            onMoveBegan: onMoveBegan,
            onTap: onTap,
            onChanged: onChanged,
            onEnded: onEnded,
            onInteractionReset: onInteractionReset,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            shouldAllowHorizontalEdgeScroll: shouldAllowHorizontalEdgeScroll,
            shouldAllowVerticalEdgeScroll: shouldAllowVerticalEdgeScroll,
            cardContentLeft: cardContentLeft,
            cardContentTop: cardContentTop,
            cardContentWidth: cardContentWidth,
            cardContentHeight: cardContentHeight,
            useCardViewportForEdgeScroll: useCardViewportForEdgeScroll
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.isUserInteractionEnabled = true

        let preparingLongPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePreparingLongPress(_:))
        )
        preparingLongPress.minimumPressDuration = ProviderWeeklyScheduleGridDragLayout.moveHoldHighlightDelay
        preparingLongPress.allowableMovement = ProviderWeeklyScheduleGridDragLayout.moveHoldMaxDistance
        preparingLongPress.delegate = context.coordinator
        view.addGestureRecognizer(preparingLongPress)
        context.coordinator.preparingLongPressRecognizer = preparingLongPress

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = ProviderWeeklyScheduleGridDragLayout.moveHoldDuration
        longPress.allowableMovement = ProviderWeeklyScheduleGridDragLayout.moveHoldMaxDistance
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)
        context.coordinator.longPressRecognizer = longPress

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        tap.require(toFail: longPress)
        view.addGestureRecognizer(tap)
        context.coordinator.tapRecognizer = tap

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.panRecognizer = pan
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let wasImmediateDrag = context.coordinator.allowsImmediateDrag
        context.coordinator.allowsImmediateDrag = allowsImmediateDrag
        if wasImmediateDrag != allowsImmediateDrag {
            context.coordinator.resetEphemeralGestureState()
        }
        context.coordinator.onHoldIndicationBegan = onHoldIndicationBegan
        context.coordinator.onHoldIndicationEnded = onHoldIndicationEnded
        context.coordinator.onMoveBegan = onMoveBegan
        context.coordinator.onTap = onTap
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onInteractionReset = onInteractionReset
        context.coordinator.viewportWidth = viewportWidth
        context.coordinator.viewportHeight = viewportHeight
        context.coordinator.shouldAllowHorizontalEdgeScroll = shouldAllowHorizontalEdgeScroll
        context.coordinator.shouldAllowVerticalEdgeScroll = shouldAllowVerticalEdgeScroll
        context.coordinator.cardContentLeft = cardContentLeft
        context.coordinator.cardContentTop = cardContentTop
        context.coordinator.cardContentWidth = cardContentWidth
        context.coordinator.cardContentHeight = cardContentHeight
        context.coordinator.useCardViewportForEdgeScroll = useCardViewportForEdgeScroll
        context.coordinator.configureScrollViewInteraction(for: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardownScrollViewInteraction()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var allowsImmediateDrag: Bool
        var onHoldIndicationBegan: () -> Void
        var onHoldIndicationEnded: () -> Void
        var onMoveBegan: () -> Void
        var onTap: () -> Void
        var onChanged: (CGPoint, CGPoint) -> Void
        var onEnded: (CGPoint, CGPoint) -> Void
        var onInteractionReset: () -> Void
        var viewportWidth: CGFloat
        var viewportHeight: CGFloat
        var shouldAllowHorizontalEdgeScroll: (CGFloat, CGPoint, CGPoint) -> Bool
        var shouldAllowVerticalEdgeScroll: (CGFloat, CGPoint, CGPoint) -> Bool
        var cardContentLeft: CGFloat
        var cardContentTop: CGFloat
        var cardContentWidth: CGFloat
        var cardContentHeight: CGFloat
        var useCardViewportForEdgeScroll: Bool
        weak var panRecognizer: UIPanGestureRecognizer?
        weak var preparingLongPressRecognizer: UILongPressGestureRecognizer?
        weak var longPressRecognizer: UILongPressGestureRecognizer?
        weak var tapRecognizer: UITapGestureRecognizer?

        private var didBeginMoveSession = false
        private var isHoldIndicationActive = false

        private var canTrackPan: Bool {
            allowsImmediateDrag || didBeginMoveSession
        }

        func resetEphemeralGestureState() {
            didBeginMoveSession = false
            isHoldIndicationActive = false
            lastValidGridPoint = nil
            stopEdgeScroll()
        }

        private var scrollOffsetObservations: [NSKeyValueObservation] = []
        private weak var horizontalScrollView: UIScrollView?
        private weak var verticalScrollView: UIScrollView?
        private weak var horizontalCoordinateScrollView: UIScrollView?
        private weak var verticalCoordinateScrollView: UIScrollView?
        private var lastValidGridPoint: CGPoint?
        private var edgeScrollDisplayLink: CADisplayLink?
        private var targetHorizontalEdgeIntensity: CGFloat = 0
        private var targetVerticalEdgeIntensity: CGFloat = 0
        private weak var edgeScrollRecognizer: UIPanGestureRecognizer?

        init(
            allowsImmediateDrag: Bool,
            onHoldIndicationBegan: @escaping () -> Void,
            onHoldIndicationEnded: @escaping () -> Void,
            onMoveBegan: @escaping () -> Void,
            onTap: @escaping () -> Void,
            onChanged: @escaping (CGPoint, CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint) -> Void,
            onInteractionReset: @escaping () -> Void,
            viewportWidth: CGFloat,
            viewportHeight: CGFloat,
            shouldAllowHorizontalEdgeScroll: @escaping (CGFloat, CGPoint, CGPoint) -> Bool,
            shouldAllowVerticalEdgeScroll: @escaping (CGFloat, CGPoint, CGPoint) -> Bool,
            cardContentLeft: CGFloat,
            cardContentTop: CGFloat,
            cardContentWidth: CGFloat,
            cardContentHeight: CGFloat,
            useCardViewportForEdgeScroll: Bool
        ) {
            self.allowsImmediateDrag = allowsImmediateDrag
            self.onHoldIndicationBegan = onHoldIndicationBegan
            self.onHoldIndicationEnded = onHoldIndicationEnded
            self.onMoveBegan = onMoveBegan
            self.onTap = onTap
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onInteractionReset = onInteractionReset
            self.viewportWidth = viewportWidth
            self.viewportHeight = viewportHeight
            self.shouldAllowHorizontalEdgeScroll = shouldAllowHorizontalEdgeScroll
            self.shouldAllowVerticalEdgeScroll = shouldAllowVerticalEdgeScroll
            self.cardContentLeft = cardContentLeft
            self.cardContentTop = cardContentTop
            self.cardContentWidth = cardContentWidth
            self.cardContentHeight = cardContentHeight
            self.useCardViewportForEdgeScroll = useCardViewportForEdgeScroll
        }

        deinit {
            stopEdgeScroll()
            teardownScrollViewInteraction()
        }

        func configureScrollViewInteraction(for view: UIView) {
            guard let pan = panRecognizer else { return }
            let scrollViews = view.enclosingScheduleScrollViews
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

            guard let hScroll = horizontalCoordinateScrollView
                ?? host.enclosingScheduleScrollViews.first(where: Self.canScrollHorizontally)
                ?? host.enclosingScheduleScrollViews.last
            else { return nil }

            let x = recognizer.location(in: hScroll).x
            let y: CGFloat
            if let vScroll = verticalCoordinateScrollView
                ?? host.enclosingScheduleScrollViews.first(where: Self.canScrollVertically) {
                y = recognizer.location(in: vScroll).y
            } else {
                y = recognizer.location(in: hScroll).y
            }

            return CGPoint(x: x, y: y)
        }

        private func notifyDragChange(recognizer: UIPanGestureRecognizer) {
            guard let gridPoint = fingerGridPoint(recognizer: recognizer) else { return }
            lastValidGridPoint = gridPoint
            onChanged(gridPoint, currentScrollOffset())
        }

        @objc func handlePreparingLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard !allowsImmediateDrag else { return }
            switch recognizer.state {
            case .began:
                guard !isHoldIndicationActive else { return }
                isHoldIndicationActive = true
                onHoldIndicationBegan()
            case .ended, .cancelled, .failed:
                guard isHoldIndicationActive else { return }
                isHoldIndicationActive = false
                if !didBeginMoveSession {
                    onHoldIndicationEnded()
                }
            default:
                break
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard !allowsImmediateDrag else { return }
            switch recognizer.state {
            case .began:
                guard !didBeginMoveSession else { return }
                didBeginMoveSession = true
                onMoveBegan()
            case .ended, .cancelled, .failed:
                didBeginMoveSession = false
                if isHoldIndicationActive {
                    isHoldIndicationActive = false
                    onHoldIndicationEnded()
                }
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            // Allow taps during move mode (immediate drag) so the booking can still open details.
            // Ignore only if this touch already committed a hold-to-move session.
            guard !didBeginMoveSession else { return }
            onTap()
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            if let host = recognizer.view {
                configureScrollViewInteraction(for: host)
            }

            switch recognizer.state {
            case .began:
                guard canTrackPan else { return }
                notifyDragChange(recognizer: recognizer)
            case .changed:
                guard canTrackPan else { return }
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

        private func axisEdgeScrollIntensity(
            leadingPositions: [CGFloat],
            trailingPositions: [CGFloat],
            viewportLength: CGFloat,
            zone: CGFloat,
            overshootCap: CGFloat,
            canScrollLeading: () -> Bool,
            canScrollTrailing: () -> Bool
        ) -> CGFloat {
            let leadingBoundary = zone
            let trailingBoundary = viewportLength - zone

            var leadingIntensity: CGFloat = 0
            var hasLeadingCandidate = false
            for position in leadingPositions where position < leadingBoundary {
                let penetration = leadingBoundary - position
                let candidate = -ProviderWeeklyScheduleGridDragLayout.edgeScrollIntensity(
                    penetration: penetration,
                    zone: zone,
                    overshootCap: overshootCap
                )
                leadingIntensity = hasLeadingCandidate
                    ? min(leadingIntensity, candidate)
                    : candidate
                hasLeadingCandidate = true
            }

            var trailingIntensity: CGFloat = 0
            var hasTrailingCandidate = false
            for position in trailingPositions where position > trailingBoundary {
                let penetration = position - trailingBoundary
                let candidate = ProviderWeeklyScheduleGridDragLayout.edgeScrollIntensity(
                    penetration: penetration,
                    zone: zone,
                    overshootCap: overshootCap
                )
                trailingIntensity = hasTrailingCandidate
                    ? max(trailingIntensity, candidate)
                    : candidate
                hasTrailingCandidate = true
            }

            let leadingActive = hasLeadingCandidate && leadingIntensity < 0 && canScrollLeading()
            let trailingActive = hasTrailingCandidate && trailingIntensity > 0 && canScrollTrailing()

            switch (leadingActive, trailingActive) {
            case (true, true):
                return abs(leadingIntensity) >= trailingIntensity ? leadingIntensity : trailingIntensity
            case (true, false):
                return leadingIntensity
            case (false, true):
                return trailingIntensity
            default:
                return 0
            }
        }

        private func resolvedHorizontalEdgeScrollIntensity(
            fingerX: CGFloat?,
            viewportWidth: CGFloat,
            scrollOffsetX: CGFloat
        ) -> CGFloat {
            var leadingPositions: [CGFloat] = []
            var trailingPositions: [CGFloat] = []

            if let fingerX {
                leadingPositions.append(fingerX)
                trailingPositions.append(fingerX)
            }

            if useCardViewportForEdgeScroll {
                let cardMinX = cardContentLeft - scrollOffsetX
                let cardMaxX = cardMinX + cardContentWidth
                leadingPositions.append(cardMinX)
                trailingPositions.append(cardMaxX)
            }

            return axisEdgeScrollIntensity(
                leadingPositions: leadingPositions,
                trailingPositions: trailingPositions,
                viewportLength: viewportWidth,
                zone: ProviderWeeklyScheduleGridDragLayout.horizontalEdgeScrollZone,
                overshootCap: ProviderWeeklyScheduleGridDragLayout.horizontalEdgeScrollOvershootCap,
                canScrollLeading: canScrollHorizontallyLeft,
                canScrollTrailing: canScrollHorizontallyRight
            )
        }

        private func resolvedVerticalEdgeScrollIntensity(
            fingerY: CGFloat?,
            viewportHeight: CGFloat,
            scrollOffsetY: CGFloat
        ) -> CGFloat {
            var leadingPositions: [CGFloat] = []
            var trailingPositions: [CGFloat] = []

            if let fingerY {
                leadingPositions.append(fingerY)
                trailingPositions.append(fingerY)
            }

            if useCardViewportForEdgeScroll {
                let cardMinY = cardContentTop - scrollOffsetY
                let cardMaxY = cardMinY + cardContentHeight
                leadingPositions.append(cardMinY)
                trailingPositions.append(cardMaxY)
            }

            return axisEdgeScrollIntensity(
                leadingPositions: leadingPositions,
                trailingPositions: trailingPositions,
                viewportLength: viewportHeight,
                zone: ProviderWeeklyScheduleGridDragLayout.verticalEdgeScrollZone,
                overshootCap: ProviderWeeklyScheduleGridDragLayout.verticalEdgeScrollOvershootCap,
                canScrollLeading: canScrollVerticallyUp,
                canScrollTrailing: canScrollVerticallyDown
            )
        }

        private func refreshTargetEdgeIntensities(recognizer: UIPanGestureRecognizer) {
            if let hScroll = horizontalScrollView,
               hScroll.bounds.width > ProviderWeeklyScheduleGridDragLayout.horizontalEdgeScrollZone * 2 {
                targetHorizontalEdgeIntensity = resolvedHorizontalEdgeScrollIntensity(
                    fingerX: fingerPositionInHorizontalViewport(recognizer)?.x,
                    viewportWidth: hScroll.bounds.width,
                    scrollOffsetX: hScroll.contentOffset.x
                )
            } else {
                targetHorizontalEdgeIntensity = 0
            }

            if let vScroll = verticalScrollView,
               vScroll.bounds.height > ProviderWeeklyScheduleGridDragLayout.verticalEdgeScrollZone * 2 {
                targetVerticalEdgeIntensity = resolvedVerticalEdgeScrollIntensity(
                    fingerY: fingerPositionInVerticalViewport(recognizer)?.y,
                    viewportHeight: vScroll.bounds.height,
                    scrollOffsetY: vScroll.contentOffset.y
                )
            } else {
                targetVerticalEdgeIntensity = 0
            }
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
            edgeScrollRecognizer = nil
        }

        @objc private func edgeScrollTick(_ link: CADisplayLink) {
            guard let recognizer = edgeScrollRecognizer else {
                stopEdgeScroll()
                return
            }

            refreshTargetEdgeIntensities(recognizer: recognizer)
            let deltaTime = max(link.duration, 1.0 / 120.0)
            let horizontalIntensity = targetHorizontalEdgeIntensity
            let verticalIntensity = targetVerticalEdgeIntensity

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
                let speed = ProviderWeeklyScheduleGridDragLayout.horizontalEdgeScrollMaxPointsPerSecond * abs(horizontalIntensity)
                let scrollDelta = (horizontalIntensity < 0 ? -speed : speed) * CGFloat(deltaTime)
                didScroll = abs(applyHorizontalScroll(scrollDelta, on: scrollView)) > 0.01 || didScroll
            }

            if abs(verticalIntensity) > 0.01,
               shouldAllowVerticalEdgeScroll(verticalIntensity, gridPoint, scrollOffset),
               let scrollView = verticalScrollView {
                let speed = ProviderWeeklyScheduleGridDragLayout.verticalEdgeScrollMaxPointsPerSecond * abs(verticalIntensity)
                let scrollDelta = (verticalIntensity < 0 ? -speed : speed) * CGFloat(deltaTime)
                didScroll = abs(applyVerticalScroll(scrollDelta, on: scrollView)) > 0.01 || didScroll
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
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer === preparingLongPressRecognizer,
               otherGestureRecognizer === longPressRecognizer {
                return true
            }
            if gestureRecognizer === longPressRecognizer,
               otherGestureRecognizer === preparingLongPressRecognizer {
                return true
            }
            if gestureRecognizer === longPressRecognizer, otherGestureRecognizer === panRecognizer {
                return true
            }
            if gestureRecognizer === panRecognizer, otherGestureRecognizer === longPressRecognizer {
                return true
            }
            if gestureRecognizer === preparingLongPressRecognizer, otherGestureRecognizer === panRecognizer {
                return true
            }
            if gestureRecognizer === panRecognizer, otherGestureRecognizer === preparingLongPressRecognizer {
                return true
            }
            if gestureRecognizer === tapRecognizer, otherGestureRecognizer === longPressRecognizer {
                return false
            }
            if gestureRecognizer === longPressRecognizer, otherGestureRecognizer === tapRecognizer {
                return false
            }
            return false
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
    var enclosingScheduleScrollViews: [UIScrollView] {
        sequence(first: self, next: { $0.superview })
            .compactMap { $0 as? UIScrollView }
            .reduce(into: [UIScrollView]()) { result, scrollView in
                if !result.contains(where: { $0 === scrollView }) {
                    result.append(scrollView)
                }
            }
    }
}
