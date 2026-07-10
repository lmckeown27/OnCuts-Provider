import Foundation

public enum OnCutsSignUpAPIError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)
    case decodingFailed
    case missingEmailOrPhone

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid server response."
        case .httpStatus(let code, let msg):
            if let msg, !msg.isEmpty { return msg }
            return "Request failed (HTTP \(code))."
        case .decodingFailed:
            return "Could not read server response."
        case .missingEmailOrPhone:
            return "Email or phone is required."
        }
    }
}

/// Minimal REST client for CampusCuts email registration + verification (matches `auth.controller.ts`).
public enum OnCutsSignUpAPI {
    public static func fetchCampuses(apiV1BaseTrimmed: String) async throws -> [OnCutsSignUpCampus] {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/campus") else {
            throw OnCutsSignUpAPIError.invalidURL
        }
        let (data, http) = try await dataGET(url: url)
        guard (200 ... 299).contains(http.statusCode) else {
            throw OnCutsSignUpAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(CampusesEnvelope.self, from: data),
              let rows = envelope.data
        else {
            throw OnCutsSignUpAPIError.decodingFailed
        }
        return rows.compactMap { row in
            let id = row.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty, !name.isEmpty else { return nil }
            return OnCutsSignUpCampus(id: id, name: name)
        }
    }

    public static func register(
        apiV1BaseTrimmed: String,
        request: OnCutsRegisterRequest
    ) async throws -> OnCutsRegisterSentResult {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/auth/register") else {
            throw OnCutsSignUpAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let encoder = JSONEncoder()
        req.httpBody = try encoder.encode(request)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OnCutsSignUpAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OnCutsSignUpAPIError.httpStatus(http.statusCode, serverMessage(from: data))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(RegisterEnvelope.self, from: data),
              let block = envelope.data
        else {
            throw OnCutsSignUpAPIError.decodingFailed
        }
        let emailResolved = block.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? request.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? ""
        let phoneResolved = block.phone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let code = block.verificationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return OnCutsRegisterSentResult(email: emailResolved, phone: phoneResolved, devVerificationCode: code)
    }

