import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Backdrop + UIKit nav underlay while the dashboard shows a pushed screen.
@MainActor
@Observable
final class ProviderShellNavigationAppearance {
    static let shared = ProviderShellNavigationAppearance()

    var navigationContainerBackdropStyle: ProviderNavigationStackDestinationBackdropStyle?

    private var containerBackdropApplyTask: Task<Void, Never>?

    func setContainerBackdrop(_ style: ProviderNavigationStackDestinationBackdropStyle) {
        containerBackdropApplyTask?.cancel()
        containerBackdropApplyTask = Task { @MainActor in
            navigationContainerBackdropStyle = style
            #if os(iOS)
            ProviderNavigationChromeBridge.applyContainerBackdropUIColor(style.uiColor)
            #endif
        }
    }

    func clearContainerBackdropImmediately() {
        containerBackdropApplyTask?.cancel()
        navigationContainerBackdropStyle = nil
        #if os(iOS)
        ProviderNavigationChromeBridge.clearContainerBackdrop()
        #endif
    }
}

#if os(iOS)
enum ProviderNavigationChromeBridge {
    static var containerBackdropUIColor: UIColor?

    static func applyContainerBackdropUIColor(_ color: UIColor) {
        containerBackdropUIColor = color
        applySynchronouslyFromKeyWindow()
    }

    static func clearContainerBackdrop() {
        containerBackdropUIColor = nil
        applySynchronouslyFromKeyWindow()
    }

    static func applySynchronouslyFromKeyWindow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { applySynchronouslyFromKeyWindow() }
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              let root = window.rootViewController?.view
        else { return }
        ProviderHubPageViewControllerSurfaceTint.applyRecursively(from: root)
    }
}
#endif

extension ProviderNavigationStackDestinationBackdropStyle {
    var uiColor: UIColor {
        switch self {
        case .shell:
            ProviderAppearance.shellBase
        case .neutralGrey:
            ProviderAppearance.groupedShellBase
        }
    }

    var containerColor: Color {
        Color(uiColor: uiColor)
    }
}
