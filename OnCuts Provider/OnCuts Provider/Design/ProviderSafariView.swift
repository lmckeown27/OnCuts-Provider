import SafariServices
import SwiftUI

/// Shared `SFSafariViewController` wrapper for in-app web fallbacks (Google Calendar OAuth, deeper
/// Admin / Campus-Manager flows that don't have native iOS parity yet, etc.). Lives in `Design/`
/// because it's a UI primitive, not a network service.
struct ProviderSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        cfg.barCollapsingEnabled = true
        return SFSafariViewController(url: url, configuration: cfg)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {
        // `SFSafariViewController` cannot change its initial URL after creation.
        // Callers must use `.id(url.absoluteString)` (or an enum id) so SwiftUI rebuilds
        // the representable when presenting a different legal page in the same sheet.
    }
}
