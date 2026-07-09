import SwiftUI

struct BookingFlowView: View {
    let barber: Barber
    let selectedService: String?
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = BookingViewModel()
    @State private var currentStep = 1
    @State private var selectedServiceType: String
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var locationDetails = ""
    @State private var specialRequests = ""
    @State private var showingPayment = false
    
    init(barber: Barber, selectedService: String?) {
        self.barber = barber
        self.selectedService = selectedService
        _selectedServiceType = State(initialValue: selectedService ?? barber.pricing.keys.first ?? "")
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Progress indicator
                ProgressIndicatorView(currentStep: currentStep, totalSteps: 4)
                    .padding()
                
                // Step content
                ScrollView {
                    VStack(spacing: 24) {
                        switch currentStep {
                        case 1:
                            ServiceSelectionStep(
                                barber: barber,
                                selectedService: $selectedServiceType
                            )
                        case 2:
                            DateTimeSelectionStep(
                                selectedDate: $selectedDate,
                                selectedTime: $selectedTime,
                                barber: barber
                            )
                        case 3:
                            LocationDetailsStep(
                                locationDetails: $locationDetails,
                                specialRequests: $specialRequests
                            )
                        case 4:
                            BookingConfirmationStep(
                                barber: barber,
                                service: selectedServiceType,
                                date: selectedDate,
                                time: selectedTime,
                                location: locationDetails,
                                requests: specialRequests
                            )
                        default:
                            EmptyView()
                        }
                    }
                    .padding()
                }
                
                // Navigation buttons
                HStack {
                    if currentStep > 1 {
                        Button("Back") {
                            currentStep -= 1
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    if currentStep < 4 {
                        Button("Next") {
                            currentStep += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isStepValid)
                    } else {
                        Button(action: {
                            Task {
                                await createBooking()
                            }
                        }) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Confirm & Pay")
                                    .bold()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoading)
                    }
                }
                .padding()
            }
            .navigationTitle("Book Appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Booking Created", isPresented: .constant(viewModel.errorMessage == nil && !viewModel.isLoading)) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your booking has been submitted!")
            }
        }
    }
    
    private var isStepValid: Bool {
        switch currentStep {
        case 1:
            return !selectedServiceType.isEmpty
        case 2:
            return selectedDate > Date()
        case 3:
            return !locationDetails.isEmpty
        default:
            return true
        }
    }
    
    private func createBooking() async {
        // Combine date and time
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
        
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        
        let scheduledDateTime = calendar.date(from: combined) ?? Date()
        
        // Default duration based on service (would be fetched from barber services)
        let duration = 45
        
        let success = await viewModel.createBooking(
            barberId: barber.id,
            serviceType: selectedServiceType,
            scheduledTime: scheduledDateTime,
            durationMinutes: duration,
            locationDetails: locationDetails,
            specialRequests: specialRequests.isEmpty ? nil : specialRequests
        )
        
        if success {
            dismiss()
        }
    }
}

struct ProgressIndicatorView: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                ZStack {
                    Circle()
                        .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 30, height: 30)
                    
                    if step < currentStep {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.caption)
                    } else {
                        Text("\(step)")
                            .foregroundColor(step == currentStep ? .white : .gray)
                            .font(.caption)
                    }
                }
                
                if step < totalSteps {
                    Rectangle()
                        .fill(step < currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
    }
}

struct ServiceSelectionStep: View {
    let barber: Barber
    @Binding var selectedService: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Service")
                .font(.title2)
                .bold()
            
            ForEach(Array(barber.pricing.keys.sorted()), id: \.self) { service in
                Button(action: {
                    selectedService = service
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(service)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("45 minutes") // Would come from service data
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("$\(Int(barber.pricing[service] ?? 0))")
                            .font(.title3)
                            .bold()
                            .foregroundColor(.green)
                        
                        if selectedService == service {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(
                        selectedService == service ?
                            Color.blue.opacity(0.1) :
                            Color(.secondarySystemBackground)
                    )
                    .cornerRadius(12)
                }
            }
        }
    }
}

struct DateTimeSelectionStep: View {
    @Binding var selectedDate: Date
    @Binding var selectedTime: Date
    let barber: Barber
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Date & Time")
                .font(.title2)
                .bold()
            
            DatePicker("Date", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
            
            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
            
            // Available time slots would be shown here
            Text("Available times based on barber's schedule")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct LocationDetailsStep: View {
    @Binding var locationDetails: String
    @Binding var specialRequests: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Location & Details")
                .font(.title2)
                .bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Where should the barber meet you?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("e.g., Smith Hall, Room 204", text: $locationDetails, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Special Requests (Optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("Any specific requests or preferences?", text: $specialRequests, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
        }
    }
}

struct BookingConfirmationStep: View {
    let barber: Barber
    let service: String
    let date: Date
    let time: Date
    let location: String
    let requests: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Confirm Booking")
                .font(.title2)
                .bold()
            
            VStack(spacing: 16) {
                ConfirmationRow(label: "Barber", value: barber.fullName)
                ConfirmationRow(label: "Service", value: service)
                ConfirmationRow(label: "Date", value: date.formatted(date: .long, time: .omitted))
                ConfirmationRow(label: "Time", value: time.formatted(date: .omitted, time: .shortened))
                ConfirmationRow(label: "Location", value: location)
                
                if !requests.isEmpty {
                    ConfirmationRow(label: "Requests", value: requests)
                }
                
                Divider()
                
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text("$\(Int(barber.pricing[service] ?? 0))")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            
            Text("Payment will be processed after service completion")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

struct ConfirmationRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.body)
        }
    }
}

