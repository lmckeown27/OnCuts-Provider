import Foundation
import SwiftUI

struct Constants {
    // API Configuration
    struct API {
        static let baseURL = "http://localhost:3000/api"
        static let timeout: TimeInterval = 30
        
        struct Endpoints {
            // Auth
            static let register = "/auth/register"
            static let login = "/auth/login"
            static let verifyEmail = "/auth/verify-email"
            
            // Barbers
            static let barbers = "/barbers"
            static func barberDetail(id: String) -> String { "/barbers/\(id)" }
            static func barberPortfolio(id: String) -> String { "/barbers/\(id)/portfolio" }
            static func barberAvailability(id: String) -> String { "/barbers/\(id)/availability" }
            
            // Bookings
            static let bookings = "/bookings"
            static func bookingDetail(id: Int) -> String { "/bookings/\(id)" }
            static func confirmBooking(id: Int) -> String { "/bookings/\(id)/confirm" }
            static func completeBooking(id: Int) -> String { "/bookings/\(id)/complete" }
            static func cancelBooking(id: Int) -> String { "/bookings/\(id)/cancel" }
            
            // Payments
            static let createPaymentIntent = "/payments/create-intent"
            static let earnings = "/payments/earnings/summary"
            static let payout = "/payments/payout"
            
            // Reviews
            static let reviews = "/reviews"
            static func barberReviews(barberId: String) -> String { "/reviews/barber/\(barberId)" }
            
            // Campus
            static let campuses = "/campus"
            static func campusBarbers(id: Int) -> String { "/campus/\(id)/barbers" }
        }
    }
    
    // UI Constants
    struct UI {
        static let cornerRadius: CGFloat = 12
        static let shadowRadius: CGFloat = 8
        static let padding: CGFloat = 16
        static let smallPadding: CGFloat = 8
        
        struct Colors {
            static let primary = Color.blue
            static let secondary = Color.green
            static let accent = Color.orange
            static let background = Color(.systemBackground)
            static let secondaryBackground = Color(.secondarySystemBackground)
        }
        
        struct Grid {
            static let columns = 2
            static let spacing: CGFloat = 12
        }
    }
    
    // Business Logic
    struct Business {
        static let platformFeePercentage = 0.05 // 5%
        static let minimumBookingAmount = 500 // $5.00 in cents
        static let maximumBookingDuration = 240 // 4 hours in minutes
    }
    
    // Storage Keys
    struct StorageKeys {
        static let authToken = "auth_token"
        static let userId = "user_id"
        static let userRole = "user_role"
        static let selectedCampusId = "selected_campus_id"
    }
}

// MARK: - Extensions

extension Color {
    static let campusCutsPrimary = Color("PrimaryColor")
    static let campusCutsAccent = Color("AccentColor")
}

