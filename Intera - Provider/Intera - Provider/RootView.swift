import SwiftUI

struct RootView: View {
    @Environment(ProviderSession.self) private var session

    var body: some View {
        ZStack {
            InteraHubTabShellBackground()
            Group {
                if session.isBootstrapping {
                    ProgressView("Loading…")
                        .tint(.providerOlive)
                        .foregroundStyle(Color.lavaShellCream)
                } else if session.isSignedIn {
                    if session.needsConsumerProviderEnrollment {
                        ProviderConsumerEnrollmentView()
                            .background(Color.clear)
                    } else {
                        ProviderShellView()
                            .background(Color.clear)
                    }
                } else {
                    AuthEntryView()
                }
            }
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
        .task {
            await session.bootstrap()
            #if os(iOS) || os(visionOS)
            await InteraProviderAppDelegate.requestNotificationAuthorizationAndRegister()
            #endif
        }
    }
}
