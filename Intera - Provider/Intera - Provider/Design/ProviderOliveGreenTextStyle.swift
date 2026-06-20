import SwiftUI
import UIKit

// MARK: - Olive green text (Intera-aligned)

/// Central styling for readable olive **copy** on the provider shell.
/// For SF Symbols and chrome tints, use ``View/foregroundStyleProviderShellIcon()`` instead.
enum ProviderOliveGreenTextStyle {
    /// Negative stroke width draws an outline around the fill (UIKit attributed-string technique).
    static let uiKitOutlineStrokeWidth: CGFloat = -0.85
    /// Shadow offset for SwiftUI `Text` / symbol outlines.
    static let swiftUIOutlineWidth: CGFloat = 0.22
    /// Outline strength (shadow / stroke reads lighter below 1).
    static let outlineOpacity: CGFloat = 0.72

    /// Adaptive olive fill — `#849E92` light / `#556860` dark.
    static var fillUIColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 85 / 255, green: 104 / 255, blue: 96 / 255, alpha: 1)
                : UIColor(red: 132 / 255, green: 158 / 255, blue: 146 / 255, alpha: 1)
        }
    }

    static var outlineUIColor: UIColor {
        UIColor { traits in
            let base = traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
            return base.withAlphaComponent(outlineOpacity)
        }
    }

    static func outlineColor(for colorScheme: ColorScheme) -> Color {
        (colorScheme == .dark ? Color.white : Color.black)
            .opacity(Double(outlineOpacity))
    }

    static func bumpedDynamicTypeSize(from size: DynamicTypeSize) -> DynamicTypeSize {
        switch size {
        case .xSmall: return .small
        case .small: return .medium
        case .medium: return .large
        case .large: return .xLarge
        case .xLarge: return .xxLarge
        case .xxLarge: return .xxxLarge
        case .xxxLarge: return .accessibility1
        case .accessibility1: return .accessibility2
        case .accessibility2: return .accessibility3
        case .accessibility3: return .accessibility4
        case .accessibility4: return .accessibility5
        case .accessibility5: return .accessibility5
        @unknown default: return size
        }
    }

    static func bumpedUIFont(_ font: UIFont) -> UIFont {
        UIFont(descriptor: font.fontDescriptor, size: font.pointSize * 1.06)
    }

    static func attributedString(_ text: String, font: UIFont, opacity: CGFloat = 1) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: bumpedUIFont(font),
            .foregroundColor: fillUIColor.withAlphaComponent(opacity),
            .strokeColor: outlineUIColor,
            .strokeWidth: uiKitOutlineStrokeWidth,
        ])
    }
}

// MARK: - SwiftUI outline ring

private struct ProviderOliveGreenTextOutlineModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let width: CGFloat
    let isEnabled: Bool

    private var outlineColor: Color {
        ProviderOliveGreenTextStyle.outlineColor(for: colorScheme)
    }

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .dynamicTypeSize(ProviderOliveGreenTextStyle.bumpedDynamicTypeSize(from: dynamicTypeSize))
                .shadow(color: outlineColor, radius: 0, x: -width, y: 0)
                .shadow(color: outlineColor, radius: 0, x: width, y: 0)
                .shadow(color: outlineColor, radius: 0, x: 0, y: -width)
                .shadow(color: outlineColor, radius: 0, x: 0, y: width)
                .shadow(color: outlineColor, radius: 0, x: -width, y: -width)
                .shadow(color: outlineColor, radius: 0, x: width, y: -width)
                .shadow(color: outlineColor, radius: 0, x: -width, y: width)
                .shadow(color: outlineColor, radius: 0, x: width, y: width)
        } else {
            content
        }
    }
}

// MARK: - UIKit label

/// Multi-line UIKit label with Intera-matched outlined olive text.
final class ProviderOutlinedOliveGreenLabel: UILabel {
    func setOutlinedText(_ text: String, font: UIFont, opacity: CGFloat = 1) {
        attributedText = ProviderOliveGreenTextStyle.attributedString(text, font: font, opacity: opacity)
    }
}

// MARK: - View API

extension View {
    func providerOliveGreenTextOutline(
        when isEnabled: Bool = true,
        width: CGFloat = ProviderOliveGreenTextStyle.swiftUIOutlineWidth
    ) -> some View {
        modifier(ProviderOliveGreenTextOutlineModifier(width: width, isEnabled: isEnabled))
    }

    /// Olive **text** fill plus adaptive outline. Do not use on SF Symbols.
    func foregroundStyleProviderOliveGreen(opacity: Double = 1) -> some View {
        foregroundStyle(Color.oliveGreen.opacity(opacity))
            .providerOliveGreenTextOutline()
    }

    /// Shell icon tint for SF Symbols — no olive outline.
    func foregroundStyleProviderShellIcon(opacity: Double = 1) -> some View {
        foregroundStyle(Color.lavaShellCreamSecondary.opacity(opacity))
    }

    /// Backward-compatible alias for outlined olive text.
    func providerOliveOutlined() -> some View {
        foregroundStyleProviderOliveGreen()
    }
}
