import Foundation
import SwiftUI

@MainActor
class BookingViewModel: ObservableObject {
    @Published var bookings: [Booking] = []
    @Published var selectedBooking: Booking?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let networkManager = NetworkManager.shared
    
    func fetchBookings() async {
        isLoading = true
        errorMessage = nil
        
        do {
            struct BookingsResponse: Codable {
                let success: Bool
                let data: [Booking]
                let count: Int
            }
            
            let response: BookingsResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.bookings,
                authenticated: true
            )
            
            bookings = response.data
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func createBooking(
        barberId: String,
        serviceType: String,
        scheduledTime: Date,
        durationMinutes: Int,
        locationDetails: String?,
        specialRequests: String?
    ) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let formatter = ISO8601DateFormatter()
            
            let request = CreateBookingRequest(
                barberId: barberId,
                serviceType: serviceType,
                scheduledTime: formatter.string(from: scheduledTime),
                durationMinutes: durationMinutes,
                locationDetails: locationDetails,
                specialRequests: specialRequests
            )
            
            let _: BookingResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.bookings,
                method: "POST",
                body: request,
                authenticated: true
            )
            
            // Refresh bookings
            await fetchBookings()
            
            isLoading = false
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    func confirmBooking(id: Int) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let _: SuccessResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.confirmBooking(id: id),
                method: "PUT",
                authenticated: true
            )
            
            await fetchBookings()
            
            isLoading = false
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    func completeBooking(id: Int) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let _: SuccessResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.completeBooking(id: id),
                method: "PUT",
                authenticated: true
            )
            
            await fetchBookings()
            
            isLoading = false
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    func cancelBooking(id: Int, reason: String?) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            struct CancelRequest: Codable {
                let reason: String?
            }
            
            let _: SuccessResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.cancelBooking(id: id),
                method: "PUT",
                body: CancelRequest(reason: reason),
                authenticated: true
            )
            
            await fetchBookings()
            
            isLoading = false
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}

