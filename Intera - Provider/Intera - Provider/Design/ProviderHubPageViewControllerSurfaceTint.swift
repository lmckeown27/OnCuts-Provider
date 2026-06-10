#if os(iOS)
import SwiftUI
import UIKit

/// Clears opaque UIKit fills on the root host; paints `UINavigationController.view` to match the active
/// shell container backdrop so push/pop gaps never show window lava.
enum ProviderHubPageViewControllerSurfaceTint {
    static func applyRecursively(from root: UIView) {
        clearTabAndNavigationChrome(window: root.window)
    }

    static func applyFromKeyWindow() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
                  let root = window.rootViewController?.view
            else { return }
            applyRecursively(from: root)
        }
    }

    private static func clearTabAndNavigationChrome(window: UIWindow?) {
        guard let host = window?.rootViewController else { return }
        host.view.backgroundColor = .clear
        host.view.isOpaque = false

        let underlay = ProviderNavigationChromeBridge.containerBackdropUIColor
        for nav in allNavigationControllers(under: host) {
            if let underlay {
                nav.view.backgroundColor = underlay
                nav.view.isOpaque = true
            } else {
                nav.view.backgroundColor = .clear
                nav.view.isOpaque = false
            }
            nav.navigationBar.isTranslucent = true
            for child in nav.viewControllers {
                child.view.backgroundColor = .clear
                child.view.isOpaque = false
            }
        }

        guard let tab = firstTabBarController(under: host) else { return }
        tab.view.backgroundColor = .clear
        tab.view.isOpaque = false
        for vc in tab.viewControllers ?? [] {
            vc.view.backgroundColor = .clear
            vc.view.isOpaque = false
            if let nav = vc as? UINavigationController, underlay == nil {
                nav.view.backgroundColor = .clear
                nav.view.isOpaque = false
                for child in nav.viewControllers {
                    child.view.backgroundColor = .clear
                    child.view.isOpaque = false
                }
            }
        }
    }

    private static func allNavigationControllers(under root: UIViewController) -> [UINavigationController] {
        var result: [UINavigationController] = []
        func visit(_ vc: UIViewController) {
            if let nav = vc as? UINavigationController {
                result.append(nav)
            }
            for child in vc.children {
                visit(child)
            }
            if let presented = vc.presentedViewController {
                visit(presented)
            }
        }
        visit(root)
        return result
    }

    private static func firstTabBarController(under root: UIViewController) -> UITabBarController? {
        if let t = root as? UITabBarController { return t }
        for child in root.children {
            if let t = firstTabBarController(under: child) { return t }
        }
        return nil
    }
}

private final class ProviderTabPagingTintAnchorView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        ProviderNavigationChromeBridge.applySynchronouslyFromKeyWindow()
    }
}

struct ProviderHubPagingChromeTint: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        ProviderTabPagingTintAnchorView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
