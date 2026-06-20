import Foundation

enum ProviderScheduleBookingConflicts {
    static func upcomingBookings(
        from bookings: [SimpleBookingDTO],
        calendar: Calendar
    ) -> [SimpleBookingDTO] {
        let startOfToday = calendar.startOfDay(for: .now)
        return bookings.filter { booking in
            guard let scheduled = booking.scheduledTime, scheduled >= startOfToday else { return false }
            return countsForScheduleConflict(booking)
        }
    }

    static func bookingsOverlappingTimeBlock(
        blockDate: Date,
        start: Date,
        end: Date,
        bookings: [SimpleBookingDTO],
        calendar: Calendar,
        durationMinutes: Int = ProviderScheduleHourlySlot.bookableSlotMinutes
    ) -> [SimpleBookingDTO] {
        guard start < end else { return [] }
        let blockDay = calendar.startOfDay(for: blockDate)
        let blockStart = minutesSinceStartOfDay(start, calendar: calendar)
        let blockEnd = minutesSinceStartOfDay(end, calendar: calendar)

        return upcomingBookings(from: bookings, calendar: calendar).filter { booking in
            guard let scheduled = booking.scheduledTime else { return false }
            guard calendar.isDate(scheduled, inSameDayAs: blockDay) else { return false }
            guard let appointment = ScheduleCanvasAppointment.from(
                booking: booking,
                calendar: calendar,
                defaultDurationMinutes: durationMinutes
            ) else { return false }
            let bookingStart = appointment.startMinute
            let bookingEnd = bookingStart + appointment.durationMinutes
            return bookingStart < blockEnd && bookingEnd > blockStart
        }
    }

    static func bookingsNewlyExcludedByScheduleChange(
        proposed: WeeklyScheduleDTO,
        original: WeeklyScheduleDTO,
        bookings: [SimpleBookingDTO],
        calendar: Calendar,
        durationMinutes: Int = ProviderScheduleHourlySlot.bookableSlotMinutes
    ) -> [SimpleBookingDTO] {
        upcomingBookings(from: bookings, calendar: calendar).filter { booking in
            guard booking.scheduledTime != nil else { return false }
            let dayKey = weeklyDayKey(for: booking.scheduledTime!, calendar: calendar)
            let wasCovered = isBookingCovered(
                booking,
                by: original[dayKey],
                calendar: calendar,
                durationMinutes: durationMinutes
            )
            let nowCovered = isBookingCovered(
                booking,
                by: proposed[dayKey],
                calendar: calendar,
                durationMinutes: durationMinutes
            )
            return wasCovered && !nowCovered
        }
    }

    static func moveBookingsMessage(
        bookings: [SimpleBookingDTO],
        calendar: Calendar,
        action: String
    ) -> String {
        guard !bookings.isEmpty else { return "" }
        let header: String
        if bookings.count == 1 {
            header = "You have an appointment during this time. Move it to another date/time before \(action)."
        } else {
            header = "You have \(bookings.count) appointments during the affected times. Move them to another date/time before \(action)."
        }
        let lines = bookings.prefix(5).map { bookingSummaryLine($0, calendar: calendar) }
        var message = header
        if !lines.isEmpty {
            message += "\n\n" + lines.joined(separator: "\n")
        }
        if bookings.count > 5 {
            message += "\n…and \(bookings.count - 5) more."
        }
        return message
    }

    private static func countsForScheduleConflict(_ booking: SimpleBookingDTO) -> Bool {
        ProviderBookingStatusDisplay.blocksScheduleConflict(booking)
    }

    private static func isBookingCovered(
        _ booking: SimpleBookingDTO,
        by entry: DayScheduleDTO,
        calendar: Calendar,
        durationMinutes: Int
    ) -> Bool {
        guard entry.enabled, !entry.intervals.isEmpty else { return false }
        guard let appointment = ScheduleCanvasAppointment.from(
            booking: booking,
            calendar: calendar,
            defaultDurationMinutes: durationMinutes
        ) else { return true }
        let bookingStart = appointment.startMinute
        let bookingEnd = bookingStart + appointment.durationMinutes
        return entry.intervals.contains { interval in
            let intervalStart = minutesFromHHMM(interval.start)
            let intervalEnd = minutesFromHHMM(interval.end)
            return intervalStart <= bookingStart && intervalEnd >= bookingEnd
        }
    }

    private static func weeklyDayKey(for date: Date, calendar: Calendar) -> WeeklyScheduleDayKey {
        switch calendar.component(.weekday, from: date) {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }

    private static func bookingSummaryLine(_ booking: SimpleBookingDTO, calendar: Calendar) -> String {
        let when = booking.scheduledTime?.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        ) ?? "Unknown time"
        return "• \(booking.consumerDisplayName) · \(booking.serviceDisplayName) · \(when)"
    }

    private static func minutesSinceStartOfDay(_ date: Date, calendar: Calendar) -> Int {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return hour * 60 + minute
    }

    private static func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let hour = parts.first.flatMap { Int($0) } ?? 0
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return hour * 60 + minute
    }
}
