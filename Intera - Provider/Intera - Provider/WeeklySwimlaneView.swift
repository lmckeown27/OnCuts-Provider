import SwiftUI

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

// MARK: - Layout constants

private enum WeeklySwimlaneLayout {
    static let timeGutterWidth: CGFloat = 46
    static let timeGutterLabelFontSize: CGFloat = 8
    static let dayHeaderHeight: CGFloat = 42
    static let outerPadding: CGFloat = 10
    static let trackCornerRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 7
    static let densityStripeWidth: CGFloat = 3.5
    static let minimumCardHeight: CGFloat = 18
    /// Increase to add more vertical breathing room between appointments.
    static let verticalScaleBoost: CGFloat = 1.08
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
    let onDayTap: (Date) -> Void
    let onBookingTap: (SimpleBookingDTO) -> Void

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

    var body: some View {
        VStack(spacing: 0) {
            dayHeaderRow
                .padding(.horizontal, WeeklySwimlaneLayout.outerPadding)
                .padding(.top, WeeklySwimlaneLayout.outerPadding)

            trackScrollRegion
                .padding(.horizontal, WeeklySwimlaneLayout.outerPadding)
                .padding(.bottom, WeeklySwimlaneLayout.outerPadding)
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .top)
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: WeeklySwimlaneLayout.timeGutterWidth)

            ForEach(0 ..< 7, id: \.self) { offset in
                let day = dayDate(offset: offset)
                dayHeader(for: day, showsDivider: offset < 6)
            }
        }
        .frame(height: WeeklySwimlaneLayout.dayHeaderHeight)
    }

    @ViewBuilder
    private var trackScrollRegion: some View {
        let tracks = AnyView(
            HStack(alignment: .top, spacing: 0) {
                WeeklySwimlaneTimeGutterView(
                    startMinute: startMinute,
                    endMinute: endMinute,
                    pointsPerMinute: pointsPerMinute,
                    trackHeight: contentTrackHeight
                )
                .frame(width: WeeklySwimlaneLayout.timeGutterWidth)

                ForEach(0 ..< 7, id: \.self) { offset in
                    WeeklySwimlaneDayTrackView(
                        day: dayDate(offset: offset),
                        calendar: calendar,
                        appointments: appointments(for: dayDate(offset: offset)),
                        availabilityIntervals: availabilityIntervals(for: offset),
                        startMinute: startMinute,
                        endMinute: endMinute,
                        pointsPerMinute: pointsPerMinute,
                        trackHeight: contentTrackHeight,
                        showsTrailingDivider: offset < 6,
                        onDayTap: onDayTap,
                        onBookingTap: onBookingTap
                    )
                }
            }
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
    private func dayHeader(for day: Date, showsDivider: Bool) -> some View {
        let isToday = calendar.isDateInToday(day)

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                onDayTap(day)
            }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.provider(.caption2, weight: .semibold))
                    .foregroundStyle(isToday ? Color.lavaShellCream : Color.lavaShellCreamSecondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.provider(size: 15, weight: isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? Color.providerOlive : Color.lavaShellCream)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isToday {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.providerOlive.opacity(0.14))
                }
            }
            .overlay(alignment: .trailing) {
                if showsDivider {
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.5))
                        .frame(width: 0.5)
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
}

// MARK: - Time gutter

private struct WeeklySwimlaneTimeGutterView: View {
    let startMinute: Int
    let endMinute: Int
    let pointsPerMinute: CGFloat
    let trackHeight: CGFloat

    private var hourMarkers: [Int] {
        let firstHour = (startMinute / 60) * 60
        return stride(from: max(firstHour, startMinute), to: endMinute, by: 60).map { $0 }
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
                    .frame(width: WeeklySwimlaneLayout.timeGutterWidth, alignment: .trailing)
                    .offset(y: CGFloat(minute - startMinute) * pointsPerMinute)
                    .padding(.trailing, 2)
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
    let calendar: Calendar
    let appointments: [SwimlaneAppointment]
    let availabilityIntervals: [BarberAvailabilityIntervalDTO]
    let startMinute: Int
    let endMinute: Int
    let pointsPerMinute: CGFloat
    let trackHeight: CGFloat
    let showsTrailingDivider: Bool
    let onDayTap: (Date) -> Void
    let onBookingTap: (SimpleBookingDTO) -> Void

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
                        .padding(.horizontal, 5)
                }
            }

            ForEach(appointments) { appointment in
                WeeklySwimlaneAppointmentCard(
                    appointment: appointment,
                    startMinute: startMinute,
                    pointsPerMinute: pointsPerMinute,
                    onTap: { onBookingTap(appointment.booking) }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: trackHeight, alignment: .top)
        .padding(.horizontal, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                onDayTap(day)
            }
        }
        .overlay(alignment: .trailing) {
            if showsTrailingDivider {
                Rectangle()
                    .fill(Color(uiColor: .separator).opacity(0.5))
                    .frame(width: 0.5)
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

private struct WeeklySwimlaneAppointmentCard: View {
    let appointment: SwimlaneAppointment
    let startMinute: Int
    let pointsPerMinute: CGFloat
    let onTap: () -> Void

    private var cardTop: CGFloat {
        CGFloat(appointment.startMinute - startMinute) * pointsPerMinute
    }

    private var cardHeight: CGFloat {
        max(
            WeeklySwimlaneLayout.minimumCardHeight,
            CGFloat(appointment.durationMinutes) * pointsPerMinute
        )
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.providerOlive.opacity(appointment.densityWeight))
                    .frame(width: WeeklySwimlaneLayout.densityStripeWidth)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appointment.booking.consumerDisplayName)
                        .font(.provider(size: cardHeight > 34 ? 11 : 10, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(cardHeight > 44 ? 2 : 1)
                        .minimumScaleFactor(0.85)

                    if cardHeight > 40 {
                        Text(appointment.booking.serviceDisplayName)
                            .font(.provider(size: 9, weight: .medium))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: cardHeight, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: WeeklySwimlaneLayout.cardCornerRadius, style: .continuous)
                    .fill(Color.providerOlive.opacity(0.26))
            }
            .clipShape(RoundedRectangle(cornerRadius: WeeklySwimlaneLayout.cardCornerRadius, style: .continuous))
            .padding(.horizontal, 5)
        }
        .buttonStyle(.plain)
        .offset(y: cardTop)
    }
}
