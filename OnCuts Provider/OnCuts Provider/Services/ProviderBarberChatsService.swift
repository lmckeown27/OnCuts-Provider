import Foundation

/// Barber-to-barber peer roster + admin support inbox (`/messages/barber-chats/*`, `/messages/cm-barber/*`).
@MainActor
enum ProviderBarberChatsService {
    /// Web parity — active barbers on a campus (Stripe-connected, excludes self).
    static func fetchPeerBarbers(campusId: String?) async throws -> [BarberChatRowDTO] {
        var path = "messages/barber-chats/barbers"
        if let campusId, !campusId.isEmpty {
            let enc = campusId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? campusId
            path += "?campusId=\(enc)"
        }
        return try await fetchBarbers(path: path)
    }

    /// Admin support inbox — active barbers on a campus with existing support thread metadata.
    static func fetchSupportBarbers(campusId: String) async throws -> [BarberChatRowDTO] {
        let enc = campusId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? campusId
        let rows = try await fetchBarbers(path: "messages/cm-barber/conversations?campusId=\(enc)")
        return rows.map { $0.tagged(campusId: campusId) }
    }

    /// Admin support inbox across every campus — preserves campus grouping metadata.
    static func fetchSupportBarbersAllCampuses(campusIds: [String]) async throws -> [BarberChatRowDTO] {
        guard !campusIds.isEmpty else { return [] }

        var merged: [BarberChatRowDTO] = []
        try await withThrowingTaskGroup(of: [BarberChatRowDTO].self) { group in
            for campusId in campusIds {
                group.addTask {
                    try await fetchSupportBarbers(campusId: campusId)
                }
            }
            for try await rows in group {
                merged.append(contentsOf: rows)
            }
        }
        return merged
    }

    /// Start or reopen a peer barber-to-barber thread.
    static func startPeerConversation(otherBarberUserId: String) async throws -> Int {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/barber-chats",
            method: "POST",
            jsonBody: ["otherBarberUserId": otherBarberUserId]
        )
        return try decodeConversationId(from: data)
    }

    /// Admin opens a support thread with a barber (`booking_id IS NULL`).
    static func startSupportConversation(barberUserId: String) async throws -> Int {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "messages/cm-barber",
            method: "POST",
            jsonBody: ["barberUserId": barberUserId]
        )
        return try decodeConversationId(from: data)
    }

    private static func fetchBarbers(path: String) async throws -> [BarberChatRowDTO] {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = JSONDecoder()
        let env = try dec.decode(BarberChatsListEnvelope.self, from: data)
        return env.data?.barbers ?? []
    }

    private static func decodeConversationId(from data: Data) throws -> Int {
        let dec = JSONDecoder()
        let env = try dec.decode(StartBarberChatConversationEnvelope.self, from: data)
        guard let id = env.data?.conversation?.id else {
            throw OnCutsHTTPError.decoding
        }
        return id
    }
}
