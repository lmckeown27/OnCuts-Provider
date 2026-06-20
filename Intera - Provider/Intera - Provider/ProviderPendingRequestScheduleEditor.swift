import SwiftUI

/// Inline daily schedule picker for a pending request (parity with schedule dashboard hour rows).
struct ProviderPendingRequestScheduleEditor: View {
    let barberId: String
    let bookingId: String
    let customerName: String
    let serviceType: String
    var bookingStatus: String? = "pending"
    @Binding var selectedDateTime: Date
    @Binding var hasConflict: Bool
    var showsSelectedDayHeadline: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var dayAvailability: BarberAvailabilityDayData?
    @State private var dayBookings: [SimpleBookingDTO] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var allowedDayStarts: Set<Date> = []
    @State private var isLoadingAllowedDays = false
    @State private var visibleMonth = Date()

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    private static let scheduleStepMinutes = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ProviderRescheduleCalendarView(
                    selectedDay: dayOnlyBinding,
                    allowedDayStarts: allowedDayStarts,
                    isLoadingAllowedDays: isLoadingAllowedDays,
                    onVisibleMonthChange: { month in
                        visibleMonth = month
                    }
                )
                .frame(minHeight: 320)
            }
            .padding(10)
            .background(scheduleChromeBackground(cornerRadius: 12, style: .neutral))

            if showsSelectedDayHeadline {
                Text(selectedDateTime, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.provider(.title3, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
            }

            Text("Scroll the wheel to choose an available time")
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamTertiary)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading schedule…")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
            } else if let loadError {
                Text(loadError)
                    .font(.provider(.footnote))
                    .foregroundStyle(.red.opacity(0.9))
            } else {
                timeWheelSection
            }
        }
        .task(id: dayTaskKey) { await reloadDay() }
        .task(id: monthTaskKey) { await reloadAllowedDays(for: visibleMonth) }
        .onAppear {
            visibleMonth = selectedDateTime
        }
        .onChange(of: selectedDateTime) { _, _ in
            refreshConflict()
        }
        .onChange(of: visibleMonth) { _, month in
            Task { await reloadAllowedDays(for: month) }
        }
    }

    private var monthTaskKey: String {
        let month = calendar.dateComponents([.year, .month], from: visibleMonth)
        return "\(month.year ?? 0)-\(month.month ?? 0)"
    }

    /// Writable binding to the selected calendar day (start-of-day); preserves time-of-day.
    private var dayOnlyBinding: Binding<Date> {
        Binding(
            get: { calendar.startOfDay(for: selectedDateTime) },
            set: { newDay in
                let dayStart = calendar.startOfDay(for: newDay)
                guard allowedDayStarts.contains(dayStart) else { return }
                mergeSelectedDay(dayStart)
            }
        )
    }

    private func mergeSelectedDay(_ dayStart: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: selectedDateTime)
        var merged = calendar.dateComponents([.year, .month, .day], from: dayStart)
        merged.hour = time.hour
        merged.minute = time.minute
        merged.second = 0
        if let combined = calendar.date(from: merged) {
            selectedDateTime = combined
        }
    }

    @ViewBuilder
    private var timeWheelSection: some View {
        let times = allSelectableStartTimes
        if times.isEmpty {
            Text("No available times on this day.")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                selectedTimeSummary

                VStack(spacing: 0) {
                    Picker("Available time", selection: wheelMinutesBinding) {
                        ForEach(times, id: \.self) { startMinutes in
                            Text(Self.format12h(minutes: startMinutes))
                                .font(.provider(.body, weight: .medium))
                                .tag(startMinutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(scheduleChromeBackground(cornerRadius: 14, style: .neutral))
                .id(dayTaskKey)
            }
        }
    }

    private var selectedTimeSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedDateTime.formatted(date: .omitted, time: .shortened))
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(onOliveChromePrimary)
                Spacer()
                proposedSlotStatusPill
            }
            Text(customerName)
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(onOliveChromePrimary)
            Text(serviceType)
                .font(.provider(.subheadline))
                .foregroundStyle(onOliveChromeSecondary)
            Text("45-minute appointment")
                .font(.provider(.caption2))
                .foregroundStyle(onOliveChromeTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(scheduleChromeBackground(cornerRadius: 14, style: .selected))
    }

    private var wheelMinutesBinding: Binding<Int> {
        Binding(
            get: {
                let current = selectedMinutesOfDay
                let times = allSelectableStartTimes
                if times.contains(current) { return current }
                return times.first ?? current
            },
            set: { selectStartTime($0) }
        )
    }

    private var allSelectableStartTimes: [Int] {
        let intervals = dayAvailability?.intervals ?? []
        guard !intervals.isEmpty else { return [] }

        var times: [Int] = []
        var seen = Set<Int>()
        for interval in intervals {
            let intervalStart = ProviderScheduleHourlySlot.minutesFromHHMM(interval.start)
            let intervalEnd = ProviderScheduleHourlySlot.minutesFromHHMM(interval.end)
            var minute = intervalStart
            while minute + ProviderScheduleHourlySlot.bookableSlotMinutes <= intervalEnd {
                if !seen.contains(minute), isValidStartTime(minute) {
                    seen.insert(minute)
                    times.append(minute)
                }
                minute += Self.scheduleStepMinutes
            }
        }
        return times.sorted()
    }

    @ViewBuilder
    private func scheduleChromeBackground(cornerRadius: CGFloat, style: Chrome) -> some View {
        switch style {
        case .neutral:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.providerScheduleCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.providerScheduleCardStroke, lineWidth: 0.6)
                )
        case .booked:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.providerOlive.opacity(0.44))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.providerOlive.opacity(0.68), lineWidth: 0.6)
                )
        case .selected:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(selectedChromeFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.providerOlive.opacity(colorScheme == .dark ? 0.75 : 0.85), lineWidth: 0.6)
                )
        }
    }

    private var selectedChromeFill: Color {
        colorScheme == .dark
            ? Color.providerOlive.opacity(0.52)
            : Color.providerOlive.opacity(0.92)
    }

    private var onOliveChromePrimary: Color {
        colorScheme == .dark ? Color.lavaShellCream : Color.providerOnOliveFill
    }

    private var onOliveChromeSecondary: Color {
        colorScheme == .dark ? Color.lavaShellCreamSecondary : Color.providerOnOliveFillSecondary
    }

    private var onOliveChromeTertiary: Color {
        colorScheme == .dark ? Color.lavaShellCreamTertiary : Color.providerOnOliveFillTertiary
    }

    private enum Chrome {
        case neutral, booked, selected
    }

    private var isPendingBooking: Bool {
        ProviderBookingStatusDisplay.normalized(bookingStatus) == "pending"
    }

    private var proposedSlotStatusPill: some View {
        Group {
            if isPendingBooking {
                bookingStatusPill(bookingStatus)
            } else {
                Text("Selected")
                    .font(.provider(.caption2, weight: .bold))
                    .foregroundStyle(onOliveChromePrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.providerOlive.opacity(colorScheme == .dark ? 0.35 : 0.55), in: Capsule())
            }
        }
    }

    private func bookingStatusPill(_ status: String?) -> some View {
        let colors = ProviderBookingStatusDisplay.detailPillColors(for: status)
        return Text(ProviderBookingStatusDisplay.title(for: status))
            .font(.provider(.caption2, weight: .bold))
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colors.background, in: Capsule())
    }

    // MARK: - Data

    private func reloadDay() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let availability = ProviderAvailabilityService.getDayAvailability(
                barberId: barberId,
                date: selectedDateTime
            )
            async let bookings = ProviderBookingsService.listBookings(role: "barber")
            let (day, all) = try await (availability, bookings)
            dayAvailability = day
            let dayStart = calendar.startOfDay(for: selectedDateTime)
            dayBookings = all.filter { booking in
                guard let st = booking.scheduledTime else { return false }
                return calendar.isDate(st, inSameDayAs: dayStart)
            }
            snapToSelectableTimeIfNeeded()
            refreshConflict()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            dayAvailability = nil
            dayBookings = []
        }
    }

    private func reloadAllowedDays(for month: Date) async {
        isLoadingAllowedDays = true
        defer { isLoadingAllowedDays = false }

        let today = calendar.startOfDay(for: Date())
        let days = daysInMonth(containing: month).filter { $0 >= today }
        var openDays = Set<Date>()

        for day in days {
            if let availability = try? await ProviderAvailabilityService.getDayAvailability(
                barberId: barberId,
                date: day
            ), !(availability.intervals ?? []).isEmpty {
                openDays.insert(calendar.startOfDay(for: day))
            }
        }

        allowedDayStarts = openDays

        let selectedDay = calendar.startOfDay(for: selectedDateTime)
        if !openDays.isEmpty, !openDays.contains(selectedDay) {
            if let nearest = openDays.filter({ $0 >= today }).sorted().first {
                mergeSelectedDay(nearest)
            }
        }
    }

    private func daysInMonth(containing month: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: monthInterval.start)
        else { return [] }

        return dayRange.compactMap { day -> Date? in
            var components = calendar.dateComponents([.year, .month], from: monthInterval.start)
            components.day = day
            return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
        }
    }

    private func snapToSelectableTimeIfNeeded() {
        let times = allSelectableStartTimes
        guard !times.isEmpty else { return }
        if times.contains(selectedMinutesOfDay) { return }
        if let first = times.first {
            selectStartTime(first)
        }
    }

    private var dayTaskKey: String {
        let day = calendar.startOfDay(for: selectedDateTime)
        return "\(day.timeIntervalSince1970)"
    }

    private func refreshConflict() {
        hasConflict = ProviderRequestTriageEngine.hasCommittedConflict(
            proposedStart: selectedDateTime,
            bookingId: bookingId,
            bookings: dayBookings,
            dayAvailability: dayAvailability,
            timeZone: .current
        )
    }

    private var selectedMinutesOfDay: Int {
        calendar.component(.hour, from: selectedDateTime) * 60
            + calendar.component(.minute, from: selectedDateTime)
    }

    private func isValidStartTime(_ startMinutes: Int) -> Bool {
        guard isWithinWorkingIntervals(startMinutes: startMinutes) else { return false }
        guard isAPISlotWindowAvailable(startMinutes: startMinutes) else { return false }
        guard booking(atStartMinutes: startMinutes) == nil else { return false }

        let dayStart = calendar.startOfDay(for: selectedDateTime)
        guard let startDate = calendar.date(byAdding: .minute, value: startMinutes, to: dayStart) else {
            return false
        }

        return !ProviderRequestTriageEngine.hasCommittedConflict(
            proposedStart: startDate,
            bookingId: bookingId,
            bookings: dayBookings,
            dayAvailability: dayAvailability,
            timeZone: calendar.timeZone
        )
    }

    private func isWithinWorkingIntervals(startMinutes: Int) -> Bool {
        let appointmentMinutes = ProviderScheduleHourlySlot.bookableSlotMinutes
        let intervals = dayAvailability?.intervals ?? []
        return intervals.contains { interval in
            let intervalStart = ProviderScheduleHourlySlot.minutesFromHHMM(interval.start)
            let intervalEnd = ProviderScheduleHourlySlot.minutesFromHHMM(interval.end)
            return startMinutes >= intervalStart
                && startMinutes + appointmentMinutes <= intervalEnd
        }
    }

    private func isAPISlotWindowAvailable(startMinutes: Int) -> Bool {
        guard let slots = dayAvailability?.slots, !slots.isEmpty else { return true }

        let appointmentMinutes = ProviderScheduleHourlySlot.bookableSlotMinutes
        for offset in stride(from: 0, to: appointmentMinutes, by: Self.scheduleStepMinutes) {
            let minuteMark = startMinutes + offset
            let timeKey = ProviderScheduleHourlySlot.hhmm(from: minuteMark)
            guard let slot = slots.first(where: { $0.time == timeKey }) else { return false }
            guard slot.available else { return false }
        }
        return true
    }

    private func booking(atStartMinutes startMinutes: Int) -> SimpleBookingDTO? {
        let dayStart = calendar.startOfDay(for: selectedDateTime)
        guard let startDate = calendar.date(byAdding: .minute, value: startMinutes, to: dayStart) else {
            return nil
        }
        let duration = TimeInterval(ProviderScheduleHourlySlot.bookableSlotMinutes * 60)
        let candidate = DateInterval(start: startDate, duration: duration)

        return dayBookings.first { booking in
            guard booking.id != bookingId, let scheduled = booking.scheduledTime else { return false }
            let existing = DateInterval(start: scheduled, duration: duration)
            return candidate.intersects(existing)
        }
    }

    private func selectStartTime(_ startMinutes: Int) {
        let dayStart = calendar.startOfDay(for: selectedDateTime)
        guard let date = calendar.date(byAdding: .minute, value: startMinutes, to: dayStart) else { return }
        selectedDateTime = date
    }

    private static func format12h(minutes: Int) -> String {
        ProviderScheduleHourlySlot.format12h(minutes: minutes)
    }

    private func yyyyMMdd(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func dateFrom(dayKey: String, minutes: Int) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        c.hour = minutes / 60
        c.minute = minutes % 60
        c.second = 0
        return calendar.date(from: c)
    }

    private func timeIntervalOnDay(dayKey: String, startHHMM: String, endHHMM: String) -> DateInterval? {
        guard let start = dateFrom(dayKey: dayKey, hhmm: startHHMM),
              let end = dateFrom(dayKey: dayKey, hhmm: endHHMM),
              end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func dateFrom(dayKey: String, hhmm: String) -> Date? {
        let hm = hhmm.split(separator: ":").compactMap { Int($0) }
        guard hm.count >= 2 else { return nil }
        let minutes = hm[0] * 60 + hm[1]
        return dateFrom(dayKey: dayKey, minutes: minutes)
    }
}

