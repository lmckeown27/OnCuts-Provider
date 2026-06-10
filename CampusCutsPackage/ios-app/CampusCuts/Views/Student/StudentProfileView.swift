import SwiftUI

struct StudentProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 70, height: 70)
                            .overlay(
                                Text(authViewModel.currentUser?.firstName.prefix(1).uppercased() ?? "?")
                                    .font(.title)
                                    .foregroundColor(.blue)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authViewModel.currentUser?.fullName ?? "")
                                .font(.title3)
                                .bold()
                            
                            Text(authViewModel.currentUser?.email ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Account") {
                    NavigationLink(destination: Text("Edit Profile")) {
                        Label("Edit Profile", systemImage: "person.circle")
                    }
                    
                    NavigationLink(destination: Text("Booking History")) {
                        Label("Booking History", systemImage: "clock.arrow.circlepath")
                    }
                    
                    NavigationLink(destination: Text("Saved Barbers")) {
                        Label("Saved Barbers", systemImage: "heart.fill")
                    }
                }
                
                Section("Preferences") {
                    NavigationLink(destination: Text("Notifications")) {
                        Label("Notifications", systemImage: "bell.fill")
                    }
                    
                    NavigationLink(destination: Text("Payment Methods")) {
                        Label("Payment Methods", systemImage: "creditcard.fill")
                    }
                }
                
                Section("Support") {
                    NavigationLink(destination: Text("Contact Us")) {
                        Label("Contact Us", systemImage: "envelope.fill")
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
    StudentProfileView()
        .environmentObject(AuthViewModel())
}

