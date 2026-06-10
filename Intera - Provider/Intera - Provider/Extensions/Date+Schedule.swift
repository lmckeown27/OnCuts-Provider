import Foundation

extension Date {
    /// ISO 8601 with fractional seconds for `bookings-simple` updates.
    func campusCutsISO8601String() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: self)
    }
}

extension SimpleBookingDTO {
    func formattedSchedule(reference: Date = .now) -> String {
        guard let scheduledTime else { return "Time TBD" }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        return scheduledTime.formatted(style)
    }

    func isSameCalendarDay(as date: Date, calendar: Calendar = .current) -> Bool {
        guard let scheduledTime else { return false }
        return calendar.isDate(scheduledTime, inSameDayAs: date)
    }

    func isInWeek(containing referenceMonday: Date, calendar: Calendar = .current) -> Bool {
        guard let scheduledTime else { return false }
        let end = calendar.date(byAdding: .day, value: 7, to: referenceMonday) ?? referenceMonday
        return scheduledTime >= referenceMonday && scheduledTime < end
    }

    func isInMonth(containing monthStart: Date, calendar: Calendar = .current) -> Bool {
        guard let scheduledTime else { return false }
        return calendar.isDate(scheduledTime, equalTo: monthStart, toGranularity: .month)
    }
}