// MARK: - Hourly slots (shared with schedule dashboard logic)

struct ProviderScheduleHourlySlot: Hashable {
    let startHour: Int
    let startMinutes: Int
    let endMinutes: Int
    let start: String
    let end: String

    /// CampusCuts bookable appointment length used on the provider schedule.
    static let bookableSlotMinutes = 45

    var displayRange: String {
        "\(Self.format12h(minutes: startMinutes)) – \(Self.format12h(minutes: endMinutes))"
    }

    static func generate(from intervals: [BarberAvailabilityIntervalDTO]) -> [ProviderScheduleHourlySlot] {
        var seen = Set<Int>()
        var slots: [ProviderScheduleHourlySlot] = []
        for interval in intervals {
            guard let startHour = parseHour(interval.start),
                  let endHour = parseHour(interval.end),
                  endHour > startHour
            else { continue }
            for h in startHour ..< endHour where !seen.contains(h) {
                seen.insert(h)
                slots.append(
                    ProviderScheduleHourlySlot(
                        startHour: h,
                        startMinutes: h * 60,
                        endMinutes: (h + 1) * 60,
                        start: String(format: "%02d:00", h),
                        end: String(format: "%02d:00", h + 1)
                    )
                )
            }
        }
        return slots.sorted { $0.startHour < $1.startHour }
    }

