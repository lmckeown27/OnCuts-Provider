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
                    .modifier(PinchZoomGestureModifier(isEnabled: pinchZoomEnabled, gesture: magnificationGesture))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                    onBookingTap: onBookingTap,
                    onAvailableMinuteTap: onAvailableMinuteTap
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
    let onBookingTap: (SimpleBookingDTO) -> Void
    let onAvailableMinuteTap: (Int) -> Void

    private var tickStep: Int {
        scale >= 3.5 ? 5 : (scale >= 2.0 ? 15 : 30)
    }

    /// Points per minute for timeline layout; grows with pinch zoom and may exceed the viewer box height.
    private var verticalScale: CGFloat {
        scale * ProviderScheduleZoom.timelineVerticalScaleBoost
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
            Button {
                onBookingTap(app.booking)
            } label: {
                HStack(spacing: 0) {
                    Spacer().frame(width: 52)
                    appointmentBlockContent(for: app, blockHeight: height)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .background(appointmentColor(for: app.booking))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .frame(height: height)
            }
            .buttonStyle(.plain)
            .offset(y: top)
        }
    }

    @ViewBuilder
    private func appointmentBlockContent(for app: ScheduleCanvasAppointment, blockHeight: CGFloat) -> some View {
        let booking = app.booking
        let detailLevel = appointmentDetailLevel(for: blockHeight)

        VStack(alignment: .center, spacing: detailLineSpacing(for: detailLevel)) {
            if detailTextOpacity > 0.05 {
                Text(booking.consumerDisplayName)
                    .font(.system(size: consumerFontSize(for: blockHeight, level: detailLevel), weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit(for: detailLevel, primary: true))
                    .minimumScaleFactor(0.85)
                    .opacity(detailTextOpacity)

                Text(booking.serviceDisplayName)
                    .font(.system(size: serviceFontSize(for: blockHeight, level: detailLevel), weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit(for: detailLevel, primary: false))
                    .minimumScaleFactor(0.85)
                    .opacity(detailTextOpacity * 0.9)

                if detailLevel >= .standard {
                    Text(appointmentTimeRange(for: app))
                        .font(.system(size: detailFontSize(for: blockHeight), weight: .medium))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .multilineTextAlignment(.center)

                    Text(ProviderBookingStatusDisplay.title(for: booking.status))
                        .font(.system(size: detailFontSize(for: blockHeight) - 1, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .multilineTextAlignment(.center)
                }

                if detailLevel >= .detailed {
                    if let price = formattedPrice(for: booking) {
                        Text(price)
                            .font(.system(size: detailFontSize(for: blockHeight), weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream)
                            .multilineTextAlignment(.center)
                    }

                    if let duration = formattedDuration(minutes: app.durationMinutes) {
                        Text(duration)
                            .font(.system(size: detailFontSize(for: blockHeight) - 1, weight: .medium))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                            .multilineTextAlignment(.center)
                    }

                    if booking.hasPendingRescheduleRequest {
                        Text("Reschedule requested")
                            .font(.system(size: detailFontSize(for: blockHeight) - 1, weight: .semibold))
                            .foregroundStyle(Color.orange.opacity(0.95))
                            .multilineTextAlignment(.center)
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
                    }

                    if let notes = trimmedNonEmpty(booking.notes) {
                        Text(notes)
                            .font(.system(size: detailFontSize(for: blockHeight) - 1, weight: .regular))
                            .italic()
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
            }
        }
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
        if ProviderBookingStatusDisplay.isScheduleCompleted(status: booking.status) {
            return Color.green.opacity(0.32)
        }
        if ProviderBookingStatusDisplay.isScheduleBooked(status: booking.status) {
            return Color.providerOlive.opacity(0.44)
        }
        return Color.providerScheduleCardFill
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
