import SwiftUI
import UIKit

// MARK: - Layout

private enum ProviderWeeklyScheduleGridDragLayout {
    static let moveHoldDuration = 0.25
    static let moveHoldMaxDistance: CGFloat = 10
    static var moveHoldHighlightDelay: Double { moveHoldDuration * 0.42 }
    static let viewportEdgeInset: CGFloat = 4
    static let horizontalEdgeScrollZone: CGFloat = 72
    static let horizontalEdgeScrollMaxPointsPerSecond: CGFloat = 120
    static let horizontalEdgeScrollOvershootCap: CGFloat = 1.4
    static let verticalEdgeScrollZone: CGFloat = 72
    static let verticalEdgeScrollMaxPointsPerSecond: CGFloat = 96
    static let verticalEdgeScrollOvershootCap: CGFloat = 1.25
    static let verticalEdgeScrollIntensitySmoothingRate: CGFloat = 5
}

// MARK: - Move resolver

struct ProviderWeeklyScheduleGridMoveResolver {
    let model: ProviderWeeklyScheduleGridModel
    let calendar: Calendar
    let dayColumnWidth: CGFloat
    let positionedBookings: [ProviderWeeklyScheduleGridPositionedBooking]

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
            excludingBookingID: positioned.booking.id
        )
        let offsetX = CGFloat(resolved.dayIndex - positioned.dayIndex) * dayColumnWidth
        let offsetY = CGFloat(resolved.startRowIndex - positioned.startRowIndex) * rowHeight
        return CGPoint(x: offsetX, y: offsetY)
    }

    @discardableResult
    func handleDragEndedFromGridPoint(
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
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
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
        totalOffsetX: CGFloat,
        totalOffsetY: CGFloat,
        onProposed: (SimpleBookingDTO, Date) -> Void
    ) -> Bool {
        let proposed = proposedPosition(
            for: positioned,
            totalOffsetX: totalOffsetX,
            totalOffsetY: totalOffsetY
        )
        guard proposed.dayIndex != positioned.dayIndex || proposed.startRowIndex != positioned.startRowIndex else {
            return false
        }
        guard let proposedDate = scheduledDate(
            dayIndex: proposed.dayIndex,
            startRowIndex: proposed.startRowIndex
        ) else {
            return false
        }
        onProposed(positioned.booking, proposedDate)
        return true
    }

    private func proposedPosition(
        for positioned: ProviderWeeklyScheduleGridPositionedBooking,
        totalOffsetX: CGFloat,
        totalOffsetY: CGFloat
    ) -> (dayIndex: Int, startRowIndex: Int) {
        let dayDelta = Int(round(totalOffsetX / dayColumnWidth))
        let rowDelta = Int(round(totalOffsetY / rowHeight))
        return resolvedPosition(
            dayIndex: positioned.dayIndex + dayDelta,
            rowIndex: positioned.startRowIndex + rowDelta,
            rowSpan: positioned.rowSpan,
            excludingBookingID: positioned.booking.id
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
        excludingBookingID: String
    ) -> (dayIndex: Int, startRowIndex: Int) {
        let clampedDay = min(max(dayIndex, 0), model.weekDays.count - 1)
        let snappedRow = snappedRowIndex(from: rowIndex)

        if isOpenSlot(
            dayIndex: clampedDay,
            startRowIndex: snappedRow,
            rowSpan: rowSpan,
            excludingBookingID: excludingBookingID
        ) {
            return (clampedDay, snappedRow)
        }

        if let nearest = nearestOpenStart(
            aroundDayIndex: clampedDay,
            aroundRowIndex: snappedRow,
            rowSpan: rowSpan,
            excludingBookingID: excludingBookingID
        ) {
            return nearest
        }

        return (clampedDay, snappedRow)
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
    @Binding var activeMoveDragBookingID: String?
    let onMoveBookingRequested: (SimpleBookingDTO) -> Void
    let onViewBooking: (SimpleBookingDTO) -> Void
    let onBookingTimeChangeProposed: (SimpleBookingDTO, Date) -> Void

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
        let isDragActive = activeMoveDragBookingID == positioned.booking.id

        ProviderWeeklyScheduleGridDraggableBookingCard(
            originX: originX,
            top: positioned.yOffset,
            height: positioned.height,
            columnWidth: dayColumnWidth,
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
                    if positioned.booking.id == editingID {
                        activeMoveDragBookingID = positioned.booking.id
                    } else {
                        activeMoveDragBookingID = nil
                    }
                    return
                }
                onViewBooking(positioned.booking)
            },
            onMoveRequested: { onMoveBookingRequested(positioned.booking) },
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
            },
            accessibilityName: positioned.booking.consumerDisplayName
        ) {
            ProviderWeeklyScheduleGridBookingCardContent(
                booking: positioned.booking,
                cardHeight: positioned.height,
                isMoveSession: isMoveSession,
                isDragActive: isDragActive
            )
        }
    }
}

// MARK: - Booking card content

