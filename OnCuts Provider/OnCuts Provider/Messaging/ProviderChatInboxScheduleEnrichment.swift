import Foundation

/// Fills missing inbox appointment times from `bookings-simple`, matching chat detail behavior.
@MainActor
enum ProviderChatInboxScheduleEnrichment {
    static func enrich(_ rows: [ConversationRow]) async -> [ConversationRow] {
        let missingBookingIds = Set(
            rows.compactMap { row -> String? in
                guard row.booking?.scheduledTime == nil else { return nil }
                return row.resolvedLinkedBookingId
            }
        )
        guard !missingBookingIds.isEmpty else { return rows }

        var scheduleByBookingId: [String: Date] = [:]

        if let bookings = try? await ProviderBookingsService.listBookings(role: "barber") {
            for booking in bookings where missingBookingIds.contains(booking.id) {
                if let schedule = booking.providerEffectiveScheduledTime {
                    scheduleByBookingId[booking.id] = schedule
                }
            }
        }

        var enriched = rows.map { applyCachedSchedule(to: $0, scheduleByBookingId: scheduleByBookingId) }

        let unresolvedBookingIds = Set(
            enriched.compactMap { row -> String? in
                guard row.booking?.scheduledTime == nil else { return nil }
                return row.resolvedLinkedBookingId
            }
        )
        guard !unresolvedBookingIds.isEmpty else { return enriched }

        await withTaskGroup(of: (String, Date?).self) { group in
            for bookingId in unresolvedBookingIds {
                group.addTask {
                    let booking = try? await ProviderBookingsService.fetchBooking(id: bookingId)
                    return (bookingId, booking?.providerEffectiveScheduledTime)
                }
            }
            for await (bookingId, schedule) in group {
                if let schedule {
                    scheduleByBookingId[bookingId] = schedule
                }
            }
        }

        return enriched.map { applyCachedSchedule(to: $0, scheduleByBookingId: scheduleByBookingId) }
    }

    private static func applyCachedSchedule(
        to row: ConversationRow,
        scheduleByBookingId: [String: Date]
    ) -> ConversationRow {
        guard row.booking?.scheduledTime == nil,
              let bookingId = row.resolvedLinkedBookingId,
              let schedule = scheduleByBookingId[bookingId] else {
            return row
        }
        return row.withScheduledTime(schedule)
    }
}

extension ConversationRow {
    /// Real booking UUID when the thread is tied to a booking (not synthetic `conv-*` ids).
    var resolvedLinkedBookingId: String? {
        for raw in [bookingId, booking?.id] {
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("conv-") else { continue }
            return trimmed
        }
        return nil
    }

    func withScheduledTime(_ schedule: Date) -> ConversationRow {
        let updatedBooking = ConversationBookingSummary(
            id: booking?.id ?? bookingId,
            serviceName: booking?.serviceName,
            scheduledTime: schedule,
            status: booking?.status
        )
        return ConversationRow(
            id: id,
            bookingId: bookingId,
            booking: updatedBooking,
            unreadCount: unreadCount,
            lastMessage: lastMessage,
            otherUser: otherUser
        )
    }
}
