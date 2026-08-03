import Foundation

/// Short-lived local booking snapshots so the calendar does not snap back to a stale
/// list payload right after cancel / complete / tip mutations.
@MainActor
enum ProviderScheduleBookingOverrides {
    private struct Entry {
        var booking: SimpleBookingDTO
        var expires: Date
    }

    private static var entries: [String: Entry] = [:]
    private static let ttl: TimeInterval = 20

    static func remember(_ booking: SimpleBookingDTO) {
        entries[booking.id] = Entry(booking: booking, expires: Date().addingTimeInterval(ttl))
    }

    static func merge(serverList: [SimpleBookingDTO]) -> [SimpleBookingDTO] {
        pruneExpired()
        guard !entries.isEmpty else { return serverList }

        return serverList.map { server in
            guard let local = entries[server.id]?.booking else { return server }
            let merged = preferMoreAdvancedLifecycle(local: local, server: server)
            // Drop override once the server has caught up (or surpassed) the local snapshot.
            if lifecycleRank(merged) >= lifecycleRank(local),
               merged.isCancelledOrRejected == local.isCancelledOrRejected,
               merged.isTipSettled == local.isTipSettled || !local.isTipSettled {
                entries.removeValue(forKey: server.id)
            }
            return merged
        }
    }

    private static func pruneExpired() {
        let now = Date()
        entries = entries.filter { $0.value.expires > now }
    }

    /// Prefer terminal / tip-settled local fields when the barber list is briefly stale.
    private static func preferMoreAdvancedLifecycle(
        local: SimpleBookingDTO,
        server: SimpleBookingDTO
    ) -> SimpleBookingDTO {
        if lifecycleRank(server) > lifecycleRank(local) {
            return server
        }
        if local.isCancelledOrRejected, !server.isCancelledOrRejected {
            return local
        }
        if local.isTipSettled, !server.isTipSettled {
            return server.mergingTipLifecycle(from: local)
        }
        if local.statusUpper == "COMPLETED", server.statusUpper == "PAID" {
            return local
        }
        if local.statusUpper == "PAID", server.statusUpper == "ACCEPTED", local.paidAt != nil {
            return local
        }
        return server.mergingTipLifecycle(from: local)
    }

    private static func lifecycleRank(_ booking: SimpleBookingDTO) -> Int {
        if booking.isCancelledOrRejected { return 50 }
        if booking.isTipSettled || booking.isLegacyFinishedPaid { return 40 }
        switch ProviderBookingStatusDisplay.normalized(booking.status) {
        case "completed": return 30
        case "paid": return 20
        case "accepted", "booked", "in_progress": return 10
        case "pending": return 5
        default: return 0
        }
    }
}
