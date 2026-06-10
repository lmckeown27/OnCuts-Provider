import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var selectedCampus: Campus?
    @State private var selectedRole: UserRole = .student
    @State private var campuses: [Campus] = []
    @State private var showingCampusSelection = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                }
                
                Section("Account Details") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    
                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirmPassword)
                    
                    if password != confirmPassword && !confirmPassword.isEmpty {
                        Text("Passwords don't match")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section("Campus") {
                    Button(action: {
                        showingCampusSelection = true
                    }) {
                        HStack {
                            Text(selectedCampus?.name ?? "Select Campus")
                                .foregroundColor(selectedCampus == nil ? .gray : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("Account Type") {
                    Picker("Role", selection: $selectedRole) {
                        Text("Student").tag(UserRole.student)
                        Text("Barber").tag(UserRole.barber)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section {
                    Button(action: {
                        Task {
                            await registerUser()
                        }
                    }) {
                        if authViewModel.isLoading {
                            HStack {
                                ProgressView()
                                Text("Creating account...")
                            }
                        } else {
                            Text("Create Account")
                                .frame(maxWidth: .infinity)
                                .bold()
                        }
                    }
                    .disabled(!isFormValid || authViewModel.isLoading)
                }
                
                if let errorMessage = authViewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCampusSelection) {
                CampusSelectionView(selectedCampus: $selectedCampus, campuses: $campuses)
            }
            .task {
                await loadCampuses()
            }
        }
    }
    
    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        password == confirmPassword &&
        password.count >= 8 &&
        !firstName.isEmpty &&
        !lastName.isEmpty &&
        selectedCampus != nil
    }
    
    private func loadCampuses() async {
        do {
            let response: CampusResponse = try await NetworkManager.shared.request(
                endpoint: Constants.API.Endpoints.campuses
            )
            campuses = response.data
        } catch {
            print("Failed to load campuses: \(error)")
        }
    }
    
    private func registerUser() async {
        guard let campusId = selectedCampus?.id else { return }
        
        await authViewModel.register(
            email: email,
            password: password,
            firstName: firstName,
            lastName: lastName,
            campusId: campusId,
            role: selectedRole
        )
        
        if authViewModel.isAuthenticated {
            dismiss()
        }
    }
}

#Preview {
    SignUpView()
        .environmentObject(AuthViewModel())
}

