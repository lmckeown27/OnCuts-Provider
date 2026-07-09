import SwiftUI
import PhotosUI

struct BarberProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = BarberViewModel()
    @State private var showingEditProfile = false
    @State private var showingPortfolioManager = false
    
    var body: some View {
        NavigationStack {
            List {
                // Profile section
                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 70, height: 70)
                            .overlay(
                                Text(authViewModel.currentUser?.firstName.prefix(1).uppercased() ?? "?")
                                    .font(.title)
                                    .foregroundColor(.green)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authViewModel.currentUser?.fullName ?? "")
                                .font(.title3)
                                .bold()
                            
                            Text("Barber")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Business") {
                    NavigationLink(destination: Text("Edit Profile")) {
                        Label("Edit Profile", systemImage: "person.circle")
                    }
                    
                    NavigationLink(destination: Text("Portfolio Manager")) {
                        Label("Manage Portfolio", systemImage: "photo.on.rectangle.angled")
                    }
                    
                    NavigationLink(destination: Text("Services & Pricing")) {
                        Label("Services & Pricing", systemImage: "dollarsign.circle")
                    }
                    
                    NavigationLink(destination: Text("Availability")) {
                        Label("Availability Settings", systemImage: "calendar")
                    }
                }
                
                Section("Analytics") {
                    NavigationLink(destination: Text("Performance Metrics")) {
                        Label("Performance Metrics", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    
                    NavigationLink(destination: Text("Client Reviews")) {
                        Label("Client Reviews", systemImage: "star.fill")
                    }
                }
                
                Section("Settings") {
                    NavigationLink(destination: Text("Notifications")) {
                        Label("Notifications", systemImage: "bell.fill")
                    }
                    
                    NavigationLink(destination: Text("Payout Settings")) {
                        Label("Payout Settings", systemImage: "banknote")
                    }
                }
                
                Section("Support") {
                    NavigationLink(destination: Text("Contact Support")) {
                        Label("Contact Support", systemImage: "envelope.fill")
                    }
                }
                
                Section {
                    Button(action: {
                        authViewModel.logout()
                    }) {
                        Text("Log Out")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    BarberProfileView()
        .environmentObject(AuthViewModel())
}

