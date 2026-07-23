import Foundation
import SwiftUI

/// Provider inbox row — schedule-anchored chat summary (no studio/shop/chair fields).
struct ProviderChatThread: Identifiable, Hashable {
    let conversationId: Int
    let clientName: String
    let serviceName: String
    let appointmentTime: String
    let appointmentDayLabel: String
    let appointmentDateLabel: String
    let bookingStatusTitle: String
    let bookingStatusRaw: String?
    let lastMessage: String
    let isToday: Bool
    let unreadCount: Int

    var id: Int { conversationId }

    var hasUnread: Bool { unreadCount > 0 }

    var unreadBadgeLabel: String {
        unreadCount == 1 ? "1 New" : "\(unreadCount) New"
    }

    var titleLine: String {
        "\(clientName): \(serviceName)"
    }

    var bookingStatusColor: Color {
        ProviderBookingStatusDisplay.inboxStatusLabelColor(for: bookingStatusRaw)
    }
}

// MARK: - Mapping

extension ProviderChatThread {
    static func from(
        row: ConversationRow,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> ProviderChatThread {
        let scheduled = row.booking?.scheduledTime
        let schedule = appointmentSchedule(for: scheduled, calendar: calendar, now: now)

        let statusRaw = row.booking?.status ?? (row.bookingId != nil ? "pending" : nil)

        return ProviderChatThread(
            conversationId: row.id,
            clientName: clientName(from: row),
            serviceName: serviceName(from: row),
            appointmentTime: schedule.time,
            appointmentDayLabel: schedule.day,
            appointmentDateLabel: schedule.date,
            bookingStatusTitle: bookingStatusTitle(from: row),
            bookingStatusRaw: statusRaw,
            lastMessage: lastMessagePreview(from: row),
            isToday: schedule.isToday,
            unreadCount: max(0, row.unreadCount ?? 0)
        )
    }

    static func sortedForInbox(_ threads: [ProviderChatThread], calendar: Calendar = .current) -> [ProviderChatThread] {
        threads.sorted { lhs, rhs in
            if lhs.isToday != rhs.isToday { return lhs.isToday && !rhs.isToday }
            if lhs.hasUnread != rhs.hasUnread { return lhs.hasUnread && !rhs.hasUnread }
            return lhs.clientName.localizedCaseInsensitiveCompare(rhs.clientName) == .orderedAscending
        }
    }

    private static func clientName(from row: ConversationRow) -> String {
        if let display = row.otherUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty {
            return display
        }
        let first = row.otherUser?.firstName ?? ""
        let last = row.otherUser?.lastName ?? ""
        let joined = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "Client" : joined
    }

    private static func serviceName(from row: ConversationRow) -> String {
        if let name = row.booking?.serviceDisplayName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "Appointment"
    }

    private static func bookingStatusTitle(from row: ConversationRow) -> String {
        if let status = row.booking?.status {
            return ProviderBookingStatusDisplay.title(for: status)
        }
        return row.bookingId != nil ? "Pending" : "—"
    }

    private static func lastMessagePreview(from row: ConversationRow) -> String {
        let trimmed = row.lastMessage?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No messages yet" : trimmed
    }

    private static func appointmentSchedule(
        for scheduled: Date?,
        calendar: Calendar,
        now: Date
    ) -> (time: String, day: String, date: String, isToday: Bool) {
        guard let scheduled else {
            return ("—", "No appt", "—", false)
        }

        let month = calendar.component(.month, from: scheduled)
        let day = calendar.component(.day, from: scheduled)
        let dateLabel = "\(month)/\(day)"
        let timeLabel = scheduled.formatted(date: .omitted, time: .shortened)

        if calendar.isDate(scheduled, inSameDayAs: now) {
            return (timeLabel, "Today", dateLabel, true)
        }
        if calendar.isDateInTomorrow(scheduled) {
            return (timeLabel, "Tomorrow", dateLabel, false)
        }
        let weekday = scheduled.formatted(.dateTime.weekday(.abbreviated))
        return (timeLabel, weekday, dateLabel, false)
    }
}
