import SwiftUI
import Charts

struct BarberDashboardView: View {
    @StateObject private var viewModel = BarberDashboardViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Quick stats cards
                    StatsCardsView(viewModel: viewModel)
                    
                    // Earnings chart
                    EarningsChartView(viewModel: viewModel)
                    
                    // Recent bookings
                    RecentBookingsView(viewModel: viewModel)
                    
                    // Performance metrics
                    PerformanceMetricsView(viewModel: viewModel)
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await viewModel.loadDashboardData()
            }
            .task {
                await viewModel.loadDashboardData()
            }
        }
    }
}

struct StatsCardsView: View {
    @ObservedObject var viewModel: BarberDashboardViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(
                    title: "Today's Earnings",
                    value: "$\(viewModel.todayEarnings)",
                    icon: "dollarsign.circle.fill",
                    color: .green
                )
                
                StatCard(
                    title: "This Week",
                    value: "$\(viewModel.weekEarnings)",
                    icon: "calendar",
                    color: .blue
                )
            }
            
            HStack(spacing: 12) {
                StatCard(
                    title: "Pending",
                    value: "\(viewModel.pendingBookings)",
                    icon: "clock.fill",
                    color: .orange
                )
                
                StatCard(
                    title: "Rating",
                    value: String(format: "%.1f★", viewModel.averageRating),
                    icon: "star.fill",
                    color: .yellow
                )
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .bold()
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct EarningsChartView: View {
    @ObservedObject var viewModel: BarberDashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Earnings")
                .font(.headline)
            
            // Placeholder for chart
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 200)
                .overlay(
                    Text("Chart: Last 7 days earnings")
                        .foregroundColor(.secondary)
                )
        }
    }
}

struct RecentBookingsView: View {
    @ObservedObject var viewModel: BarberDashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Bookings")
                    .font(.headline)
                
                Spacer()
                
                NavigationLink(destination: Text("All Bookings")) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            
            if viewModel.recentBookings.isEmpty {
                Text("No recent bookings")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewModel.recentBookings.prefix(5)) { booking in
                    BookingRowView(booking: booking)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct PerformanceMetricsView: View {
    @ObservedObject var viewModel: BarberDashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance")
                .font(.headline)
            
            HStack {
                MetricView(
                    label: "Completion Rate",
                    value: "\(viewModel.completionRate)%",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                Divider()
                
                MetricView(
                    label: "Response Time",
                    value: "\(viewModel.avgResponseTime)m",
                    icon: "clock.fill",
                    color: .blue
                )
                
                Divider()
                
                MetricView(
                    label: "Repeat Clients",
                    value: "\(viewModel.repeatClientRate)%",
                    icon: "arrow.clockwise",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct MetricView: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// ViewModel for dashboard
@MainActor
class BarberDashboardViewModel: ObservableObject {
    @Published var todayEarnings = 0
    @Published var weekEarnings = 0
    @Published var pendingBookings = 0
    @Published var averageRating = 0.0
    @Published var recentBookings: [Booking] = []
    @Published var completionRate = 0
    @Published var avgResponseTime = 0
    @Published var repeatClientRate = 0
    @Published var isLoading = false
    
    func loadDashboardData() async {
        isLoading = true
        
        // Fetch data from API
        // This would call multiple endpoints to gather dashboard data
        
        // Simulated data for now
        await Task.sleep(1_000_000_000) // 1 second
        
        todayEarnings = 125
        weekEarnings = 450
        pendingBookings = 3
        averageRating = 4.8
        completionRate = 98
        avgResponseTime = 12
        repeatClientRate = 65
        
        isLoading = false
    }
}

#Preview {
    BarberDashboardView()
        .environmentObject(AuthViewModel())
}

