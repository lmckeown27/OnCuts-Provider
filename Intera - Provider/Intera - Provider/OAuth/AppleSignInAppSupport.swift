import AuthenticationServices
import Foundation

/// Bridges `ASAuthorizationAppleIDCredential` → supplement persistence (OnCuts consumer `AppleSignInAppSupport` parity).
enum AppleSignInAppSupport {
    static func mergeCredentialIntoSupplementStore(_ credential: ASAuthorizationAppleIDCredential) {
        if let e = credential.email {
            let t = e.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { AppleSignInSupplementStore.save(email: t) }
        }
        if let name = credential.fullName {
            if let g = name.givenName {
                let t = g.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { AppleSignInSupplementStore.save(firstName: t) }
            }
            if let f = name.familyName {
                let t = f.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { AppleSignInSupplementStore.save(lastName: t) }
            }
        }
    }
}
