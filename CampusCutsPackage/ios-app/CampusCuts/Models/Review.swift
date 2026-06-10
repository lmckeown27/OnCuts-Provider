import Foundation

struct Review: Identifiable, Codable {
    let id: String
    let blockchainReviewId: Int
    let bookingId: Int
    let reviewText: String
    let images: [String]?
    let helpfulCount: Int
    let createdAt: Date
    
    // From joins
    let clientFirstName: String?
    let clientLastName: String?
    
    var clientFullName: String? {
        guard let first = clientFirstName, let last = clientLastName else { return nil }
        return "\(first) \(last)"
    }
    
    var clientInitials: String {
        guard let first = clientFirstName, let last = clientLastName else { return "?" }
        return "\(first.prefix(1))\(last.prefix(1))".uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case blockchainReviewId = "blockchain_review_id"
        case bookingId = "booking_id"
        case reviewText = "review_text"
        case images
        case helpfulCount = "helpful_count"
        case createdAt = "created_at"
        case clientFirstName = "client_first_name"
        case clientLastName = "client_last_name"
    }
}

struct SubmitReviewRequest: Codable {
    let bookingId: Int
    let rating: Int
    let reviewText: String
    let images: [String]?
}

struct ReviewResponse: Codable {
    let success: Bool
    let data: [Review]
    let pagination: Pagination?
}

struct Pagination: Codable {
    let page: Int
    let limit: Int
    let total: Int
    let pages: Int
}

