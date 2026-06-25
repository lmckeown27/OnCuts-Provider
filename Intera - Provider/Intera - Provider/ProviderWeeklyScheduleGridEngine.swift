import Foundation

// MARK: - Constants

enum ProviderWeeklyScheduleGridMetrics {
    static let slotMinutes = 5
    static let rowHeight: CGFloat = 10
    static let visibleHours = 5
    static let visibleGridHeight: CGFloat = 600
    static let minimumGridHeight: CGFloat = 240
    static let timeGutterWidth: CGFloat = 48
    static let defaultBookingDurationMinutes = 60
    /// Space between the weekday header row and the scrollable time grid.
    static let dayHeaderGridSpacing: CGFloat = 10
    /// Inset above the first time label and grid rows.
    static let timeGutterTopPadding: CGFloat = 8
    /// Default horizontal scroll target — Friday column (Mon = 0).
    static let fridayDayIndex = 4
    static let fridayDayScrollID = "schedule-friday-peek"
    /// Width of Friday visible on first load (~uppercase "F" in the header).
    static let fridayPeekVisibleWidth: CGFloat = 12
    /// Extra space below the last row so the final time label can scroll into view.
    static let bottomScrollPadding: CGFloat = 80
    /// Snap dragged bookings to this minute increment.
    static let moveSnapStepMinutes = 15
}

// MARK: - Types

enum ProviderWeeklyScheduleSlotStatus: Equatable {
    case unavailable
    case open
    case booked
    case blocked
    case google
}

struct ProviderWeeklyScheduleDayColumn: Identifiable, Equatable {
    let date: Date
    let dateKey: String
    let dayKey: WeeklyScheduleDayKey
    let shortLabel: String
    let isToday: Bool
    /// False when the day is disabled or has no availability intervals configured.
    let isDaySelected: Bool

    var id: String { dateKey }
}

struct ProviderWeeklyScheduleGridCell: Equatable {
    let status: ProviderWeeklyScheduleSlotStatus
    let booking: SimpleBookingDTO?
    let blockId: String?
}

struct ProviderWeeklyScheduleGridStats: Equatable {
    var open: Int
    var booked: Int
    var blocked: Int
    var google: Int
    var unavailable: Int
}

struct ProviderWeeklyScheduleGridModel: Equatable {
    let weekDays: [ProviderWeeklyScheduleDayColumn]
    let timeRows: [Int]
    let gridStartMin: Int
    let gridEndMin: Int
    let cells: [[ProviderWeeklyScheduleGridCell]]
    let stats: ProviderWeeklyScheduleGridStats
    let totalContentHeight: CGFloat

    var isEmptyAvailability: Bool { timeRows.isEmpty }
}

struct ProviderWeeklyScheduleGridPositionedBooking: Identifiable, Equatable {
    let booking: SimpleBookingDTO
    let dayIndex: Int
    let startRowIndex: Int
    let rowSpan: Int

    var id: String { booking.id }

    var yOffset: CGFloat {
        CGFloat(startRowIndex) * ProviderWeeklyScheduleGridMetrics.rowHeight
    }

    var height: CGFloat {
        CGFloat(rowSpan) * ProviderWeeklyScheduleGridMetrics.rowHeight
    }

    func startMinute(in model: ProviderWeeklyScheduleGridModel) -> Int {
        model.timeRows[startRowIndex]
    }
}

struct ProviderWeeklyScheduleBusyInterval: Equatable {
    let start: Date
    let end: Date
}

// MARK: - Engine

