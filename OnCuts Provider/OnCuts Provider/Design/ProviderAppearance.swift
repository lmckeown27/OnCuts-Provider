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
    /// Standard adaptive body text on provider surfaces.
    static let inboxMessageOlive = ProviderAppearance.primaryText
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

    /// Weekly grid canvas, time gutter, and day header row backdrop.
    static let scheduleGridBackground = shellBase

    /// Labels drawn on saturated booking fills (pending yellow, etc.).
    /// Dark mode uses pure white — cream reads too muted on those fills.
    static let scheduleAppointmentPrimaryLabel = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : ink
    }

    static let scheduleAppointmentSecondaryLabel = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.92)
            : inkSecondary
    }

    static let scheduleAppointmentTertiaryLabel = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.8)
            : inkTertiary
    }

    /// Web parity action pills (`Edit Schedule`, `Block Time`) — white in light, elevated in dark.
    static let scheduleActionBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.white
    }

    static let scheduleActionForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? cream
            : UIColor(red: 55 / 255, green: 65 / 255, blue: 81 / 255, alpha: 1)
    }

    static let scheduleActionBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.22)
            : UIColor(red: 209 / 255, green: 213 / 255, blue: 219 / 255, alpha: 1)
    }

    static let scheduleActionShadow = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.45)
            : UIColor.black.withAlphaComponent(0.08)
    }

    /// Day column headers — gray-100 / elevated dark.
    static let scheduleDayHeaderFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1)
    }

    static let scheduleDayHeaderForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? creamSecondary
            : UIColor(red: 55 / 255, green: 65 / 255, blue: 81 / 255, alpha: 1)
    }

    /// Today column header — gray-900 in light, inverted cream pill in dark.
    static let scheduleDayHeaderTodayFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? cream.withAlphaComponent(0.92)
            : UIColor(red: 17 / 255, green: 24 / 255, blue: 39 / 255, alpha: 1)
    }

    static let scheduleDayHeaderTodayForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? ink : UIColor.white
    }

    /// Open availability slots and upcoming appointment fills.
    static let scheduleOpenSlotFill = UIColor { traits in
        let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.48 : 0.55
        return olive.withAlphaComponent(alpha)
    }

    static let scheduleUpcomingAppointmentFill = scheduleOpenSlotFill

    static let scheduleCompletedAppointmentFill = UIColor { traits in
        let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.42 : 0.35
        return UIColor.systemGreen.withAlphaComponent(alpha)
    }

    static let scheduleBlockedSlotFill = UIColor { traits in
        let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.50 : 0.55
        return UIColor.systemRed.withAlphaComponent(alpha)
    }

    static let scheduleTodayColumnHighlight = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? olive.withAlphaComponent(0.16)
            : olive.withAlphaComponent(0.08)
    }

    /// Entire-day cross-out overlay on unselected availability days.
    static let scheduleEntireDayCrossOutFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.04)
            : olive.withAlphaComponent(0.06)
    }

    static let scheduleEntireDayCrossOutStroke = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : olive.withAlphaComponent(0.24)
    }

    static let scheduleEntireDayCrossOutLine = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? creamSecondary.withAlphaComponent(0.28)
            : olive.withAlphaComponent(0.44)
    }

    static let scheduleDiagonalCrossOutLineBlocked = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? creamSecondary.withAlphaComponent(0.34)
            : inkSecondary.withAlphaComponent(0.38)
    }

    static let scheduleDiagonalCrossOutLineGoogle = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? creamSecondary.withAlphaComponent(0.26)
            : inkSecondary.withAlphaComponent(0.32)
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

    /// Standard adaptive body text (`lavaShellCream` / ink).
    static var oliveGreen: Color { lavaShellCream }

    /// Inbox preview text — alias of secondary body text for legacy call sites.
    static var providerInboxMessageOlive: Color { lavaShellCreamSecondary }

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

    static var providerScheduleGridBackground: Color { Color(uiColor: ProviderAppearance.scheduleGridBackground) }

    /// Primary / secondary text on colored booking blocks.
    static var providerScheduleAppointmentPrimaryLabel: Color {
        Color(uiColor: ProviderAppearance.scheduleAppointmentPrimaryLabel)
    }
    static var providerScheduleAppointmentSecondaryLabel: Color {
        Color(uiColor: ProviderAppearance.scheduleAppointmentSecondaryLabel)
    }
    static var providerScheduleAppointmentTertiaryLabel: Color {
        Color(uiColor: ProviderAppearance.scheduleAppointmentTertiaryLabel)
    }

    /// Schedule action pills (`Edit Schedule`, `Block Time`).
    static var providerScheduleActionBackground: Color { Color(uiColor: ProviderAppearance.scheduleActionBackground) }
    static var providerScheduleActionForeground: Color { Color(uiColor: ProviderAppearance.scheduleActionForeground) }
    static var providerScheduleActionBorder: Color { Color(uiColor: ProviderAppearance.scheduleActionBorder) }
    static var providerScheduleActionShadow: Color { Color(uiColor: ProviderAppearance.scheduleActionShadow) }

    /// Schedule day column headers.
    static var providerScheduleDayHeaderFill: Color { Color(uiColor: ProviderAppearance.scheduleDayHeaderFill) }
    static var providerScheduleDayHeaderForeground: Color { Color(uiColor: ProviderAppearance.scheduleDayHeaderForeground) }
    static var providerScheduleDayHeaderTodayFill: Color { Color(uiColor: ProviderAppearance.scheduleDayHeaderTodayFill) }
    static var providerScheduleDayHeaderTodayForeground: Color { Color(uiColor: ProviderAppearance.scheduleDayHeaderTodayForeground) }

    static var providerScheduleOpenSlotFill: Color { Color(uiColor: ProviderAppearance.scheduleOpenSlotFill) }
    static var providerScheduleUpcomingAppointmentFill: Color { Color(uiColor: ProviderAppearance.scheduleUpcomingAppointmentFill) }
    static var providerScheduleCompletedAppointmentFill: Color { Color(uiColor: ProviderAppearance.scheduleCompletedAppointmentFill) }
    static var providerScheduleBlockedSlotFill: Color { Color(uiColor: ProviderAppearance.scheduleBlockedSlotFill) }
    static var providerScheduleTodayColumnHighlight: Color { Color(uiColor: ProviderAppearance.scheduleTodayColumnHighlight) }

    static var providerScheduleEntireDayCrossOutFill: Color { Color(uiColor: ProviderAppearance.scheduleEntireDayCrossOutFill) }
    static var providerScheduleEntireDayCrossOutStroke: Color { Color(uiColor: ProviderAppearance.scheduleEntireDayCrossOutStroke) }
    static var providerScheduleEntireDayCrossOutLine: Color { Color(uiColor: ProviderAppearance.scheduleEntireDayCrossOutLine) }
    static var providerScheduleDiagonalCrossOutLineBlocked: Color { Color(uiColor: ProviderAppearance.scheduleDiagonalCrossOutLineBlocked) }
    static var providerScheduleDiagonalCrossOutLineGoogle: Color { Color(uiColor: ProviderAppearance.scheduleDiagonalCrossOutLineGoogle) }
}
