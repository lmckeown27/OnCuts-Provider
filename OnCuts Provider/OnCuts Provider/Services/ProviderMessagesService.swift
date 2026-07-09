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

struct BookingConversationContext {
    let bookingId: String
    let consumerUserId: String
    let serviceName: String?
    let servicePriceCents: Int?
    let scheduledTime: Date?
    let location: String?
    let notes: String?
    let consumerName: String?
    let barberName: String?

    static func from(booking: SimpleBookingDTO) -> BookingConversationContext? {
        guard let consumerUserId = booking.consumerId?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !consumerUserId.isEmpty
        else { return nil }

        let consumerName = booking.resolvedConsumerDisplayName
        return BookingConversationContext(
            bookingId: booking.id,
            consumerUserId: consumerUserId,
            serviceName: booking.serviceName ?? booking.serviceType,
            servicePriceCents: booking.priceUsdCents,
            scheduledTime: booking.scheduledTime,
            location: booking.location,
            notes: booking.notes,
            consumerName: consumerName,
            barberName: booking.resolvedBarberDisplayName
        )
    }

    static func from(request: BookingRequestRow) -> BookingConversationContext? {
        guard let consumerUserId = request.customerId?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !consumerUserId.isEmpty
        else { return nil }

        return BookingConversationContext(
            bookingId: request.bookingId,
            consumerUserId: consumerUserId,
            serviceName: request.serviceType,
            servicePriceCents: request.price.map { Int(($0 * 100).rounded()) },
            scheduledTime: nil,
            location: request.location,
            notes: nil,
            consumerName: request.customerName,
            barberName: nil
        )
    }
}

private extension SimpleBookingDTO {
    var resolvedConsumerDisplayName: String? {
        if let consumerName {
            let trimmed = consumerName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let parts = [consumer?.firstName, consumer?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var resolvedBarberDisplayName: String? {
        if let barberName {
            let trimmed = barberName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let parts = [barber?.firstName, barber?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

@MainActor
enum ProviderMessagesService {
    private static let bookingConversationDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func listConversations(page: Int = 1) async throws -> [ConversationRow] {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations?page=\(page)&limit=40"
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(ConversationsEnvelope.self, from: data)
        return env.data?.conversations ?? []
    }

    static func fetchConversation(conversationId: Int) async throws -> ConversationRow? {
        do {
            let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
                path: "messages/conversations/\(conversationId)"
            )
            let dec = OnCutsHTTPClient.jsonDecoderSnake()
            let env = try dec.decode(ConversationDetailEnvelope.self, from: data)
            return env.data?.conversation
        } catch let error as OnCutsHTTPError {
            if case .httpStatus(404, _) = error { return nil }
            throw error
        }
    }

    /// Conversation-only booking requests use synthetic ids like `conv-123`.
    static func parseConversationId(fromBookingKey bookingKey: String) -> Int? {
        let normalized = bookingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.lowercased().hasPrefix("conv-") else { return nil }
        return Int(normalized.dropFirst(5))
    }

    /// Resolves the inbox thread for a booking when the booking payload omits `conversationId`.
    static func conversationId(forBookingId bookingId: String) async throws -> Int? {
        if let parsed = parseConversationId(fromBookingKey: bookingId) {
            return parsed
        }

        let normalized = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let conversations = try await listConversations()
        return conversations.first { row in
            let linked = row.bookingId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let summaryId = row.booking?.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return linked == normalized || summaryId == normalized
        }?.id
    }

    /// Finds an existing thread or creates one with booking context (web `startBookingConversation` parity).
    static func resolveOrStartConversation(
        bookingId: String,
        booking: SimpleBookingDTO?,
        request: BookingRequestRow? = nil
    ) async throws -> Int? {
        if let parsed = parseConversationId(fromBookingKey: bookingId) {
            return parsed
        }

        if let conversationId = booking?.conversationId {
            return conversationId
        }

        if let found = try await conversationId(forBookingId: bookingId) {
            return found
        }

        let context = booking.flatMap(BookingConversationContext.from(booking:))
            ?? request.flatMap(BookingConversationContext.from(request:))
        guard let context else { return nil }

        return try await startBookingConversation(context: context)
    }

    static func startBookingConversation(context: BookingConversationContext) async throws -> Int {
        var body: [String: Any] = [
            "otherUserId": context.consumerUserId,
            "bookingId": context.bookingId,
        ]
        if let serviceName = context.serviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !serviceName.isEmpty {
            body["serviceName"] = serviceName
        }
        if let servicePriceCents = context.servicePriceCents {
            body["servicePrice"] = Double(servicePriceCents) / 100.0
        }
        if let scheduledTime = context.scheduledTime {
            body["scheduledTime"] = bookingConversationDateFormatter.string(from: scheduledTime)
        }
        if let location = context.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            body["location"] = location
        }
        if let notes = context.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            body["notes"] = notes
        }
        if let consumerName = context.consumerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !consumerName.isEmpty {
            body["consumerName"] = consumerName
        }
        if let barberName = context.barberName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !barberName.isEmpty {
            body["barberName"] = barberName
        }

        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations",
            method: "POST",
            jsonBody: body,
            acceptableStatuses: 200 ..< 300
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        if let start = try? dec.decode(StartConversationEnvelope.self, from: data),
           let id = start.data?.conversation?.id {
            return id
        }
        if let detail = try? dec.decode(ConversationDetailEnvelope.self, from: data),
           let id = detail.data?.conversation?.id {
            return id
        }
        throw OnCutsHTTPError.decoding
    }

    static func listMessages(conversationId: Int) async throws -> [ChatMessageDTO] {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations/\(conversationId)/messages?page=1&limit=100"
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(MessagesEnvelope.self, from: data)
        return env.data?.messages ?? []
    }

    static func sendText(conversationId: Int, text: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations/\(conversationId)/messages",
            method: "POST",
            jsonBody: ["content": text, "messageType": "text"]
        )
    }

    static func uploadChatImage(jpegData: Data, fileName: String = "photo.jpg") async throws -> String {
        let data = try await OnCutsHTTPClient.uploadMultipart(
            path: "upload/chat-image",
            fieldName: "image",
            fileName: fileName,
            mimeType: "image/jpeg",
            fileData: jpegData
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(ChatImageUploadEnvelope.self, from: data)
        guard let url = env.data?.url, !url.isEmpty else {
            throw OnCutsHTTPError.decoding
        }
        return url
    }

    static func sendImage(conversationId: Int, mediaUrl: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations/\(conversationId)/messages",
            method: "POST",
            jsonBody: ["content": "", "messageType": "image", "mediaUrl": mediaUrl]
        )
    }

    static func markRead(conversationId: Int) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/conversations/\(conversationId)/read",
            method: "PUT",
            jsonBody: [:]
        )
    }

    // MARK: - UGC safety (Guideline 1.2)

    static func blockConsumer(userId: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/blocks",
            method: "POST",
            jsonBody: ["blockedUserId": userId]
        )
    }

    static func reportConsumer(userId: String, conversationId: Int, reason: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
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
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "messages/blocks")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
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
