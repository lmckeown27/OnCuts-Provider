import SwiftUI
import UIKit

/// App-wide Clarendon typography (Super Clarendon on iOS).
enum ProviderTypography {
    enum Clarendon {
        static let regular = "Superclarendon-Regular"
        static let light = "Superclarendon-Light"
        static let bold = "Superclarendon-Bold"
        static let black = "Superclarendon-Black"
        static let italic = "Superclarendon-Italic"
    }

    // MARK: - SwiftUI

    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom(swiftFaceName(for: weight), size: swiftSize(for: style), relativeTo: style)
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(swiftFaceName(for: weight), size: size, relativeTo: style)
    }

    // MARK: - UIKit

    static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) -> UIFont {
        let face = uiFaceName(for: weight)
        guard let base = UIFont(name: face, size: size) else {
            return UIFont.systemFont(ofSize: size, weight: weight)
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
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

    private static func swiftFaceName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light:
            return Clarendon.light
        case .semibold, .bold, .heavy:
            return Clarendon.bold
        case .black:
            return Clarendon.black
        default:
            return Clarendon.regular
        }
    }

    private static func uiFaceName(for weight: UIFont.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light:
            return Clarendon.light
        case .semibold, .bold, .heavy:
            return Clarendon.bold
        case .black:
            return Clarendon.black
        default:
            return Clarendon.regular
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

extension UIFont {
    static func provider(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) -> UIFont {
        ProviderTypography.uiFont(size: size, weight: weight, textStyle: textStyle)
    }

    static func providerPreferred(forTextStyle style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        ProviderTypography.preferredUIFont(forTextStyle: style, weight: weight)
    }
}
