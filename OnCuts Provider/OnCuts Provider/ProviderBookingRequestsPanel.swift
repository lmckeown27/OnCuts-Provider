import SwiftUI

/// Pending **booking requests** only (legacy standalone surface). Prefer the header **Requests** tray via **`ProviderRequestsInboxView`**.
struct ProviderBookingRequestsPanel: View {
    var body: some View {
        ProviderRequestsInboxContent(mode: .requestsOnly)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
    }
}
