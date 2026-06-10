import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Inbox presentation

/// Who sent the most recent message in the conversation, from this user's perspective.
///
    /// Drives inbox preview bubble styling — same received vs sent palette as the thread.
    enum ProviderConversationLastMessageDirection: Hashable {
        /// We sent the most recent message (ball is in their court).
        case sent
        /// They sent the most recent message (ball is in our court).
        case received
        /// Conversation has no messages yet, or we don't know the current user id.
        case none
    }

struct ProviderConversationPresentation: Hashable {
    let row: ConversationRow
    let displayName: String
    let preview: String
    let timestamp: String
    let unreadCount: Int
    /// Direction of the latest message, used to color the row's status dot.
    let lastMessageDirection: ProviderConversationLastMessageDirection
    let badgeText: String?
    #if canImport(UIKit)
    let badgeBackgroundColor: UIColor?
    let badgeForegroundColor: UIColor?
    #endif
    let isOnline: Bool
    let avatarURL: URL?

    /// - Parameters:
    ///   - row: Conversation envelope from `GET /messages/conversations`.
    ///   - currentUserId: Signed-in user's UUID (`session.authUser?.id`). Required to derive
    ///     `lastMessageDirection`; when `nil` the dot is hidden because we can't tell sides apart.
    ///   - now: Reference point for the relative timestamp — exposed for deterministic tests.
    init(row: ConversationRow, currentUserId: String? = nil, now: Date = .now) {
        self.row = row

        if let display = row.otherUser?.displayName, !display.isEmpty {
            displayName = display
        } else {
            let first = row.otherUser?.firstName ?? ""
            let last = row.otherUser?.lastName ?? ""
            let joined = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            displayName = joined.isEmpty ? "Conversation" : joined
        }

        preview = row.lastMessage?.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (row.lastMessage?.content ?? "")
            : "No messages yet"

        if let date = row.lastMessage?.time {
            timestamp = ProviderConversationPresentation.relativeTimestamp(from: date, now: now)
        } else {
            timestamp = ""
        }

        unreadCount = row.unreadCount ?? 0
        isOnline = false
        avatarURL = row.otherUser?.avatarURL

        // Direction is "unknown" (→ no dot) when either the conversation has no messages yet, or
        // we weren't given a `currentUserId` to compare against. Comparing the trimmed UUID
        // strings sidesteps any whitespace/case oddities from the JSON.
        if let me = currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !me.isEmpty,
           let sender = row.lastMessage?.senderId?.trimmingCharacters(in: .whitespacesAndNewlines), !sender.isEmpty {
            lastMessageDirection = (sender.caseInsensitiveCompare(me) == .orderedSame) ? .sent : .received
        } else {
            lastMessageDirection = .none
        }

        if let status = row.booking?.status ?? (row.bookingId != nil ? "pending" : nil) {
            badgeText = ProviderBookingStatusDisplay.title(for: status)
            #if canImport(UIKit)
            let colors = ProviderBookingStatusDisplay.uiKitBadgeColors(for: status)
            badgeBackgroundColor = colors.background
            badgeForegroundColor = colors.foreground
            #endif
        } else {
            badgeText = nil
            #if canImport(UIKit)
            badgeBackgroundColor = nil
            badgeForegroundColor = nil
            #endif
        }
    }

    private static func relativeTimestamp(from date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Chat feed items

enum ProviderChatFeedItem: Hashable {
    case text(ChatMessageDTO)
    case bookingRequest(ChatMessageDTO)

    var id: Int {
        switch self {
        case .text(let message), .bookingRequest(let message):
            return message.id
        }
    }

    static func from(messages: [ChatMessageDTO]) -> [ProviderChatFeedItem] {
        messages.map { message in
            message.isBookingRequest ? .bookingRequest(message) : .text(message)
        }
    }
}
