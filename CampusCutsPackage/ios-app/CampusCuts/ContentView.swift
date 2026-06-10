import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                if authViewModel.currentUser?.role == .barber {
                    BarberTabView()
                } else {
                    StudentTabView()
                }
            } else {
                LoginView()
            }
        }
    }
}

struct StudentTabView: View {
    var body: some View {
        TabView {
            DiscoveryView()
                .tabItem {
                    Label("Discover", systemImage: "scissors")
                }
            
            BookingsListView()
                .tabItem {
                    Label("Bookings", systemImage: "calendar")
                }
            
            StudentProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
        .accentColor(.blue)
    }
}

struct BarberTabView: View {
    var body: some View {
        TabView {
            BarberDashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
            
            BarberCalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
            
            EarningsView()
                .tabItem {
                    Label("Earnings", systemImage: "dollarsign.circle.fill")
                }
            
            BarberProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
        .accentColor(.green)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(NetworkManager())
}