    /// `POST /auth/resend-verification` — new code for an existing pending registration (same response shape as register).
    public static func resendVerification(
        apiV1BaseTrimmed: String,
        email: String?,
        phone: String?
    ) async throws -> OnCutsRegisterSentResult {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/auth/resend-verification") else {
            throw OnCutsSignUpAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: String] = [:]
        if let p = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            body["phone"] = p
        } else if let e = email?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            body["email"] = e
        } else {
            throw OnCutsSignUpAPIError.missingEmailOrPhone
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OnCutsSignUpAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OnCutsSignUpAPIError.httpStatus(http.statusCode, serverMessage(from: data))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(RegisterEnvelope.self, from: data),
              let block = envelope.data
        else {
            throw OnCutsSignUpAPIError.decodingFailed
        }
        let resolvedEmail = block.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let em = resolvedEmail.nilIfEmpty ?? fallback
        let phoneOut = block.phone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? phone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let code = block.verificationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return OnCutsRegisterSentResult(email: em, phone: phoneOut, devVerificationCode: code)
    }

    public static func verifyEmail(
        apiV1BaseTrimmed: String,
        email: String?,
        phone: String?,
        code: String
    ) async throws -> OnCutsVerifiedSession {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/auth/verify-email") else {
            throw OnCutsSignUpAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["code": code]
        if let p = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            body["phone"] = p
        } else if let e = email?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            body["email"] = e
        } else {
            throw OnCutsSignUpAPIError.missingEmailOrPhone
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OnCutsSignUpAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OnCutsSignUpAPIError.httpStatus(http.statusCode, serverMessage(from: data))
        }
        let fallback = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try decodeVerifiedSession(from: data, fallbackEmail: fallback)
    }

    /// `GET /auth/check-email?email=` — returns whether a user exists.
    public static func checkEmailExists(apiV1BaseTrimmed: String, email: String) async throws -> Bool {
        try await checkEmailAccountStatus(apiV1BaseTrimmed: apiV1BaseTrimmed, email: email).exists
    }

    /// `GET /auth/check-email?email=` — whether the email exists and whether it belongs to an Operator.
    public static func checkEmailAccountStatus(
        apiV1BaseTrimmed: String,
        email: String
    ) async throws -> OnCutsEmailAccountStatus {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: base + "/auth/check-email")
        components?.queryItems = [
            URLQueryItem(name: "email", value: email.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        guard let url = components?.url else {
            throw OnCutsSignUpAPIError.invalidURL
        }
        let (data, http) = try await dataGET(url: url)
        guard (200 ... 299).contains(http.statusCode) else {
            throw OnCutsSignUpAPIError.httpStatus(http.statusCode, serverMessage(from: data))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(CheckEmailEnvelope.self, from: data),
              let exists = envelope.data?.exists
        else {
            throw OnCutsSignUpAPIError.decodingFailed
        }
        let isOperator = envelope.data?.isOperator ?? exists
        return OnCutsEmailAccountStatus(exists: exists, isOperator: isOperator)
    }

    /// `POST /auth/signup/send-phone-code` — SMS OTP without password (phone-first flow).
    public static func sendPhoneSignupCode(
        apiV1BaseTrimmed: String,
        phone: String,
        firstName: String,
        lastName: String,
        role: String,
        campusId: String?
    ) async throws -> OnCutsPhoneSignupSendResult {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/auth/signup/send-phone-code") else {
            throw OnCutsSignUpAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "lastName": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "role": role,
        ]
        if let campusId, !campusId.isEmpty {
            body["campusId"] = campusId
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OnCutsSignUpAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OnCutsSignUpAPIError.httpStatus(http.statusCode, serverMessage(from: data))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(PhoneSignupSendEnvelope.self, from: data),
              let block = envelope.data
        else {
            throw OnCutsSignUpAPIError.decodingFailed
        }
        let phoneOut = block.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? phone
        let code = block.verificationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return OnCutsPhoneSignupSendResult(phone: phoneOut, devVerificationCode: code)
    }

    /// `POST /auth/signup/verify-phone-code` — exchange OTP for a signup ticket.
    public static func verifyPhoneSignupCode(
        apiV1BaseTrimmed: String,
        phone: String,
        code: String
    ) async throws -> OnCutsPhoneSignupVerifyResult {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/auth/signup/verify-phone-code") else {
            throw OnCutsSignUpAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: String] = [
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OnCutsSignUpAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OnCutsSignUpAPIError.httpStatus(http.statusCode, serverMessage(from: data))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(PhoneSignupVerifyEnvelope.self, from: data),
              let block = envelope.data,
              let tok = block.phoneSignupToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        else {
            throw OnCutsSignUpAPIError.decodingFailed
        }
        let phoneOut = block.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? phone
        return OnCutsPhoneSignupVerifyResult(phoneSignupToken: tok, phone: phoneOut)
    }

    /// `POST /auth/signup/complete-phone` — create account after SMS + ticket.
    public static func completePhoneSignup(
        apiV1BaseTrimmed: String,
        phoneSignupToken: String,
        password: String
    ) async throws -> OnCutsVerifiedSession {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/auth/signup/complete-phone") else {
            throw OnCutsSignUpAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: String] = [
            "phoneSignupToken": phoneSignupToken.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OnCutsSignUpAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OnCutsSignUpAPIError.httpStatus(http.statusCode, serverMessage(from: data))
        }
        return try decodeVerifiedSession(from: data, fallbackEmail: "")
    }

    /// `POST /auth/login` — email + password; response shape matches verify-email `data` block.
    public static func login(
        apiV1BaseTrimmed: String,
        email: String,
        password: String
    ) async throws -> OnCutsVerifiedSession {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/auth/login") else {
            throw OnCutsSignUpAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: String] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OnCutsSignUpAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OnCutsSignUpAPIError.httpStatus(http.statusCode, serverMessage(from: data))
        }
        return try decodeVerifiedSession(from: data, fallbackEmail: email)
    }

    // MARK: - Private

    private struct CampusesEnvelope: Decodable {
        let data: [CampusRow]?
        struct CampusRow: Decodable {
            let id: String?
            let name: String?
        }
    }

    private struct RegisterEnvelope: Decodable {
        let data: RegisterData?
        struct RegisterData: Decodable {
            let email: String?
            let phone: String?
            let verificationCode: String?
        }
    }

    private struct PhoneSignupSendEnvelope: Decodable {
        let data: PhoneSignupSendData?
        struct PhoneSignupSendData: Decodable {
            let phone: String?
            let verificationCode: String?
        }
    }

    private struct PhoneSignupVerifyEnvelope: Decodable {
        let data: PhoneSignupVerifyData?
        struct PhoneSignupVerifyData: Decodable {
            let phoneSignupToken: String?
            let phone: String?
        }
    }

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
            }
        }
    }

    private struct CheckEmailEnvelope: Decodable {
        let data: CheckData?
        struct CheckData: Decodable {
            let exists: Bool?
            let isOperator: Bool?
        }
    }

    private static func decodeVerifiedSession(from data: Data, fallbackEmail: String) throws -> OnCutsVerifiedSession {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(VerifyEnvelope.self, from: data),
              let block = envelope.data
        else {
            throw OnCutsSignUpAPIError.decodingFailed
        }
        let access = block.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? block.token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let access, !access.isEmpty else {
            throw OnCutsSignUpAPIError.decodingFailed
        }
        let refresh = block.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let user = block.user
        let uid = user?.id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
        guard !uid.isEmpty else {
            throw OnCutsSignUpAPIError.decodingFailed
        }
        let em = user?.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackEmail
        let fn = user?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? user?.first_name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
        let ln = user?.lastName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? user?.last_name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
        let role = user?.role?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "CONSUMER"
        return OnCutsVerifiedSession(
            accessToken: access,
            refreshToken: refresh,
            userId: uid,
            email: em,
            firstName: fn,
            lastName: ln,
            backendRole: role
        )
    }

    private static func dataGET(url: URL) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OnCutsSignUpAPIError.invalidResponse
        }
        return (data, http)
    }

    private static func serverMessage(from data: Data) -> String? {
        struct Err: Decodable {
            let error: Msg?
            let message: String?
            let errors: [SubErr]?
            struct Msg: Decodable {
                let message: String?
            }
            struct SubErr: Decodable {
                let msg: String?
                let message: String?
            }
        }
        guard let e = try? JSONDecoder().decode(Err.self, from: data) else {
            return String(data: data, encoding: .utf8)
        }
        let firstNested = e.errors?.first.flatMap { $0.msg ?? $0.message }
        return e.message ?? e.error?.message ?? firstNested
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
