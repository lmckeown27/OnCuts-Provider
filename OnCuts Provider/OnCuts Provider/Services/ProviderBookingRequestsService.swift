import Foundation

@MainActor
enum ProviderBookingRequestsService {
    static func listPending(barberTableId: String) async throws -> [BookingRequestRow] {
        let enc = barberTableId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? barberTableId
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "booking-requests/barber/\(enc)/pending")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(BookingRequestsPendingEnvelope.self, from: data).requests
    }

    /// Pending queue plus same-day schedule intersect (bookings + availability).
    static func loadTriageQueue(
        barberTableId: String,
        bookingsHint: [SimpleBookingDTO]? = nil
    ) async throws -> [RequestTriageItem] {
        let bookings: [SimpleBookingDTO]
        if let bookingsHint, !bookingsHint.isEmpty {
            bookings = bookingsHint
        } else {
            bookings = try await ProviderBookingsService.listBookings(role: "barber")
        }

        var pending: [BookingRequestRow]
        do {
            pending = try await listPending(barberTableId: barberTableId)
        } catch {
            pending = []
            guard !bookings.isEmpty else { throw error }
        }

        pending = mergePendingRequests(apiRows: pending, bookings: bookings)
        return await ProviderRequestTriageEngine.build(
            pending: pending,
            bookings: bookings,
            barberTableId: barberTableId
        )
    }

    /// Fills gaps when `/booking-requests/.../pending` omits rows that still exist on `bookings-simple`.
    private static func mergePendingRequests(
        apiRows: [BookingRequestRow],
        bookings: [SimpleBookingDTO]
    ) -> [BookingRequestRow] {
        let apiIds = Set(apiRows.map(\.bookingId))
        let supplemental = bookings
            .filter { $0.statusUpper == "PENDING" && !apiIds.contains($0.id) }
            .map(BookingRequestRow.init(synthesizingPendingBooking:))
        guard !supplemental.isEmpty else { return apiRows }
        return apiRows + supplemental
    }

    static func accept(bookingId: String, barberTableId: String, message: String?) async throws {
        var body: [String: Any] = ["barberId": barberTableId]
        if let message, !message.isEmpty { body["message"] = message }
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
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
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "booking-requests/\(bookingId)/reject",
            method: "POST",
            jsonBody: ["barberId": barberTableId, "reason": reason]
        )
    }
}

extension BookingRequestRow {
    /// Builds a triage row from `bookings-simple` when the booking-requests endpoint omits it.
    init(synthesizingPendingBooking booking: SimpleBookingDTO) {
        bookingId = booking.id
        customerId = booking.consumerId
        customerName = booking.consumerDisplayName
        serviceType = booking.serviceDisplayName
        if let scheduled = booking.scheduledTime {
            requestedDate = scheduled.campusCutsISO8601String()
            requestedTime = nil
        } else {
            requestedDate = nil
            requestedTime = nil
        }
        location = booking.location
        status = booking.status
        price = booking.priceUsdCents.map { Double($0) / 100.0 }
    }
}
