import SwiftUI

/// Shared motion for switching between signed-out auth and the signed-in shell.
enum ProviderRootTransition {
    static let duration: TimeInterval = 0.42
    static let animation: Animation = .easeInOut(duration: duration)

    /// Signed-in hub entering after auth succeeds.
    static let signedInPresentation = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .center)),
        removal: .opacity.combined(with: .scale(scale: 1.012, anchor: .center))
    )

    /// Auth landing entering after sign-out.
    static let signedOutPresentation = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.975, anchor: .center)),
        removal: .opacity.combined(with: .scale(scale: 1.015, anchor: .center))
    )

    static let bootstrapPresentation = AnyTransition.opacity

    /// Inline password field reveal on the auth landing screen.
    static let passwordFieldReveal: Animation = .spring(response: 0.44, dampingFraction: 0.86)

    static let passwordFieldPresentation = AnyTransition.asymmetric(
        insertion: .opacity
            .combined(with: .move(edge: .top))
            .combined(with: .scale(scale: 0.97, anchor: .top)),
        removal: .opacity
            .combined(with: .move(edge: .top))
            .combined(with: .scale(scale: 0.97, anchor: .top))
    )
}

extension ProviderSession {
    /// Stable animation key for `RootView` phase changes (auth ↔ shell ↔ bootstrap).
    var rootPresentationPhase: String {
        if isBootstrapping { return "bootstrapping" }
        if !isSignedIn { return "signedOut-\(authPresentationEpoch)" }
        if needsConsumerProviderEnrollment { return "enrollment" }
        return "shell"
    }
}
