import Foundation

struct Barber: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let bio: String
    let profileImageUrl: String?
    let pricing: [String: Double]
    let instantBook: Bool
    let averageResponseTime: Int?
    let totalEarnings: Double
    let totalBookings: Int
    let averageRating: Double
    let yearsExperience: Int?
    let firstName: String
    let lastName: String
    let aptosAddress: String
    let campusId: Int
    let portfolio: [PortfolioImage]?
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
    
    var ratingStars: String {
        let fullStars = Int(averageRating)
        let hasHalfStar = averageRating - Double(fullStars) >= 0.5
        let emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0)
        
        return String(repeating: "★", count: fullStars) +
               (hasHalfStar ? "⯨" : "") +
               String(repeating: "☆", count: emptyStars)
    }
    
    var formattedRating: String {
        String(format: "%.1f", averageRating)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, bio, pricing, portfolio
        case userId = "user_id"
        case profileImageUrl = "profile_image_url"
        case instantBook = "instant_book"
        case averageResponseTime = "average_response_time"
        case totalEarnings = "total_earnings"
        case totalBookings = "total_bookings"
        case averageRating = "average_rating"
        case yearsExperience = "years_experience"
        case firstName = "first_name"
        case lastName = "last_name"
        case aptosAddress = "aptos_address"
        case campusId = "campus_id"
    }
}

struct PortfolioImage: Identifiable, Codable, Hashable {
    let id: String?
    let url: String
    let caption: String?
    
    var displayId: String {
        id ?? url
    }
}

struct BarberResponse: Codable {
    let success: Bool
    let data: [Barber]
    let count: Int
}

struct SingleBarberResponse: Codable {
    let success: Bool
    let data: Barber
}

