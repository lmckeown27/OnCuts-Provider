import Foundation

enum BookingStatus: String, Codable {
    case pending = "pending"
    case confirmed = "confirmed"
    case completed = "completed"
    case cancelled = "cancelled"
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var color: String {
        switch self {
        case .pending: return "orange"
        case .confirmed: return "blue"
        case .completed: return "green"
        case .cancelled: return "red"
        }
    }
}

struct Booking: Identifiable, Codable {
    let id: String
    let blockchainBookingId: Int
    let barberId: String
    let clientId: String
    let locationDetails: String?
    let specialRequests: String?
    let reminderSent: Bool
    let notificationSent: Bool
    let createdAt: Date
    let updatedAt: Date
    
    // Additional fields from joins
    let barberFirstName: String?
    let barberLastName: String?
    let barberImage: String?
    let clientFirstName: String?
    let clientLastName: String?
    
    var barberFullName: String? {
        guard let first = barberFirstName, let last = barberLastName else { return nil }
        return "\(first) \(last)"
    }
    
    var clientFullName: String? {
        guard let first = clientFirstName, let last = clientLastName else { return nil }
        return "\(first) \(last)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case blockchainBookingId = "blockchain_booking_id"
        case barberId = "barber_id"
        case clientId = "client_id"
        case locationDetails = "location_details"
        case specialRequests = "special_requests"
        case reminderSent = "reminder_sent"
        case notificationSent = "notification_sent"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case barberFirstName = "barber_first_name"
        case barberLastName = "barber_last_name"
        case barberImage = "barber_image"
        case clientFirstName = "client_first_name"
        case clientLastName = "client_last_name"
    }
}

struct CreateBookingRequest: Codable {
    let barberId: String
    let serviceType: String
    let scheduledTime: String
    let durationMinutes: Int
    let locationDetails: String?
    let specialRequests: String?
}

struct BookingResponse: Codable {
    let success: Bool
    let data: BookingData
    let message: String?
}

struct BookingData: Codable {
    let booking: Booking
    let transactionHash: String
    
    enum CodingKeys: String, CodingKey {
        case booking
        case transactionHash = "transactionHash"
    }
}

