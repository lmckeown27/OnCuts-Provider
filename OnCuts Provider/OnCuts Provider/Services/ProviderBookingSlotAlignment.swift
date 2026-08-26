import Foundation

/// Aligns operator reschedule times to each day's availability window + booking interval step.
///
/// Backend validates `(startMinutes - intervalStart) % slotInterval == 0` per day. Cross-day moves
/// fail when days use different window starts (e.g. Tue 9:40am vs Wed 9:00am). Snap before PUT.
enum ProviderBookingSlotAlignment {
    static func slotAlignsToInterval(
        startMinutes: Int,
        intervals: [BarberAvailabilityIntervalDTO],
        slotIncrementMinutes: Int
    ) -> Bool {
        guard slotIncrementMinutes > 0 else { return true }
        return intervals.contains { interval in
            let intervalStart = ProviderScheduleHourlySlot.minutesFromHHMM(interval.start)
            let intervalEnd = ProviderScheduleHourlySlot.minutesFromHHMM(interval.end)
            guard startMinutes >= intervalStart, startMinutes < intervalEnd else { return false }
            return (startMinutes - intervalStart) % slotIncrementMinutes == 0
        }
    }

    static func alignedStartMinutes(
        intervals: [BarberAvailabilityIntervalDTO],
        slotIncrementMinutes: Int,
        appointmentDurationMinutes: Int
    ) -> [Int] {
        guard slotIncrementMinutes > 0, appointmentDurationMinutes > 0 else { return [] }

        var seen = Set<Int>()
        var minutes: [Int] = []

        for interval in intervals {
            let intervalStart = ProviderScheduleHourlySlot.minutesFromHHMM(interval.start)
            let intervalEnd = ProviderScheduleHourlySlot.minutesFromHHMM(interval.end)
            var minute = intervalStart
            while minute + appointmentDurationMinutes <= intervalEnd {
                if !seen.contains(minute) {
                    seen.insert(minute)
                    minutes.append(minute)
                }
                minute += slotIncrementMinutes
            }
        }

        return minutes.sorted()
    }

    /// Nearest valid bookable start on the proposed calendar day (ties prefer earlier).
    static func snapToNearestBookableStart(
        proposed: Date,
        intervals: [BarberAvailabilityIntervalDTO],
        slotIntervalMinutes: Int,
        appointmentDurationMinutes: Int,
        calendar: Calendar
    ) -> Date? {
        let proposedMinutes =
            calendar.component(.hour, from: proposed) * 60
            + calendar.component(.minute, from: proposed)

        let candidates = alignedStartMinutes(
            intervals: intervals,
            slotIncrementMinutes: slotIntervalMinutes,
            appointmentDurationMinutes: appointmentDurationMinutes
        )
        guard !candidates.isEmpty else { return nil }

        if candidates.contains(proposedMinutes) {
            let dayStart = calendar.startOfDay(for: proposed)
            return calendar.date(byAdding: .minute, value: proposedMinutes, to: dayStart)
        }

        guard let nearest = candidates.min(by: { lhs, rhs in
            let dl = abs(lhs - proposedMinutes)
            let dr = abs(rhs - proposedMinutes)
            if dl != dr { return dl < dr }
            return lhs < rhs
        }) else {
            return nil
        }

        let dayStart = calendar.startOfDay(for: proposed)
        return calendar.date(byAdding: .minute, value: nearest, to: dayStart)
    }
}

extension BarberAvailabilityDayData {
    static let defaultBookingSlotIntervalMinutes = 15

    var resolvedBookingSlotIntervalMinutes: Int {
        let allowed = [15, 30, 45]
        if let value = bookingSlotIntervalMinutes, allowed.contains(value) {
            return value
        }
        return Self.defaultBookingSlotIntervalMinutes
    }

    var resolvedAppointmentDurationMinutes: Int {
        if let value = appointmentDurationMinutes, value > 0 {
            return value
        }
        return ProviderScheduleHourlySlot.bookableSlotMinutes
    }
}
