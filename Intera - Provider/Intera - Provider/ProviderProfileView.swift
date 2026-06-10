import SwiftUI

/// Account screen: native **UIKit** profile editor (web parity) + quick account actions.
struct ProviderProfileContent: View {
    @Environment(ProviderSession.self) private var session

    var body: some View {
        ProviderProfileEditViewRepresentable()
            .environment(session)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
            }
    }
}

struct ProviderProfileView: View {
    var body: some View {
        NavigationStack {
            ProviderProfileContent()
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
    }
}
