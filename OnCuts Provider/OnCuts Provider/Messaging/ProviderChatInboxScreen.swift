import SwiftUI

/// SwiftUI provider message list — schedule-anchored card inbox (replaces UIKit table rows).
struct ProviderChatInboxScreen: View {
    var reloadToken: UUID

    var onConversationsUpdated: ([ConversationRow]) -> Void

    @State private var threads: [ProviderChatThread] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private var calendar: Calendar { .current }

    var body: some View {
        ProviderChatInboxListView(
            threads: threads,
            isLoading: isLoading,
            errorText: errorText,
            onRefresh: { await loadConversations() }
        )
        .task(id: reloadToken) {
            await loadConversations()
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerMessagingUnreadCountShouldRefresh)) { _ in
            Task { await loadConversations() }
        }
    }

    @MainActor
    private func loadConversations() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await ProviderMessagesService.listConversations()
            let enriched = await ProviderChatInboxScheduleEnrichment.enrich(fetched)
            threads = ProviderChatThread.sortedForInbox(
                enriched.map { ProviderChatThread.from(row: $0, calendar: calendar) },
                calendar: calendar
            )
            errorText = nil
            onConversationsUpdated(enriched)
            for thread in threads.prefix(6) {
                ProviderConversationMessagesPrefetch.prefetch(conversationId: thread.conversationId)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
