import SwiftUI

/// Signed-out auth surfaces — solid brand olive backdrop with gold/cream accents.
private struct ProviderAuthIntegratedBackground: View {
    var body: some View {
        Color.providerOlive
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}

private struct ProviderAuthIntegratedScreenChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            ProviderAuthIntegratedBackground()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS) || os(visionOS) || os(macOS)
        .onCutsNavigationShellBackgroundClear()
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }
}

extension View {
    func providerAuthIntegratedScreenChrome() -> some View {
        modifier(ProviderAuthIntegratedScreenChromeModifier())
    }

    /// Typed text on olive auth fields — light ink without toggling keyboard appearance.
    func providerAuthOliveFieldInk() -> some View {
        foregroundStyle(Color.providerOnOliveFill)
            .tint(Color.providerBrandGold)
            // Lock the field (and its keyboard) to dark so light-mode UITextField
            // does not keep swapping system-black ink / light keyboard.
            .colorScheme(.dark)
    }
}

