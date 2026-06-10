//
//  BarberDashboardViewModel.swift
//  CampusCutsModule
//
//  Internal ViewModel for the barber dashboard.
//

import Foundation
import SwiftUI

@MainActor
internal class BarberDashboardViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var pendingBookings: [Booking] = []
    @Published var upcomingBookings: [Booking] = []
    @Published var completedBookings: [Booking] = []
    @Published var selectedTab: DashboardTab = .pending
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let session: UserSessionProtocol
    private let apiService: CampusCutsAPIService
    private let liveDataSafetyMode: Bool
    
    // MARK: - Types
    
    enum DashboardTab: String, CaseIterable {
        case pending = "Pending"
        case upcoming = "Upcoming"
        case completed = "Completed"
    }
    
    // MARK: - Computed Properties
    
    var currentBookings: [Booking] {
        switch selectedTab {
        case .pending:
            return pendingBookings
        case .upcoming:
            return upcomingBookings
        case .completed:
            return completedBookings
        }
    }
    
    var pendingCount: Int { pendingBookings.count }
    var upcomingCount: Int { upcomingBookings.count }
    
    // MARK: - Initialization
    
    init(session: UserSessionProtocol, apiService: CampusCutsAPIService, liveDataSafetyMode: Bool = false) {
        self.session = session
        self.apiService = apiService
        self.liveDataSafetyMode = liveDataSafetyMode
    }
    
    // MARK: - Public Methods
    
    func loadBookings() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let pending = apiService.fetchBookings(status: "PENDING")
            async let accepted = apiService.fetchBookings(status: "ACCEPTED")
            async let completed = apiService.fetchBookings(status: "COMPLETED")
            
            let (p, a, c) = try await (pending, accepted, completed)
            
            self.pendingBookings = p
            self.upcomingBookings = a
            self.completedBookings = c
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func acceptBooking(_ booking: Booking) async {
        if liveDataSafetyMode {
            errorMessage = "Live Data Mode is on — booking actions are disabled."
            return
        }
        do {
            _ = try await apiService.updateBookingStatus(bookingId: booking.id, status: "ACCEPTED")
            await loadBookings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func rejectBooking(_ booking: Booking) async {
        if liveDataSafetyMode {
            errorMessage = "Live Data Mode is on — booking actions are disabled."
            return
        }
        do {
            _ = try await apiService.updateBookingStatus(bookingId: booking.id, status: "REJECTED")
            await loadBookings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func completeBooking(_ booking: Booking) async {
        if liveDataSafetyMode {
            errorMessage = "Live Data Mode is on — booking actions are disabled."
            return
        }
        do {
            _ = try await apiService.updateBookingStatus(bookingId: booking.id, status: "COMPLETED")
            await loadBookings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func logout() {
        session.requestLogout()
    }
}

