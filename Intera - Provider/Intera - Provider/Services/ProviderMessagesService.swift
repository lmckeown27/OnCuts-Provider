import Foundation
import UIKit

private struct ChatImageUploadEnvelope: Decodable {
    let data: ChatImageUploadData?
}

private struct ChatImageUploadData: Decodable {
    let url: String
}

extension UIImage {
    fileprivate func jpegDataForChatUpload(maxPixel: CGFloat = 1600, quality: CGFloat = 0.82) -> Data? {
        let scaled = scaledToFit(maxPixel: maxPixel)
        return scaled.jpegData(compressionQuality: quality)
    }

    fileprivate func scaledToFit(maxPixel: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxPixel, maxSide > 0 else { return self }
        let scale = maxPixel / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

@MainActor
enum ProviderMessagesService {
    static func listConversations(page: Int = 1) async throws -> [ConversationRow] {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations?page=\(page)&limit=40"
        )
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(ConversationsEnvelope.self, from: data)
        return env.data?.conversations ?? []
    }

    /// Resolves the inbox thread for a booking when the booking payload omits `conversationId`.
    static func conversationId(forBookingId bookingId: String) async throws -> Int? {
        let normalized = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let conversations = try await listConversations()
        return conversations.first { row in
            let linked = row.bookingId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let summaryId = row.booking?.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return linked == normalized || summaryId == normalized
        }?.id
    }

    static func listMessages(conversationId: Int) async throws -> [ChatMessageDTO] {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations/\(conversationId)/messages?page=1&limit=100"
        )
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(MessagesEnvelope.self, from: data)
        return env.data?.messages ?? []
    }

    static func sendText(conversationId: Int, text: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations/\(conversationId)/messages",
            method: "POST",
            jsonBody: ["content": text, "messageType": "text"]
        )
    }

    static func uploadChatImage(jpegData: Data, fileName: String = "photo.jpg") async throws -> String {
        let data = try await CampusCutsHTTPClient.uploadMultipart(
            path: "upload/chat-image",
            fieldName: "image",
            fileName: fileName,
            mimeType: "image/jpeg",
            fileData: jpegData
        )
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(ChatImageUploadEnvelope.self, from: data)
        guard let url = env.data?.url, !url.isEmpty else {
            throw CampusCutsHTTPError.decoding
        }
        return url
    }

    static func sendImage(conversationId: Int, mediaUrl: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations/\(conversationId)/messages",
            method: "POST",
            jsonBody: ["content": "", "messageType": "image", "mediaUrl": mediaUrl]
        )
    }

    static func markRead(conversationId: Int) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations/\(conversationId)/read",
            method: "PUT",
            jsonBody: [:]
        )
    }

    // MARK: - UGC safety (Guideline 1.2)

    static func blockConsumer(userId: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/blocks",
            method: "POST",
            jsonBody: ["blockedUserId": userId]
        )
    }

    static func reportConsumer(userId: String, conversationId: Int, reason: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/reports",
            method: "POST",
            jsonBody: [
                "reportedUserId": userId,
                "conversationId": conversationId,
                "reason": reason,
            ]
        )
    }

    static func sendPhoto(conversationId: Int, image: UIImage) async throws {
        guard let data = image.jpegDataForChatUpload() else {
            throw NSError(
                domain: "ProviderMessages",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not prepare the photo."]
            )
        }
        let url = try await uploadChatImage(jpegData: data)
        try await sendImage(conversationId: conversationId, mediaUrl: url)
    }

    static func listBlockedUsers() async throws -> [BlockedConsumerRow] {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "messages/blocks")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BlockedConsumersEnvelope.self, from: data)
        return env.data ?? []
    }
}

// MARK: - Thread prefetch / cache

/// In-memory message cache so opening a conversation can render immediately after inbox tap.
@MainActor
enum ProviderConversationMessagesPrefetch {
    private static var cache: [Int: [ChatMessageDTO]] = [:]
    private static var inFlight: Set<Int> = []

    static func cachedMessages(for conversationId: Int) -> [ChatMessageDTO]? {
        cache[conversationId]
    }

    static func store(conversationId: Int, messages: [ChatMessageDTO]) {
        cache[conversationId] = messages
    }

    static func invalidate(conversationId: Int) {
        cache.removeValue(forKey: conversationId)
        inFlight.remove(conversationId)
    }

    static func prefetch(conversationId: Int) {
        guard cache[conversationId] == nil, !inFlight.contains(conversationId) else { return }
        inFlight.insert(conversationId)
        Task {
            defer { inFlight.remove(conversationId) }
            guard let messages = try? await ProviderMessagesService.listMessages(conversationId: conversationId) else {
                return
            }
            cache[conversationId] = messages
        }
    }
}
