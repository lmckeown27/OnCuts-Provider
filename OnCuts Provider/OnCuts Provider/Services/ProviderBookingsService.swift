import Foundation

@MainActor
enum ProviderBookingsService {
    static func listBookings(role: String = "barber", status: String? = nil) async throws -> [SimpleBookingDTO] {
        var path = "bookings-simple?role=\(role)"
        if let status, !status.isEmpty {
            path += "&status=\(status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? status)"
        }
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
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

    /// Hydrate tip / cancellation fields that the barber list sometimes omits so the
    /// calendar can drop settled or cancelled rows. Call after assigning the list so
    /// Pending / Paid cards appear immediately.
    static func enrichLifecycleFieldsForSchedule(_ bookings: [SimpleBookingDTO]) async -> [SimpleBookingDTO] {
        let needsEnrichment = bookings.filter { booking in
            guard booking.isVisibleOnMainSchedule else { return false }
            // Tip-pending or unpaid post-complete may already be settled on detail.
            if booking.isAwaitingTip || booking.isAwaitingPostCompletePayment { return true }
            // Active row with a cancel stamp — confirm detail so it can leave the calendar.
            return booking.hasPlausibleCancelledAt
        }
        guard !needsEnrichment.isEmpty else { return bookings }

        var byId: [String: SimpleBookingDTO] = [:]
        for booking in needsEnrichment {
            guard let detail = try? await fetchBooking(id: booking.id) else { continue }
            byId[booking.id] = detail
        }
        guard !byId.isEmpty else { return bookings }

        return bookings.map { booking in
            guard let detail = byId[booking.id] else { return booking }
            return booking.mergingTipLifecycle(from: detail)
        }
    }

    static func fetchBooking(id: String) async throws -> SimpleBookingDTO {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "bookings-simple/\(id)")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BookingSimpleDetailEnvelope.self, from: data)
        guard let booking = env.booking?.asSimpleBookingDTO() else {
            throw URLError(.badServerResponse)
        }
        return booking
    }

    static func updateBookingStatus(id: String, status: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)/status",
            method: "PUT",
            jsonBody: ["status": status]
        )
    }

    static func markComplete(id: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)/complete",
            method: "PUT",
            jsonBody: [:]
        )
    }

    static func undoComplete(id: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)/undo-complete",
            method: "PUT",
            jsonBody: [:]
        )
    }

    static func requestPayment(id: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)/request-payment",
            method: "POST",
            jsonBody: [:]
        )
    }

    static func reschedule(id: String, scheduledTimeISO: String, location: String?, notes: String?) async throws {
        var body: [String: Any] = ["scheduledTime": scheduledTimeISO]
        if let location { body["location"] = location }
        if let notes { body["notes"] = notes }
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)",
            method: "PUT",
            jsonBody: body
        )
    }

    /// Snaps `proposedTime` to the target day's bookable grid, then reschedules.
    @discardableResult
    static func rescheduleWithDayAlignment(
        barberId: String,
        bookingId: String,
        proposedTime: Date,
        durationMinutes: Int = ProviderScheduleHourlySlot.bookableSlotMinutes,
        location: String?,
        notes: String?,
        timeZone: TimeZone = .current
    ) async throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let dayData = try await ProviderAvailabilityService.getDayAvailability(
            barberId: barberId,
            date: proposedTime,
            timeZone: timeZone
        )
        let intervals = dayData.intervals ?? []
        let slotInterval = dayData.resolvedBookingSlotIntervalMinutes
        let appointmentDuration = durationMinutes > 0
            ? durationMinutes
            : dayData.resolvedAppointmentDurationMinutes

        let snapped = ProviderBookingSlotAlignment.snapToNearestBookableStart(
            proposed: proposedTime,
            intervals: intervals,
            slotIntervalMinutes: slotInterval,
            appointmentDurationMinutes: appointmentDuration,
            calendar: calendar
        ) ?? proposedTime

        try await reschedule(
            id: bookingId,
            scheduledTimeISO: snapped.campusCutsISO8601String(),
            location: location,
            notes: notes
        )
        return snapped
    }

    static func cancelBooking(id: String, reason: String?) async throws {
        var body: [String: Any] = [:]
        if let reason, !reason.isEmpty { body["reason"] = reason }
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(id)",
            method: "DELETE",
            jsonBody: body
        )
    }

    static func approveRescheduleRequest(bookingId: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(bookingId)/reschedule-request/approve",
            method: "POST",
            jsonBody: [:]
        )
    }

    static func rejectRescheduleRequest(bookingId: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "bookings-simple/\(bookingId)/reschedule-request/reject",
            method: "POST",
            jsonBody: [:]
        )
    }
}
