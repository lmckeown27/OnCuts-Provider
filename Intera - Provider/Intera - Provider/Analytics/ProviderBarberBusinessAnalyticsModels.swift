import Foundation

// MARK: - Timeline filters

enum BarberAnalyticsPeriod: String, CaseIterable, Identifiable {
    case oneWeek = "1W"
    case fourWeeks = "4W"
    case mtd = "MTD"
    case qtd = "QTD"
    case ytd = "YTD"
    case oneYear = "1Y"
    case all = "All"

    var id: String { rawValue }

    var summaryLabel: String { rawValue }
}

// MARK: - Performance timeline chart (parity with Admin dashboard)

enum BarberPerformanceTimeline: String, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }

    var segmentTitle: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var helperSubtitle: String {
        switch self {
        case .daily: return "Each day for the past week."
        case .weekly: return "Each week for the past month."
        case .monthly: return "Each month for the past six months."
        }
    }

    var chartBucketCount: Int {
        switch self {
        case .daily: return 7
        case .weekly: return 4
        case .monthly: return 6
        }
    }

    var bucketUnitSingular: String {
        switch self {
        case .daily: return "day"
        case .weekly: return "week"
        case .monthly: return "month"
        }
    }

    var bestBucketLabel: String { "Best \(bucketUnitSingular)" }
    var primaryMetricTitle: String { "Average per \(bucketUnitSingular)" }
}

struct BarberPerformanceMetricPoint: Identifiable, Hashable {
    let id: String
    let bucketIndex: Int
    let date: Date
    let revenueDollars: Double
    let bookings: Int
}

// MARK: - Aggregated dashboard snapshot

struct BarberBusinessAnalyticsSnapshot: Hashable {
    let period: BarberAnalyticsPeriod
    let periodLabel: String
    let grossVolumeCents: Int
    let bookingCount: Int
    let uniqueClientCount: Int
    let chartPoints: [BarberAnalyticsChartPoint]
    let cardVolumeCents: Int
    let cardCompletionCount: Int
    let cashVolumeCents: Int
    let cashCompletionCount: Int
    let platformCutCents: Int
    let cardTakeHomeCents: Int
    let cashTakeHomeCents: Int
    let takeHomeCents: Int
    let tipTotalCents: Int
    let pendingCount: Int
    let upcomingCount: Int
    let completedCount: Int
    let completionRate: Double
    let estimatedNetTakeHomeCents: Int
}

struct BarberAnalyticsChartPoint: Identifiable, Hashable {
    let id: String
    let date: Date
    let volumeCents: Int
    let bookingCount: Int
}

// MARK: - Clients directory

struct BarberClient: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String?
    let profileImageURL: URL?
    let bookingCount: Int
    let lifetimeVolumeCents: Int
    let lastBookingDate: Date?

    var formattedLastBooking: String {
        guard let lastBookingDate else { return "No bookings yet" }
        return lastBookingDate.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

struct BarberAnalyticsAggregateDTO: Decodable, Hashable {
    let uniqueClients: Int?
    let totalBookings: Int?
    let avgBookingValue: Double?
    let lifetimeEarnings: Double?

    enum CodingKeys: String, CodingKey {
        case uniqueClients = "unique_clients"
        case totalBookings = "total_bookings"
        case avgBookingValue = "avg_booking_value"
        case lifetimeEarnings = "lifetime_earnings"
    }
}
