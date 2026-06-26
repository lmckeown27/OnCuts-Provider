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
            .font: UIFont.providerPreferred(forTextStyle: .headline, weight: .semibold),
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

// MARK: - Chats hub segments

enum ProviderChatsInboxSegment: String, CaseIterable, Identifiable {
    case clients
    case providers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clients: return "Clients"
        case .providers: return "Providers"
        }
    }
}

// MARK: - Messages route

/// Unified chats hub: client conversations + local provider roster.
struct ProviderMessagesInboxView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(ProviderShellNavigator.self) private var shellNavigator

    @State private var conversations: [ConversationRow] = []
    @State private var supplementalConversations: [Int: ConversationRow] = [:]
    @State private var showingBlockedUsers = false
    @State private var inboxReloadToken = UUID()
    @State private var selectedSegment: ProviderChatsInboxSegment = .clients

    private var showsProvidersSegment: Bool {
        session.hasProviderProfile || session.authUser?.hasAdminPrivileges == true
    }

    var body: some View {
        @Bindable var navigator = shellNavigator

        NavigationStack(path: $navigator.messagesDetailPath) {
            VStack(spacing: 0) {
                if showsProvidersSegment {
                    Picker("Chats", selection: $selectedSegment) {
                        ForEach(ProviderChatsInboxSegment.allCases) { segment in
                            Text(segment.title).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }

                Group {
                    switch selectedSegment {
                    case .clients:
                        ProviderChatInboxScreen(
                            reloadToken: inboxReloadToken,
                            onConversationsUpdated: { rows in
                                conversations = rows
                            }
                        )
                    case .providers:
                        ProviderBarberChatsRosterView { row in
                            supplementalConversations[row.id] = row
                            navigator.messagesDetailPath.append(row.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .providerNavigationStackDestinationBackdrop(style: .neutralGrey)
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedSegment == .clients {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingBlockedUsers = true
                        } label: {
                            Image(systemName: "person.crop.circle.badge.minus")
                        }
                        .accessibilityLabel("Blocked Users")
                    }
                }
            }
            .navigationDestination(for: Int.self) { conversationId in
                if let conversation = conversation(for: conversationId) {
                    ProviderChatDetailHost(
                        conversation: conversation,
                        barberTableId: session.barberProfile?.id,
                        onNavigateBack: {
                            guard !navigator.messagesDetailPath.isEmpty else { return }
                            navigator.messagesDetailPath.removeLast()
                        },
                        onBlocked: {
                            navigator.messagesDetailPath = []
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

    private func conversation(for conversationId: Int) -> ConversationRow? {
        conversations.first(where: { $0.id == conversationId })
            ?? supplementalConversations[conversationId]
    }

    private func loadConversationsForDeepLink(conversationId: Int) async {
        ProviderConversationMessagesPrefetch.prefetch(conversationId: conversationId)
        guard let rows = try? await ProviderMessagesService.listConversations() else { return }
        conversations = rows
        if let match = rows.first(where: { $0.id == conversationId }) {
            supplementalConversations[conversationId] = match
        }
    }
}
