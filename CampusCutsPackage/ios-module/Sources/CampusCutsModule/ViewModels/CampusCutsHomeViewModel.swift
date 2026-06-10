//
//  CampusCutsHomeViewModel.swift
//  CampusCutsModule
//
//  Internal ViewModel for the main CampusCuts home screen.
//

import Foundation
import SwiftUI

@MainActor
internal class CampusCutsHomeViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var barbers: [Barber] = []
    @Published var campuses: [Campus] = []
    @Published var selectedCampus: Campus?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    
    // MARK: - Dependencies
    
    private let session: UserSessionProtocol
    private let apiService: CampusCutsAPIService
    
    // MARK: - Computed Properties
    
    var filteredBarbers: [Barber] {
        if searchText.isEmpty {
            return barbers
        }
        return barbers.filter { barber in
            barber.businessName.localizedCaseInsensitiveContains(searchText) ||
            (barber.bio?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var userName: String {
        session.userName
    }
    
    var userRole: String {
        session.userRole
    }
    
    // MARK: - Initialization
    
    init(session: UserSessionProtocol, apiService: CampusCutsAPIService) {
        self.session = session
        self.apiService = apiService
    }
    
    // MARK: - Public Methods
    
    func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let campusesTask = apiService.fetchCampuses()
            async let barbersTask = apiService.fetchBarbers()
            
            let (fetchedCampuses, fetchedBarbers) = try await (campusesTask, barbersTask)
            
            self.campuses = fetchedCampuses
            self.barbers = fetchedBarbers
            
            if selectedCampus == nil, let first = fetchedCampuses.first {
                selectedCampus = first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func selectCampus(_ campus: Campus) async {
        selectedCampus = campus
        isLoading = true
        
        do {
            barbers = try await apiService.fetchBarbers(campusId: campus.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func refreshBarbers() async {
        do {
            barbers = try await apiService.fetchBarbers(campusId: selectedCampus?.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func logout() {
        session.requestLogout()
    }
}

