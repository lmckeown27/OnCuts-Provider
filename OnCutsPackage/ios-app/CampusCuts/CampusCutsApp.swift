import SwiftUI

@main
struct CampusCutsApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var networkManager = NetworkManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(networkManager)
        }
    }
}

