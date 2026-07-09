import Foundation
import SwiftUI

@MainActor
class BarberViewModel: ObservableObject {
    @Published var barbers: [Barber] = []
    @Published var selectedBarber: Barber?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var selectedCampusId: Int?
    
    // Filters
    @Published var minRating: Double = 0
    @Published var maxPrice: Double = 100
    @Published var selectedSpecialty: String?
    @Published var instantBookOnly = false
    
    private let networkManager = NetworkManager.shared
    
    var filteredBarbers: [Barber] {
        barbers.filter { barber in
            let matchesSearch = searchText.isEmpty ||
                barber.fullName.localizedCaseInsensitiveContains(searchText) ||
                barber.bio.localizedCaseInsensitiveContains(searchText)
            
            let matchesRating = barber.averageRating >= minRating
            
            let matchesInstantBook = !instantBookOnly || barber.instantBook
            
            return matchesSearch && matchesRating && matchesInstantBook
        }
    }
    
    func fetchBarbers(campusId: Int? = nil) async {
        isLoading = true
        errorMessage = nil
        
        do {
            var endpoint = Constants.API.Endpoints.barbers
            
            if let campusId = campusId {
                endpoint += "?campusId=\(campusId)"
            }
            
            let response: BarberResponse = try await networkManager.request(
                endpoint: endpoint,
                authenticated: false
            )
            
            barbers = response.data
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func fetchBarberDetail(id: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response: SingleBarberResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.barberDetail(id: id),
                authenticated: false
            )
            
            selectedBarber = response.data
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func createBarberProfile(
        bio: String,
        pricing: [String: Double],
        specialties: [String],
        yearsExperience: Int?,
        instantBook: Bool
    ) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            struct CreateBarberRequest: Codable {
                let bio: String
                let pricing: [String: Double]
                let specialties: [String]
                let yearsExperience: Int?
                let instantBook: Bool
            }
            
            let request = CreateBarberRequest(
                bio: bio,
                pricing: pricing,
                specialties: specialties,
                yearsExperience: yearsExperience,
                instantBook: instantBook
            )
            
            let _: SingleBarberResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.barbers,
                method: "POST",
                body: request,
                authenticated: true
            )
            
            isLoading = false
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    func uploadPortfolioImage(barberId: String, image: Data, caption: String?) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let _ = try await networkManager.uploadImage(
                endpoint: Constants.API.Endpoints.barberPortfolio(id: barberId),
                image: image
            )
            
            // Refresh barber data
            await fetchBarberDetail(id: barberId)
            
            isLoading = false
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}

