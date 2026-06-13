import Foundation

// MARK: - Triage domain (client intersect layer)

enum RequestScheduleSlotType: Hashable {
    case booked
    case proposed
    case open
}

struct RequestScheduleContextItem: Identifiable, Hashable {
    let id = UUID()
    let timeLabel: String
    let title: String
    let type: RequestScheduleSlotType
    let sortKey: Date
}

struct RequestTriageItem: Identifiable, Hashable {
    let row: BookingRequestRow
    let requestedStart: Date
    let durationMinutes: Int
    let surroundingSchedule: [RequestScheduleContextItem]
    let hasConflict: Bool

    var id: String { row.id }
}

/// Merges pending booking inquiries with same-day confirmed/blocked schedule data.
@MainActor
enum ProviderRequestTriageEngine {
    private static let defaultDurationMinutes = 45
    /// Matches schedule dashboard / availability API appointment blocks (1 hour).
    private static let bookingSlotMinutes = 60
    /// Statuses that actually occupy the calendar (barber has committed).
    private static let committedStatuses: Set<String> = [
        "ACCEPTED", "CONFIRMED", "PAID", "COMPLETED", "SCHEDULED", "IN_PROGRESS",
    ]

    private static let pendingStatuses: Set<String> = ["PENDING"]

    static func build(
        pending: [BookingRequestRow],
        bookings: [SimpleBookingDTO],
        barberTableId: String,
        timeZone: TimeZone = .current
    ) async -> [RequestTriageItem] {
        var availabilityCache: [String: BarberAvailabilityDayData] = [:]
        var result: [RequestTriageItem] = []

        for request in pending {
            guard let start = parseRequestedInstant(request) else {
                result.append(
                    RequestTriageItem(
                        row: request,
                        requestedStart: Date(),
                        durationMinutes: defaultDurationMinutes,
                        surroundingSchedule: [],
                        hasConflict: false
                    )
                )
                continue
            }

            let dayKey = yyyyMMdd(start, timeZone: timeZone)
            if availabilityCache[dayKey] == nil {
                let dayData = (try? await ProviderAvailabilityService.getDayAvailability(
                    barberId: barberTableId,
                    date: start,
                    timeZone: timeZone
                )) ?? BarberAvailabilityDayData(
                    date: dayKey,
                    dayOfWeek: nil,
                    available: false,
                    intervals: [],
                    bookedSlots: [],
                    slots: []
                )
                availabilityCache[dayKey] = dayData
            }

            let dayAvailability = availabilityCache[dayKey]!
            let duration = defaultDurationMinutes
            let durationSeconds = TimeInterval(duration * 60)
            let proposedInterval = DateInterval(start: start, duration: durationSeconds)

            let pendingOnDay = pendingIntervals(
                onDayKey: dayKey,
                pending: pending,
                bookings: bookings,
                timeZone: timeZone,
                durationSeconds: durationSeconds
            )
            let pendingBookingIds = Set(pending.map(\.bookingId))

            var committedIntervals: [DateInterval] = []
            var timelineEntries: [(interval: DateInterval, label: String, type: RequestScheduleSlotType)] = []

            for booking in bookings {
                guard booking.id != request.bookingId else { continue }
                guard let scheduled = booking.scheduledTime else { continue }
                guard yyyyMMdd(scheduled, timeZone: timeZone) == dayKey else { continue }
                let status = booking.statusUpper
                let interval = DateInterval(start: scheduled, duration: durationSeconds)
                let name = booking.consumerDisplayName
                let svc = booking.serviceDisplayName

                if committedStatuses.contains(status) {
                    committedIntervals.append(interval)
                    timelineEntries.append((interval, "\(name) (\(svc))", .booked))
                } else if pendingStatuses.contains(status), !pendingBookingIds.contains(booking.id) {
                    timelineEntries.append((interval, "Pending: \(name) (\(svc))", .proposed))
                }
            }

            for other in pending where other.bookingId != request.bookingId {
                guard let otherStart = parseRequestedInstant(other) else { continue }
                guard yyyyMMdd(otherStart, timeZone: timeZone) == dayKey else { continue }
                let interval = DateInterval(start: otherStart, duration: durationSeconds)
                let name = other.customerName ?? "Customer"
                let svc = other.serviceDisplayName
                timelineEntries.append((interval, "Pending: \(name) (\(svc))", .proposed))
            }

            for slot in dayAvailability.bookedSlots ?? [] {
                guard let interval = timeIntervalOnDay(dayKey: dayKey, startHHMM: slot.start, endHHMM: slot.end, timeZone: timeZone) else {
                    continue
                }
                // Availability API includes this pending inquiry in bookedSlots; only show PROPOSED for it.
                let isViewingThisBooking = proposedInterval.intersects(interval)
                if !isViewingThisBooking {
                    timelineEntries.append((interval, "Blocked / booked", .booked))
                }
                if !isPendingOnlyAvailabilityBlock(
                    interval,
                    pendingOnDay: pendingOnDay,
                    committedOnDay: committedIntervals
                ) {
                    committedIntervals.append(interval)
                }
            }

            let hasConflict = committedIntervals.contains { $0.intersects(proposedInterval) }

            let surroundingSchedule = buildSurroundingSchedule(
                proposedStart: start,
                durationMinutes: duration,
                request: request,
                timelineEntries: timelineEntries,
                dayAvailability: dayAvailability,
                timeZone: timeZone
            )

            result.append(
                RequestTriageItem(
                    row: request,
                    requestedStart: start,
                    durationMinutes: duration,
                    surroundingSchedule: surroundingSchedule,
                    hasConflict: hasConflict
                )
            )
        }

        return result.sorted { $0.requestedStart < $1.requestedStart }
    }

