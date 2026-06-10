import SwiftUI

// MARK: - Shell background (system light / dark — no lava lamp)

enum InteraLavaMidnight {
    /// Primary screen background — `systemBackground` (white in light mode, dark in dark mode).
    static var color: Color { Color(uiColor: uiColor) }
    #if os(iOS)
    static var uiColor: UIColor { ProviderAppearance.shellBase }
    #endif
}

/// Flat adaptive fill behind the signed-in hub and pushed shell routes.
private struct ProviderShellBackgroundFill: View {
    var body: some View {
        Color(uiColor: ProviderAppearance.shellBase)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .all)
            .allowsHitTesting(false)
    }
}

/// Grouped-style fill (e.g. Messages inbox) — `secondarySystemGroupedBackground`.
private struct ProviderGroupedShellBackgroundFill: View {
    var body: some View {
        Color(uiColor: ProviderAppearance.groupedShellBase)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .all)
            .allowsHitTesting(false)
    }
}

/// Shared root background for the signed-in shell.
struct InteraHubTabShellBackground: View {
    var body: some View {
        ProviderShellBackgroundFill()
    }
}

// MARK: - Pushed destinations

private struct InteraPushedNavigationChromeFill: View {
    var body: some View {
        ProviderShellBackgroundFill()
    }
}

private struct InteraNeutralPushedNavigationChromeFill: View {
    var body: some View {
        ProviderGroupedShellBackgroundFill()
    }
}

extension View {
    func providerNavigationStackDestinationBackdrop() -> some View {
        providerNavigationStackDestinationBackdrop(style: .shell)
    }

    func providerNavigationStackDestinationBackdrop(
        style: ProviderNavigationStackDestinationBackdropStyle
    ) -> some View {
        ZStack {
            Group {
                switch style {
                case .shell:
                    InteraPushedNavigationChromeFill()
                case .neutralGrey:
                    InteraNeutralPushedNavigationChromeFill()
                }
            }
            .ignoresSafeArea()
            self
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum ProviderNavigationStackDestinationBackdropStyle {
    case shell
    case neutralGrey
}

// MARK: - Navigation chrome

extension View {
    func interaNavigationShellBackgroundClear() -> some View {
        #if os(iOS) || os(visionOS) || os(macOS)
        containerBackground(Color.clear, for: .navigation)
        #else
        self
        #endif
    }

    func providerHubScheduleChrome() -> some View {
        interaNavigationShellBackgroundClear()
    }

    @ViewBuilder
    func providerShellNavigationContainerChrome(
        backdrop: ProviderNavigationStackDestinationBackdropStyle?
    ) -> some View {
        #if os(iOS) || os(visionOS) || os(macOS)
        if let backdrop {
            containerBackground(backdrop.containerColor, for: .navigation)
        } else {
            interaNavigationShellBackgroundClear()
        }
        #else
        self
        #endif
    }

    func providerPushedDestinationChrome(
        style: ProviderNavigationStackDestinationBackdropStyle = .shell
    ) -> some View {
        ZStack {
            Group {
                switch style {
                case .shell:
                    InteraPushedNavigationChromeFill()
                case .neutralGrey:
                    InteraNeutralPushedNavigationChromeFill()
                }
            }
            .ignoresSafeArea()
            self
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    func providerPushedDestinationChrome(for route: ProviderShellRoute) -> some View {
        providerPushedDestinationChrome(style: route.pushedBackdropStyle)
    }
}

// MARK: - Provider screen chrome

private struct ProviderLavaToolbarChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
    }
}

private struct ProviderLavaScreenChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .interaNavigationShellBackgroundClear()
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
    }
}

private struct ProviderFormSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.visible)
    }
}

extension View {
    func providerLavaToolbarChrome() -> some View {
        modifier(ProviderLavaToolbarChromeModifier())
    }

    func providerLavaScreenChrome() -> some View {
        modifier(ProviderLavaScreenChromeModifier())
    }

    func providerLavaIntegratedFormSurface() -> some View {
        modifier(ProviderFormSurfaceModifier())
    }

    func providerLavaIntegratedListSurface() -> some View {
        modifier(ProviderFormSurfaceModifier())
            .listStyle(.plain)
            .listSectionSpacing(14)
            .listRowSeparatorTint(Color(uiColor: ProviderAppearance.separator))
    }

    func providerLavaIntegratedListRowBackground(
        cornerRadius: CGFloat = 14,
        horizontalInset: CGFloat = 14,
        verticalInset: CGFloat = 5
    ) -> some View {
        listRowInsets(EdgeInsets(top: verticalInset, leading: horizontalInset, bottom: verticalInset, trailing: horizontalInset))
            .listRowBackground(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.providerElevatedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.providerElevatedSurfaceStroke, lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Sheet shell

struct ProviderLavaSheetContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            ProviderShellBackgroundFill()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
    }
}
