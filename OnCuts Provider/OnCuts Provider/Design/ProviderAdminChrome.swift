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
}
