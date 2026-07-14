import SwiftUI

struct ProviderChatView: View {
    let conversation: ConversationRow
    @State private var messages: [ChatMessageDTO] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var errorAlert: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { msg in
                            bubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .scrollContentBackground(.hidden)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider().opacity(0.35)
            HStack {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.provider(.title2))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding()
        }
        .background(Color.clear)
        .providerNavigationStackDestinationBackdrop()
        .providerPageNavigationTitle(chatTitle)
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .task { await load() }
        .alert("Error", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
            Button("OK", role: .cancel) { errorAlert = nil }
        } message: { Text(errorAlert ?? "") }
    }

    private var chatTitle: String {
        if let d = conversation.otherUser?.displayName, !d.isEmpty { return d }
        let f = conversation.otherUser?.firstName ?? ""
        let l = conversation.otherUser?.lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "Chat" : joined
    }

    @ViewBuilder
    private func bubble(_ msg: ChatMessageDTO) -> some View {
        let own = msg.isOwn == true
        HStack {
            if own { Spacer(minLength: 40) }
            Text(msg.content ?? "")
                .padding(10)
                .foregroundStyle(Color.lavaShellCream)
                .background(own ? Color.providerOlive.opacity(0.35) : Color.lavaShellCream.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            if !own { Spacer(minLength: 40) }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try? await ProviderMessagesService.markRead(conversationId: conversation.id)
            messages = try await ProviderMessagesService.listMessages(conversationId: conversation.id)
        } catch {
            errorAlert = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await ProviderMessagesService.sendText(conversationId: conversation.id, text: text)
            draft = ""
            await load()
        } catch {
            errorAlert = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}