enum ProviderWeeklyScheduleGridEngine {
    static func weekStartMonday(from anchor: Date, weekOffset: Int, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: anchor)
        let weekday = calendar.component(.weekday, from: start)
        let daysFromMonday = weekday == 1 ? 6 : weekday - 2
        let shifted = calendar.date(byAdding: .day, value: -daysFromMonday + weekOffset * 7, to: start) ?? start
        return calendar.startOfDay(for: shifted)
    }

    static func buildWeekDays(
        weekStartMonday: Date,
        today: Date,
        calendar: Calendar,
        weeklySchedule: WeeklyScheduleDTO
    ) -> [ProviderWeeklyScheduleDayColumn] {
        let mondayKeys: [WeeklyScheduleDayKey] = [
            .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
        ]
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (0 ..< 7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStartMonday) ?? weekStartMonday
            let key = mondayKeys[offset]
            return ProviderWeeklyScheduleDayColumn(
                date: date,
                dateKey: dateKey(for: date, calendar: calendar),
                dayKey: key,
                shortLabel: labels[offset],
                isToday: calendar.isDate(date, inSameDayAs: today),
                isDaySelected: !dayIntervals(for: key, schedule: weeklySchedule).isEmpty
            )
        }
    }

    static func dayIntervals(for dayKey: WeeklyScheduleDayKey, schedule: WeeklyScheduleDTO) -> [ScheduleIntervalDTO] {
        let day = schedule[dayKey]
        guard day.enabled else { return [] }
        return day.intervals.filter { !$0.start.isEmpty && !$0.end.isEmpty }
    }

    static func buildModel(
        weekOffset: Int,
        today: Date,
        calendar: Calendar,
        weeklySchedule: WeeklyScheduleDTO,
        weeklyTimeBlocks: [BarberTimeBlockDTO],
        bookings: [SimpleBookingDTO],
        googleBusyTimes: [ProviderWeeklyScheduleBusyInterval]
    ) -> ProviderWeeklyScheduleGridModel {
        let weekStart = weekStartMonday(from: today, weekOffset: weekOffset, calendar: calendar)
        let weekDays = buildWeekDays(
            weekStartMonday: weekStart,
            today: today,
            calendar: calendar,
            weeklySchedule: weeklySchedule
        )
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

        let weekBookings = bookings.filter { booking in
            guard let scheduled = booking.providerEffectiveScheduledTime else { return false }
            return scheduled >= weekStart && scheduled < weekEnd
        }

        var minStart = 24 * 60
        var maxEnd = 0
        for day in weekDays {
            for interval in dayIntervals(for: day.dayKey, schedule: weeklySchedule) {
                minStart = min(minStart, minutesFromHHMM(interval.start))
                maxEnd = max(maxEnd, minutesFromHHMM(interval.end))
            }
        }

        let slot = ProviderWeeklyScheduleGridMetrics.slotMinutes
        let gridStartMin: Int
        let gridEndMin: Int
        let timeRows: [Int]

        if minStart >= maxEnd {
            gridStartMin = 8 * 60
            gridEndMin = 18 * 60
            timeRows = stride(from: gridStartMin, to: gridEndMin, by: slot).map { $0 }
        } else {
            gridStartMin = (minStart / slot) * slot
            gridEndMin = ((maxEnd + slot - 1) / slot) * slot
            timeRows = stride(from: gridStartMin, to: gridEndMin, by: slot).map { $0 }
        }

        var stats = ProviderWeeklyScheduleGridStats(open: 0, booked: 0, blocked: 0, google: 0, unavailable: 0)
        var cells: [[ProviderWeeklyScheduleGridCell]] = []

        for slotStartMin in timeRows {
            let slotEndMin = slotStartMin + slot
            var row: [ProviderWeeklyScheduleGridCell] = []

            for day in weekDays {
                let intervals = dayIntervals(for: day.dayKey, schedule: weeklySchedule)
                let inAvailability = intervals.contains { interval in
                    let iStart = minutesFromHHMM(interval.start)
                    let iEnd = minutesFromHHMM(interval.end)
                    return slotStartMin >= iStart && slotEndMin <= iEnd
                }

                guard inAvailability else {
                    row.append(.init(status: .unavailable, booking: nil, blockId: nil))
                    stats.unavailable += 1
                    continue
                }

                if let booking = weekBookings.first(where: { apt in
                    guard let scheduled = apt.providerEffectiveScheduledTime else { return false }
                    guard calendar.isDate(scheduled, inSameDayAs: day.date) else { return false }
                    let aptStart = calendar.component(.hour, from: scheduled) * 60 + calendar.component(.minute, from: scheduled)
                    let duration = ProviderWeeklyScheduleGridMetrics.defaultBookingDurationMinutes
                    let aptEnd = aptStart + duration
                    return slotStartMin < aptEnd && slotEndMin > aptStart
                }) {
                    row.append(.init(status: .booked, booking: booking, blockId: nil))
                    stats.booked += 1
                    continue
                }

                if let block = overlappingBlock(
                    blocks: weeklyTimeBlocks,
                    dateKey: day.dateKey,
                    slotStartMin: slotStartMin,
                    slotEndMin: slotEndMin
                ) {
                    row.append(.init(status: .blocked, booking: nil, blockId: block.id))
                    stats.blocked += 1
                    continue
                }

                if overlapsGoogleBusy(
                    day: day.date,
                    slotStartMin: slotStartMin,
                    slotEndMin: slotEndMin,
                    calendar: calendar,
                    busyTimes: googleBusyTimes
                ) {
                    row.append(.init(status: .google, booking: nil, blockId: nil))
                    stats.google += 1
                    continue
                }

                row.append(.init(status: .open, booking: nil, blockId: nil))
                stats.open += 1
            }
            cells.append(row)
        }

        let totalContentHeight = CGFloat(timeRows.count) * ProviderWeeklyScheduleGridMetrics.rowHeight
        return ProviderWeeklyScheduleGridModel(
            weekDays: weekDays,
            timeRows: timeRows,
            gridStartMin: gridStartMin,
            gridEndMin: gridEndMin,
            cells: cells,
            stats: stats,
            totalContentHeight: totalContentHeight
        )
    }

    static func autoScrollTargetMinute(
        weekOffset: Int,
        gridStartMin: Int,
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard weekOffset == 0 else { return gridStartMin }
        let nowMin = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return max(gridStartMin, nowMin - 60)
    }

    // MARK: - Private

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return 0 }
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }

    private static func overlappingBlock(
        blocks: [BarberTimeBlockDTO],
        dateKey: String,
        slotStartMin: Int,
        slotEndMin: Int
    ) -> BarberTimeBlockDTO? {
        blocks.first { block in
            guard normalizedBlockDate(block.blockDate) == dateKey else { return false }
            let blockStart = minutesFromHHMM(block.startTime)
            let blockEnd = minutesFromHHMM(block.endTime)
            return slotStartMin < blockEnd && slotEndMin > blockStart
        }
    }

    private static func normalizedBlockDate(_ raw: String) -> String {
        String(raw.prefix(10))
    }

    private static func overlapsGoogleBusy(
        day: Date,
        slotStartMin: Int,
        slotEndMin: Int,
        calendar: Calendar,
        busyTimes: [ProviderWeeklyScheduleBusyInterval]
    ) -> Bool {
        guard let slotStart = calendar.date(byAdding: .minute, value: slotStartMin, to: calendar.startOfDay(for: day)),
              let slotEnd = calendar.date(byAdding: .minute, value: slotEndMin, to: calendar.startOfDay(for: day))
        else { return false }
        return busyTimes.contains { busy in
            busy.start < slotEnd && busy.end > slotStart
        }
    }

    static func hhmm(from minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func formatTimeLabel(minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        if minute == 0 {
            return "\(displayHour) \(period)"
        }
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    static func positionedBookings(in model: ProviderWeeklyScheduleGridModel) -> [ProviderWeeklyScheduleGridPositionedBooking] {
        guard !model.timeRows.isEmpty else { return [] }
        var positioned: [ProviderWeeklyScheduleGridPositionedBooking] = []

        for dayIndex in 0 ..< model.weekDays.count {
            var rowIndex = 0
            while rowIndex < model.timeRows.count {
                let cell = model.cells[rowIndex][dayIndex]
                guard cell.status == .booked, let booking = cell.booking else {
                    rowIndex += 1
                    continue
                }

                let startRow = rowIndex
                let bookingID = booking.id
                while rowIndex < model.timeRows.count,
                      model.cells[rowIndex][dayIndex].status == .booked,
                      model.cells[rowIndex][dayIndex].booking?.id == bookingID {
                    rowIndex += 1
                }

                positioned.append(
                    ProviderWeeklyScheduleGridPositionedBooking(
                        booking: booking,
                        dayIndex: dayIndex,
                        startRowIndex: startRow,
                        rowSpan: rowIndex - startRow
                    )
                )
            }
        }

        return positioned
    }
}
