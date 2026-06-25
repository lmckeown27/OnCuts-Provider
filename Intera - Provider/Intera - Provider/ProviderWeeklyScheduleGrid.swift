import SwiftUI

/// Monday-start weekly calendar: 7 columns × 5-minute rows. Time axis scrolls inside a fixed viewport.
struct ProviderWeeklyScheduleGrid: View {
    let model: ProviderWeeklyScheduleGridModel
    let weekOffset: Int
    let isLoading: Bool
    /// When set, the scrollable time region fills this height (typically the remaining hub viewport).
    let viewportHeight: CGFloat?
    var appointmentDragEnabled: Bool = false
    @Binding var editingMoveBookingID: String?
    let onUnblockTime: (_ blockId: String) -> Void
    let onViewBooking: (SimpleBookingDTO) -> Void
    let onMoveBookingRequested: (SimpleBookingDTO) -> Void
    let onBookingTimeChangeProposed: (SimpleBookingDTO, Date, Bool) -> Void
    let onBookingMoveProposalCleared: () -> Void

    @State private var didInitialScroll = false
    @State private var horizontalScrollOffset: CGFloat = 0

    private static let gridMinWidth: CGFloat = 640
    private static let daysScrollWidth: CGFloat = gridMinWidth - ProviderWeeklyScheduleGridMetrics.timeGutterWidth

    private var dayColumnWidth: CGFloat {
        Self.daysScrollWidth / 7
    }

    private var positionedBookings: [ProviderWeeklyScheduleGridPositionedBooking] {
        ProviderWeeklyScheduleGridEngine.positionedBookings(in: model)
    }

