//
//  ConsumerViewModel.swift
//  CampusCutsModule
//
//  Internal ViewModel for consumer-facing views.
//

import Foundation
import SwiftUI

@MainActor
internal class ConsumerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var barbers: [Barber] = []
    @Published var myBookings: [Booking] = []
    @Published var selectedBarber: Barber?
    @Published var selectedService: BarberService?
    @Published var selectedDate: Date = Date()
    @Published var availableSlots: [TimeSlot] = []
    @Published var selectedSlot: TimeSlot?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var currentView: ConsumerViewState = .browse
    
    // MARK: - Dependencies
    
    private let session: UserSessionProtocol
    private let apiService: CampusCutsAPIService
    private let liveDataSafetyMode: Bool
    
    // MARK: - Types
    
    enum ConsumerViewState {
        case browse
        case barberDetail
        case booking
        case myBookings
    }
    
    // MARK: - Computed Properties
    
    var filteredBarbers: [Barber] {
        if searchText.isEmpty {
            return barbers
        }
        return barbers.filter { barber in
            barber.businessName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var upcomingBookings: [Booking] {
        myBookings.filter { $0.status == .pending || $0.status == .accepted }
    }
    
    var pastBookings: [Booking] {
        myBookings.filter { $0.status == .completed || $0.status == .cancelled }
    }
    
    // MARK: - Initialization
    
    init(session: UserSessionProtocol, apiService: CampusCutsAPIService, liveDataSafetyMode: Bool = false) {
        self.session = session
        self.apiService = apiService
        self.liveDataSafetyMode = liveDataSafetyMode
    }
    
    // MARK: - Public Methods
    
    func loadBarbers() async {
        isLoading = true
        errorMessage = nil
        
        do {
            barbers = try await apiService.fetchBarbers()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func loadMyBookings() async {
        isLoading = true
        
        do {
            myBookings = try await apiService.fetchBookings()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func selectBarber(_ barber: Barber) async {
        selectedBarber = barber
        currentView = .barberDetail
        
        do {
            // Load barber's services
            _ = try await apiService.fetchBarberServices(barberId: barber.id)
            // Services would be stored in the barber detail view
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func loadAvailability(for date: Date) async {
        guard let barber = selectedBarber else { return }
        
        isLoading = true
        let dateString = formatDate(date)
        
        do {
            let availability = try await apiService.fetchBarberAvailability(barberId: barber.id, date: dateString)
            availableSlots = availability.availableSlots.filter { $0.isAvailable == true }
        } catch {
            errorMessage = error.localizedDescription
            availableSlots = []
        }
        
        isLoading = false
    }
    
    func createBooking(notes: String?, paymentMethod: String) async -> Bool {
        if liveDataSafetyMode {
            errorMessage = "Live Data Mode is on — booking is disabled to avoid real charges. Use Stripe test mode from a non-production build."
            return false
        }
        guard let barber = selectedBarber,
              let service = selectedService,
              let slot = selectedSlot else {
            errorMessage = "Please select all booking details"
            return false
        }
        
        isLoading = true
        
        let request = CreateBookingRequest(
            barberId: barber.id,
            serviceId: service.id,
            bookingDate: formatDate(selectedDate),
            startTime: slot.startTime,
            notes: notes,
            paymentMethod: paymentMethod
        )
        
        do {
            _ = try await apiService.createBooking(request)
            await loadMyBookings()
            
            // Reset selection
            selectedBarber = nil
            selectedService = nil
            selectedSlot = nil
            currentView = .myBookings
            
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    func cancelBooking(_ booking: Booking, reason: String?) async {
        if liveDataSafetyMode {
            errorMessage = "Live Data Mode is on — changes to live bookings are disabled."
            return
        }
        do {
            _ = try await apiService.cancelBooking(bookingId: booking.id, reason: reason)
            await loadMyBookings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func logout() {
        session.requestLogout()
    }
    
    // MARK: - Private Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

