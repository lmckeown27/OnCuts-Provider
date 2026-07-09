import SwiftUI

/// One-off **barber time block** editor (parity with web `BlockTimeModal` / Manage availability).
struct ProviderTimeBlockEditorSheet: View {
    let barberId: String?
    let navigationTitle: String
    let confirmButtonTitle: String
    let bookings: [SimpleBookingDTO]
    let calendar: Calendar
    let onSaved: (BarberTimeBlockDTO?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var blocksEntireDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var isSaving = false
    @State private var errorText: String?

    init(
        barberId: String?,
        navigationTitle: String = "Add time block",
        confirmButtonTitle: String = "Save",
        initialDate: Date? = nil,
        initialBlocksEntireDay: Bool? = nil,
        initialStart: Date? = nil,
        initialEnd: Date? = nil,
        bookings: [SimpleBookingDTO] = [],
        calendar: Calendar = .current,
        onSaved: @escaping (BarberTimeBlockDTO?) -> Void
    ) {
        self.barberId = barberId
        self.navigationTitle = navigationTitle
        self.confirmButtonTitle = confirmButtonTitle
        self.bookings = bookings
        self.calendar = calendar
        self.onSaved = onSaved
        let cal = calendar
        let day0 = initialDate.map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: Self.defaultBlockStart(from: .now, calendar: cal))
        let blocksWholeDay = initialBlocksEntireDay ?? (initialStart == nil)
        let defaultStart = initialDate.map {
            Self.blockStart(on: $0, defaultStartFromNow: Self.defaultBlockStart(from: .now, calendar: cal), calendar: cal)
        } ?? Self.defaultBlockStart(from: .now, calendar: cal)
        let rawStart = initialStart ?? defaultStart
        let s = Self.time(on: day0, from: rawStart, calendar: cal)
        let e = Self.endTime(following: s, preferredEnd: initialEnd, calendar: cal)
        _date = State(initialValue: day0)
        _blocksEntireDay = State(initialValue: blocksWholeDay)
        _start = State(initialValue: s)
        _end = State(initialValue: e)
    }

    static let entireDayStartTime = "00:00"
    static let entireDayEndTime = "23:59"

    /// Default block start: one hour after the user opens the editor.
    static func defaultBlockStart(from reference: Date, calendar: Calendar) -> Date {
        calendar.date(bySetting: .second, value: 0, of: calendar.date(byAdding: .hour, value: 1, to: reference) ?? reference)
            ?? reference
    }

    /// Maps the default start onto a selected schedule day when it falls on another calendar day.
    static func blockStart(on day: Date, defaultStartFromNow: Date, calendar: Calendar) -> Date {
        if calendar.isDate(defaultStartFromNow, inSameDayAs: day) {
            return defaultStartFromNow
        }
        return time(on: calendar.startOfDay(for: day), from: defaultStartFromNow, calendar: calendar)
    }

    /// Applies a wall-clock time onto the selected block date.
    static func time(on day: Date, from source: Date, calendar: Calendar) -> Date {
        calendar.date(
            bySettingHour: calendar.component(.hour, from: source),
            minute: calendar.component(.minute, from: source),
            second: 0,
            of: day
        ) ?? source
    }

    /// Ensures the default block is one hour long even if a stale end time is passed in.
    static func endTime(following start: Date, preferredEnd: Date?, calendar: Calendar) -> Date {
        let defaultEnd = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        guard let preferredEnd, preferredEnd > start else { return defaultEnd }
        return preferredEnd
    }

    static func isEntireDayBlock(startTime: String, endTime: String) -> Bool {
        startTime == entireDayStartTime && endTime == entireDayEndTime
    }

    static func entireDayRange(on day: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: day)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: dayStart) ?? dayStart
        return (dayStart, end)
    }

    static func displayTimeRange(startTime: String, endTime: String) -> String {
        if isEntireDayBlock(startTime: startTime, endTime: endTime) {
            return "All day"
        }
        return "\(pretty12h(startTime)) – \(pretty12h(endTime))"
    }

    static func pretty12h(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":")
        guard let hour = parts.first.flatMap({ Int($0) }) else { return hhmm }
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        if minute == 0 {
            return "\(displayHour) \(period)"
        }
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $date, in: Date().addingTimeInterval(-86_400)..., displayedComponents: .date)
                }

                Section {
                    Toggle("Block entire day", isOn: $blocksEntireDay)
                }

                if !blocksEntireDay {
                    Section("Time") {
                        DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            Task { await save() }
                        } label: {
                            Text(isSaving ? "Saving…" : confirmButtonTitle)
                                .font(.provider(.headline, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .padding(.horizontal, 48)
                                .padding(.vertical, 14)
                                .frame(minWidth: 200)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.providerOlive)
                                )
                                .foregroundStyle(Color.lavaShellCream)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || barberId == nil)
                        .opacity(isSaving || barberId == nil ? 0.45 : 1)
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(Color.clear)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.provider(.caption))
                            .foregroundStyle(.red)
                    }
                }
            }
            .providerLavaIntegratedFormSurface()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: date) { _, newDate in
            let day = calendar.startOfDay(for: newDate)
            start = Self.time(on: day, from: start, calendar: calendar)
            end = Self.time(on: day, from: end, calendar: calendar)
            if end <= start {
                end = Self.endTime(following: start, preferredEnd: nil, calendar: calendar)
            }
        }
        .onChange(of: start) { _, newStart in
            if end <= newStart {
                end = Self.endTime(following: newStart, preferredEnd: nil, calendar: calendar)
            }
        }
        .onChange(of: blocksEntireDay) { _, isEntireDay in
            guard !isEntireDay else { return }
            let day = calendar.startOfDay(for: date)
            let defaultStart = Self.blockStart(
                on: day,
                defaultStartFromNow: Self.defaultBlockStart(from: .now, calendar: calendar),
                calendar: calendar
            )
            start = Self.time(on: day, from: defaultStart, calendar: calendar)
            end = Self.endTime(following: start, preferredEnd: nil, calendar: calendar)
        }
    }

    private func save() async {
        guard let barberId else { return }

        let resolvedRange: (start: Date, end: Date)
        if blocksEntireDay {
            resolvedRange = Self.entireDayRange(on: date, calendar: calendar)
        } else {
            resolvedRange = (start, end)
        }

        guard resolvedRange.start < resolvedRange.end else {
            errorText = "End time must be after start time."
            return
        }

        let conflicts = ProviderScheduleBookingConflicts.bookingsOverlappingTimeBlock(
            blockDate: date,
            start: resolvedRange.start,
            end: resolvedRange.end,
            bookings: bookings,
            calendar: calendar
        )
        if !conflicts.isEmpty {
            errorText = ProviderScheduleBookingConflicts.moveBookingsMessage(
                bookings: conflicts,
                calendar: calendar,
                action: blocksEntireDay ? "blocking this day" : "blocking this time"
            )
            return
        }

        isSaving = true
        errorText = nil
        defer { isSaving = false }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        let dateString = f.string(from: date)
        let startString = blocksEntireDay ? Self.entireDayStartTime : Self.hhmmFromDate(resolvedRange.start)
        let endString = blocksEntireDay ? Self.entireDayEndTime : Self.hhmmFromDate(resolvedRange.end)

        do {
            let block = try await ProviderAvailabilityManagementService.createTimeBlock(
                barberId: barberId,
                blockDate: dateString,
                startTime: startString,
                endTime: endString,
                reason: nil
            )
            onSaved(block)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not save time block."
        }
    }

    private static func hhmmFromDate(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }
}
