import CampusCutsModule
import Foundation

enum AuthBackendVerificationError: LocalizedError {
    case decoding
    case accountNotFound
    case message(String)

    var errorDescription: String? {
        switch self {
        case .decoding: return "Could not read server response."
        case .accountNotFound:
            return "No account for this Google email yet. Create an account with email first, then you can use Google next time."
        case .message(let s): return s
        }
    }
}

/// Session from `POST /auth/google` or `POST /auth/apple` plus flags from `data.user` (consumer parity).
struct ProviderOAuthSessionOutcome: Sendable {
    let session: CampusCutsVerifiedSession
    let needsPlatformPassword: Bool
}

/// Exchanges Google / Apple ID tokens for **CampusCuts** JWTs (`data.accessToken`). Never use the provider JWT as the API `Authorization` bearer.
/// Same envelope as email verification; uses `AppConfiguration` auth URLs; Apple retries `urlAuthAppleLegacy` on **404** (OnCuts consumer parity).
enum AuthBackendVerification {
    private struct VerifyEnvelope: Decodable {
        let data: VerifyData?
        struct VerifyData: Decodable {
            let accessToken: String?
            let token: String?
            let refreshToken: String?
            let user: UserBlock?
            struct UserBlock: Decodable {
                let id: String?
                let email: String?
                let firstName: String?
                let lastName: String?
                let first_name: String?
                let last_name: String?
                let role: String?
                let needsPlatformPassword: Bool?
            }
        }
    }

    private struct ApiErrorEnvelope: Decodable {
        let success: Bool?
        let error: Err?
        struct Err: Decodable {
            let message: String?
            let code: String?
        }
    }

    /// `POST` `AppConfiguration.urlAuthGoogle` with `{ "idToken": … }`.
    static func verifyGoogleIDTokenAndFetchSessionTokens(_ idToken: String) async throws -> ProviderOAuthSessionOutcome {
        try await postSession(url: AppConfiguration.urlAuthGoogle, body: ["idToken": idToken], googleAccountNotFound: true)
    }

    /// Primary `POST` `AppConfiguration.urlAuthApple`; on **404**, retries `AppConfiguration.urlAuthAppleLegacy`.
    static func verifyAppleIdentityTokenAndFetchSessionTokens(
        identityToken: String,
        firstName: String?,
        lastName: String?,
        email: String?
    ) async throws -> ProviderOAuthSessionOutcome {
        var body: [String: Any] = ["identityToken": identityToken]
        if let g = firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
            body["firstName"] = g
        }
        if let f = lastName?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            body["lastName"] = f
        }
        if let e = email?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            body["email"] = e
        }

        let (data, status) = try await postData(url: AppConfiguration.urlAuthApple, body: body)
        if status == 404 {
            return try await postSession(url: AppConfiguration.urlAuthAppleLegacy, body: body, googleAccountNotFound: false)
        }
        guard (200 ..< 300).contains(status) else {
            let msg = apiErrorMessage(from: data) ?? String(data: data, encoding: .utf8)
            throw AuthBackendVerificationError.message(msg ?? "Request failed (\(status))")
        }
        return try decodeOutcome(from: data, fallbackEmail: "")
    }

    private static func postSession(
        url: URL,
        body: [String: Any],
        googleAccountNotFound: Bool
    ) async throws -> ProviderOAuthSessionOutcome {
        let (data, status) = try await postData(url: url, body: body)
        if googleAccountNotFound, status == 401, apiErrorCode(from: data) == "ACCOUNT_NOT_FOUND" {
            throw AuthBackendVerificationError.accountNotFound
        }
        guard (200 ..< 300).contains(status) else {
            let msg = apiErrorMessage(from: data) ?? String(data: data, encoding: .utf8)
            throw AuthBackendVerificationError.message(msg ?? "Request failed (\(status))")
        }
        return try decodeOutcome(from: data, fallbackEmail: "")
    }

    private static func postData(url: URL, body: [String: Any]) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AuthBackendVerificationError.message("Bad response")
        }
        return (data, http.statusCode)
    }

    private static func apiErrorCode(from data: Data) -> String? {
        let d = JSONDecoder()
        guard let env = try? d.decode(ApiErrorEnvelope.self, from: data) else { return nil }
        return env.error?.code?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        let d = JSONDecoder()
        guard let env = try? d.decode(ApiErrorEnvelope.self, from: data) else { return nil }
        return env.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeOutcome(from data: Data, fallbackEmail: String) throws -> ProviderOAuthSessionOutcome {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(VerifyEnvelope.self, from: data),
              let block = envelope.data
        else {
            throw AuthBackendVerificationError.decoding
        }
        let access = nonEmptyTrim(block.accessToken) ?? nonEmptyTrim(block.token)
        guard let access, !access.isEmpty else {
            throw AuthBackendVerificationError.decoding
        }
        let refresh = nonEmptyTrim(block.refreshToken)
        let user = block.user
        let uid = nonEmptyTrim(user?.id) ?? ""
        guard !uid.isEmpty else {
            throw AuthBackendVerificationError.decoding
        }
        let emRaw = nonEmptyTrim(user?.email)
        let em = emRaw ?? fallbackEmail
        let fn = nonEmptyTrim(user?.firstName)
            ?? nonEmptyTrim(user?.first_name) ?? ""
        let ln = nonEmptyTrim(user?.lastName)
            ?? nonEmptyTrim(user?.last_name) ?? ""
        let role = nonEmptyTrim(user?.role) ?? "CONSUMER"
        let emailFinal = em.isEmpty ? "user@signed-in.local" : em
        let needsPw = user?.needsPlatformPassword ?? false
        let session = CampusCutsVerifiedSession(
            accessToken: access,
            refreshToken: refresh,
            userId: uid,
            email: emailFinal,
            firstName: fn,
            lastName: ln,
            backendRole: role
        )
        return ProviderOAuthSessionOutcome(session: session, needsPlatformPassword: needsPw)
    }

    private static func nonEmptyTrim(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
