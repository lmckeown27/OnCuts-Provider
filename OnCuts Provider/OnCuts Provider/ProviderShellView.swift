import SwiftUI

/// Entry point for the signed-in provider experience (header + schedule hub + pushed messages / bookings).
struct ProviderShellView: View {
    var body: some View {
        ProviderDashboardShellView()
            .environment(ProviderShellNavigationAppearance.shared)
    }
}
