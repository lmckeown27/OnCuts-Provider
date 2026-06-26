import SwiftUI
import UIKit

// MARK: - Standard provider text styling

/// Legacy entry points for olive outlined copy now resolve to the platform's standard adaptive text color.
enum ProviderOliveGreenTextStyle {
    static func attributedString(_ text: String, font: UIFont, opacity: CGFloat = 1) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: ProviderAppearance.primaryText.withAlphaComponent(opacity),
        ])
    }
}

// MARK: - UIKit label

/// Multi-line UIKit label using standard provider text color.
final class ProviderOutlinedOliveGreenLabel: UILabel {
    func setOutlinedText(_ text: String, font: UIFont, opacity: CGFloat = 1) {
        self.font = font
        textColor = ProviderAppearance.primaryText.withAlphaComponent(opacity)
        self.text = text
    }
}

// MARK: - View API

extension View {
    func providerOliveGreenTextOutline(
        when isEnabled: Bool = true,
        width: CGFloat = 0
    ) -> some View {
        self
    }

    /// Standard adaptive body text. Do not use on SF Symbols.
    func foregroundStyleProviderOliveGreen(opacity: Double = 1) -> some View {
        foregroundStyle(Color.lavaShellCream.opacity(opacity))
    }

    /// Shell icon tint for SF Symbols.
    func foregroundStyleProviderShellIcon(opacity: Double = 1) -> some View {
        foregroundStyle(Color.lavaShellCreamSecondary.opacity(opacity))
    }

    /// Backward-compatible alias for standard body text.
    func providerOliveOutlined() -> some View {
        foregroundStyleProviderOliveGreen()
    }
}
