import SwiftUI

// MARK: - Workload model

enum WorkloadIntensity: Equatable {
    case none
    case low
    case medium
    case high

    init(bookingCount: Int) {
        switch bookingCount {
        case 0:
            self = .none
        case 1 ... 2:
            self = .low
        case 3 ... 5:
            self = .medium
        default:
            self = .high
        }
    }

    var backgroundColor: Color {
        switch self {
        case .none:
            return Color(.secondarySystemGroupedBackground)
        case .low:
            return Color.providerOlive.opacity(0.15)
        case .medium:
            return Color.providerOlive.opacity(0.40)
        case .high:
            return Color.providerOlive.opacity(0.75)
        }
    }

    var dayNumberColor: Color {
        switch self {
        case .high:
            return Color.lavaShellCream
        case .medium:
            return Color.providerOlive
        case .low:
            return Color.lavaShellCream
        case .none:
            return Color.lavaShellCreamSecondary
        }
    }

    var badgeColor: Color {
        switch self {
        case .high:
            return Color.lavaShellCream.opacity(0.92)
        case .medium, .low:
            return Color.providerOlive
        case .none:
            return Color.clear
        }
    }
}

struct DailyWorkload: Identifiable, Equatable {
    let date: Date
    let bookingCount: Int

    var id: Date { date }

    var intensity: WorkloadIntensity {
        WorkloadIntensity(bookingCount: bookingCount)
    }
}

// MARK: - Monthly density grid

struct BarberMonthlyDensityView: View {
    let calendar: Calendar
    let monthAnchor: Date
    let workloads: [DailyWorkload]
    let selectedDate: Date
    var availableHeight: CGFloat?
    let onDayTap: (Date) -> Void

    private let defaultCellHeight: CGFloat = 52
    private let gridSpacing: CGFloat = 6
    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]
    private let gridVerticalPadding: CGFloat = 20

    private var workloadByDay: [Date: DailyWorkload] {
        Dictionary(uniqueKeysWithValues: workloads.map { (calendar.startOfDay(for: $0.date), $0) })
    }

    private var gridDays: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: monthAnchor) ?? 1 ..< 29
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor)) ?? monthAnchor
        let weekday = calendar.component(.weekday, from: first)
        let pad = (weekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: pad)
        for d in range {
            if let date = calendar.date(byAdding: .day, value: d - 1, to: first) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var gridRowCount: Int {
        let itemCount = weekdayLabels.count + gridDays.count
        return max(1, (itemCount + 6) / 7)
    }

    private var cellHeight: CGFloat {
        guard let availableHeight else { return defaultCellHeight }
        let spacingTotal = CGFloat(max(0, gridRowCount - 1)) * gridSpacing
        let usableHeight = availableHeight - gridVerticalPadding - spacingTotal
        return max(34, usableHeight / CGFloat(gridRowCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 7),
                spacing: gridSpacing
            ) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.provider(.caption2, weight: .bold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .frame(height: cellHeight)
                }

                ForEach(gridDays.indices, id: \.self) { index in
                    if let date = gridDays[index] {
                        dayCell(for: date)
                    } else {
                        Color.clear
                            .frame(height: cellHeight)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let dayStart = calendar.startOfDay(for: date)
        let workload = workloadByDay[dayStart] ?? DailyWorkload(date: dayStart, bookingCount: 0)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                onDayTap(date)
            }
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.provider(size: 13, weight: isToday || isSelected ? .bold : .semibold))
                    .foregroundStyle(workload.intensity.dayNumberColor)

                if workload.bookingCount > 0 {
                    Text("\(workload.bookingCount)")
                        .font(.provider(size: 10, weight: .bold))
                        .foregroundStyle(workload.intensity.badgeColor)
                        .monospacedDigit()
                } else {
                    Text(" ")
                        .font(.provider(size: 10))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(workload.intensity.backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isToday ? Color.providerOlive : Color.clear,
                        lineWidth: isToday ? 2 : 0
                    )
            }
            .overlay {
                if isSelected, !isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.lavaShellCream.opacity(0.55), lineWidth: 1.5)
                }
            }
            .scaleEffect(isSelected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isSelected)
    }
}

extension BarberMonthlyDensityView {
    /// Builds one workload entry per day in the visible month grid.
    static func workloads(
        monthAnchor: Date,
        bookings: [SimpleBookingDTO],
        calendar: Calendar
    ) -> [DailyWorkload] {
        let range = calendar.range(of: .day, in: .month, for: monthAnchor) ?? 1 ..< 29
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor)) ?? monthAnchor

        return range.compactMap { dayIndex -> DailyWorkload? in
            guard let date = calendar.date(byAdding: .day, value: dayIndex - 1, to: first) else { return nil }
            let count = bookings.filter { $0.isSameCalendarDay(as: date, calendar: calendar) }.count
            return DailyWorkload(date: calendar.startOfDay(for: date), bookingCount: count)
        }
    }
}
