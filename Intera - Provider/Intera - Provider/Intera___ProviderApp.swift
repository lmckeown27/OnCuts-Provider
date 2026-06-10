import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct InteraProviderApp: App {
    #if os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor(InteraProviderAppDelegate.self) private var appDelegate
    #endif

    @State private var session = ProviderSession()

    init() {
        #if os(iOS)
        ProviderAppearance.configureGlobalUIKitAppearance()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { @MainActor in
                    GoogleSignInAppSupport.configure()
                }
                #if os(iOS) || os(visionOS) || os(macOS)
                .onOpenURL { url in
                    _ = GoogleSignInAppSupport.handleURL(url)
                }
                #endif
        }
    }
}
