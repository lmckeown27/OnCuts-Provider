import Foundation

struct Campus: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let domain: String
    let city: String
    let state: String
    
    var displayLocation: String {
        "\(city), \(state)"
    }
    
    var displayName: String {
        name
    }
}

struct CampusResponse: Codable {
    let success: Bool
    let data: [Campus]
    let count: Int
}

struct CampusStats: Codable {
    let totalBarbers: Int
    let totalClients: Int
    let totalBookings: Int
    let avgRating: Double
    
    enum CodingKeys: String, CodingKey {
        case totalBarbers = "total_barbers"
        case totalClients = "total_clients"
        case totalBookings = "total_bookings"
        case avgRating = "avg_rating"
    }
}

