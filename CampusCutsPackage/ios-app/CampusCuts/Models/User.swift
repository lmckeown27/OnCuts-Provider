import Foundation

enum UserRole: String, Codable {
    case student
    case barber
}

struct User: Identifiable, Codable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let campusId: Int
    let role: UserRole
    let aptosAddress: String
    let emailVerified: Bool
    let studentIdVerified: Bool
    let createdAt: Date
    let isActive: Bool
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, email, role
        case firstName = "first_name"
        case lastName = "last_name"
        case campusId = "campus_id"
        case aptosAddress = "aptos_address"
        case emailVerified = "email_verified"
        case studentIdVerified = "student_id_verified"
        case createdAt = "created_at"
        case isActive = "is_active"
    }
}

struct AuthResponse: Codable {
    let success: Bool
    let data: AuthData
    let message: String?
}

struct AuthData: Codable {
    let user: User
    let token: String
    let aptosAddress: String?
    
    enum CodingKeys: String, CodingKey {
        case user, token
        case aptosAddress = "aptos_address"
    }
}

