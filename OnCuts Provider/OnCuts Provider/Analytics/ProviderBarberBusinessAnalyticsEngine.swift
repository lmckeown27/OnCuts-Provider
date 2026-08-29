import Foundation

/// Client-side intersect layer: folds bookings + payout summary into dashboard snapshots.
enum ProviderBarberBusinessAnalyticsEngine {
    private static let platformFeeRate = 0.15
    private static let paidStatuses: Set<String> = ["PAID", "COMPLETED"]
    private static let pendingStatuses: Set<String> = ["PENDING"]
    private static let upcomingStatuses: Set<String> = [
        "ACCEPTED", "CONFIRMED", "SCHEDULED", "IN_PROGRESS",
    ]
    private static let completedStatuses: Set<String> = ["COMPLETED", "PAID"]

    static func buildSnapshot(
        bookings: [SimpleBookingDTO],
        period: BarberAnalyticsPeriod,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> BarberBusinessAnalyticsSnapshot {
        let interval = periodInterval(period, calendar: calendar, now: now)
        let inPeriod = bookings.filter { booking in
            guard let date = analyticsAnchorDate(for: booking) else { return period == .all }
            guard let interval else { return true }
            return interval.contains(date)
        }

        // Payment stats use COMPLETED + PAID card bookings (cash is excluded).
        let paidInPeriod = inPeriod.filter(\.isPaidForRevenueAnalytics)
        let grossVolumeCents = paidInPeriod.reduce(0) { $0 + revenueCents(for: $1) }

        var paymentVolumeCents = 0
        var paymentCompletionCount = 0
        for booking in paidInPeriod where !booking.isCashPayment {
            // Explicit card *or* null method (legacy Stripe).
            paymentVolumeCents += revenueCents(for: booking)
            paymentCompletionCount += 1
        }

        let platformCutCents = Int((Double(paymentVolumeCents) * platformFeeRate).rounded())
        let takeHomeCents = max(0, paymentVolumeCents - platformCutCents)
        let tipsCents = paidInPeriod.reduce(0) { $0 + max(0, $1.tipAmountCents ?? 0) }

        let pendingCount = inPeriod.filter { pendingStatuses.contains($0.statusUpper) }.count
        let upcomingCount = inPeriod.filter { upcomingStatuses.contains($0.statusUpper) }.count
        let completedCount = inPeriod.filter { completedStatuses.contains($0.statusUpper) }.count
        let completionDenominator = max(1, pendingCount + upcomingCount + completedCount)
        let completionRate = Double(completedCount) / Double(completionDenominator)

        let uniqueClients = Set(
            paidInPeriod.compactMap(\.consumerId).filter { !$0.isEmpty }
        ).count

        return BarberBusinessAnalyticsSnapshot(
            period: period,
            periodLabel: period.summaryLabel,
            grossVolumeCents: grossVolumeCents,
            bookingCount: paidInPeriod.count,
            uniqueClientCount: uniqueClients,
            chartPoints: chartPoints(from: paidInPeriod, period: period, calendar: calendar, now: now),
            paymentVolumeCents: paymentVolumeCents,
            paymentCompletionCount: paymentCompletionCount,
            platformCutCents: platformCutCents,
            takeHomeCents: takeHomeCents,
            tipTotalCents: tipsCents,
            pendingCount: pendingCount,
            upcomingCount: upcomingCount,
            completedCount: completedCount,
            completionRate: completionRate,
            estimatedNetTakeHomeCents: takeHomeCents
        )
    }

    static func buildClients(from bookings: [SimpleBookingDTO]) -> [BarberClient] {
        var grouped: [String: (bookings: [SimpleBookingDTO], name: String, avatar: URL?)] = [:]

        for booking in bookings {
            let key = booking.consumerId?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key, !key.isEmpty else { continue }

            var bucket = grouped[key] ?? (bookings: [], name: booking.consumerDisplayName, avatar: avatarURL(from: booking))
            bucket.bookings.append(booking)
            if bucket.avatar == nil {
                bucket.avatar = avatarURL(from: booking)
            }
            grouped[key] = bucket
        }

        return grouped.map { id, bucket in
            let sorted = bucket.bookings.sorted {
                let left = $0.paidAt ?? $0.scheduledTime ?? .distantPast
                let right = $1.paidAt ?? $1.scheduledTime ?? .distantPast
                return left > right
            }
            let volume = bucket.bookings
                .filter(\.isPaidForRevenueAnalytics)
                .reduce(0) { $0 + revenueCents(for: $1) }
            return BarberClient(
                id: id,
                name: bucket.name,
                email: nil,
                profileImageURL: bucket.avatar,
                bookingCount: bucket.bookings.count,
                lifetimeVolumeCents: volume,
                lastBookingDate: sorted.first?.paidAt ?? sorted.first?.scheduledTime
            )
        }
        .sorted {
            ($0.lastBookingDate ?? .distantPast) > ($1.lastBookingDate ?? .distantPast)
        }
    }

    static func normalizedMetricPoints(
        from bookings: [SimpleBookingDTO],
        timeline: BarberPerformanceTimeline,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [BarberPerformanceMetricPoint] {
        let paid = paidBookings(in: timeline, from: bookings, calendar: calendar, now: now)
        let bucketDates = chartBucketDates(for: timeline, calendar: calendar, now: now)
        var totalsByBucket: [Date: (revenueDollars: Double, bookings: Int)] = [:]

        for booking in paid {
            guard let anchor = analyticsAnchorDate(for: booking) else { continue }
            let bucket = bucketStart(for: anchor, timeline: timeline, calendar: calendar)
            let existing = totalsByBucket[bucket] ?? (0, 0)
            totalsByBucket[bucket] = (
                revenueDollars: existing.revenueDollars + Double(revenueCents(for: booking)) / 100.0,
                bookings: existing.bookings + 1
            )
        }

        let dayFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return formatter
        }()

        return bucketDates.enumerated().map { index, bucket in
            let totals = totalsByBucket[bucket] ?? (0, 0)
            return BarberPerformanceMetricPoint(
                id: dayFormatter.string(from: bucket),
                bucketIndex: index,
                date: bucket,
                revenueDollars: totals.revenueDollars,
                bookings: totals.bookings
            )
        }
    }

    /// Paid bookings whose settle/schedule date falls in the chart window for the selected timeline.
    static func paidBookings(
        in timeline: BarberPerformanceTimeline,
        from bookings: [SimpleBookingDTO],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [SimpleBookingDTO] {
        let bucketDates = Set(chartBucketDates(for: timeline, calendar: calendar, now: now))
        return paidBookings(from: bookings).filter { booking in
            guard let anchor = analyticsAnchorDate(for: booking) else { return false }
            let bucket = bucketStart(for: anchor, timeline: timeline, calendar: calendar)
            return bucketDates.contains(bucket)
        }
    }

    /// Backward-compatible alias used by the analytics shell snapshot builder.
    static func bookings(
        in timeline: BarberPerformanceTimeline,
        from bookings: [SimpleBookingDTO],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [SimpleBookingDTO] {
        paidBookings(in: timeline, from: bookings, calendar: calendar, now: now)
    }

    /// All settled bookings used for all-time payment / admin-parity revenue totals.
    static func paidBookings(from bookings: [SimpleBookingDTO]) -> [SimpleBookingDTO] {
        bookings.filter(\.isPaidForRevenueAnalytics)
    }

    static func bookings(forClientId clientId: String, from bookings: [SimpleBookingDTO]) -> [SimpleBookingDTO] {
        let trimmedId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return [] }

        return bookings
            .filter { $0.consumerId?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedId }
            .sorted { lhs, rhs in
                let left = lhs.paidAt ?? lhs.scheduledTime ?? .distantPast
                let right = rhs.paidAt ?? rhs.scheduledTime ?? .distantPast
                return left > right
            }
    }

    static func enrichClients(_ clients: [BarberClient], conversations: [ConversationRow]) -> [BarberClient] {
        // Conversations can repeat the same other-user id (e.g. multiple threads); uniquing avoids a fatal Dictionary crash.
        let byUserId: [String: ConversationOtherUser] = Dictionary(
            conversations.compactMap { row -> (String, ConversationOtherUser)? in
                guard let user = row.otherUser, let id = user.id else { return nil }
                return (id, user)
            },
            uniquingKeysWith: { _, latest in latest }
        )

        return clients.map { client in
            guard let other = byUserId[client.id] else { return client }
            let name = other.displayName
                ?? [other.firstName, other.lastName].compactMap { $0 }.joined(separator: " ")
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let avatar = profileURL(from: other.profilePicture) ?? client.profileImageURL
            return BarberClient(
                id: client.id,
                name: trimmedName.isEmpty ? client.name : trimmedName,
                email: client.email,
                profileImageURL: avatar,
                bookingCount: client.bookingCount,
                lifetimeVolumeCents: client.lifetimeVolumeCents,
                lastBookingDate: client.lastBookingDate
            )
        }
    }

    // MARK: - Private

    private static func revenueCents(for booking: SimpleBookingDTO) -> Int {
        if let paid = booking.totalPaidCents, paid > 0 { return paid }
        if let price = booking.priceUsdCents, price > 0 { return price }
        return 0
    }

    /// Prefer `paidAt` for revenue bucketing (admin charts), fall back to scheduled time.
    private static func analyticsAnchorDate(for booking: SimpleBookingDTO) -> Date? {
        booking.paidAt ?? booking.scheduledTime
    }

    private static func avatarURL(from booking: SimpleBookingDTO) -> URL? {
        guard let raw = booking.consumer?.avatar?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private static func profileURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private static func periodInterval(
        _ period: BarberAnalyticsPeriod,
        calendar: Calendar,
        now: Date
    ) -> DateInterval? {
        let startOfToday = calendar.startOfDay(for: now)
        switch period {
        case .oneWeek:
            guard let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) else { return nil }
            return DateInterval(start: start, end: now)
        case .fourWeeks:
            guard let start = calendar.date(byAdding: .day, value: -27, to: startOfToday) else { return nil }
            return DateInterval(start: start, end: now)
        case .mtd:
            let comps = calendar.dateComponents([.year, .month], from: now)
            guard let start = calendar.date(from: comps) else { return nil }
            return DateInterval(start: start, end: now)
        case .qtd:
            let month = calendar.component(.month, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = quarterStartMonth
            comps.day = 1
            guard let start = calendar.date(from: comps) else { return nil }
            return DateInterval(start: start, end: now)
        case .ytd:
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = 1
            comps.day = 1
            guard let start = calendar.date(from: comps) else { return nil }
            return DateInterval(start: start, end: now)
        case .oneYear:
            guard let start = calendar.date(byAdding: .day, value: -364, to: startOfToday) else { return nil }
            return DateInterval(start: start, end: now)
        case .all:
            return nil
        }
    }

    private static func chartPoints(
        from bookings: [SimpleBookingDTO],
        period: BarberAnalyticsPeriod,
        calendar: Calendar,
        now: Date
    ) -> [BarberAnalyticsChartPoint] {
        let bucketUnit: Calendar.Component = {
            switch period {
            case .oneWeek, .fourWeeks, .mtd: return .day
            case .qtd, .ytd, .oneYear, .all: return .weekOfYear
            }
        }()

        var buckets: [Date: (volume: Int, count: Int)] = [:]
        for booking in bookings {
            guard let date = analyticsAnchorDate(for: booking) else { continue }
            let bucketStart: Date
            if bucketUnit == .day {
                bucketStart = calendar.startOfDay(for: date)
            } else {
                bucketStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
            }
            var entry = buckets[bucketStart] ?? (volume: 0, count: 0)
            entry.volume += revenueCents(for: booking)
            entry.count += 1
            buckets[bucketStart] = entry
        }

        return buckets.keys.sorted().map { date in
            let entry = buckets[date] ?? (volume: 0, count: 0)
            return BarberAnalyticsChartPoint(
                id: ISO8601DateFormatter().string(from: date),
                date: date,
                volumeCents: entry.volume,
                bookingCount: entry.count
            )
        }
    }

    private static func chartBucketDates(
        for timeline: BarberPerformanceTimeline,
        calendar: Calendar,
        now: Date
    ) -> [Date] {
        let count = timeline.chartBucketCount
        let anchor = calendar.startOfDay(for: now)

        switch timeline {
        case .daily:
            return (0..<count).compactMap { offset in
                calendar.date(byAdding: .day, value: -(count - 1 - offset), to: anchor)
            }

        case .weekly:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
            return (0..<count).compactMap { offset in
                calendar.date(byAdding: .weekOfYear, value: -(count - 1 - offset), to: weekStart)
            }

        case .monthly:
            let monthStart = calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor
            return (0..<count).compactMap { offset in
                calendar.date(byAdding: .month, value: -(count - 1 - offset), to: monthStart)
            }
        }
    }

    private static func bucketStart(
        for date: Date,
        timeline: BarberPerformanceTimeline,
        calendar: Calendar
    ) -> Date {
        switch timeline {
        case .daily:
            return calendar.startOfDay(for: date)
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
                ?? calendar.startOfDay(for: date)
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)?.start
                ?? calendar.startOfDay(for: date)
        }
    }
}
