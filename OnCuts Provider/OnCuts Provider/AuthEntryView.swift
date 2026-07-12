import AuthenticationServices
import OnCutsModule
import SwiftUI

/// Integrated Workflow auth — email-first landing, returning sign-in, and barber registration.
struct AuthEntryView: View {
    @Environment(ProviderSession.self) private var session
    @State private var authPath = NavigationPath()

    @State private var email = ""
    @State private var emailFieldInvalid = false
    @State private var emailIsSchoolEmail = false
    @State private var showsReturningPasswordField = false
    @State private var showsCreateAccountPrompt = false
    @State private var showsBecomeOperatorPrompt = false
    @State private var landingResolvedEmail: String?
    @FocusState private var landingFocusedField: LandingField?
    @State private var password = ""
    @State private var isLandingPasswordVisible = false
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var acceptedTerms = false
    @State private var presentedLegalDocument: LegalDocument?

    @State private var campuses: [OnCutsSignUpCampus] = []
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
        case createAccount
    }

    private enum LandingField: Hashable {
        case email
        case password
    }

    private enum AuthLandingInputKind {
        case email
        case password
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

    /// Integrated Workflow content width — 24pt side padding applied at the stack level.
    private let authContentMaxWidth: CGFloat = 360
    private let authHorizontalPadding: CGFloat = 24
    private let authIconSize: CGFloat = 120

    private var showsLandingEmailResolutionPrompt: Bool {
        showsCreateAccountPrompt || showsBecomeOperatorPrompt
    }

    private var showsLandingPasswordField: Bool {
        showsReturningPasswordField || showsBecomeOperatorPrompt
    }

    private var landingResolutionMessage: String? {
        if showsCreateAccountPrompt {
            return "No account found for this email."
        }
        if showsBecomeOperatorPrompt {
            return "This account is not an Operator"
        }
        return nil
    }

    private var landingPrimaryActionDisabled: Bool {
        if isBusy { return true }
        if showsLandingPasswordField, password.isEmpty { return true }
        return false
    }

    var body: some View {
        NavigationStack(path: $authPath) {
            integratedAuthLanding
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .providerAuthIntegratedScreenChrome()
                .navigationDestination(for: AuthDestination.self) { dest in
                    switch dest {
                    case .createAccount:
                        createAccountPage
                    }
                }
                .onChange(of: authPath.count) { _, newCount in
                    if newCount == 0 {
                        resetCreateAccountFlow()
                        emailFieldInvalid = false
                        emailIsSchoolEmail = false
                        errorText = nil
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
        .tint(.providerBrandGold)
        .foregroundStyle(Color.lavaShellCream)
    }

    // MARK: - Integrated landing

    private var integratedAuthLanding: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissKeyboard() }

                    VStack(spacing: 12) {
                        Image("OnCutsProviderAppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: authIconSize, height: authIconSize)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                            .accessibilityHidden(true)

                        Text("OnCuts Operator")
                            .font(.provider(.largeTitle, weight: .bold))
                            .foregroundStyle(Color.providerBrandGold)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissKeyboard() }

                    VStack(alignment: .leading, spacing: 8) {
                        authLandingTextField(
                            placeholder: "Email",
                            text: $email,
                            isInvalid: emailFieldInvalid || emailIsSchoolEmail,
                            kind: .email,
                            reservedTrailingSpace: showsLandingEmailResolutionPrompt ? 28 : 0
                        )
                        .focused($landingFocusedField, equals: LandingField.email)
                        .overlay(alignment: .trailing) {
                            if showsLandingEmailResolutionPrompt {
                                Button {
                                    clearLandingEmail()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.lavaShellCreamSecondary)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.14), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 12)
                                .accessibilityLabel("Clear email")
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        }
                        .onChange(of: email) { _, newValue in
                            let normalized = ProviderAuthEmailValidation.normalized(newValue)
                            if let resolved = landingResolvedEmail, normalized != resolved {
                                resetLandingEmailResolution()
                            }
                            if emailIsSchoolEmail, !ProviderAuthEmailValidation.isSchoolEmail(newValue) {
                                emailIsSchoolEmail = false
                            }
                            if emailFieldInvalid,
                               ProviderAuthEmailValidation.isValid(newValue),
                               !ProviderAuthEmailValidation.isSchoolEmail(newValue) {
                                emailFieldInvalid = false
                            }
                        }

                        if showsLandingPasswordField {
                            authLandingTextField(
                                placeholder: "Password",
                                text: $password,
                                isInvalid: false,
                                kind: .password,
                                isPasswordVisible: $isLandingPasswordVisible
                            )
                            .focused($landingFocusedField, equals: LandingField.password)
                            .transition(ProviderRootTransition.passwordFieldPresentation)
                        }

                        if emailIsSchoolEmail {
                            Text("We'd rather you not sign up with your school email :)")
                                .font(.provider(.caption))
                                .foregroundStyle(.red)
                        } else if emailFieldInvalid {
                            Text("Enter a valid email address.")
                                .font(.provider(.caption))
                                .foregroundStyle(.red)
                        }
                    }
                    .animation(ProviderRootTransition.passwordFieldReveal, value: showsLandingPasswordField)
                    .animation(ProviderRootTransition.passwordFieldReveal, value: showsLandingEmailResolutionPrompt)

                    if let landingResolutionMessage {
                        Text(landingResolutionMessage)
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(ProviderRootTransition.passwordFieldPresentation)
                            .animation(ProviderRootTransition.passwordFieldReveal, value: showsLandingEmailResolutionPrompt)
                    }

                    Button {
                        Task { await continueWithEmail() }
                    } label: {
                        Group {
                            if isBusy {
                                ProgressView()
                                    .tint(Color.providerOnBrandGold)
                            } else {
                                Text(landingPrimaryButtonTitle)
                                    .font(.provider(.headline, weight: .semibold))
                                    .contentTransition(.interpolate)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(Color.providerOnBrandGold)
                        .background(Color.providerBrandGold, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(landingPrimaryActionDisabled)
                    .animation(ProviderRootTransition.passwordFieldReveal, value: showsLandingPasswordField)
                    .animation(ProviderRootTransition.passwordFieldReveal, value: showsLandingEmailResolutionPrompt)

                    if let errorText, authPath.isEmpty {
                        Text(errorText)
                            .font(.provider(.footnote))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    authSocialDivider
                        .contentShape(Rectangle())
                        .onTapGesture { dismissKeyboard() }

                    integratedOAuthPillRow

                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissKeyboard() }
                }
                .frame(maxWidth: authContentMaxWidth)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                .padding(.horizontal, authHorizontalPadding)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
        }
    }

    @ViewBuilder
    private func authLandingTextField(
        placeholder: String,
        text: Binding<String>,
        isInvalid: Bool,
        kind: AuthLandingInputKind,
        reservedTrailingSpace: CGFloat = 0,
        isPasswordVisible: Binding<Bool>? = nil
    ) -> some View {
        let showsPasswordToggle = kind == .password && isPasswordVisible != nil
        let trailingInset = reservedTrailingSpace + (showsPasswordToggle ? 36 : 0)

        Group {
            switch kind {
            case .email:
                TextField(placeholder, text: text)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    #endif
            case .password:
                if isPasswordVisible?.wrappedValue == true {
                    TextField(placeholder, text: text)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: text)
                        .textContentType(.password)
                }
            }
        }
        .font(.provider(.body))
        .padding(.leading, 16)
        .padding(.trailing, 16 + trailingInset)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isInvalid ? Color.red : Color.white.opacity(0.22),
                    lineWidth: isInvalid ? 1.5 : 0.8
                )
        )
        .overlay(alignment: .trailing) {
            if showsPasswordToggle, let isPasswordVisible {
                Button {
                    isPasswordVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isPasswordVisible.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .accessibilityLabel(isPasswordVisible.wrappedValue ? "Hide password" : "Show password")
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(Color.providerBrandGold)
    }

    private var authSocialDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.lavaShellCream.opacity(0.28))
                .frame(height: 1)
            Text("Or")
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Rectangle()
                .fill(Color.lavaShellCream.opacity(0.28))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var integratedOAuthPillRow: some View {
        #if os(iOS) || os(visionOS) || os(macOS)
        if GoogleSignInAppSupport.isConfigured {
            HStack(spacing: 12) {
                integratedApplePill
                integratedGooglePill
            }
        } else {
            integratedApplePill
        }
        #else
        integratedApplePill
        #endif
    }

    private var integratedApplePill: some View {
        Button {
            startAppleIDSignIn()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "apple.logo")
                    .font(.provider(size: 16, weight: .semibold))
                Text("Apple")
                    .font(.provider(.subheadline, weight: .semibold))
                if isBusy {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Continue with Apple")
    }

    #if os(iOS) || os(visionOS) || os(macOS)
    private var integratedGooglePill: some View {
        Button {
            Task { await signInWithGoogle() }
        } label: {
            HStack(spacing: 6) {
                OnCutsGoogleGMark(size: 18)
                Text("Google")
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color(white: 0.18))
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.94), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Continue with Google")
    }
    #endif

    // MARK: - Create account (pushed)

    private var createAccountPage: some View {
        Form {
            createAccountSections
            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.provider(.footnote))
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
        .tint(.providerBrandGold)
        .providerAuthIntegratedScreenChrome()
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

    private var selectedCreateAccountCampus: OnCutsSignUpCampus? {
        campuses.first { $0.id == selectedCampusId }
    }

    private var filteredCreateAccountCampuses: [OnCutsSignUpCampus] {
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
                    .font(.provider(.footnote))
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
                    .font(.provider(.subheadline))
                    .foregroundStyle(Color.lavaShellCream)
                    .fixedSize(horizontal: false, vertical: true)
                // Separate rows: multiple `Button`s in one Form `HStack` often route taps to the wrong action.
                Button("Terms of Service") {
                    presentedLegalDocument = .terms
                }
                .buttonStyle(.borderless)
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(Color.providerOlive)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Privacy Policy") {
                    presentedLegalDocument = .privacy
                }
                .buttonStyle(.borderless)
                .font(.provider(.subheadline, weight: .semibold))
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
            campuses = try await OnCutsSignUpAPI.fetchCampuses(
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
        OnCutsAppleIDSignInCoordinator.perform { result in
            Task { @MainActor in
                isBusy = false
                await handleAppleSignIn(result)
            }
        }
    }

    private func clearLandingEmail() {
        withAnimation(ProviderRootTransition.passwordFieldReveal) {
            email = ""
            emailFieldInvalid = false
            emailIsSchoolEmail = false
            showsReturningPasswordField = false
            showsCreateAccountPrompt = false
            showsBecomeOperatorPrompt = false
            landingResolvedEmail = nil
            password = ""
            isLandingPasswordVisible = false
            landingFocusedField = LandingField.email
        }
    }

    private var landingPrimaryButtonTitle: String {
        if showsReturningPasswordField { return "Sign in" }
        if showsCreateAccountPrompt { return "Create Account?" }
        if showsBecomeOperatorPrompt { return "Become an Operator?" }
        return "Continue"
    }

    private func resetLandingEmailResolution(animated: Bool = true) {
        let updates = {
            showsReturningPasswordField = false
            showsCreateAccountPrompt = false
            showsBecomeOperatorPrompt = false
            landingResolvedEmail = nil
            password = ""
            isLandingPasswordVisible = false
            landingFocusedField = nil
        }
        if animated {
            withAnimation(ProviderRootTransition.passwordFieldReveal) {
                updates()
            }
        } else {
            updates()
        }
    }

    private func resetCreateAccountFlow() {
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

    private func continueWithEmail() async {
        errorText = nil
        guard ProviderAuthEmailValidation.isValid(email) else {
            emailFieldInvalid = true
            emailIsSchoolEmail = false
            return
        }
        if ProviderAuthEmailValidation.isSchoolEmail(email) {
            emailIsSchoolEmail = true
            emailFieldInvalid = false
            return
        }
        emailFieldInvalid = false
        emailIsSchoolEmail = false
        let normalized = ProviderAuthEmailValidation.normalized(email)
        email = normalized

        if showsReturningPasswordField || showsBecomeOperatorPrompt {
            await signIn(routeToProviderEnrollment: showsBecomeOperatorPrompt)
            return
        }

        if showsCreateAccountPrompt {
            dismissKeyboard()
            authPath.append(AuthDestination.createAccount)
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let status = try await OnCutsAuthService.checkAccountStatus(
                email: normalized,
                apiV1BaseTrimmed: AppConfiguration.apiV1BaseTrimmed
            )
            errorText = nil
            if status.exists {
                password = ""
                isLandingPasswordVisible = false
                withAnimation(ProviderRootTransition.passwordFieldReveal) {
                    landingResolvedEmail = normalized
                    showsCreateAccountPrompt = false
                    showsBecomeOperatorPrompt = false
                    if status.isOperator {
                        showsReturningPasswordField = true
                    } else {
                        showsReturningPasswordField = false
                        showsBecomeOperatorPrompt = true
                    }
                }
                landingFocusedField = LandingField.password
            } else {
                withAnimation(ProviderRootTransition.passwordFieldReveal) {
                    showsReturningPasswordField = false
                    showsBecomeOperatorPrompt = false
                    password = ""
                    isLandingPasswordVisible = false
                    landingFocusedField = nil
                    landingResolvedEmail = normalized
                    showsCreateAccountPrompt = true
                }
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func signIn(routeToProviderEnrollment: Bool = false) async {
        dismissKeyboard()
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            try await session.signIn(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                routeToProviderEnrollment: routeToProviderEnrollment
            )
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
            if isOAuthUserCancellation(error) { return }
            GoogleSignInAppSupport.signOutSDK()
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if isOAuthUserCancellation(error) { return }
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

    /// User dismissed Apple / Google without completing — not an error to surface on the landing.
    private func isOAuthUserCancellation(_ error: Error) -> Bool {
        if let authErr = error as? ASAuthorizationError, authErr.code == .canceled {
            return true
        }
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        #if os(iOS) || os(visionOS) || os(macOS)
        // Google Sign-In: `GIDSignInErrorCode.canceled` == -5, domain `com.google.GIDSignIn`.
        if ns.domain == "com.google.GIDSignIn", ns.code == -5 {
            return true
        }
        #endif
        let message = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            .lowercased()
        return message.contains("canceled the sign-in")
            || message.contains("cancelled the sign-in")
            || message.contains("the user canceled")
            || message.contains("the user cancelled")
    }

    private func registerSendCode() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        if ProviderAuthEmailValidation.isSchoolEmail(email) {
            errorText = "We'd rather you not sign up with your school email :)"
            return
        }
        do {
            let req = OnCutsRegisterRequest(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                role: "barber",
                campusId: selectedCampusId,
                acceptedTerms: acceptedTerms
            )
            let sent = try await OnCutsAuthService.sendRegistrationVerificationEmail(
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
            let verified = try await OnCutsAuthService.verify(
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
            _ = try await OnCutsAuthService.resendVerificationCode(
                email: verificationEmail,
                apiV1BaseTrimmed: AppConfiguration.apiV1BaseTrimmed
            )
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func dismissKeyboard() {
        landingFocusedField = nil
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
