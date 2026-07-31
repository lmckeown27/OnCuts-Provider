import SwiftUI
import UIKit

/// Adaptive Admin panel tokens — follow the device appearance (light/dark), not a static web stone theme.
enum ProviderAdminChrome {
    static var canvasBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var cardBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var border: Color { Color(uiColor: ProviderAppearance.elevatedSurfaceStroke) }
    static var mutedFill: Color { Color(uiColor: ProviderAppearance.elevatedSurface) }
    static var primaryText: Color { Color(uiColor: ProviderAppearance.primaryText) }
    static var secondaryText: Color { Color(uiColor: ProviderAppearance.secondaryText) }
    static var tertiaryText: Color { Color(uiColor: ProviderAppearance.tertiaryText) }
    static var destructive: Color { Color(uiColor: .systemRed) }
    static var accent: Color { Color.providerOlive }
    static var separator: Color { Color(uiColor: ProviderAppearance.separator) }

    /// Back-compat aliases used across Admin views.
    static var stoneBackground: Color { canvasBackground }
    static var stoneCard: Color { cardBackground }
    static var stoneBorder: Color { border }
    static var stoneMutedFill: Color { mutedFill }

    static let panelMaxWidth: CGFloat = 672
    static let panelCornerRadiusPhone: CGFloat = 22
    static let panelCornerRadiusPad: CGFloat = 24
}

extension View {
    /// Adaptive card surface used throughout the Admin panel.
    func providerAdminCardBackground(cornerRadius: CGFloat = 12) -> some View {
        background(
            ProviderAdminChrome.cardBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(ProviderAdminChrome.border, lineWidth: 1)
        )
    }

    /// Dismiss Admin keyboards on scroll and on taps outside the keyboard / text fields.
    ///
    /// Resign is always deferred to the next run-loop turn so we never re-enter SwiftUI
    /// layout mid-update (that path previously crashed Operators → Applications with
    /// `EXC_BAD_ACCESS` / stack overflow when resign ran synchronously from `onChange`).
    ///
    /// - Parameter onDismiss: Optional FocusState / local-state clear, also invoked async.
    func providerAdminDismissesKeyboardOnOutsideTap(
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        scrollDismissesKeyboard(.immediately)
            .background {
                ProviderAdminKeyboardDismissTapInstaller {
                    DispatchQueue.main.async {
                        onDismiss?()
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
    }
}

extension ProviderAdminChrome {
    static func dismissKeyboard() {
        // Always hop to the next run-loop turn so we never resign first responder
        // synchronously inside a SwiftUI `onChange` / gesture update.
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

/// Non-canceling window tap so Admin content / chrome taps dismiss the keyboard without
/// blocking buttons. Ignores taps that land on the keyboard or inside text inputs.
private struct ProviderAdminKeyboardDismissTapInstaller: UIViewRepresentable {
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        context.coordinator.beginObservingKeyboard()
        DispatchQueue.main.async {
            context.coordinator.install(from: probe)
        }
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.install(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDismiss: () -> Void
        private weak var installedOn: UIView?
        private var tap: UITapGestureRecognizer?
        private var keyboardFrameInScreen: CGRect = .null
        private var keyboardObservers: [NSObjectProtocol] = []

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func beginObservingKeyboard() {
            guard keyboardObservers.isEmpty else { return }
            let center = NotificationCenter.default
            keyboardObservers = [
                center.addObserver(
                    forName: UIResponder.keyboardWillChangeFrameNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    self?.updateKeyboardFrame(from: note)
                },
                center.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.keyboardFrameInScreen = .null
                },
            ]
        }

        func tearDown() {
            if let existing = tap {
                installedOn?.removeGestureRecognizer(existing)
            }
            tap = nil
            installedOn = nil
            for observer in keyboardObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            keyboardObservers = []
        }

        func install(from probe: UIView) {
            guard let hostView = Self.hostView(for: probe) else { return }
            guard installedOn !== hostView else { return }

            if let existing = tap {
                installedOn?.removeGestureRecognizer(existing)
            }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            hostView.addGestureRecognizer(recognizer)
            tap = recognizer
            installedOn = hostView
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            guard let hostView = installedOn else { return }
            let pointInHost = gesture.location(in: hostView)
            let pointInScreen = hostView.convert(pointInHost, to: nil)
            guard isTapAboveKeyboard(pointInScreen: pointInScreen) else { return }
            onDismiss()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            let pointInScreen = touch.location(in: nil)
            guard isTapAboveKeyboard(pointInScreen: pointInScreen) else { return false }

            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView {
                    return false
                }
                let typeName = String(describing: type(of: current))
                if typeName.contains("Keyboard")
                    || typeName.contains("InputSet")
                    || typeName.contains("UIRemoteKeyboard")
                    || typeName.contains("UITextEffects") {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func updateKeyboardFrame(from note: Notification) {
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }
            let screenBounds = UIScreen.main.bounds
            if frame.isEmpty || frame.minY >= screenBounds.maxY - 1 {
                keyboardFrameInScreen = .null
            } else {
                keyboardFrameInScreen = frame
            }
        }

        private func isTapAboveKeyboard(pointInScreen: CGPoint) -> Bool {
            guard !keyboardFrameInScreen.isNull, !keyboardFrameInScreen.isEmpty else {
                return true
            }
            return pointInScreen.y < keyboardFrameInScreen.minY - 0.5
        }

        private static func hostView(for probe: UIView) -> UIView? {
            // Prefer the window so taps on Admin chrome (header / tab bar) also dismiss.
            if let window = probe.window { return window }
            var ancestor: UIView? = probe.superview
            while let node = ancestor {
                if node.superview is UIWindow { return node }
                ancestor = node.superview
            }
            return probe.superview
        }
    }
}
