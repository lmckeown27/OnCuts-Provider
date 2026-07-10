import SwiftUI

struct RootView: View {
    @Environment(ProviderSession.self) private var session

    var body: some View {
        ZStack {
            rootBackdrop
            rootContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                #if os(iOS)
                .overlay(alignment: .topLeading) {
                    ProviderHubPagingChromeTint()
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                #endif
        }
        .environment(\.font, .provider(.body))
        .animation(ProviderRootTransition.animation, value: session.rootPresentationPhase)
        .task {
            await session.bootstrap()
            #if os(iOS) || os(visionOS)
            await OnCutsProviderAppDelegate.requestNotificationAuthorizationAndRegister()
            #endif
        }
    }

    @ViewBuilder
    private var rootBackdrop: some View {
        if session.isSignedIn, !session.isBootstrapping {
            OnCutsHubTabShellBackground()
                .transition(.opacity)
        } else {
            Color.providerOlive
                .ignoresSafeArea()
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        Group {
            if session.isBootstrapping {
                ProgressView("Loading…")
                    .tint(.providerOlive)
                    .foregroundStyle(Color.lavaShellCream)
                    .transition(ProviderRootTransition.bootstrapPresentation)
            } else if session.isSignedIn {
                if session.needsConsumerProviderEnrollment {
                    ProviderConsumerEnrollmentView()
                        .background(Color.clear)
                        .transition(ProviderRootTransition.signedInPresentation)
                } else {
                    ProviderShellView()
                        .background(Color.clear)
                        .transition(ProviderRootTransition.signedInPresentation)
                }
            } else {
                AuthEntryView()
                    .id(session.authPresentationEpoch)
                    .transition(ProviderRootTransition.signedOutPresentation)
            }
        }
    }
}
