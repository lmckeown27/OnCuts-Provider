import CoreText
import SwiftUI
import UIKit

/// App-wide Inter Variable typography.
enum ProviderTypography {
    enum InterVariable {
        /// PostScript name from bundled `InterVariable.ttf`.
        static let postScriptName = "InterVariable"
    }

    private static let variationAttribute = UIFontDescriptor.AttributeName(
        rawValue: kCTFontVariationAttribute as String
    )

    // MARK: - SwiftUI

    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        font(size: swiftSize(for: style), weight: weight, relativeTo: style)
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(InterVariable.postScriptName, size: size, relativeTo: style)
            .weight(weight)
    }

    // MARK: - UIKit

    static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) -> UIFont {
        guard let base = UIFont(name: InterVariable.postScriptName, size: size) else {
            return UIFont.systemFont(ofSize: size, weight: weight)
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            variationAttribute: ["wght": wghtAxis(for: weight)],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }

    static func preferredUIFont(forTextStyle style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let reference = UIFont.preferredFont(forTextStyle: style)
        return uiFont(size: reference.pointSize, weight: weight, textStyle: style)
    }

    static func configureGlobalUIKitAppearance() {
        let body = uiFont(size: 17, weight: .regular, textStyle: .body)
        let headline = uiFont(size: 17, weight: .bold, textStyle: .headline)
        let footnote = uiFont(size: 13, weight: .regular, textStyle: .footnote)
        let caption = uiFont(size: 12, weight: .regular, textStyle: .caption1)

        UILabel.appearance().font = body
        UITextField.appearance().font = body
        UITextView.appearance().font = body

        UIButton.appearance().titleLabel?.font = body

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [
            .font: headline,
            .foregroundColor: ProviderAppearance.primaryText,
        ]
        nav.largeTitleTextAttributes = [
            .font: uiFont(size: 34, weight: .bold, textStyle: .largeTitle),
            .foregroundColor: ProviderAppearance.primaryText,
        ]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = nav
        navBar.scrollEdgeAppearance = nav
        navBar.compactAppearance = nav
        navBar.compactScrollEdgeAppearance = nav

        let seg = UISegmentedControl.appearance()
        seg.setTitleTextAttributes([
            .font: footnote,
            .foregroundColor: ProviderAppearance.segmentedNormalTitle,
        ], for: .normal)
        seg.setTitleTextAttributes([
            .font: caption,
            .foregroundColor: ProviderAppearance.segmentedSelectedTitle,
        ], for: .selected)
    }

    // MARK: - Private

    private static func wghtAxis(for weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight, .thin: return 200
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }

    private static func wghtAxis(for weight: UIFont.Weight) -> CGFloat {
        switch weight {
        case .ultraLight, .thin: return 200
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }

    private static func swiftSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}

extension Font {
    static func provider(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        ProviderTypography.font(style, weight: weight)
    }

    static func provider(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        ProviderTypography.font(size: size, weight: weight, relativeTo: style)
    }
}

extension View {
    /// Shared inline nav title used by hub sheets and shell destinations (headline semibold principal).
    func providerPageNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.provider(.headline, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
    }
}

extension UIFont {
    static func provider(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) -> UIFont {
        ProviderTypography.uiFont(size: size, weight: weight, textStyle: textStyle)
    }

    static func providerPreferred(forTextStyle style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        ProviderTypography.preferredUIFont(forTextStyle: style, weight: weight)
    }
}
