import SwiftUI

/// Standalone requests list (previously a tab). Prefer the header **Requests** tray via **`ProviderRequestsInboxView`**.
struct ProviderRequestsListView: View {
    var body: some View {
        NavigationStack {
            ProviderBookingRequestsPanel()
                .providerPageNavigationTitle("Bookings")
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
    }
}
