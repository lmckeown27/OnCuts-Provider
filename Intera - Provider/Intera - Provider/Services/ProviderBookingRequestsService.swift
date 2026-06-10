import Foundation

@MainActor
enum ProviderBookingRequestsService {
    static func listPending(barberTableId: String) async throws -> [BookingRequestRow] {
        let enc = barberTableId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? barberTableId
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "booking-requests/barber/\(enc)/pending")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(BookingRequestsPendingEnvelope.self, from: data).requests ?? []
    }

    /// Pending queue plus same-day schedule intersect (bookings + availability).
    static func loadTriageQueue(barberTableId: String) async throws -> [RequestTriageItem] {
        async let pendingTask = listPending(barberTableId: barberTableId)
        async let bookingsTask = ProviderBookingsService.listBookings(role: "barber")
        let (pending, bookings) = try await (pendingTask, bookingsTask)
        return await ProviderRequestTriageEngine.build(
            pending: pending,
            bookings: bookings,
            barberTableId: barberTableId
        )
    }

    static func accept(bookingId: String, barberTableId: String, message: String?) async throws {
        var body: [String: Any] = ["barberId": barberTableId]
        if let message, !message.isEmpty { body["message"] = message }
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "booking-requests/\(bookingId)/accept",
            method: "POST",
            jsonBody: body
        )
    }

    static func reject(bookingId: String, barberTableId: String, reason: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "booking-requests/\(bookingId)/reject",
            method: "POST",
            jsonBody: ["barberId": barberTableId, "reason": reason]
        )
    }
}
