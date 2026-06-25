import Foundation

@MainActor
enum ProviderBookingsService {
    static func listBookings(role: String = "barber", status: String? = nil) async throws -> [SimpleBookingDTO] {
        var path = "bookings-simple?role=\(role)"
        if let status, !status.isEmpty {
            path += "&status=\(status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? status)"
        }
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BookingsSimpleListEnvelope.self, from: data)
        let bookings = env.resolvedBookings
        #if DEBUG
        if bookings.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataObj = json["data"] as? [String: Any],
           let raw = dataObj["bookings"] as? [Any],
           !raw.isEmpty {
            print("[ProviderBookingsService] Decoded 0 bookings but API returned \(raw.count).")
        }
        #endif
        return bookings
    }

    static func fetchBooking(id: String) async throws -> SimpleBookingDTO {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "bookings-simple/\(id)")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BookingSimpleDetailEnvelope.self, from: data)
        guard let booking = env.booking?.asSimpleBookingDTO() else {
            throw URLError(.badServerResponse)
        }
        return booking
    }

    static func updateBookingStatus(id: String, status: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)/status",
            method: "PUT",
            jsonBody: ["status": status]
        )
    }

    static func markComplete(id: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)/complete",
            method: "PUT",
            jsonBody: [:]
        )
    }

    static func undoComplete(id: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)/undo-complete",
            method: "PUT",
            jsonBody: [:]
        )
    }

    static func requestPayment(id: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)/request-payment",
            method: "POST",
            jsonBody: [:]
        )
    }

    static func reschedule(id: String, scheduledTimeISO: String, location: String?, notes: String?) async throws {
        var body: [String: Any] = ["scheduledTime": scheduledTimeISO]
        if let location { body["location"] = location }
        if let notes { body["notes"] = notes }
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)",
            method: "PUT",
            jsonBody: body
        )
    }

    static func cancelBooking(id: String, reason: String?) async throws {
        var body: [String: Any] = [:]
        if let reason, !reason.isEmpty { body["reason"] = reason }
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)",
            method: "DELETE",
            jsonBody: body
        )
    }

    static func approveRescheduleRequest(bookingId: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(bookingId)/reschedule-request/approve",
            method: "POST",
            jsonBody: [:]
        )
    }

    static func rejectRescheduleRequest(bookingId: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(bookingId)/reschedule-request/reject",
            method: "POST",
            jsonBody: [:]
        )
    }
}
