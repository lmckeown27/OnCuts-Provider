import SwiftUI

struct BarberCalendarView: View {
    @StateObject private var viewModel = BookingViewModel()
    @State private var selectedDate = Date()
    @State private var showingAvailabilitySettings = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Calendar view
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Divider()
                
                // Appointments for selected date
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Appointments")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if viewModel.bookings.isEmpty {
                        ContentUnavailableView(
                            "No Appointments",
                            systemImage: "calendar.badge.clock",
                            description: Text("You have no appointments scheduled for this day")
                        )
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(viewModel.bookings) { booking in
                                    AppointmentCardView(booking: booking, viewModel: viewModel)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingAvailabilitySettings = true
                    }) {
                        Label("Availability", systemImage: "calendar.badge.clock")
                    }
                }
            }
            .sheet(isPresented: $showingAvailabilitySettings) {
                AvailabilitySettingsView()
            }
            .task {
                await viewModel.fetchBookings()
            }
        }
    }
}

struct AppointmentCardView: View {
    let booking: Booking
    @ObservedObject var viewModel: BookingViewModel
    @State private var showingActions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let clientName = booking.clientFullName {
                        Text(clientName)
                            .font(.headline)
                    }
                    
                    Text(booking.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("Pending")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
            }
            
            if let location = booking.locationDetails {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(location)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await viewModel.confirmBooking(id: booking.blockchainBookingId)
                    }
                }) {
                    Text("Confirm")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: {
                    Task {
                        await viewModel.cancelBooking(id: booking.blockchainBookingId, reason: "Barber cancelled")
                    }
                }) {
                    Text("Decline")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct AvailabilitySettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var availability: [DayAvailability] = []
    
    var body: some View {
        NavigationStack {
            Form {
                ForEach(0..<7) { dayIndex in
                    Section(dayName(for: dayIndex)) {
                        Toggle("Available", isOn: .constant(true))
                        
                        DatePicker("Start Time", selection: .constant(Date()), displayedComponents: .hourAndMinute)
                        DatePicker("End Time", selection: .constant(Date()), displayedComponents: .hourAndMinute)
                    }
                }
                
                Section {
                    Button("Save Availability") {
                        // Save availability
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Set Availability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func dayName(for index: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[index]
    }
}

struct DayAvailability {
    var dayOfWeek: Int
    var isAvailable: Bool
    var startTime: Date
    var endTime: Date
}

#Preview {
    BarberDashboardView()
        .environmentObject(AuthViewModel())
}

