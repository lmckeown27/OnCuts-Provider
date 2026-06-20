import SwiftUI
import UIKit

// MARK: - Adaptive colors (light + dark)

/// Semantic colors that resolve per `UIUserInterfaceStyle`.
enum ProviderAppearance {
    // MARK: UIColor (UIKit + dynamic Color)

    private static let cream = UIColor(red: 245 / 255, green: 245 / 255, blue: 220 / 255, alpha: 1)
    private static let creamSecondary = UIColor(red: 245 / 255, green: 245 / 255, blue: 220 / 255, alpha: 0.82)
    private static let creamTertiary = UIColor(red: 245 / 255, green: 245 / 255, blue: 220 / 255, alpha: 0.64)

    private static let ink = UIColor(red: 26 / 255, green: 28 / 255, blue: 38 / 255, alpha: 1)
    private static let inkSecondary = UIColor(red: 26 / 255, green: 28 / 255, blue: 38 / 255, alpha: 0.72)
    private static let inkTertiary = UIColor(red: 26 / 255, green: 28 / 255, blue: 38 / 255, alpha: 0.52)

    static let primaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark ? cream : ink
    }

    static let secondaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark ? creamSecondary : inkSecondary
    }

    static let tertiaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark ? creamTertiary : inkTertiary
    }

    /// Primary screen background — white in light mode, dark in dark mode.
    static let shellBase = UIColor.systemBackground

    /// Grouped list / inbox background — light grey in light mode, elevated dark in dark mode.
    static let groupedShellBase = UIColor.secondarySystemGroupedBackground

    static let neutralPushedBackdrop = groupedShellBase

    static let elevatedSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.06)
    }

    static let elevatedSurfaceStroke = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.10)
    }

    static let separator = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor.black.withAlphaComponent(0.12)
    }

    static let olive = UIColor(red: 90 / 255, green: 114 / 255, blue: 104 / 255, alpha: 1)
    /// Light green for unread / new-message affordances (`#A8E5BC`).
    static let messageUnreadAccent = UIColor(red: 0xA8 / 255, green: 0xE5 / 255, blue: 0xBC / 255, alpha: 1)
    /// Olive **text** fill — matches Intera `Color.oliveGreen` (`#849E92` / `#556860`).
    static let inboxMessageOlive = ProviderOliveGreenTextStyle.fillUIColor
    static let oliveFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 90 / 255, green: 114 / 255, blue: 104 / 255, alpha: 0.92)
            : UIColor(red: 90 / 255, green: 114 / 255, blue: 104 / 255, alpha: 1)
    }

    static let segmentedNormalTitle = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.7)
            : inkSecondary
    }

    static let segmentedSelectedTitle = UIColor { traits in
        traits.userInterfaceStyle == .dark ? cream : UIColor.white
    }

    static let segmentedBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.06)
    }

    // MARK: Schedule hub (Daily / Weekly / Monthly)

    /// Mode rail, date row, and similar grouped controls on the main schedule page.
    static let scheduleTrackFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.42)
            : UIColor(red: 248 / 255, green: 248 / 255, blue: 252 / 255, alpha: 1)
    }

    static let scheduleTrackStroke = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.22)
            : UIColor.black.withAlphaComponent(0.07)
    }

    /// Opaque fill for floating appointment move / confirm prompts over the schedule.
    static let schedulePromptCardFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 26 / 255, green: 28 / 255, blue: 38 / 255, alpha: 1)
            : UIColor(red: 244 / 255, green: 244 / 255, blue: 248 / 255, alpha: 1)
    }

    /// Day rows, time slots, availability wells, and other schedule cards.
    static let scheduleCardFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.38)
            : UIColor(red: 244 / 255, green: 244 / 255, blue: 248 / 255, alpha: 1)
    }

    static let scheduleCardStroke = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.2)
            : UIColor.black.withAlphaComponent(0.06)
    }

    /// Date chevrons, secondary actions, and compact circular controls.
    static let scheduleControlFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.52)
            : UIColor(red: 250 / 255, green: 250 / 255, blue: 253 / 255, alpha: 1)
    }

    static let scheduleControlStroke = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.22)
            : UIColor.black.withAlphaComponent(0.08)
    }

    // MARK: SwiftUI

    static var isDarkMode: Bool {
        UITraitCollection.current.userInterfaceStyle == .dark
    }

    static func configureGlobalUIKitAppearance() {
        UITableView.appearance().backgroundColor = .clear
        UITableView.appearance().separatorColor = separator

        UICollectionView.appearance().backgroundColor = .clear
        UITabBar.appearance().isTranslucent = true

        ProviderTypography.configureGlobalUIKitAppearance()

        let seg = UISegmentedControl.appearance()
        seg.backgroundColor = segmentedBackground
        seg.selectedSegmentTintColor = oliveFill
    }
}

// MARK: - SwiftUI aliases (backward compatible)

extension Color {
    /// Primary foreground — light ink in light mode, cream in dark mode.
    static var lavaShellCream: Color { Color(uiColor: ProviderAppearance.primaryText) }
    static var lavaShellCreamSecondary: Color { Color(uiColor: ProviderAppearance.secondaryText) }
    static var lavaShellCreamTertiary: Color { Color(uiColor: ProviderAppearance.tertiaryText) }

    static var providerElevatedSurface: Color { Color(uiColor: ProviderAppearance.elevatedSurface) }
    static var providerElevatedSurfaceStroke: Color { Color(uiColor: ProviderAppearance.elevatedSurfaceStroke) }

    static var providerNeutralPushedBackdrop: Color { Color(uiColor: ProviderAppearance.neutralPushedBackdrop) }

    /// Messaging accent blue (`#3A86FF`) — today's appointment highlights in inbox cards.
    static var providerBrandAccent: Color {
        Color(red: 58 / 255, green: 134 / 255, blue: 255 / 255)
    }

    /// Light green for unread / new-message badges and ribbons (`#A8E5BC`).
    static var providerMessageUnreadAccent: Color { Color(uiColor: ProviderAppearance.messageUnreadAccent) }

    /// Olive **text** fill (`#849E92` light / `#556860` dark). Prefer ``View/foregroundStyleProviderOliveGreen(opacity:)`` for glyphs.
    static var oliveGreen: Color { Color(uiColor: ProviderOliveGreenTextStyle.fillUIColor) }

    /// Olive inbox preview text — alias of ``oliveGreen`` for legacy call sites.
    static var providerInboxMessageOlive: Color { oliveGreen }

    static var providerFormGroupedBackground: Color {
        Color(uiColor: ProviderAppearance.groupedShellBase)
    }

    static var providerScheduleTrackFill: Color { Color(uiColor: ProviderAppearance.scheduleTrackFill) }
    static var providerScheduleTrackStroke: Color { Color(uiColor: ProviderAppearance.scheduleTrackStroke) }
    static var providerScheduleCardFill: Color { Color(uiColor: ProviderAppearance.scheduleCardFill) }
    static var providerSchedulePromptCardFill: Color { Color(uiColor: ProviderAppearance.schedulePromptCardFill) }
    static var providerScheduleCardStroke: Color { Color(uiColor: ProviderAppearance.scheduleCardStroke) }
    static var providerScheduleControlFill: Color { Color(uiColor: ProviderAppearance.scheduleControlFill) }
    static var providerScheduleControlStroke: Color { Color(uiColor: ProviderAppearance.scheduleControlStroke) }
}
