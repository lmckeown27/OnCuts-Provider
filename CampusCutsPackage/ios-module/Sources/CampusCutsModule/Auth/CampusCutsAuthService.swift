import Foundation

// MARK: - Session alias

/// JWT-backed session after email verification; use as temporary onboarding state in host shells.
public typealias CampusCutsAuthSession = CampusCutsVerifiedSession

// MARK: - Sign-in surface (labels / analytics — OAuth UI lives in the host app)

public enum CampusCutsSignInProvider: String, Sendable {
    case google
    case apple
    case email
}

/// High-level onboarding entry points. Wraps `CampusCutsSignUpAPI` so future packages can share the same call shape.
public enum CampusCutsAuthService {
    /// Creates a pending registration and sends the verification email (`POST /auth/register`).
    public static func sendRegistrationVerificationEmail(
        apiV1BaseTrimmed: String,
        request: CampusCutsRegisterRequest
    ) async throws -> CampusCutsRegisterSentResult {
        try await CampusCutsSignUpAPI.register(apiV1BaseTrimmed: apiV1BaseTrimmed, request: request)
    }

    /// Legacy name aligned with product copy (“send code”) — same as `sendRegistrationVerificationEmail`.
    public static func sendVerificationCode(
        apiV1BaseTrimmed: String,
        request: CampusCutsRegisterRequest
    ) async throws -> CampusCutsRegisterSentResult {
        try await sendRegistrationVerificationEmail(apiV1BaseTrimmed: apiV1BaseTrimmed, request: request)
    }

    /// Phone-first signup: send SMS before password (`POST /auth/signup/send-phone-code`).
    public static func sendPhoneSignupCode(
        apiV1BaseTrimmed: String,
        phone: String,
        firstName: String,
        lastName: String,
        role: String = "student",
        campusId: String? = nil
    ) async throws -> CampusCutsPhoneSignupSendResult {
        try await CampusCutsSignUpAPI.sendPhoneSignupCode(
            apiV1BaseTrimmed: apiV1BaseTrimmed,
            phone: phone,
            firstName: firstName,
            lastName: lastName,
            role: role,
            campusId: campusId
        )
    }

    /// Exchange SMS code for a short-lived signup token (`POST /auth/signup/verify-phone-code`).
    public static func verifyPhoneSignupCode(
        apiV1BaseTrimmed: String,
        phone: String,
        code: String
    ) async throws -> CampusCutsPhoneSignupVerifyResult {
        try await CampusCutsSignUpAPI.verifyPhoneSignupCode(
            apiV1BaseTrimmed: apiV1BaseTrimmed,
            phone: phone,
            code: code
        )
    }

    /// Create account with password after SMS + token (`POST /auth/signup/complete-phone`).
    public static func completePhoneSignup(
        apiV1BaseTrimmed: String,
        phoneSignupToken: String,
        password: String
    ) async throws -> CampusCutsVerifiedSession {
        try await CampusCutsSignUpAPI.completePhoneSignup(
            apiV1BaseTrimmed: apiV1BaseTrimmed,
            phoneSignupToken: phoneSignupToken,
            password: password
        )
    }

    /// Resends the verification message for a pending registration (`POST /auth/resend-verification`).
    public static func resendVerification(
        apiV1BaseTrimmed: String,
        email: String?,
        phone: String?
    ) async throws -> CampusCutsRegisterSentResult {
        try await CampusCutsSignUpAPI.resendVerification(
            apiV1BaseTrimmed: apiV1BaseTrimmed,
            email: email,
            phone: phone
        )
    }

    /// Resend using email only (email-based signup).
    public static func resendVerificationCode(
        email: String,
        apiV1BaseTrimmed: String
    ) async throws -> CampusCutsRegisterSentResult {
        try await resendVerification(apiV1BaseTrimmed: apiV1BaseTrimmed, email: email, phone: nil)
    }

    /// Verifies the code (`POST /auth/verify-email`). Pass **either** `email` **or** `phone` (E.164).
    public static func verify(
        code: String,
        email: String?,
        phone: String?,
        apiV1BaseTrimmed: String
    ) async throws -> CampusCutsVerifiedSession {
        try await CampusCutsSignUpAPI.verifyEmail(
            apiV1BaseTrimmed: apiV1BaseTrimmed,
            email: email,
            phone: phone,
            code: code
        )
    }

    /// Verifies using email (traditional flow).
    public static func verify(code: String, email: String, apiV1BaseTrimmed: String) async throws -> CampusCutsVerifiedSession {
        try await verify(code: code, email: email, phone: nil, apiV1BaseTrimmed: apiV1BaseTrimmed)
    }

    /// Whether a user already exists (`GET /auth/check-email?email=`).
    public static func checkAccount(email: String, apiV1BaseTrimmed: String) async throws -> Bool {
        try await CampusCutsSignUpAPI.checkEmailExists(apiV1BaseTrimmed: apiV1BaseTrimmed, email: email)
    }

    /// Password sign-in (`POST /auth/login`).
    public static func loginWithEmailPassword(
        email: String,
        password: String,
        apiV1BaseTrimmed: String
    ) async throws -> CampusCutsVerifiedSession {
        try await CampusCutsSignUpAPI.login(
            apiV1BaseTrimmed: apiV1BaseTrimmed,
            email: email,
            password: password
        )
    }
}
