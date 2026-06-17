import SwiftUI
import UIKit

// MARK: - Inbox host

/// UIKit inbox list hosted as the root of a SwiftUI `NavigationStack` (same pattern as Bookings).
struct ProviderMessagesInboxUIKitHost: UIViewControllerRepresentable {
    var barberTableId: String?
    var currentUserId: String?
    var reloadToken: UUID
    var onConversationSelected: (ConversationRow) -> Void
    var onConversationsUpdated: ([ConversationRow]) -> Void

    func makeUIViewController(context: Context) -> ProviderInboxViewController {
        let inbox = ProviderInboxViewController()
        inbox.barberTableId = barberTableId
        inbox.currentUserId = currentUserId
        inbox.onConversationSelected = onConversationSelected
        inbox.onConversationsUpdated = onConversationsUpdated
        context.coordinator.lastReloadToken = reloadToken
        return inbox
    }

    func updateUIViewController(_ inbox: ProviderInboxViewController, context: Context) {
        inbox.barberTableId = barberTableId
        inbox.currentUserId = currentUserId
        inbox.onConversationSelected = onConversationSelected
        inbox.onConversationsUpdated = onConversationsUpdated

        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            inbox.reloadConversations()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastReloadToken: UUID?
    }
}

// MARK: - Conversation detail host

/// UIKit chat thread hosted directly in SwiftUI `NavigationStack` so edge-swipe back works.
struct ProviderChatDetailHost: UIViewControllerRepresentable {
    let conversation: ConversationRow
    var barberTableId: String?
    var onNavigateBack: () -> Void
    var onBlocked: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBlocked: onBlocked)
    }

    func makeUIViewController(context: Context) -> ProviderChatDetailViewController {
        let detail = ProviderChatDetailViewController(conversation: conversation)
        detail.barberTableId = barberTableId
        detail.delegate = context.coordinator
        detail.onNavigateBack = onNavigateBack
        context.coordinator.detail = detail
        return detail
    }

    func updateUIViewController(_ detail: ProviderChatDetailViewController, context: Context) {
        detail.barberTableId = barberTableId
        detail.onNavigateBack = onNavigateBack
        context.coordinator.detail = detail
    }

    final class Coordinator: NSObject, ProviderChatDetailViewControllerDelegate {
        let onBlocked: () -> Void
        weak var detail: ProviderChatDetailViewController?

        init(onBlocked: @escaping () -> Void) {
            self.onBlocked = onBlocked
        }

        func chatDetailViewControllerDidBlockConsumer(
            _ controller: ProviderChatDetailViewController,
            conversationId: Int
        ) {
            onBlocked()
        }
    }
}

// MARK: - Shared chat navigation bar chrome

enum ProviderChatNavigationBarStyle {
    static func apply(to navigationBar: UINavigationBar) {
        let olive = ProviderChatDesignTokens.Color.providerOlive
        navigationBar.tintColor = olive
        navigationBar.prefersLargeTitles = false

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ProviderAppearance.neutralPushedBackdrop
        appearance.shadowColor = ProviderChatDesignTokens.Color.separator
        appearance.titleTextAttributes = [
            .foregroundColor: ProviderChatDesignTokens.Color.lavaShellCream,
        ]

        let barButtonTitleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: olive]
        appearance.buttonAppearance.normal.titleTextAttributes = barButtonTitleAttributes
        appearance.doneButtonAppearance.normal.titleTextAttributes = barButtonTitleAttributes
        if #available(iOS 26.0, *) {
            appearance.prominentButtonAppearance.normal.titleTextAttributes = barButtonTitleAttributes
        }

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }
}

// MARK: - Blocked users sheet

struct ProviderBlockedUsersHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ProviderBlockedUsersViewController {
        ProviderBlockedUsersViewController()
    }

    func updateUIViewController(_ uiViewController: ProviderBlockedUsersViewController, context: Context) {}
}

// MARK: - Messages route

/// Messages inbox + conversation detail inside an inner `NavigationStack` (Bookings parity).
struct ProviderMessagesInboxView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(ProviderShellNavigator.self) private var shellNavigator

    @State private var conversations: [ConversationRow] = []
    @State private var showingBlockedUsers = false
    @State private var inboxReloadToken = UUID()

    var body: some View {
        @Bindable var navigator = shellNavigator

        NavigationStack(path: $navigator.messagesDetailPath) {
            ProviderChatInboxScreen(
                reloadToken: inboxReloadToken,
                onConversationsUpdated: { rows in
                    conversations = rows
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .providerNavigationStackDestinationBackdrop(style: .neutralGrey)
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingBlockedUsers = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.minus")
                    }
                    .accessibilityLabel("Blocked Users")
                }
            }
            .navigationDestination(for: Int.self) { conversationId in
                if let conversation = conversations.first(where: { $0.id == conversationId }) {
                    ProviderChatDetailHost(
                        conversation: conversation,
                        barberTableId: session.barberProfile?.id,
                        onNavigateBack: {
                            guard !navigator.messagesDetailPath.isEmpty else { return }
                            navigator.messagesDetailPath.removeLast()
                        },
                        onBlocked: {
                            navigator.messagesDetailPath = NavigationPath()
                            inboxReloadToken = UUID()
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.providerNeutralPushedBackdrop)
                    .toolbar(.hidden, for: .navigationBar)
                } else {
                    ProgressView()
                        .tint(.providerOlive)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.providerNeutralPushedBackdrop)
                        .toolbar(.hidden, for: .navigationBar)
                        .task { await loadConversationsForDeepLink(conversationId: conversationId) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerMessagingUnreadCountShouldRefresh)) { _ in
            guard shellNavigator.messagesDetailPath.isEmpty else { return }
            inboxReloadToken = UUID()
        }
        .onChange(of: shellNavigator.messagesDetailPath.count) { _, count in
            #if os(iOS)
            ProviderShellNavigationPopBridge.shared.setHostDestinationPresented(count > 0)
            #endif
        }
        .onAppear {
            #if os(iOS)
            ProviderShellNavigationPopBridge.shared.setHostDestinationPresented(
                !shellNavigator.messagesDetailPath.isEmpty
            )
            #endif
        }
        .sheet(isPresented: $showingBlockedUsers) {
            NavigationStack {
                ProviderBlockedUsersHost()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Blocked Users")
                                .font(.provider(.headline, weight: .semibold))
                        }
                    }
            }
            .foregroundStyle(Color.lavaShellCream)
            .tint(.providerOlive)
            .providerLavaScreenChrome()
            .presentationDragIndicator(.visible)
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
    }

    private func loadConversationsForDeepLink(conversationId: Int) async {
        ProviderConversationMessagesPrefetch.prefetch(conversationId: conversationId)
        guard let rows = try? await ProviderMessagesService.listConversations() else { return }
        conversations = rows
    }
}