struct ProviderWeeklyScheduleGridBookingCardContent: View {
    let booking: SimpleBookingDTO
    let cardHeight: CGFloat
    var isMoveSession: Bool = false
    var isDragActive: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.providerBrandAccent.opacity(0.75))

            if isMoveSession {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.provider(size: moveModeIconSize, weight: .semibold))
                    .foregroundStyle(
                        isDragActive
                            ? Color.lavaShellCreamSecondary.opacity(0.88)
                            : Color.lavaShellCream.opacity(0.92)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cardHeight >= 24 {
                Text(booking.consumerInitials)
                    .font(.provider(.caption2, weight: .bold))
                    .foregroundStyle(Color.lavaShellCream)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .lineLimit(1)
            }
        }
    }

    private var moveModeIconSize: CGFloat {
        cardHeight >= 36 ? 14 : 11
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
    let isDragActive: Bool
    let canRequestMove: Bool
    let snapDragOffsetFromGridPoint: (CGPoint) -> CGPoint
    let onTap: () -> Void
    let onMoveRequested: () -> Void
    let onDragEndedAtGridPoint: (CGPoint) -> Bool
    let accessibilityName: String
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
                    ProviderWeeklyScheduleGridPlaneDragOverlay(
                        onChanged: handleDragChanged,
                        onEnded: handleDragEnded,
                        onInteractionReset: handleDragInteractionReset,
                        viewportWidth: viewportWidth,
                        viewportHeight: viewportHeight,
                        shouldAllowHorizontalEdgeScroll: { _, _, _ in true },
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
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.92), lineWidth: 2.5)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: originX + dragDelta.x, y: top + dragDelta.y)
            .zIndex(isDragActive ? 3 : (isMoveSession ? 2 : (isPressingForMove ? 2 : 1)))
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
            .accessibilityLabel("\(accessibilityName), tap for booking details")
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
        let inset = ProviderWeeklyScheduleGridDragLayout.viewportEdgeInset
        let minY = scrollOffset.y + inset - top
        let maxY = scrollOffset.y + viewportHeight - inset - top - height
        return (minY, max(maxY, minY))
    }

    private func allowsVerticalEdgeScroll(
        intensity: CGFloat,
        gridPoint: CGPoint,
        scrollOffset: CGPoint
    ) -> Bool {
        let slotClamped = snapDragOffsetFromGridPoint(gridPoint)
        let clampedY = clampVerticalDragOffset(slotClamped.y, scrollOffset: scrollOffset)
        let inset = ProviderWeeklyScheduleGridDragLayout.viewportEdgeInset

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
            .modifier(ProviderWeeklyScheduleGridBookingInteractionModifier(
                isEnabled: !isMoveSession,
                canRequestMove: canRequestMove,
                moveHoldDuration: ProviderWeeklyScheduleGridDragLayout.moveHoldDuration,
                moveHoldMaxDistance: ProviderWeeklyScheduleGridDragLayout.moveHoldMaxDistance,
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

// MARK: - Hold-to-move interaction

private struct ProviderWeeklyScheduleGridBookingInteractionModifier: ViewModifier {
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
                deadline: .now() + ProviderWeeklyScheduleGridDragLayout.moveHoldHighlightDelay,
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
        if Date().timeIntervalSince(began) >= moveHoldDuration * 0.45 {
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

// MARK: - UIKit plane drag

private struct ProviderWeeklyScheduleGridPlaneDragOverlay: UIViewRepresentable {
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
        private weak var horizontalScrollView: UIScrollView?
        private weak var verticalScrollView: UIScrollView?
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

        private func horizontalEdgeScrollIntensity(
            fingerX: CGFloat,
            viewportWidth: CGFloat,
            canScrollLeft: () -> Bool,
            canScrollRight: () -> Bool
        ) -> CGFloat {
            let zone = ProviderWeeklyScheduleGridDragLayout.horizontalEdgeScrollZone
            let overshootCap = ProviderWeeklyScheduleGridDragLayout.horizontalEdgeScrollOvershootCap

            if fingerX < zone {
                guard canScrollLeft() else { return 0 }
                return -min((zone - fingerX) / zone, overshootCap)
            }
            if fingerX > viewportWidth - zone {
                guard canScrollRight() else { return 0 }
                return min((fingerX - (viewportWidth - zone)) / zone, overshootCap)
            }
            return 0
        }

        private func verticalEdgeScrollIntensity(
            fingerY: CGFloat,
            viewportHeight: CGFloat,
            canScrollUp: () -> Bool,
            canScrollDown: () -> Bool
        ) -> CGFloat {
            let zone = ProviderWeeklyScheduleGridDragLayout.verticalEdgeScrollZone
            let overshootCap = ProviderWeeklyScheduleGridDragLayout.verticalEdgeScrollOvershootCap

            if fingerY < zone {
                guard canScrollUp() else { return 0 }
                return -min((zone - fingerY) / zone, overshootCap)
            }
            if fingerY > viewportHeight - zone {
                guard canScrollDown() else { return 0 }
                return min((fingerY - (viewportHeight - zone)) / zone, overshootCap)
            }
            return 0
        }

        private func refreshTargetEdgeIntensities(recognizer: UIPanGestureRecognizer) {
            if let finger = fingerPositionInHorizontalViewport(recognizer),
               let hScroll = horizontalScrollView,
               hScroll.bounds.width > ProviderWeeklyScheduleGridDragLayout.horizontalEdgeScrollZone * 2 {
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
               let vScroll = verticalScrollView,
               vScroll.bounds.height > ProviderWeeklyScheduleGridDragLayout.verticalEdgeScrollZone * 2 {
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
            smoothedVerticalEdgeIntensity += (targetVerticalEdgeIntensity - smoothedVerticalEdgeIntensity)
                * min(1, ProviderWeeklyScheduleGridDragLayout.verticalEdgeScrollIntensitySmoothingRate * deltaTime)

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
