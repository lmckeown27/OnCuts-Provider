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
    static func loadTriageQueue(
        barberTableId: String,
        bookingsHint: [SimpleBookingDTO]? = nil
    ) async throws -> [RequestTriageItem] {
        async let pendingTask = listPending(barberTableId: barberTableId)
        let bookings: [SimpleBookingDTO]
        if let bookingsHint, !bookingsHint.isEmpty {
            bookings = bookingsHint
        } else {
            bookings = try await ProviderBookingsService.listBookings(role: "barber")
        }
        let pending = try await pendingTask
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

    /// Accept a pending inquiry after applying any consumer reschedule request so the accepted time matches what the barber reviewed.
    static func acceptApplyingConsumerSchedule(
        bookingId: String,
        barberTableId: String,
        booking: SimpleBookingDTO?,
        message: String?
    ) async throws {
        if let booking,
           booking.statusUpper == "PENDING",
           booking.hasPendingRescheduleRequest {
            try await ProviderBookingsService.approveRescheduleRequest(bookingId: bookingId)
        }
        try await accept(bookingId: bookingId, barberTableId: barberTableId, message: message)
    }

    static func reject(bookingId: String, barberTableId: String, reason: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "booking-requests/\(bookingId)/reject",
            method: "POST",
            jsonBody: ["barberId": barberTableId, "reason": reason]
        )
    }
}