    // MARK: - Surrounding schedule (1 slot before · proposed · 1 slot after)

    /// Hour-aligned window: one booking slot before, the proposed inquiry, one slot after.
    private static func buildSurroundingSchedule(
        proposedStart: Date,
        durationMinutes: Int,
        request: BookingRequestRow,
        timelineEntries: [(interval: DateInterval, label: String, type: RequestScheduleSlotType)],
        dayAvailability: BarberAvailabilityDayData,
        timeZone: TimeZone
    ) -> [RequestScheduleContextItem] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        let proposedHour = hourStart(for: proposedStart, timeZone: timeZone)
        guard let beforeHour = cal.date(byAdding: .hour, value: -1, to: proposedHour),
              let afterHour = cal.date(byAdding: .hour, value: 1, to: proposedHour)
        else {
            return [proposedContextItem(start: proposedStart, request: request, timeZone: timeZone)]
        }

        let slotDuration = TimeInterval(bookingSlotMinutes * 60)
        let beforeWindow = DateInterval(start: beforeHour, duration: slotDuration)
        let afterWindow = DateInterval(start: afterHour, duration: slotDuration)

        var items: [RequestScheduleContextItem] = []
        if let before = resolveHourWindow(
            beforeWindow,
            timelineEntries: timelineEntries,
            dayAvailability: dayAvailability,
            timeZone: timeZone
        ) {
            items.append(before)
        }
        items.append(proposedContextItem(start: proposedStart, request: request, timeZone: timeZone))
        if let after = resolveHourWindow(
            afterWindow,
            timelineEntries: timelineEntries,
            dayAvailability: dayAvailability,
            timeZone: timeZone
        ) {
            items.append(after)
        }
        return items
    }

    private static func proposedContextItem(
        start: Date,
        request: BookingRequestRow,
        timeZone: TimeZone
    ) -> RequestScheduleContextItem {
        RequestScheduleContextItem(
            timeLabel: displayWallClockTime(from: request) ?? timeLabel(start, timeZone: timeZone),
            title: "\(request.customerName ?? "Customer"): \(request.serviceDisplayName)",
            type: .proposed,
            sortKey: start
        )
    }

    private static func displayWallClockTime(from row: BookingRequestRow) -> String? {
        ProviderBookingScheduleParsing.displayWallClockTime(from: row)
    }

    private static func resolveHourWindow(
        _ window: DateInterval,
        timelineEntries: [(interval: DateInterval, label: String, type: RequestScheduleSlotType)],
        dayAvailability: BarberAvailabilityDayData,
        timeZone: TimeZone
    ) -> RequestScheduleContextItem? {
        let matches = timelineEntries.filter { $0.interval.intersects(window) }
        if let best = matches.max(by: { overlapDuration($0.interval, window) < overlapDuration($1.interval, window) }) {
            return RequestScheduleContextItem(
                timeLabel: timeLabel(window.start, timeZone: timeZone),
                title: best.label,
                type: best.type,
                sortKey: window.start
            )
        }

        if isHourWithinWorkingHours(window.start, intervals: dayAvailability.intervals ?? [], timeZone: timeZone) {
            return RequestScheduleContextItem(
                timeLabel: timeLabel(window.start, timeZone: timeZone),
                title: "Open availability",
                type: .open,
                sortKey: window.start
            )
        }

        return RequestScheduleContextItem(
            timeLabel: timeLabel(window.start, timeZone: timeZone),
            title: "Outside working hours",
            type: .open,
            sortKey: window.start
        )
    }

    private static func hourStart(for date: Date, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: date)
        return cal.date(from: comps) ?? date
    }

    private static func isHourWithinWorkingHours(
        _ date: Date,
        intervals: [BarberAvailabilityIntervalDTO],
        timeZone: TimeZone
    ) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hour = cal.component(.hour, from: date)
        for interval in intervals {
            guard let startHour = hourComponent(from: interval.start),
                  let endHour = hourComponent(from: interval.end),
                  endHour > startHour
            else { continue }
            if hour >= startHour, hour < endHour { return true }
        }
        return false
    }

    private static func hourComponent(from hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard let first = parts.first, let h = Int(first), (0 ... 24).contains(h) else { return nil }
        return h
    }

    private static func overlapDuration(_ a: DateInterval, _ b: DateInterval) -> TimeInterval {
        let start = max(a.start, b.start)
        let end = min(a.end, b.end)
        return max(0, end.timeIntervalSince(start))
    }

    // MARK: - Conflict rules

    /// Whether a draft time overlaps committed calendar blocks (for inline request editor).
    static func hasCommittedConflict(
        proposedStart: Date,
        bookingId: String,
        bookings: [SimpleBookingDTO],
        dayAvailability: BarberAvailabilityDayData?,
        timeZone: TimeZone = .current
    ) -> Bool {
        let durationSeconds = TimeInterval(defaultDurationMinutes * 60)
        let proposedInterval = DateInterval(start: proposedStart, duration: durationSeconds)
        let dayKey = yyyyMMdd(proposedStart, timeZone: timeZone)
        let committed = committedCalendarIntervals(
            dayKey: dayKey,
            editingBookingId: bookingId,
            bookings: bookings,
            dayAvailability: dayAvailability,
            durationSeconds: durationSeconds,
            timeZone: timeZone
        )
        return committed.contains { $0.intersects(proposedInterval) }
    }

    /// Whether an hour row should render as blocked while rescheduling a pending inquiry.
    static func isHourBlockedWhileEditing(
        slotStart: Date,
        editingBookingId: String,
        bookings: [SimpleBookingDTO],
        dayAvailability: BarberAvailabilityDayData?,
        timeZone: TimeZone = .current
    ) -> Bool {
        let slotInterval = DateInterval(
            start: slotStart,
            duration: TimeInterval(bookingSlotMinutes * 60)
        )
        let dayKey = yyyyMMdd(slotStart, timeZone: timeZone)
        let committed = committedCalendarIntervals(
            dayKey: dayKey,
            editingBookingId: editingBookingId,
            bookings: bookings,
            dayAvailability: dayAvailability,
            durationSeconds: TimeInterval(bookingSlotMinutes * 60),
            timeZone: timeZone
        )
        return committed.contains { $0.intersects(slotInterval) }
    }

    private static func committedCalendarIntervals(
        dayKey: String,
        editingBookingId: String,
        bookings: [SimpleBookingDTO],
        dayAvailability: BarberAvailabilityDayData?,
        durationSeconds: TimeInterval,
        timeZone: TimeZone
    ) -> [DateInterval] {
        var committedIntervals: [DateInterval] = []
        for booking in bookings {
            guard booking.id != editingBookingId else { continue }
            guard let scheduled = booking.scheduledTime else { continue }
            guard yyyyMMdd(scheduled, timeZone: timeZone) == dayKey else { continue }
            guard committedStatuses.contains(booking.statusUpper) else { continue }
            committedIntervals.append(DateInterval(start: scheduled, duration: durationSeconds))
        }

        let pendingOnDay = bookings
            .filter { pendingStatuses.contains($0.statusUpper) && $0.id != editingBookingId }
            .compactMap { b -> DateInterval? in
                guard let scheduled = b.scheduledTime else { return nil }
                guard yyyyMMdd(scheduled, timeZone: timeZone) == dayKey else { return nil }
                return DateInterval(start: scheduled, duration: durationSeconds)
            }

        let editingOriginalInterval = editingBookingInterval(
            bookingId: editingBookingId,
            bookings: bookings,
            dayKey: dayKey,
            durationSeconds: durationSeconds,
            timeZone: timeZone
        )

        for slot in dayAvailability?.bookedSlots ?? [] {
            guard let interval = timeIntervalOnDay(
                dayKey: dayKey,
                startHHMM: slot.start,
                endHHMM: slot.end,
                timeZone: timeZone
            ) else { continue }

            if isAvailabilityBlockExclusiveToEditingBooking(
                interval,
                editingOriginalInterval: editingOriginalInterval,
                committedIntervals: committedIntervals,
                pendingOnDay: pendingOnDay
            ) {
                continue
            }

            if !isPendingOnlyAvailabilityBlock(
                interval,
                pendingOnDay: pendingOnDay,
                committedOnDay: committedIntervals
            ) {
                committedIntervals.append(interval)
            }
        }

        return committedIntervals
    }

    private static func editingBookingInterval(
        bookingId: String,
        bookings: [SimpleBookingDTO],
        dayKey: String,
        durationSeconds: TimeInterval,
        timeZone: TimeZone
    ) -> DateInterval? {
        guard let booking = bookings.first(where: { $0.id == bookingId }),
              let scheduled = booking.scheduledTime,
              yyyyMMdd(scheduled, timeZone: timeZone) == dayKey
        else { return nil }
        return DateInterval(start: scheduled, duration: durationSeconds)
    }

    /// Availability blocks that only exist because of the inquiry being rescheduled — including adjacent hours in the same block.
    private static func isAvailabilityBlockExclusiveToEditingBooking(
        _ interval: DateInterval,
        editingOriginalInterval: DateInterval?,
        committedIntervals: [DateInterval],
        pendingOnDay: [DateInterval]
    ) -> Bool {
        guard let editingOriginalInterval, editingOriginalInterval.intersects(interval) else {
            return false
        }
        let blockedByOther = committedIntervals.contains { $0.intersects(interval) }
            || pendingOnDay.contains { $0.intersects(interval) }
        return !blockedByOther
    }

    /// Unaccepted inquiries and other `PENDING` bookings do not block the calendar.
    private static func pendingIntervals(
        onDayKey dayKey: String,
        pending: [BookingRequestRow],
        bookings: [SimpleBookingDTO],
        timeZone: TimeZone,
        durationSeconds: TimeInterval
    ) -> [DateInterval] {
        var intervals: [DateInterval] = []
        for row in pending {
            guard let start = parseRequestedInstant(row) else { continue }
            guard yyyyMMdd(start, timeZone: timeZone) == dayKey else { continue }
            intervals.append(DateInterval(start: start, duration: durationSeconds))
        }
        for booking in bookings {
            guard pendingStatuses.contains(booking.statusUpper) else { continue }
            guard let scheduled = booking.scheduledTime else { continue }
            guard yyyyMMdd(scheduled, timeZone: timeZone) == dayKey else { continue }
            intervals.append(DateInterval(start: scheduled, duration: durationSeconds))
        }
        return intervals
    }

    /// Availability `bookedSlots` merge pending bookings with real blocks; strip pending-only rows for conflict checks.
    private static func isPendingOnlyAvailabilityBlock(
        _ interval: DateInterval,
        pendingOnDay: [DateInterval],
        committedOnDay: [DateInterval]
    ) -> Bool {
        guard pendingOnDay.contains(where: { $0.intersects(interval) }) else { return false }
        guard !committedOnDay.contains(where: { $0.intersects(interval) }) else { return false }
        return true
    }

    // MARK: - Parsing

    static func parseRequestedInstant(_ row: BookingRequestRow) -> Date? {
        ProviderBookingScheduleParsing.requestedInstant(from: row)
    }

    // MARK: - Time helpers

    private static func yyyyMMdd(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func timeLabel(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale.current
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private static func timeIntervalOnDay(
        dayKey: String,
        startHHMM: String,
        endHHMM: String,
        timeZone: TimeZone
    ) -> DateInterval? {
        guard let dayStart = dateFrom(dayKey: dayKey, hourMinute: startHHMM, timeZone: timeZone),
              let dayEnd = dateFrom(dayKey: dayKey, hourMinute: endHHMM, timeZone: timeZone),
              dayEnd > dayStart
        else { return nil }
        return DateInterval(start: dayStart, end: dayEnd)
    }

    private static func dateFrom(dayKey: String, hourMinute: String, timeZone: TimeZone) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let hm = hourMinute.split(separator: ":").compactMap { Int($0) }
        guard hm.count >= 2 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        c.hour = hm[0]
        c.minute = hm[1]
        c.second = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: c)
    }

}
