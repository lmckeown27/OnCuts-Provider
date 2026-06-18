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
