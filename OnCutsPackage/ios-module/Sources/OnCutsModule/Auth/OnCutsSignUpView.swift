import SwiftUI

/// Email + password sign-up aligned with the legacy CampusCuts iOS `SignUpView` and `POST /api/v1/auth/register` + `verify-email`.
public struct OnCutsSignUpView: View {
    public let apiV1BaseTrimmed: String
    /// Called after email verification returns JWTs.
    public let onSignedIn: (OnCutsVerifiedSession) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .form

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var accountKind: AccountKind = .student
    @State private var selectedCampus: OnCutsSignUpCampus?
    @State private var campuses: [OnCutsSignUpCampus] = []
    @State private var showCampusPicker = false

    @State private var verificationEmail = ""
    @State private var verificationCode = ""
    @State private var devCodeHint: String?

    @State private var isLoading = false
    @State private var errorMessage: String?

    private enum Phase {
        case form
        case verifyEmail
    }

    private enum AccountKind: String, CaseIterable, Identifiable {
        case student
        case barber
        var id: String { rawValue }
        var label: String {
            switch self {
            case .student: return "Student"
            case .barber: return "Barber"
            }
        }
    }

    public init(apiV1BaseTrimmed: String, onSignedIn: @escaping (OnCutsVerifiedSession) -> Void) {
        self.apiV1BaseTrimmed = apiV1BaseTrimmed
        self.onSignedIn = onSignedIn
    }

    public var body: some View {
        Group {
            switch phase {
            case .form:
                formContent
            case .verifyEmail:
                verifyContent
            }
        }
        .navigationTitle(phase == .form ? "Sign Up" : "Verify email")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .sheet(isPresented: $showCampusPicker) {
            NavigationStack {
                List(campuses) { c in
                    Button {
                        selectedCampus = c
                        showCampusPicker = false
                    } label: {
                        HStack {
                            Text(c.name)
                            Spacer()
                            if selectedCampus?.id == c.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .navigationTitle("Campus")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showCampusPicker = false }
                    }
                }
            }
        }
        .task(id: accountKind) {
            #if os(iOS)
            if accountKind == .barber {
                await loadCampusesIfNeeded()
            }
            #else
            await loadCampusesIfNeeded()
            #endif
        }
    }

    // MARK: - Form

    @ViewBuilder
    private var campusSelectionSection: some View {
        Section("Campus") {
            Button {
                showCampusPicker = true
            } label: {
                HStack {
                    Text(selectedCampus?.name ?? "Select campus")
                        .foregroundStyle(selectedCampus == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            if accountKind == .student {
                Button("No campus (optional)") {
                    selectedCampus = nil
                }
                .font(.subheadline)
            }
        }
    }

    private var formContent: some View {
        Form {
            Section("Personal information") {
                TextField("First name", text: $firstName)
                TextField("Last name", text: $lastName)
            }
            Section("Account") {
                TextField("Email", text: $email)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                SecureField("Confirm password", text: $confirmPassword)
                if password != confirmPassword, !confirmPassword.isEmpty {
                    Text("Passwords don’t match")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            #if os(iOS)
            if accountKind == .barber {
                campusSelectionSection
            }
            #else
            campusSelectionSection
            #endif
            Section("Account type") {
                Picker("Role", selection: $accountKind) {
                    ForEach(AccountKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
            }
            if let errorMessage, !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await submitRegister() }
                } label: {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Creating account…")
                        }
                    } else {
                        Text("Create account")
                            .frame(maxWidth: .infinity)
                            .bold()
                    }
                }
                .disabled(!isFormValid || isLoading)
            }
        }
    }

    // MARK: - Verify

    private var verifyContent: some View {
        Form {
            Section {
                Text("We sent a verification code to **\(verificationEmail)**.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let devCodeHint, !devCodeHint.isEmpty {
                Section("Development") {
                    Text("Server returned code: **\(devCodeHint)**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Code") {
                TextField("6-digit code", text: $verificationCode)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }
            if let errorMessage, !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await submitVerify() }
                } label: {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Verifying…")
                        }
                    } else {
                        Text("Verify and sign in")
                            .frame(maxWidth: .infinity)
                            .bold()
                    }
                }
                .disabled(verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 || isLoading)
            }
        }
    }

    private var isFormValid: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !password.isEmpty, password == confirmPassword, password.count >= 8, !f.isEmpty, !l.isEmpty else {
            return false
        }
        return true
    }

    private func loadCampusesIfNeeded() async {
        guard campuses.isEmpty else { return }
        do {
            campuses = try await OnCutsSignUpAPI.fetchCampuses(apiV1BaseTrimmed: apiV1BaseTrimmed)
        } catch {
            campuses = []
        }
    }

    private func submitRegister() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let req = OnCutsRegisterRequest(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            role: accountKind.rawValue,
            campusId: selectedCampus?.id
        )
        do {
            let sent = try await OnCutsSignUpAPI.register(apiV1BaseTrimmed: apiV1BaseTrimmed, request: req)
            verificationEmail = sent.email
            devCodeHint = sent.devVerificationCode
            verificationCode = sent.devVerificationCode ?? ""
            phase = .verifyEmail
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitVerify() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let em = verificationEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !em.isEmpty else {
            errorMessage = "Enter the verification code."
            return
        }
        do {
            let session = try await OnCutsSignUpAPI.verifyEmail(
                apiV1BaseTrimmed: apiV1BaseTrimmed,
                email: em,
                phone: nil,
                code: code
            )
            onSignedIn(session)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
