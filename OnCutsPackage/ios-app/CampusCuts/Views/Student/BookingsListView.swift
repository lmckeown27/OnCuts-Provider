import SwiftUI

struct BookingsListView: View {
    @StateObject private var viewModel = BookingViewModel()
    @State private var selectedFilter: BookingFilter = .upcoming
    
    enum BookingFilter: String, CaseIterable {
        case upcoming = "Upcoming"
        case past = "Past"
        case cancelled = "Cancelled"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(BookingFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Bookings list
                if viewModel.isLoading {
                    ProgressView("Loading bookings...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.bookings.isEmpty {
                    ContentUnavailableView(
                        "No Bookings",
                        systemImage: "calendar.badge.clock",
                        description: Text("You don't have any bookings yet")
                    )
                } else {
                    List {
                        ForEach(viewModel.bookings) { booking in
                            NavigationLink(destination: BookingDetailView(booking: booking)) {
                                BookingRowView(booking: booking)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("My Bookings")
            .refreshable {
                await viewModel.fetchBookings()
            }
            .task {
                await viewModel.fetchBookings()
            }
        }
    }
}

struct BookingRowView: View {
    let booking: Booking
    
    var body: some View {
        HStack(spacing: 12) {
            // Barber image or placeholder
            if let imageUrl = booking.barberImage {
                AsyncImage(url: URL(string: imageUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let barberName = booking.barberFullName {
                    Text(barberName)
                        .font(.headline)
                }
                
                Text(booking.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let location = booking.locationDetails {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Status badge (would show actual status from blockchain)
            Text("Pending")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

struct BookingDetailView: View {
    let booking: Booking
    @StateObject private var viewModel = BookingViewModel()
    @State private var showingCancelConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Barber info
                if let barberName = booking.barberFullName {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Barber")
                            .font(.headline)
                        Text(barberName)
                            .font(.title3)
                    }
                }
                
                Divider()
                
                // Booking details
                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "Date", value: booking.createdAt.formatted(date: .long, time: .omitted))
                    DetailRow(label: "Time", value: booking.createdAt.formatted(date: .omitted, time: .shortened))
                    
                    if let location = booking.locationDetails {
                        DetailRow(label: "Location", value: location)
                    }
                    
                    if let requests = booking.specialRequests {
                        DetailRow(label: "Special Requests", value: requests)
                    }
                }
                
                Divider()
                
                // Actions
                VStack(spacing: 12) {
                    Button(action: {
                        showingCancelConfirmation = true
                    }) {
                        Text("Cancel Booking")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        // Open chat
                    }) {
                        Label("Message Barber", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Booking Details")
        .confirmationDialog("Cancel Booking?", isPresented: $showingCancelConfirmation) {
            Button("Cancel Booking", role: .destructive) {
                Task {
                    await viewModel.cancelBooking(id: booking.blockchainBookingId, reason: nil)
                }
            }
            Button("Keep Booking", role: .cancel) {}
        } message: {
            Text("Are you sure you want to cancel this booking?")
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

#Preview {
    BookingsListView()
}

