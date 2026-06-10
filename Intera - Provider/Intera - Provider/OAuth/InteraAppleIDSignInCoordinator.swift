import AuthenticationServices
import Foundation

#if os(iOS) || os(visionOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Presents **Sign in with Apple** using `ASAuthorizationController` so the UI can show **Continue with** + logo instead of `SignInWithAppleButton`.
enum InteraAppleIDSignInCoordinator {
    private static var active: AppleIDSignInSession?

    static func perform(completion: @escaping @MainActor (Result<ASAuthorization, Error>) -> Void) {
        let session = AppleIDSignInSession(completion: completion)
        active = session
        session.start()
    }

    fileprivate static func clearActive() {
        active = nil
    }
}

private final class AppleIDSignInSession: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: @MainActor (Result<ASAuthorization, Error>) -> Void
    private var controller: ASAuthorizationController?

    init(completion: @escaping @MainActor (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func start() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let c = ASAuthorizationController(authorizationRequests: [request])
        c.delegate = self
        c.presentationContextProvider = self
        controller = c
        c.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS) || os(visionOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        if let win = windows.first(where: { $0.isKeyWindow }) {
            return win
        }
        if let win = windows.first {
            return win
        }
        guard let scene = scenes.first else {
            fatalError("InteraAppleIDSignInCoordinator: no UIWindowScene")
        }
        return UIWindow(windowScene: scene)
        #elseif os(macOS)
        if let w = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            return w
        }
        if let w = NSApplication.shared.windows.first {
            return w
        }
        assertionFailure("InteraAppleIDSignInCoordinator: no NSWindow for presentation anchor")
        return NSWindow()
        #else
        fatalError("Unsupported platform for Sign in with Apple")
        #endif
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            self.completion(.success(authorization))
            InteraAppleIDSignInCoordinator.clearActive()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            self.completion(.failure(error))
            InteraAppleIDSignInCoordinator.clearActive()
        }
    }
}
