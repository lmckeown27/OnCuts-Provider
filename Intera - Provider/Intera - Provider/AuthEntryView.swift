import AuthenticationServices
import CampusCutsModule
import SwiftUI

/// Landing: **Sign in manually** (pushed email/password), Apple & Google as side-by-side pills, **Create account** for barber registration.
struct AuthEntryView: View {
    @Environment(ProviderSession.self) private var session
    @State private var authPath = NavigationPath()

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var acceptedTerms = false
    @State private var presentedLegalDocument: LegalDocument?

    @State private var campuses: [CampusCutsSignUpCampus] = []
    @State private var campusesLoading = false
    @State private var showCampusPicker = false
    @State private var selectedCampusId = ""
    @State private var campusSearchText = ""

    /// Distinct sheet identity so Terms and Privacy always open the correct URL
    /// (`SFSafariViewController` does not reload when only the URL state changes).
    private enum LegalDocument: String, Identifiable {
        case terms
        case privacy

        var id: String { rawValue }

        var title: String {
            switch self {
            case .terms: "Terms of Service"
            case .privacy: "Privacy Policy"
            }
        }

        var url: URL {
            switch self {
            case .terms: AppConfiguration.termsOfServiceURL
            case .privacy: AppConfiguration.privacyPolicyURL
            }
        }
    }

    @State private var verificationEmail = ""
    @State private var verificationCode = ""
    @State private var createStep: CreateStep = .collectDetails
    @FocusState private var createAccountFocusedField: CreateAccountField?

    @State private var isBusy = false
    @State private var errorText: String?
    @State private var oAuthPasswordNotice: String?

    private enum AuthDestination: Hashable {
        case manualSignIn
        case createAccount
    }

    private enum CreateStep {
        case collectDetails
        case verifyEmail
    }

    private enum CreateAccountField: Hashable {
        case firstName
        case lastName
        case email
        case password
        case confirmPassword
        case verificationCode
    }

    var body: some View {
        NavigationStack(path: $authPath) {
            authLandingScroll
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .foregroundStyle(Color.lavaShellCream)
                .tint(.providerOlive)
                .providerLavaScreenChrome()
                .navigationDestination(for: AuthDestination.self) { dest in
                    switch dest {
                    case .manualSignIn:
                        manualSignInPage
                    case .createAccount:
                        createAccountPage
                    }
                }
                .onChange(of: authPath.count) { _, newCount in
                    if newCount == 0 {
                        createStep = .collectDetails
                        verificationCode = ""
                        firstName = ""
                        lastName = ""
                        confirmPassword = ""
                        acceptedTerms = false
                        presentedLegalDocument = nil
                        createAccountFocusedField = nil
                        selectedCampusId = ""
                        campusSearchText = ""
                        showCampusPicker = false
                    }
                }
                .alert("Account security", isPresented: Binding(
                    get: { oAuthPasswordNotice != nil },
                    set: { if !$0 { oAuthPasswordNotice = nil } }
                )) {
                    Button("OK", role: .cancel) { oAuthPasswordNotice = nil }
                } message: {
                    Text(oAuthPasswordNotice ?? "")
                }
        }
    }

    // MARK: - Landing

