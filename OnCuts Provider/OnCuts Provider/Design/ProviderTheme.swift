import SwiftUI

extension Color {
    /// Brand olive for fills, borders, and tints (`#5A7268`). For **text**, use ``Color/lavaShellCream`` or ``View/foregroundStyleProviderOliveGreen(opacity:)``.
    static let providerOlive = Color(red: 90 / 255, green: 114 / 255, blue: 104 / 255)
    /// Premium gold accent for auth CTAs and highlights (`#D4AF37`).
    static let providerBrandGold = Color(red: 212 / 255, green: 175 / 255, blue: 55 / 255)
    /// Legible label on ``providerBrandGold`` fills.
    static let providerOnBrandGold = Color(red: 26 / 255, green: 28 / 255, blue: 38 / 255)
    /// Lighter sage green for secondary booking actions (e.g. Message) — same family as ``providerOlive``, lower contrast fill.
    static let providerOliveLight = Color(red: 168 / 255, green: 215 / 255, blue: 188 / 255)

    /// Legible copy on solid or tinted ``providerOlive`` fills — always light (never adaptive ink).
    static var providerOnOliveFill: Color { .white }
    static var providerOnOliveFillSecondary: Color { Color.white.opacity(0.85) }
    static var providerOnOliveFillTertiary: Color { Color.white.opacity(0.68) }
}

/// Adaptive olive pill / segment fills used on the home header and schedule zoom bar.
enum ProviderOliveChromeStyle {
    static func headerPillFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.providerOlive.opacity(0.35)
            : Color.providerOlive.opacity(0.92)
    }

    static func headerPillForeground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.lavaShellCream : Color.providerOnOliveFill
    }

    static func headerPillBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.lavaShellCream.opacity(0.35)
            : Color.providerOnOliveFillSecondary.opacity(0.45)
    }

    static func headerIconTint(_ colorScheme: ColorScheme) -> Color? {
        colorScheme == .dark ? nil : Color.providerOnOliveFill
    }

    static func zoomSegmentActiveFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.providerOlive.opacity(0.62)
            : Color.providerOlive.opacity(0.92)
    }

    static func zoomSegmentActiveForeground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.lavaShellCream : Color.providerOnOliveFill
    }

    static func zoomSegmentInactiveForeground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.lavaShellCream.opacity(0.88)
            : Color.lavaShellCreamSecondary
    }

    // MARK: Admin dashboard tab rail

    static func adminTabTrackFill(_ colorScheme: ColorScheme) -> Color {
        Color.providerScheduleTrackFill
    }

    static func adminTabTrackStroke(_ colorScheme: ColorScheme) -> Color {
        Color.providerScheduleTrackStroke
    }

    static func adminTabActiveFill(_ colorScheme: ColorScheme) -> Color {
        zoomSegmentActiveFill(colorScheme)
    }

    static func adminTabActiveForeground(_ colorScheme: ColorScheme) -> Color {
        zoomSegmentActiveForeground(colorScheme)
    }

    static func adminTabInactiveForeground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.lavaShellCream.opacity(0.72)
            : Color.lavaShellCreamSecondary
    }
}
