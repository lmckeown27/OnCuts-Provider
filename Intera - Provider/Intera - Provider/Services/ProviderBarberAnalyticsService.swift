import Foundation

@MainActor
enum ProviderBarberAnalyticsService {
    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool?
        let data: T?
    }

    static func loadDashboard(barberId: String) async throws -> (
        bookings: [SimpleBookingDTO],
        payoutSummary: BarberPayoutSummaryDTO?,
        aggregate: BarberAnalyticsAggregateDTO?
    ) {
        async let bookingsTask = ProviderBookingsService.listBookings(role: "barber")
        async let payoutTask: BarberPayoutSummaryDTO? = {
            try? await ProviderBarberPayoutService.fetchPayoutSummary()
        }()
        async let aggregateTask = fetchAggregate(barberId: barberId)
        let bookings = try await bookingsTask
        let payout = await payoutTask
        let aggregate = await aggregateTask
        return (bookings, payout, aggregate)
    }

    static func loadClients() async throws -> [ConversationRow] {
        try await ProviderMessagesService.listConversations()
    }

    private static func fetchAggregate(barberId: String) async -> BarberAnalyticsAggregateDTO? {
        let enc = barberId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? barberId
        guard let data = try? await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/\(enc)/analytics") else {
            return nil
        }
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try? dec.decode(Envelope<BarberAnalyticsAggregateDTO>.self, from: data).data
    }
}
