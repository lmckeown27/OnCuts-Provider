import UIKit

// MARK: - Intera Provider Chat design tokens

enum ProviderChatDesignTokens {
    enum Color {
        static let brandPrimary = UIColor(red: 0x1A / 255, green: 0x1A / 255, blue: 0x2E / 255, alpha: 1)
        static let brandAccent = UIColor(red: 0x3A / 255, green: 0x86 / 255, blue: 0xFF / 255, alpha: 1)
        static let providerOlive = ProviderAppearance.olive
        static let lavaShellCream = ProviderAppearance.primaryText
        static let lavaShellCreamSecondary = ProviderAppearance.secondaryText
        static let statusGreen = UIColor(red: 0x38 / 255, green: 0xB0 / 255, blue: 0x00 / 255, alpha: 1)
        static let statusYellow = UIColor(red: 0xFF / 255, green: 0xB7 / 255, blue: 0x03 / 255, alpha: 1)

        static let screenBackground = ProviderAppearance.shellBase
        static let inboxBackdrop = ProviderAppearance.neutralPushedBackdrop
        static let cardBackground = ProviderAppearance.elevatedSurface
        static let consumerBubble = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.24, alpha: 1)
                : UIColor(white: 0.96, alpha: 1)
        }
        static let previewText = ProviderAppearance.secondaryText
        static let timestampText = ProviderAppearance.tertiaryText
        static let separator = ProviderAppearance.separator

        static let chatSentDarkGreen = UIColor(red: 0x3D / 255, green: 0x85 / 255, blue: 0x59 / 255, alpha: 1)
        static let chatReceivedLightGreen = ProviderAppearance.messageUnreadAccent

        /// Composer text field fill — faint in dark mode, solid grouped fill in light mode.
        static let composerFieldBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.secondarySystemBackground
        }

        static let composerFieldBorder = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.14)
                : UIColor.separator
        }

        static let conversationRowSelection = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.06)
                : UIColor.black.withAlphaComponent(0.05)
        }

        /// Provider-authored message bubble — olive in both light and dark mode.
        static let providerSentBubble = ProviderAppearance.olive

        static let providerSentBubbleText = UIColor.white

        /// Consumer-authored message bubble label.
        static let consumerBubbleText = ProviderAppearance.primaryText
    }

    enum Font {
        static func heading(_ size: CGFloat = 17) -> UIFont {
            .provider(size: size, weight: .bold, textStyle: .headline)
        }

        static func body(_ size: CGFloat = 15) -> UIFont {
            .provider(size: size, weight: .regular, textStyle: .body)
        }

        static func caption(_ size: CGFloat = 12) -> UIFont {
            .provider(size: size, weight: .medium, textStyle: .caption1)
        }

        static func badge(_ size: CGFloat = 11) -> UIFont {
            .provider(size: size, weight: .semibold, textStyle: .caption2)
        }
    }

    enum Metrics {
        static let horizontalPadding: CGFloat = 16
        static let bubbleCornerRadius: CGFloat = 16
        static let cardCornerRadius: CGFloat = 14
        static let avatarSize: CGFloat = 48
        static let onlineDotSize: CGFloat = 11
        static let conversationStatusBadgeCornerRadius: CGFloat = 12
        static let conversationStatusBadgePaddingH: CGFloat = 12
        static let conversationStatusBadgePaddingV: CGFloat = 7
        static let conversationStatusBadgeMinHeight: CGFloat = 32
        static let inputBarExtraBottomPadding: CGFloat = 12
        static let inputBarMinContentHeight: CGFloat = 56
        static let inputBarMaxContentHeight: CGFloat = 120
        static let composerAttachmentSize: CGFloat = 34
        static let messageImageHeight: CGFloat = 180
        static let inboxPreviewCornerRadius: CGFloat = 12
        static let inboxPreviewPaddingH: CGFloat = 10
        static let inboxPreviewPaddingV: CGFloat = 5
        /// Space between the thread header and the first message bubble.
        static let messageListTopPadding: CGFloat = 16
    }

    static func composerTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: Font.body(15),
            .foregroundColor: Color.lavaShellCream,
        ]
    }
}
