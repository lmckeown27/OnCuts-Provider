import SwiftUI

struct RootView: View {
    @Environment(ProviderSession.self) private var session

    private var showsHubRootBackground: Bool {
        session.isSignedIn && !session.needsConsumerProviderEnrollment
    }

    var body: some View {
        ZStack {
            InteraHubTabShellBackground()
                .opacity(showsHubRootBackground ? 1 : 0)
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
        .task {
            await session.bootstrap()
            #if os(iOS) || os(visionOS)
            await InteraProviderAppDelegate.requestNotificationAuthorizationAndRegister()
            #endif
        }
    }
}
