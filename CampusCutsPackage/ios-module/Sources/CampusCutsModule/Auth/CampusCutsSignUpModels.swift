import Foundation

// MARK: - API payloads

public struct CampusCutsSignUpCampus: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Maps to `POST /api/v1/auth/register` body (`role`: `student` | `barber` | `admin`).
/// Send **either** `email` **or** `phone` (E.164, e.g. `+15551234567`), not both — matches web + mobile signup.
public struct CampusCutsRegisterRequest: Encodable, Sendable {
    public var email: String?
    public var phone: String?
    public let password: String
    public let firstName: String
    public let lastName: String
    public let role: String
    public let campusId: String?
    /// Some deployments require this for `verify-email` to succeed. Omitted from JSON when `nil`.
    public let acceptedTerms: Bool?

    /// Email-based registration (default).
    public init(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        role: String,
        campusId: String?,
        acceptedTerms: Bool? = nil
    ) {
        self.email = email
        self.phone = nil
        self.password = password
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.campusId = campusId
        self.acceptedTerms = acceptedTerms
    }

    /// Phone / SMS verification path (`phone` should be E.164).
    public init(
        phone: String,
        password: String,
        firstName: String,
        lastName: String,
        role: String,
        campusId: String?,
        acceptedTerms: Bool? = nil
    ) {
        self.email = nil
        self.phone = phone
        self.password = password
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.campusId = campusId
        self.acceptedTerms = acceptedTerms
    }

    enum CodingKeys: String, CodingKey {
        case email, phone, password, firstName, lastName, role, campusId
        case acceptedTermsSnake = "accepted_terms"
        case acceptedTermsCamel = "acceptedTerms"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let email, !email.isEmpty { try c.encode(email, forKey: .email) }
        if let phone, !phone.isEmpty { try c.encode(phone, forKey: .phone) }
        try c.encode(password, forKey: .password)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(lastName, forKey: .lastName)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(campusId, forKey: .campusId)
        if let acceptedTerms {
            try c.encode(acceptedTerms, forKey: .acceptedTermsSnake)
            try c.encode(acceptedTerms, forKey: .acceptedTermsCamel)
        }
    }
}

/// Session returned after `POST /api/v1/auth/verify-email`.
public struct CampusCutsVerifiedSession: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let userId: String
    public let email: String
    public let firstName: String
    public let lastName: String
    /// Raw DB/API role, e.g. `CONSUMER`, `BARBER`.
    public let backendRole: String

    public init(
        accessToken: String,
        refreshToken: String?,
        userId: String,
        email: String,
        firstName: String,
        lastName: String,
        backendRole: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userId = userId
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.backendRole = backendRole
    }
}

/// Outcome of the register step (verification required before JWT is issued).
public struct CampusCutsRegisterSentResult: Sendable {
    /// Internal key for `verify-email` / `resend-verification` (for phone signups this is a synthetic address).
    public let email: String
    /// Present when registration used SMS.
    public let phone: String?
    /// Present only when the server runs with email/SMS auto-verify / dev helpers.
    public let devVerificationCode: String?

    public init(email: String, phone: String?, devVerificationCode: String?) {
        self.email = email
        self.phone = phone
        self.devVerificationCode = devVerificationCode
    }
}

// MARK: - Phone-first signup (SMS before password)

/// Outcome of `POST /auth/signup/send-phone-code`.
public struct CampusCutsPhoneSignupSendResult: Sendable {
    public let phone: String
    /// Present when the server runs with SMS auto-verify / dev helpers.
    public let devVerificationCode: String?

    public init(phone: String, devVerificationCode: String?) {
        self.phone = phone
        self.devVerificationCode = devVerificationCode
    }
}

/// Outcome of `POST /auth/signup/verify-phone-code` — short-lived token for `complete-phone`.
public struct CampusCutsPhoneSignupVerifyResult: Sendable {
    public let phoneSignupToken: String
    public let phone: String

    public init(phoneSignupToken: String, phone: String) {
        self.phoneSignupToken = phoneSignupToken
        self.phone = phone
    }
}
