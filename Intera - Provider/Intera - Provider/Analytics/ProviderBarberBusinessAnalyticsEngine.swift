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
            guard let date = booking.scheduledTime ?? booking.paidAt else { return period == .all }
            guard let interval else { return true }
            return interval.contains(date)
        }

        let grossVolumeCents = inPeriod.reduce(0) { $0 + revenueCents(for: $1) }
        let paidInPeriod = inPeriod.filter { paidStatuses.contains($0.statusUpper) }
        let cardVolumeCents = paidInPeriod.reduce(0) { $0 + revenueCents(for: $1) }
        let platformCutCents = Int((Double(grossVolumeCents) * platformFeeRate).rounded())
        let tipsCents = inPeriod.reduce(0) { $0 + max(0, $1.tipAmountCents ?? 0) }
        let takeHomeCents = max(0, grossVolumeCents - platformCutCents + tipsCents)

        let pendingCount = inPeriod.filter { pendingStatuses.contains($0.statusUpper) }.count
        let upcomingCount = inPeriod.filter { upcomingStatuses.contains($0.statusUpper) }.count
        let completedCount = inPeriod.filter { completedStatuses.contains($0.statusUpper) }.count
        let completionDenominator = max(1, pendingCount + upcomingCount + completedCount)
        let completionRate = Double(completedCount) / Double(completionDenominator)

        let uniqueClients = Set(
            inPeriod.compactMap(\.consumerId).filter { !$0.isEmpty }
        ).count

        return BarberBusinessAnalyticsSnapshot(
            period: period,
            periodLabel: period.summaryLabel,
            grossVolumeCents: grossVolumeCents,
            bookingCount: inPeriod.count,
            uniqueClientCount: uniqueClients,
            chartPoints: chartPoints(from: inPeriod, period: period, calendar: calendar, now: now),
            cardVolumeCents: cardVolumeCents,
            cardCompletionCount: paidInPeriod.count,
            cashVolumeCents: 0,
            cashCompletionCount: 0,
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
                ($0.scheduledTime ?? .distantPast) > ($1.scheduledTime ?? .distantPast)
            }
            let volume = bucket.bookings.reduce(0) { $0 + revenueCents(for: $1) }
            return BarberClient(
                id: id,
                name: bucket.name,
                email: nil,
                profileImageURL: bucket.avatar,
                bookingCount: bucket.bookings.count,
                lifetimeVolumeCents: volume,
                lastBookingDate: sorted.first?.scheduledTime ?? sorted.first?.paidAt
            )
        }
        .sorted {
            ($0.lastBookingDate ?? .distantPast) > ($1.lastBookingDate ?? .distantPast)
        }
    }

    static func enrichClients(_ clients: [BarberClient], conversations: [ConversationRow]) -> [BarberClient] {
        let byUserId: [String: ConversationOtherUser] = Dictionary(
            uniqueKeysWithValues: conversations.compactMap { row in
                guard let user = row.otherUser, let id = user.id else { return nil }
                return (id, user)
            }
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
            guard let date = booking.scheduledTime ?? booking.paidAt else { continue }
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
}