    private var moveResolver: ProviderWeeklyScheduleGridMoveResolver {
        ProviderWeeklyScheduleGridMoveResolver(
            model: model,
            calendar: calendar,
            dayColumnWidth: dayColumnWidth,
            positionedBookings: positionedBookings,
            earliestBookableDate: .now
        )
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    private var resolvedGridHeight: CGFloat {
        max(
            ProviderWeeklyScheduleGridMetrics.minimumGridHeight,
            viewportHeight ?? ProviderWeeklyScheduleGridMetrics.visibleGridHeight
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let daysViewportWidth = max(
                0,
                geometry.size.width - ProviderWeeklyScheduleGridMetrics.timeGutterWidth
            )
            VStack(alignment: .leading, spacing: ProviderWeeklyScheduleGridMetrics.dayHeaderGridSpacing) {
                pinnedDayHeaderRow
                gridScrollRegion(daysViewportWidth: daysViewportWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Headers

    private var pinnedDayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.providerScheduleGridBackground
                .frame(width: ProviderWeeklyScheduleGridMetrics.timeGutterWidth)
            ZStack(alignment: .leading) {
                dayHeaderRow
                    .offset(x: -horizontalScrollOffset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .padding(.bottom, 4)
        .background(Color.providerScheduleGridBackground)
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.weekDays.enumerated()), id: \.element.id) { index, day in
                dayHeaderCell(for: day)
                    .id(
                        index == ProviderWeeklyScheduleGridMetrics.fridayDayIndex
                            ? ProviderWeeklyScheduleGridMetrics.fridayDayScrollID
                            : day.id
                    )
            }
        }
        .frame(width: Self.daysScrollWidth, alignment: .leading)
    }

    private func dayHeaderCell(for day: ProviderWeeklyScheduleDayColumn) -> some View {
        VStack(spacing: 2) {
            Text(day.shortLabel)
                .font(.provider(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
            Text(dayNumber(for: day.date))
                .font(.provider(size: 16, weight: .bold))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .foregroundStyle(
            day.isToday
                ? Color.providerScheduleDayHeaderTodayForeground
                : Color.providerScheduleDayHeaderForeground
        )
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8,
                style: .continuous
            )
            .fill(
                day.isToday
                    ? Color.providerScheduleDayHeaderTodayFill
                    : Color.providerScheduleDayHeaderFill
            )
        }
        .overlay {
            if !day.isDaySelected {
                ProviderScheduleEntireDayCrossOutOverlay(cornerRadius: 8)
            }
        }
    }

    // MARK: - Scrollable grid

    private func gridScrollRegion(daysViewportWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if model.isEmptyAvailability {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear
                        .frame(width: ProviderWeeklyScheduleGridMetrics.timeGutterWidth)
                    Text("Set your weekly availability to see open slots.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, ProviderWeeklyScheduleGridMetrics.timeGutterTopPadding)
                        .padding(.horizontal, 4)
                }
            } else {
                ScrollViewReader { verticalProxy in
                    ScrollViewReader { horizontalProxy in
                        verticalGridScroll(daysViewportWidth: daysViewportWidth)
                            .onAppear {
                                scrollToInitialPosition(proxy: verticalProxy)
                                scrollToFridayPeek(
                                    proxy: horizontalProxy,
                                    viewportWidth: daysViewportWidth,
                                    animated: false
                                )
                            }
                            .onChange(of: weekOffset) { _, _ in
                                didInitialScroll = false
                                scrollToInitialPosition(proxy: verticalProxy)
                                scrollToFridayPeek(
                                    proxy: horizontalProxy,
                                    viewportWidth: daysViewportWidth,
                                    animated: true
                                )
                            }
                            .onChange(of: model.timeRows.count) { _, _ in
                                if !didInitialScroll {
                                    scrollToInitialPosition(proxy: verticalProxy)
                                }
                            }
                    }
                }
            }

            if isLoading {
                Color.providerScheduleTrackFill.opacity(0.55)
                ProgressView("Loading schedule…")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: resolvedGridHeight, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.providerScheduleTrackStroke, lineWidth: 0.6)
        }
    }

    private func verticalGridScroll(daysViewportWidth: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                timeGutter
                    .padding(.top, ProviderWeeklyScheduleGridMetrics.timeGutterTopPadding)
                horizontalDayColumnsScroll(daysViewportWidth: daysViewportWidth)
            }
            .padding(.bottom, ProviderWeeklyScheduleGridMetrics.bottomScrollPadding)
        }
        .providerScheduleGridScrollMarginsZero()
        .frame(height: resolvedGridHeight)
    }

    private func horizontalDayColumnsScroll(daysViewportWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                dayColumnsRow
                if !model.isEmptyAvailability {
                    ProviderWeeklyScheduleGridAppointmentsLayer(
                        model: model,
                        positionedBookings: positionedBookings,
                        moveResolver: moveResolver,
                        dayColumnWidth: dayColumnWidth,
                        viewportWidth: daysViewportWidth,
                        viewportHeight: resolvedGridHeight,
                        appointmentDragEnabled: appointmentDragEnabled,
                        editingMoveBookingID: $editingMoveBookingID,
                        onMoveBookingRequested: onMoveBookingRequested,
                        onViewBooking: onViewBooking,
                        onBookingTimeChangeProposed: onBookingTimeChangeProposed,
                        onBookingMoveProposalCleared: onBookingMoveProposalCleared
                    )
                }
            }
            .frame(width: Self.daysScrollWidth, alignment: .leading)
        }
        .providerScheduleGridScrollMarginsZero()
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x + geometry.contentInsets.leading
        } action: { _, newOffset in
            horizontalScrollOffset = newOffset
        }
    }

    private var dayColumnsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.weekDays.enumerated()), id: \.element.id) { dayIndex, day in
                dayColumn(dayIndex: dayIndex, day: day)
                    .id(
                        dayIndex == ProviderWeeklyScheduleGridMetrics.fridayDayIndex
                            ? ProviderWeeklyScheduleGridMetrics.fridayDayScrollID
                            : day.id
                    )
            }
        }
        .frame(width: Self.daysScrollWidth, alignment: .leading)
    }

    private var timeGutter: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.timeRows.enumerated()), id: \.offset) { _, slotStartMin in
                ZStack(alignment: .topTrailing) {
                    Color.clear
                    if slotStartMin % 30 == 0 {
                        Text(ProviderWeeklyScheduleGridEngine.formatTimeLabel(minutes: slotStartMin))
                            .font(.provider(size: 9, weight: .medium))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                            .padding(.trailing, 4)
                            .offset(y: -2)
                    }
                }
                .frame(height: ProviderWeeklyScheduleGridMetrics.rowHeight)
            }
        }
        .frame(width: ProviderWeeklyScheduleGridMetrics.timeGutterWidth)
        .background(Color.providerScheduleGridBackground)
    }

    private func dayColumn(dayIndex: Int, day: ProviderWeeklyScheduleDayColumn) -> some View {
        ZStack(alignment: .topLeading) {
            if day.isToday {
                Color.providerScheduleTodayColumnHighlight
            }
            VStack(spacing: 0) {
                ForEach(Array(model.timeRows.enumerated()), id: \.offset) { rowIndex, slotStartMin in
                    let cell = model.cells[rowIndex][dayIndex]
                    slotCell(
                        cell: cell,
                        slotStartMin: slotStartMin,
                        isHourLine: slotStartMin % 60 == 0,
                        scrollAnchorId: dayIndex == 0 ? "row-\(slotStartMin)" : nil
                    )
                }
            }

            if !day.isDaySelected {
                ProviderScheduleEntireDayCrossOutOverlay(cornerRadius: 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: model.totalContentHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: model.totalContentHeight)
    }

    @ViewBuilder
    private func slotCell(
        cell: ProviderWeeklyScheduleGridCell,
        slotStartMin: Int,
        isHourLine: Bool,
        scrollAnchorId: String?
    ) -> some View {
        let slotEndMin = slotStartMin + ProviderWeeklyScheduleGridMetrics.slotMinutes
        let startHHMM = ProviderWeeklyScheduleGridEngine.hhmm(from: slotStartMin)
        let endHHMM = ProviderWeeklyScheduleGridEngine.hhmm(from: slotEndMin)

        let background = slotBackground(for: cell, isHourLine: isHourLine)

        if cell.status == .blocked {
            Button {
                if let blockId = cell.blockId {
                    onUnblockTime(blockId)
                }
            } label: {
                background.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: cell, startHHMM: startHHMM, endHHMM: endHHMM))
            .modifier(OptionalScrollAnchor(id: scrollAnchorId))
        } else {
            background
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: cell, startHHMM: startHHMM, endHHMM: endHHMM))
                .modifier(OptionalScrollAnchor(id: scrollAnchorId))
        }
    }

    private struct OptionalScrollAnchor: ViewModifier {
        let id: String?
        func body(content: Content) -> some View {
            if let id {
                content.id(id)
            } else {
                content
            }
        }
    }

    // MARK: - Interaction

    private func scrollToFridayPeek(
        proxy: ScrollViewProxy,
        viewportWidth: CGFloat,
        animated: Bool
    ) {
        guard viewportWidth > 0 else { return }
        let peek = ProviderWeeklyScheduleGridMetrics.fridayPeekVisibleWidth
        let anchorX = max(0.5, min(0.995, (viewportWidth - peek) / viewportWidth))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(
                        ProviderWeeklyScheduleGridMetrics.fridayDayScrollID,
                        anchor: UnitPoint(x: anchorX, y: 0)
                    )
                }
            } else {
                proxy.scrollTo(
                    ProviderWeeklyScheduleGridMetrics.fridayDayScrollID,
                    anchor: UnitPoint(x: anchorX, y: 0)
                )
            }
        }
    }

    private func scrollToInitialPosition(proxy: ScrollViewProxy) {
        guard !model.isEmptyAvailability else { return }
        let targetMin = ProviderWeeklyScheduleGridEngine.autoScrollTargetMinute(
            weekOffset: weekOffset,
            gridStartMin: model.gridStartMin,
            now: .now,
            calendar: calendar
        )
        let rowIndex = max(0, (targetMin - model.gridStartMin) / ProviderWeeklyScheduleGridMetrics.slotMinutes)
        let scrollRowMin = model.timeRows.indices.contains(rowIndex) ? model.timeRows[rowIndex] : model.gridStartMin
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo("row-\(scrollRowMin)", anchor: .top)
            }
            didInitialScroll = true
        }
    }

    // MARK: - Styling

    private var openColor: Color { Color.providerScheduleOpenSlotFill }
    private var blockedColor: Color { Color.providerScheduleBlockedSlotFill }
    private var unavailableColor: Color { Color.providerScheduleCardFill.opacity(0.35) }

    private func fillColor(for cell: ProviderWeeklyScheduleGridCell) -> Color {
        switch cell.status {
        case .unavailable:
            return unavailableColor
        case .open:
            return openColor
        case .booked:
            if let booking = cell.booking {
                return booking.scheduleAppointmentFillColor
            }
            return Color.providerScheduleUpcomingAppointmentFill
        case .blocked:
            return blockedColor
        case .google:
            return Color.clear
        }
    }

    @ViewBuilder
    private func slotBackground(
        for cell: ProviderWeeklyScheduleGridCell,
        isHourLine: Bool
    ) -> some View {
        Group {
            if cell.status == .google {
                ProviderScheduleCrossOutOverlay(cornerRadius: 0, showsBorder: false)
            } else {
                Rectangle()
                    .fill(fillColor(for: cell))
                    .overlay {
                        if cell.status == .blocked {
                            ProviderScheduleDiagonalCrossOut(
                                lineColor: Color.providerScheduleDiagonalCrossOutLineBlocked
                            )
                        }
                    }
            }
        }
        .overlay(alignment: .top) {
            if isHourLine {
                Rectangle()
                    .fill(Color.providerScheduleTrackStroke.opacity(0.55))
                    .frame(height: 0.5)
            }
        }
        .frame(height: ProviderWeeklyScheduleGridMetrics.rowHeight)
    }

    private func dayNumber(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func accessibilityLabel(
        for cell: ProviderWeeklyScheduleGridCell,
        startHHMM: String,
        endHHMM: String
    ) -> String {
        switch cell.status {
        case .open:
            return "\(startHHMM) to \(endHHMM), open"
        case .booked:
            return "\(cell.booking?.consumerDisplayName ?? "Booking") at \(startHHMM), tap for details"
        case .blocked:
            return "\(startHHMM) to \(endHHMM), blocked, crossed out, tap to unblock"
        case .google:
            return "\(startHHMM), Google Calendar busy, crossed out"
        case .unavailable:
            return "\(startHHMM), unavailable"
        }
    }
}

private extension View {
    @ViewBuilder
    func providerScheduleGridScrollMarginsZero() -> some View {
        if #available(iOS 17.0, *) {
            self
                .contentMargins(.vertical, 0, for: .scrollContent)
                .contentMargins(.horizontal, 0, for: .scrollContent)
        } else {
            self
        }
    }
}
