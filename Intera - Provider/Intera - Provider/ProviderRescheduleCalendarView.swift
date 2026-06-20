import SwiftUI

/// Month grid for reschedule flows — only days in `allowedDayStarts` can be selected.
struct ProviderRescheduleCalendarView: View {
    @Binding var selectedDay: Date
    var allowedDayStarts: Set<Date>
    var isLoadingAllowedDays: Bool
    var onVisibleMonthChange: (Date) -> Void

    @State private var displayedMonth: Date

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private let weekdayColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(
        selectedDay: Binding<Date>,
        allowedDayStarts: Set<Date>,
        isLoadingAllowedDays: Bool,
        onVisibleMonthChange: @escaping (Date) -> Void
    ) {
        self._selectedDay = selectedDay
        self.allowedDayStarts = allowedDayStarts
        self.isLoadingAllowedDays = isLoadingAllowedDays
        self.onVisibleMonthChange = onVisibleMonthChange
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: cal.dateComponents([.year, .month], from: selectedDay.wrappedValue))
            ?? selectedDay.wrappedValue
        _displayedMonth = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 16) {
            monthNavigationHeader
            weekdayHeaderRow

            LazyVGrid(columns: weekdayColumns, spacing: 10) {
                ForEach(gridDates, id: \.self) { day in
                    calendarDayCell(for: day)
                }
            }
        }
        .onAppear {
            displayedMonth = startOfMonth(selectedDay)
            onVisibleMonthChange(displayedMonth)
        }
        .onChange(of: selectedDay) { _, newValue in
            displayedMonth = startOfMonth(newValue)
        }
    }

    private var monthNavigationHeader: some View {
        HStack {
            Button {
                guard canGoPreviousMonth else { return }
                displayedMonth = addMonths(-1, to: displayedMonth)
                onVisibleMonthChange(displayedMonth)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.provider(.body, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")
            .disabled(!canGoPreviousMonth || isLoadingAllowedDays)
            .opacity(canGoPreviousMonth ? 1 : 0.35)

            Spacer(minLength: 8)

            Text(Self.monthYearFormatter.string(from: displayedMonth))
                .font(.provider(.headline, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                guard canGoNextMonth else { return }
                displayedMonth = addMonths(1, to: displayedMonth)
                onVisibleMonthChange(displayedMonth)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.provider(.body, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
            .disabled(isLoadingAllowedDays)
            .opacity(canGoNextMonth ? 1 : 0.35)
        }
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(orderedWeekdayInitials.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(.provider(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var orderedWeekdayInitials: [String] {
        let syms = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return (0 ..< 7).map { syms[($0 + offset) % 7] }
    }

    private var gridDates: [Date] {
        let first = startOfMonth(displayedMonth)
        guard let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }

        let padStart = weekdayColumnIndex(for: first)
        var cells: [Date] = []

        for i in 0 ..< padStart {
            if let d = calendar.date(byAdding: .day, value: i - padStart, to: first) {
                cells.append(d)
            }
        }
        for d in 0 ..< daysInMonth {
            if let date = calendar.date(byAdding: .day, value: d, to: first) {
                cells.append(date)
            }
        }
        var next = calendar.date(byAdding: .day, value: daysInMonth, to: first) ?? first
        while cells.count % 7 != 0 {
            cells.append(next)
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }
        return cells
    }

    @ViewBuilder
    private func calendarDayCell(for day: Date) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let todayStart = calendar.startOfDay(for: Date())
        let inFutureOrToday = dayStart >= todayStart
        let passesAvailability = allowedDayStarts.contains(dayStart)
        let selectable = !isLoadingAllowedDays && inFutureOrToday && passesAvailability
        let inDisplayedMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let selected = calendar.isDate(day, inSameDayAs: selectedDay)

        let labelOpacity: Double = {
            if isLoadingAllowedDays { return 0.35 }
            if !inFutureOrToday { return 0.22 }
            if !passesAvailability { return 0.22 }
            if !inDisplayedMonth { return 0.38 }
            return 1
        }()

        Button {
            guard selectable else { return }
            selectedDay = dayStart
        } label: {
            ZStack {
                Circle()
                    .fill(selected ? Color.providerOlive : Color.clear)

                Text("\(calendar.component(.day, from: day))")
                    .font(.provider(.body, weight: .semibold))
                    .foregroundStyle(selected ? Color.lavaShellCream : Color.lavaShellCream)
                    .opacity(labelOpacity)
            }
            .frame(width: 40, height: 40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityAddTraits(selectable ? [] : .isStaticText)
    }

    private var canGoPreviousMonth: Bool {
        startOfMonth(displayedMonth) > startOfMonth(Date())
    }

    private var canGoNextMonth: Bool {
        true
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func addMonths(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: date) ?? date
    }

    private func weekdayColumnIndex(for date: Date) -> Int {
        let wd = calendar.component(.weekday, from: date)
        let first = calendar.firstWeekday
        return (wd - first + 7) % 7
    }
}
