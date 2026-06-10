import Foundation

/// Persists Apple-supplied **email** and **name** from the first authorization so later sign-ins can send them to the API when Apple omits them (Intera consumer `AppleSignInSupplementStore` parity).
enum AppleSignInSupplementStore {
    private enum Keys {
        static let email = "InteraProvider.AppleSignIn.supplementalEmail"
        static let firstName = "InteraProvider.AppleSignIn.supplementalFirstName"
        static let lastName = "InteraProvider.AppleSignIn.supplementalLastName"
    }

    static func loadEmail() -> String? { nonEmpty(UserDefaults.standard.string(forKey: Keys.email)) }
    static func loadFirstName() -> String? { nonEmpty(UserDefaults.standard.string(forKey: Keys.firstName)) }
    static func loadLastName() -> String? { nonEmpty(UserDefaults.standard.string(forKey: Keys.lastName)) }

    static func save(email: String) {
        let t = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        UserDefaults.standard.set(t, forKey: Keys.email)
    }

    static func save(firstName: String) {
        let t = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        UserDefaults.standard.set(t, forKey: Keys.firstName)
    }

    static func save(lastName: String) {
        let t = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        UserDefaults.standard.set(t, forKey: Keys.lastName)
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }
}
