import SwiftUI

/// Standalone messages stack (previously a tab). Prefer **`ProviderMessagesInboxView`** inside **`ProviderDashboardShellView`**.
struct ProviderConversationsView: View {
    var body: some View {
        NavigationStack {
            ProviderMessagesInboxView()
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
    }
}
