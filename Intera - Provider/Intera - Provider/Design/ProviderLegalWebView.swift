import SwiftUI
import WebKit

/// In-app legal page viewer. Loads the requested URL explicitly (unlike `SFSafariViewController`,
/// which cannot change URLs after creation and is sensitive to SwiftUI sheet reuse).
struct ProviderLegalWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        context.coordinator.lastLoadedURL = url
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLoadedURL != url else { return }
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator {
        var lastLoadedURL: URL?
    }
}
