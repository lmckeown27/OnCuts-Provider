import SwiftUI

// MARK: - Zoom tiers & presets

enum ProviderScheduleZoom {
    static let min: CGFloat = 0.15
    static let max: CGFloat = 5.0
    static let defaultScale: CGFloat = 1.5

    static let monthUpper: CGFloat = 0.4
    static let weekUpper: CGFloat = 1.4
    static let dayUpper: CGFloat = 3.4

    enum Preset: String, CaseIterable, Identifiable {
        case month = "1M"
        case week = "1W"
        case day = "1D"
        case minute = "Min"

        var id: String { rawValue }

        var targetScale: CGFloat {
            switch self {
            case .month: return 0.25
            case .week: return 0.9
            case .day: return 1.5
            case .minute: return 4.0
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
        if effectiveScale >= 3.5 {
            self = .minute
        } else if effectiveScale >= 1.5 {
            self = .day
        } else if effectiveScale >= ProviderScheduleZoom.monthUpper {
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

    @GestureState private var dynamicGestureScale: CGFloat = 1.0

    private var effectiveScale: CGFloat {
        max(ProviderScheduleZoom.min, min(ProviderScheduleZoom.max, zoomScale * dynamicGestureScale))
    }

    private var tier: ProviderScheduleZoomTier {
        ProviderScheduleZoomTier(effectiveScale: effectiveScale)
    }

    private var appointments: [ScheduleCanvasAppointment] {
        bookings.compactMap { ScheduleCanvasAppointment.from(booking: $0, calendar: calendar) }
            .sorted { $0.startMinute < $1.startMinute }
    }

    var body: some View {
        VStack(spacing: 0) {
            zoomContextHeader

            Divider()
                .overlay(Color.providerScheduleTrackStroke)

            GeometryReader { proxy in
                ScrollView([.vertical, .horizontal], showsIndicators: false) {
                    canvasContent(in: proxy.size)
                        .frame(minWidth: proxy.size.width, alignment: .topLeading)
                }
                .contentShape(Rectangle())
            }
            .frame(minHeight: 360)
            .gesture(magnificationGesture)
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
            Text(String(format: "%.1fx", effectiveScale))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func canvasContent(in size: CGSize) -> some View {
        switch tier {
        case .month:
            ScheduleMonthHeatmapGrid(
                calendar: calendar,
                monthAnchor: monthAnchor,
                bookings: bookings,
                onDayTap: onMonthDayTap
            )
            .frame(width: size.width)
            .transition(.opacity)
        case .week:
            ScheduleWeekColumnsCanvas(
                calendar: calendar,
                weekStart: weekStartMonday,
                bookings: bookings,
                scale: effectiveScale,
                startMinute: timelineStartMinute,
                endMinute: timelineEndMinute,
                onDayTap: onWeekDayTap,
                onBookingTap: onBookingTap
            )
            .frame(width: max(size.width, size.width))
            .transition(.opacity)
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
            .transition(.opacity)
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($dynamicGestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    zoomScale = max(ProviderScheduleZoom.min, min(ProviderScheduleZoom.max, zoomScale * value))
                }
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

    private var timelineHeight: CGFloat {
        CGFloat(endMinute - startMinute) * scale
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
                    .frame(height: CGFloat(end - start) * scale)
                    .offset(x: 52, y: CGFloat(start - startMinute) * scale)
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
                        .frame(height: max(4, CGFloat(end - start) * scale))
                }
                .offset(y: CGFloat(start - startMinute) * scale)
            }
        }
    }

    private var tickMarks: some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: startMinute, to: endMinute, by: tickStep)), id: \.self) { minute in
                HStack(alignment: .top, spacing: 6) {
                    Text(formatMinuteLabel(minute))
                        .font(.system(size: scale >= 3.5 ? 9 : 10, design: .monospaced))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .frame(width: 44, alignment: .trailing)
                    Rectangle()
                        .fill(Color.lavaShellCreamTertiary.opacity(0.35))
                        .frame(height: 0.5)
                }
                .frame(height: CGFloat(tickStep) * scale, alignment: .top)
            }
        }
    }

    private var appointmentBlocks: some View {
        ForEach(appointments) { app in
            let top = CGFloat(app.startMinute - startMinute) * scale
            let height = max(4, CGFloat(app.durationMinutes) * scale)
            Button {
                onBookingTap(app.booking)
            } label: {
                HStack(spacing: 0) {
                    Spacer().frame(width: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        if detailTextOpacity > 0.05 {
                            Text(app.booking.consumerDisplayName)
                                .font(.system(size: min(13, 9 + scale), weight: .bold))
                                .lineLimit(scale >= 3.5 ? 2 : 1)
                                .opacity(detailTextOpacity)
                            Text(app.booking.serviceDisplayName)
                                .font(.system(size: min(11, 8 + scale * 0.5)))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                                .lineLimit(1)
                                .opacity(detailTextOpacity * 0.9)
                        }
                        if scale >= 3.5 {
                            Text(formatMinuteLabel(app.startMinute))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(appointmentColor(for: app.booking))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .frame(height: height)
            }
            .buttonStyle(.plain)
            .offset(y: top)
        }
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
        String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}

// MARK: - Week columns

private struct ScheduleWeekColumnsCanvas: View {
    let calendar: Calendar
    let weekStart: Date
    let bookings: [SimpleBookingDTO]
    let scale: CGFloat
    let startMinute: Int
    let endMinute: Int
    let onDayTap: (Date) -> Void
    let onBookingTap: (SimpleBookingDTO) -> Void

    private var columnScale: CGFloat {
        max(0.35, scale * 0.55)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
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
                        .frame(height: CGFloat(endMinute - startMinute) * columnScale)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(calendar.isDateInToday(day) ? Color.providerOlive.opacity(0.22) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }
}

// MARK: - Month heatmap

private struct ScheduleMonthHeatmapGrid: View {
    let calendar: Calendar
    let monthAnchor: Date
    let bookings: [SimpleBookingDTO]
    let onDayTap: (Date) -> Void

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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                ForEach(gridDays.indices, id: \.self) { index in
                    if let date = gridDays[index] {
                        monthDayCell(date: date)
                    } else {
                        Color.clear.frame(height: 52)
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
                    .font(.system(size: 12, weight: isToday ? .bold : .semibold))
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
            .frame(height: 52)
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