    private var authLandingScroll: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .center, spacing: 20) {
                    Spacer(minLength: 0)

                    Button {
                        errorText = nil
                        password = ""
                        authPath.append(AuthDestination.manualSignIn)
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            Text("Sign in manually")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            Text("Use your email and password")
                                .font(.caption)
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    oauthPillRow
                        .frame(maxWidth: .infinity)

                    Button {
                        errorText = nil
                        authPath.append(AuthDestination.createAccount)
                    } label: {
                        Text("Create account")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    if authPath.isEmpty, let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                .padding(.horizontal, 20)
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var oauthPillRow: some View {
        #if os(iOS) || os(visionOS) || os(macOS)
        if GoogleSignInAppSupport.isConfigured {
            HStack(spacing: 12) {
                appleSignInPill
                    .frame(maxWidth: .infinity)
                googleSignInPill
                    .frame(maxWidth: .infinity)
            }
        } else {
            appleSignInPill
        }
        #else
        appleSignInPill
        #endif
    }

    private var appleSignInPill: some View {
        Button {
            startAppleIDSignIn()
        } label: {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("Continue with")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "apple.logo")
                        .font(.system(size: 15, weight: .semibold))
                    if isBusy {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .frame(minHeight: 50)
            .background(Color.black, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Continue with Apple")
    }

    #if os(iOS) || os(visionOS) || os(macOS)
    @ViewBuilder
    private var googleSignInPill: some View {
        Button {
            Task { await signInWithGoogle() }
        } label: {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Text("Continue with")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.22))
                    InteraGoogleGMark(size: 20)
                    if isBusy {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .frame(minHeight: 50)
            .background(Color.white, in: Capsule())
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Continue with Google")
    }
    #endif

    // MARK: - Manual sign-in (pushed)

    private var manualSignInPage: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            Section {
                Button {
                    Task { await signIn() }
                } label: {
                    if isBusy { ProgressView() }
                    else { Text("Sign in") }
                }
                .disabled(isBusy || email.isEmpty || password.isEmpty)
            }
            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .providerLavaIntegratedFormSurface()
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .navigationTitle("Email sign-in")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
    }

    // MARK: - Create account (pushed)

    private var createAccountPage: some View {
        Form {
            createAccountSections
            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: createStep) { _, _ in dismissKeyboard() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        .providerLavaIntegratedFormSurface()
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .task(id: createStep) {
            if createStep == .collectDetails {
                await loadCreateAccountCampusesIfNeeded()
            }
        }
        .sheet(isPresented: $showCampusPicker) {
            createAccountCampusPickerSheet
        }
        .sheet(item: $presentedLegalDocument) { document in
            NavigationStack {
                ProviderLegalWebView(url: document.url)
                    .id(document.id)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(document.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { presentedLegalDocument = nil }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var selectedCreateAccountCampus: CampusCutsSignUpCampus? {
        campuses.first { $0.id == selectedCampusId }
    }

    private var filteredCreateAccountCampuses: [CampusCutsSignUpCampus] {
        let query = campusSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return campuses }
        return campuses.filter { $0.name.lowercased().contains(query) }
    }

    private var createAccountCampusPickerSheet: some View {
        NavigationStack {
            List {
                if campusesLoading {
                    HStack {
                        ProgressView()
                        Text("Loading campuses…")
                    }
                } else if filteredCreateAccountCampuses.isEmpty {
                    Text(campusSearchText.isEmpty ? "No campuses available." : "No campuses match your search.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredCreateAccountCampuses) { campus in
                        Button {
                            selectedCampusId = campus.id
                            showCampusPicker = false
                        } label: {
                            HStack {
                                Text(campus.name)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if selectedCampusId == campus.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $campusSearchText, prompt: "Search campuses")
            .navigationTitle("Select campus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCampusPicker = false }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var createAccountSections: some View {
        switch createStep {
        case .collectDetails:
            Section("Your name") {
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                    .focused($createAccountFocusedField, equals: .firstName)
                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
                    .focused($createAccountFocusedField, equals: .lastName)
            }
            Section("Account") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .focused($createAccountFocusedField, equals: .email)
                SecureField("Password (min 8 characters)", text: $password)
                    .textContentType(.newPassword)
                    .focused($createAccountFocusedField, equals: .password)
                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .focused($createAccountFocusedField, equals: .confirmPassword)
            }
            Section("Campus") {
                if campusesLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading campuses…")
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
                } else {
                    Button {
                        dismissKeyboard()
                        showCampusPicker = true
                    } label: {
                        HStack {
                            Text(selectedCreateAccountCampus?.name ?? "Select campus")
                                .foregroundStyle(
                                    selectedCreateAccountCampus == nil
                                        ? Color.lavaShellCreamTertiary
                                        : Color.lavaShellCream
                                )
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                termsAcceptanceRow
            }
            Section {
                Button {
                    dismissKeyboard()
                    if let message = registerValidationMessage {
                        errorText = message
                        return
                    }
                    Task { await registerSendCode() }
                } label: {
                    if isBusy { ProgressView() }
                    else { Text("Continue") }
                }
                .disabled(isBusy)
            }
        case .verifyEmail:
            Section {
                Text("Enter the verification code sent to \(verificationEmail).")
                    .font(.footnote)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            Section {
                TextField("Verification code", text: $verificationCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($createAccountFocusedField, equals: .verificationCode)
            }
            Section {
                Button {
                    Task { await verifyAndSignIn() }
                } label: {
                    if isBusy { ProgressView() }
                    else { Text("Verify and continue") }
                }
                .disabled(isBusy || verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
                Button("Resend code") {
                    Task { await resendCode() }
                }
                .disabled(isBusy)
                Button("Start over") {
                    createStep = .collectDetails
                    verificationCode = ""
                    errorText = nil
                }
            }
        }
    }

    /// Toggle plus tappable legal links (web signup parity). Users can open Terms / Privacy in-app
    /// before enabling the toggle; Continue stays disabled until they accept.
    private var termsAcceptanceRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $acceptedTerms)
                .labelsHidden()
                .accessibilityLabel("Agree to Terms of Service and Privacy Policy")
                .accessibilityValue(acceptedTerms ? "Accepted" : "Not accepted")
            VStack(alignment: .leading, spacing: 8) {
                Text("I agree to the Terms of Service and Privacy Policy.")
                    .font(.subheadline)
                    .foregroundStyle(Color.lavaShellCream)
                    .fixedSize(horizontal: false, vertical: true)
                // Separate rows: multiple `Button`s in one Form `HStack` often route taps to the wrong action.
                Button("Terms of Service") {
                    presentedLegalDocument = .terms
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.providerOlive)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Privacy Policy") {
                    presentedLegalDocument = .privacy
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.providerOlive)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// User-facing reason Continue cannot proceed; `nil` when the form is ready to submit.
    private var registerValidationMessage: String? {
        if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter your first and last name."
        }
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter your email address."
        }
        if password.count < 8 {
            return "Password must be at least 8 characters."
        }
        if password != confirmPassword {
            return "Password and confirmation must match."
        }
        if selectedCampusId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Select your campus."
        }
        if !acceptedTerms {
            return "Accept the Terms of Service and Privacy Policy to continue."
        }
        return nil
    }

    private func loadCreateAccountCampusesIfNeeded() async {
        guard campuses.isEmpty, !campusesLoading else { return }
        campusesLoading = true
        defer { campusesLoading = false }
        do {
            campuses = try await CampusCutsSignUpAPI.fetchCampuses(
                apiV1BaseTrimmed: AppConfiguration.apiV1BaseTrimmed
            )
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func startAppleIDSignIn() {
        guard !isBusy else { return }
        isBusy = true
        errorText = nil
        InteraAppleIDSignInCoordinator.perform { result in
            Task { @MainActor in
                isBusy = false
                await handleAppleSignIn(result)
            }
        }
    }

    private func signIn() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            try await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func signInWithGoogle() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let idToken = try await GoogleSignInAppSupport.signInForIdToken()
            let outcome = try await AuthBackendVerification.verifyGoogleIDTokenAndFetchSessionTokens(idToken)
            try await session.adoptVerifiedSession(outcome.session)
            if outcome.needsPlatformPassword {
                oAuthPasswordNotice =
                    "Add an account password when you can (web or in-app) so you can sign in without Google if needed."
            }
        } catch {
            GoogleSignInAppSupport.signOutSDK()
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if let authErr = error as? ASAuthorizationError, authErr.code == .canceled { return }
            errorText = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  !identityToken.isEmpty
            else {
                errorText = "Apple did not return a sign-in token."
                return
            }
            AppleSignInAppSupport.mergeCredentialIntoSupplementStore(credential)

            let emailTrimmed = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let supplementalEmail: String? = emailTrimmed.isEmpty ? AppleSignInSupplementStore.loadEmail() : emailTrimmed

            let givenTrimmed = credential.fullName?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let familyTrimmed = credential.fullName?.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let firstNameSupplement = givenTrimmed.isEmpty ? AppleSignInSupplementStore.loadFirstName() : givenTrimmed
            let lastNameSupplement = familyTrimmed.isEmpty ? AppleSignInSupplementStore.loadLastName() : familyTrimmed

            isBusy = true
            errorText = nil
            defer { isBusy = false }
            do {
                let outcome = try await AuthBackendVerification.verifyAppleIdentityTokenAndFetchSessionTokens(
                    identityToken: identityToken,
                    firstName: firstNameSupplement,
                    lastName: lastNameSupplement,
                    email: supplementalEmail
                )
                try await session.adoptVerifiedSession(outcome.session)
                if outcome.needsPlatformPassword {
                    oAuthPasswordNotice =
                        "Add an account password when you can (web or in-app) so you can sign in without Apple if needed."
                }
            } catch let e as AuthBackendVerificationError {
                errorText = e.errorDescription ?? e.localizedDescription
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func registerSendCode() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let req = CampusCutsRegisterRequest(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                role: "barber",
                campusId: selectedCampusId,
                acceptedTerms: acceptedTerms
            )
            let sent = try await CampusCutsAuthService.sendRegistrationVerificationEmail(
                apiV1BaseTrimmed: AppConfiguration.apiV1BaseTrimmed,
                request: req
            )
            verificationEmail = sent.email
            if let dev = sent.devVerificationCode {
                verificationCode = dev
            }
            createStep = .verifyEmail
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func verifyAndSignIn() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let verified = try await CampusCutsAuthService.verify(
                code: code,
                email: verificationEmail,
                apiV1BaseTrimmed: AppConfiguration.apiV1BaseTrimmed
            )
            try await session.adoptVerifiedSession(verified)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resendCode() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            _ = try await CampusCutsAuthService.resendVerificationCode(
                email: verificationEmail,
                apiV1BaseTrimmed: AppConfiguration.apiV1BaseTrimmed
            )
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func dismissKeyboard() {
        createAccountFocusedField = nil
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }
}
