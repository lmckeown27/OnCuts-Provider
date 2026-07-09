#if os(iOS) || os(visionOS) || os(macOS)
import GoogleSignIn
#endif
#if os(iOS) || os(visionOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Thrown when the user invokes Google sign-in but `GoogleService-Info.plist` / `CLIENT_ID` is missing or still a placeholder (OnCuts consumer parity).
enum GoogleSignInFlowError: LocalizedError {
    case missingConfiguration
    case noHostWindow
    case missingIdToken
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Google Sign-In is not configured. Add a real `CLIENT_ID` in `GoogleService-Info.plist` (Firebase / Google Cloud iOS OAuth client) and register the reversed client ID as a URL scheme (see `GoogleSignInURL.plist` in this target)."
        case .noHostWindow: return "Could not present Google sign-in."
        case .missingIdToken: return "Google did not return an ID token."
        case .unsupportedPlatform: return "Google Sign-In is not available on this platform."
        }
    }
}

/// Parity with OnCuts consumer `GoogleSignInAppSupport`: plist-based `CLIENT_ID`, launch `configure()`, `onOpenURL` → `handleURL`, `signOut` after a failed backend exchange.
enum GoogleSignInAppSupport {
    /// Reads **`CLIENT_ID`** from bundled **`GoogleService-Info.plist`**, else **`GIDClientID`** from the main bundle Info dictionary. Rejects obvious placeholders.
    static func loadClientIDFromGoogleServicePlist() -> String? {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let raw = dict["CLIENT_ID"] as? String
        else {
            return nil
        }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !isPlaceholderClientID(id) else { return nil }
        return id
    }

    private static func isPlaceholderClientID(_ id: String) -> Bool {
        let u = id.uppercased()
        if u.contains("YOUR_") || u.contains("REPLACE") || u.contains("FIXME") || u.contains("EXAMPLE") { return true }
        return false
    }

    @MainActor
    static func configure() {
        #if os(iOS) || os(visionOS) || os(macOS)
        let fromPlist = loadClientIDFromGoogleServicePlist()
        let fromInfo = (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [fromPlist, fromInfo].compactMap { s -> String? in
            guard let s, !s.isEmpty, !isPlaceholderClientID(s) else { return nil }
            return s
        }
        guard let clientID = candidates.first else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        #endif
    }

    @MainActor
    static var isConfigured: Bool {
        #if os(iOS) || os(visionOS) || os(macOS)
        GIDSignIn.sharedInstance.configuration != nil
        #else
        false
        #endif
    }

    /// Clears the Google SDK session after a failed CampusCuts token exchange (consumer parity).
    @MainActor
    static func signOutSDK() {
        #if os(iOS) || os(visionOS) || os(macOS)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    @MainActor
    static func signInForIdToken() async throws -> String {
        #if os(iOS) || os(visionOS)
        guard isConfigured else { throw GoogleSignInFlowError.missingConfiguration }
        guard let presenter = topViewController() else { throw GoogleSignInFlowError.noHostWindow }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idTok = result.user.idToken else {
            throw GoogleSignInFlowError.missingIdToken
        }
        let token = idTok.tokenString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GoogleSignInFlowError.missingIdToken }
        return token
        #elseif os(macOS)
        guard isConfigured else { throw GoogleSignInFlowError.missingConfiguration }
        guard let presenter = keyMacWindow()?.contentViewController else { throw GoogleSignInFlowError.noHostWindow }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idTok = result.user.idToken else {
            throw GoogleSignInFlowError.missingIdToken
        }
        let token = idTok.tokenString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GoogleSignInFlowError.missingIdToken }
        return token
        #else
        throw GoogleSignInFlowError.unsupportedPlatform
        #endif
    }

    #if os(iOS) || os(visionOS)
    @MainActor
    static func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
    #elseif os(macOS)
    @MainActor
    static func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
    #endif

    #if os(iOS) || os(visionOS)
    @MainActor
    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? keyWindow()?.rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
    #elseif os(macOS)
    @MainActor
    private static func keyMacWindow() -> NSWindow? {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first { $0.isKeyWindow }
    }
    #endif
}
