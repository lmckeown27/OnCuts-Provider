import SwiftUI

/// Account screen: SwiftUI barber control center.
struct ProviderProfileContent: View {
    var body: some View {
        BarberAccountControlView()
            .providerPageNavigationTitle("Account")
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