    /// Fixed-length bookable windows (e.g. 45 min) aligned to the schedule grid.
    static func generateBookableSlots(
        from intervals: [BarberAvailabilityIntervalDTO],
        slotMinutes: Int = bookableSlotMinutes
    ) -> [ProviderScheduleHourlySlot] {
        guard slotMinutes > 0 else { return [] }
        var seen = Set<Int>()
        var slots: [ProviderScheduleHourlySlot] = []
        for interval in intervals {
            let intervalStart = minutesFromHHMM(interval.start)
            let intervalEnd = minutesFromHHMM(interval.end)
            guard intervalEnd > intervalStart else { continue }

            var slotStart = (intervalStart / slotMinutes) * slotMinutes
            if slotStart < intervalStart { slotStart += slotMinutes }

            while slotStart + slotMinutes <= intervalEnd {
                if !seen.contains(slotStart) {
                    seen.insert(slotStart)
                    let slotEnd = slotStart + slotMinutes
                    slots.append(
                        ProviderScheduleHourlySlot(
                            startHour: slotStart / 60,
                            startMinutes: slotStart,
                            endMinutes: slotEnd,
                            start: hhmm(from: slotStart),
                            end: hhmm(from: slotEnd)
                        )
                    )
                }
                slotStart += slotMinutes
            }
        }
        return slots.sorted { $0.startMinutes < $1.startMinutes }
    }

    static func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }

    static func hhmm(from totalMinutes: Int) -> String {
        String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private static func parseHour(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard let first = parts.first, let h = Int(first), (0 ... 24).contains(h) else { return nil }
        return h
    }

    static func format12h(minutes: Int) -> String {
        var c = DateComponents()
        c.hour = minutes / 60
        c.minute = minutes % 60
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: c) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
