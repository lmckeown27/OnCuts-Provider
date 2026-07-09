import Foundation
import SwiftUI

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let networkManager = NetworkManager.shared
    
    init() {
        checkAuthStatus()
    }
    
    func checkAuthStatus() {
        if let token = UserDefaults.standard.string(forKey: Constants.StorageKeys.authToken),
           !token.isEmpty {
            isAuthenticated = true
            // Optionally fetch user profile
        }
    }
    
    func register(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        campusId: Int,
        role: UserRole
    ) async {
        isLoading = true
        errorMessage = nil
        
        do {
            struct RegisterRequest: Codable {
                let email: String
                let password: String
                let firstName: String
                let lastName: String
                let campusId: Int
                let role: String
            }
            
            let request = RegisterRequest(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                campusId: campusId,
                role: role.rawValue
            )
            
            let response: AuthResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.register,
                method: "POST",
                body: request
            )
            
            // Save token
            UserDefaults.standard.set(response.data.token, forKey: Constants.StorageKeys.authToken)
            UserDefaults.standard.set(response.data.user.id, forKey: Constants.StorageKeys.userId)
            UserDefaults.standard.set(response.data.user.role.rawValue, forKey: Constants.StorageKeys.userRole)
            
            currentUser = response.data.user
            isAuthenticated = true
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            struct LoginRequest: Codable {
                let email: String
                let password: String
            }
            
            let request = LoginRequest(email: email, password: password)
            
            let response: AuthResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.login,
                method: "POST",
                body: request
            )
            
            // Save token
            UserDefaults.standard.set(response.data.token, forKey: Constants.StorageKeys.authToken)
            UserDefaults.standard.set(response.data.user.id, forKey: Constants.StorageKeys.userId)
            UserDefaults.standard.set(response.data.user.role.rawValue, forKey: Constants.StorageKeys.userRole)
            
            currentUser = response.data.user
            isAuthenticated = true
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: Constants.StorageKeys.authToken)
        UserDefaults.standard.removeObject(forKey: Constants.StorageKeys.userId)
        UserDefaults.standard.removeObject(forKey: Constants.StorageKeys.userRole)
        
        currentUser = nil
        isAuthenticated = false
    }
    
    func verifyEmail(token: String) async -> Bool {
        do {
            struct VerifyRequest: Codable {
                let token: String
            }
            
            let _: SuccessResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.verifyEmail,
                method: "POST",
                body: VerifyRequest(token: token)
            )
            
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

