import SwiftUI

/// Inline daily schedule picker for a pending request (parity with schedule dashboard hour rows).
struct ProviderPendingRequestScheduleEditor: View {
    let barberId: String
    let bookingId: String
    let customerName: String
    let serviceType: String
    @Binding var selectedDateTime: Date
    @Binding var hasConflict: Bool

    @State private var dayAvailability: BarberAvailabilityDayData?
    @State private var dayBookings: [SimpleBookingDTO] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Date")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                DatePicker(
                    "",
                    selection: dayOnlyBinding,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(.providerOlive)
            }
            .padding(10)
            .background(scheduleChromeBackground(cornerRadius: 12, style: .neutral))

            Text(selectedDateTime, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream)

            Text("Tap an available hour for this appointment")
                .font(.caption)
                .foregroundStyle(Color.lavaShellCreamTertiary)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading schedule…")
                        .font(.footnote)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
            } else if let loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
            } else {
                scheduleHourList
            }
        }
        .task(id: dayTaskKey) { await reloadDay() }
        .onChange(of: selectedDateTime) { _, _ in
            refreshConflict()
        }
    }

    private var dayTaskKey: String {
        let day = calendar.startOfDay(for: selectedDateTime)
        return "\(day.timeIntervalSince1970)"
    }

    /// Date-only picker; preserves time-of-day on the draft appointment.
    private var dayOnlyBinding: Binding<Date> {
        Binding(
            get: { calendar.startOfDay(for: selectedDateTime) },
            set: { newDay in
                let time = calendar.dateComponents([.hour, .minute], from: selectedDateTime)
                var merged = calendar.dateComponents([.year, .month, .day], from: newDay)
                merged.hour = time.hour
                merged.minute = time.minute
                merged.second = 0
                if let combined = calendar.date(from: merged) {
                    selectedDateTime = combined
                }
            }
        )
    }

    @ViewBuilder
    private var scheduleHourList: some View {
        let intervals = dayAvailability?.intervals ?? []
        let slots = ProviderScheduleHourlySlot.generate(from: intervals)
        if slots.isEmpty {
            Text("No working hours on this day.")
                .font(.footnote)
                .foregroundStyle(Color.lavaShellCreamSecondary)
        } else {
            VStack(spacing: 8) {
                ForEach(slots, id: \.start) { slot in
                    hourRow(for: slot)
                }
            }
        }
    }

    @ViewBuilder
    private func hourRow(for slot: ProviderScheduleHourlySlot) -> some View {
        let booking = booking(for: slot)
        let isSelected = isDraftHour(slot)
        if let booking, booking.id != bookingId {
            bookedRow(slot: slot, booking: booking)
        } else if isSelected {
            proposedRow(slot: slot)
        } else if isHourBookedByAvailability(slot) {
            blockedRow(slot: slot)
        } else {
            Button {
                selectHour(slot)
            } label: {
                availableRow(slot: slot)
            }
            .buttonStyle(.plain)
        }
    }

    private func proposedRow(slot: ProviderScheduleHourlySlot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(slot.displayRange)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                Spacer()
                Text("PENDING")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.providerOlive.opacity(0.35), in: Capsule())
            }
            Text(customerName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream)
            Text(serviceType)
                .font(.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text("Selected time — tap another open hour to move")
                .font(.caption2)
                .foregroundStyle(Color.lavaShellCreamTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(scheduleChromeBackground(cornerRadius: 14, style: .selected))
    }

    private func bookedRow(slot: ProviderScheduleHourlySlot, booking: SimpleBookingDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(slot.displayRange)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                Spacer()
                Text(booking.statusUpper)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.providerElevatedSurface, in: Capsule())
            }
            Text(booking.consumerDisplayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream)
            Text(booking.serviceDisplayName)
                .font(.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(scheduleChromeBackground(cornerRadius: 14, style: .booked))
    }

    private func availableRow(slot: ProviderScheduleHourlySlot) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.providerOlive)
                .frame(width: 8, height: 8)
            Text(slot.displayRange)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.lavaShellCream)
            Spacer()
            Text("Available")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(scheduleChromeBackground(cornerRadius: 12, style: .neutral))
    }

    private func blockedRow(slot: ProviderScheduleHourlySlot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text(slot.displayRange)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.lavaShellCream)
            Spacer()
            Text("Blocked")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(scheduleChromeBackground(cornerRadius: 12, style: .neutral))
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
                .fill(Color.providerOlive.opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.providerOlive.opacity(0.75), lineWidth: 0.6)
                )
        }
    }

    private enum Chrome {
        case neutral, booked, selected
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
            refreshConflict()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            dayAvailability = nil
            dayBookings = []
        }
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

    private func booking(for slot: ProviderScheduleHourlySlot) -> SimpleBookingDTO? {
        dayBookings.first { b in
            guard let st = b.scheduledTime else { return false }
            let mins = calendar.component(.hour, from: st) * 60 + calendar.component(.minute, from: st)
            return mins >= slot.startMinutes && mins < slot.endMinutes
        }
    }

    private func isDraftHour(_ slot: ProviderScheduleHourlySlot) -> Bool {
        let mins = calendar.component(.hour, from: selectedDateTime) * 60
            + calendar.component(.minute, from: selectedDateTime)
        return mins >= slot.startMinutes && mins < slot.endMinutes
    }

    private func isHourBookedByAvailability(_ slot: ProviderScheduleHourlySlot) -> Bool {
        if isDraftHour(slot) { return false }
        let dayKey = yyyyMMdd(selectedDateTime)
        guard let slotStart = dateFrom(dayKey: dayKey, minutes: slot.startMinutes) else { return false }
        return ProviderRequestTriageEngine.isHourBlockedWhileEditing(
            slotStart: slotStart,
            editingBookingId: bookingId,
            bookings: dayBookings,
            dayAvailability: dayAvailability,
            timeZone: calendar.timeZone
        )
    }

    private func selectHour(_ slot: ProviderScheduleHourlySlot) {
        let dayStart = calendar.startOfDay(for: selectedDateTime)
        guard let hourDate = calendar.date(byAdding: .minute, value: slot.startMinutes, to: dayStart) else { return }
        selectedDateTime = hourDate
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

    private static func minutesFromHHMM(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }

    private static func hhmm(from totalMinutes: Int) -> String {
        String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private static func parseHour(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard let first = parts.first, let h = Int(first), (0 ... 24).contains(h) else { return nil }
        return h
    }

    private static func format12h(minutes: Int) -> String {
        var c = DateComponents()
        c.hour = minutes / 60
        c.minute = minutes % 60
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: c) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
