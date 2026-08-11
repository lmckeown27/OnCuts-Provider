import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Native SwiftUI barber account management — public identity, visibility, and account safety.
struct BarberAccountControlView: View {
    @Environment(ProviderSession.self) private var session

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var biography = ""
    @State private var instagramHandle = ""
    /// Marketplace hide (`isHidden`). Checked = hidden from consumer search. Independent of `isActive`.
    @State private var isHiddenFromConsumers = false
    @State private var isSavingVisibility = false

    @State private var avatarURL: URL?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoLibraryPicker = false
    @State private var showCameraPicker = false
    @State private var isSaving = false
    @State private var isUploadingPhoto = false
    @State private var isHydratingFromServer = false
    @State private var isEditingProfile = false
    @State private var showSignOutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showDeletePasswordSheet = false
    @State private var showingBlockedUsers = false
    @State private var deletePassword = ""
    @State private var isDeletingAccount = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @FocusState private var focusedField: AccountField?

    private enum AccountField: Hashable {
        case firstName
        case lastName
        case aboutYou
        case instagram
    }

    private let profileAvatarSize: CGFloat = ProviderSquaredAvatarMetrics.profileSize
    private let profileCameraButtonSize: CGFloat = 32

    var body: some View {
        Form {
            profileHeaderSection
            coreDetailsSection
            visibilitySection
            accountActionsSection
        }
        .scrollDismissesKeyboard(.immediately)
        .providerLavaIntegratedFormSurface()
        .disabled(isDeletingAccount || isUploadingPhoto || isSaving)
        #if canImport(UIKit)
        .background {
            ProviderAccountKeyboardDismissTapInstaller {
                dismissKeyboard()
            }
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sign Out") {
                    dismissKeyboard()
                    showSignOutAlert = true
                }
                .font(.provider(.body, weight: .semibold))
                .foregroundStyle(Color.red)
            }
            #if canImport(UIKit)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissKeyboard()
                }
                .font(.provider(.body, weight: .semibold))
            }
            #endif
        }
        .overlay {
            if isUploadingPhoto || isDeletingAccount || isSaving {
                ProgressView()
                    .tint(.providerOlive)
            }
        }
        .onAppear(perform: loadFromSession)
        .task {
            await session.refreshMarketplaceVisibilityFromMe()
            loadFromSession()
        }
        .onChange(of: session.barberProfile?.id) { _, _ in
            loadFromSession()
        }
        .onChange(of: session.barberProfile?.isHidden) { _, _ in
            guard !isSavingVisibility else { return }
            loadFromSession()
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard isEditingProfile, let item else { return }
            Task { await uploadProfilePhoto(from: item) }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("Sign Out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task { await session.signOut() }
            }
        } message: {
            Text("You'll lose immediate access to your schedule and inbox on this device until you sign in again. Pending bookings are not cancelled.")
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await beginAccountDeletion() }
            }
        } message: {
            Text("This permanently deletes your account and historical customer records. You will immediately lose access to your schedule, messages, and payout settings. This cannot be undone.")
        }
        .sheet(isPresented: $showDeletePasswordSheet) {
            deletePasswordSheet
        }
        .sheet(isPresented: $showingBlockedUsers) {
            NavigationStack {
                ProviderBlockedUsersHost()
                    .providerPageNavigationTitle("Blocked Users")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingBlockedUsers = false
                            }
                        }
                    }
            }
            .foregroundStyle(Color.lavaShellCream)
            .tint(.providerOlive)
            .providerLavaScreenChrome()
            .presentationDragIndicator(.visible)
        }
        .photosPicker(isPresented: $showPhotoLibraryPicker, selection: $selectedPhotoItem, matching: .images)
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showCameraPicker) {
            ProviderProfileImageCameraPicker { image in
                Task { await uploadProfilePhoto(image: image) }
            }
            .ignoresSafeArea()
        }
        #endif
    }

    // MARK: - Sections

    private var profileHeaderSection: some View {
        Section {
            VStack(spacing: 8) {
                Group {
                    if isEditingProfile {
                        Menu {
                            profilePhotoMenuActions
                        } label: {
                            avatarMenuLabel
                        }
                        .menuStyle(.borderlessButton)
                        .menuOrder(.fixed)
                        .accessibilityLabel("Change profile photo")
                    } else {
                        avatarMenuLabel
                            .accessibilityLabel("Profile photo")
                    }
                }

                editProfileControl

                HStack(spacing: 4) {
                    Text("@")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(accountFieldSecondaryColor)
                    TextField("Instagram", text: $instagramHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .foregroundStyle(accountFieldPrimaryColor)
                        .focused($focusedField, equals: .instagram)
                        .disabled(!isEditingProfile)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(accountFieldChrome(cornerRadius: 14))
                .animation(.easeInOut(duration: 0.18), value: isEditingProfile)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
        }
    }

    private var avatarMenuLabel: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarView
                .opacity(isEditingProfile ? 1 : 0.72)
            if isEditingProfile {
                profileCameraBadge
                    .allowsHitTesting(false)
            }
        }
        .frame(width: profileAvatarSize, height: profileAvatarSize)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.18), value: isEditingProfile)
    }

    private var editProfileControl: some View {
        Group {
            if isEditingProfile {
                Button {
                    Task { await commitProfileEdits() }
                } label: {
                    Text("Save")
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.providerOnOliveFill)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Color.providerOlive,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save profile")
            } else {
                Button {
                    beginEditingProfile()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .frame(width: 36, height: 36)
                        .background(accountGlassChrome(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit profile")
            }
        }
    }

    private var accountFieldPrimaryColor: Color {
        isEditingProfile ? Color.lavaShellCream : Color.lavaShellCreamSecondary
    }

    private var accountFieldSecondaryColor: Color {
        isEditingProfile ? Color.lavaShellCreamSecondary : Color.lavaShellCreamTertiary
    }

    private func accountGlassChrome(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.providerElevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.providerElevatedSurfaceStroke, lineWidth: 0.5)
            )
    }

    private func accountFieldChrome(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isEditingProfile
                    ? Color.providerElevatedSurface
                    : Color.providerElevatedSurface.opacity(0.42)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isEditingProfile
                            ? Color.providerOlive.opacity(0.72)
                            : Color.secondary.opacity(0.55),
                        lineWidth: isEditingProfile ? 1.5 : 1.25
                    )
            )
    }

    @ViewBuilder
    private func accountFormFieldRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .foregroundStyle(accountFieldPrimaryColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accountFieldChrome(cornerRadius: 14))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowSeparator(.hidden)
            .animation(.easeInOut(duration: 0.18), value: isEditingProfile)
    }

    @ViewBuilder
    private var profilePhotoMenuActions: some View {
        #if canImport(UIKit)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button("Take Photo") {
                showCameraPicker = true
            }
        }
        #endif
        Button("Photo Library") {
            showPhotoLibraryPicker = true
        }
    }

    private var profileCameraBadge: some View {
        ZStack {
            Circle()
                .fill(Color.providerOlive)
            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: profileCameraButtonSize, height: profileCameraButtonSize)
        .overlay(
            Circle()
                .strokeBorder(Color(uiColor: ProviderAppearance.shellBase), lineWidth: 2)
        )
        .offset(x: 3, y: 3)
    }

    @ViewBuilder
    private var avatarView: some View {
        let fallbackName = [firstName, lastName].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let displayName = fallbackName.isEmpty ? session.displayName : fallbackName

        ProviderSquaredAvatarView(
            url: avatarURL,
            fallbackName: displayName,
            size: profileAvatarSize
        )
    }

    private var coreDetailsSection: some View {
        Section {
            accountFormFieldRow {
                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .firstName)
                    .disabled(!isEditingProfile)
            }

            accountFormFieldRow {
                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .lastName)
                    .disabled(!isEditingProfile)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("About You")
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(accountFieldSecondaryColor)
                    .underline()
                TextEditor(text: $biography)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(accountFieldPrimaryColor)
                    .focused($focusedField, equals: .aboutYou)
                    .disabled(!isEditingProfile)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accountFieldChrome(cornerRadius: 14))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowSeparator(.hidden)
            .animation(.easeInOut(duration: 0.18), value: isEditingProfile)
        }
    }

    private var visibilitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Toggle(isOn: hideFromConsumersBinding) {
                        Text("Hide my profile from consumers")
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(accountFieldPrimaryColor)
                    }
                    .disabled(isSavingVisibility || session.barberProfile?.id == nil)
                    .tint(.providerOlive)

                    Button {
                        dismissKeyboard()
                        showingBlockedUsers = true
                    } label: {
                        Text("Blocked Users")
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.providerOnOliveFill)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                Color.providerOlive,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                }

                if isHiddenFromConsumers {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warning: Profile Hidden")
                            .font(.provider(.caption, weight: .semibold))
                            .foregroundStyle(Color.orange)
                        Text("It will be virtually impossible for consumers to book a service with you while your profile is hidden. Only enable this if you need a temporary break from taking bookings.")
                            .font(.provider(.caption))
                            .foregroundStyle(accountFieldPrimaryColor.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.orange.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(accountFieldChrome(cornerRadius: 14))
            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
            .listRowBackground(Color.clear)
        }
    }

    private var hideFromConsumersBinding: Binding<Bool> {
        Binding(
            get: { isHiddenFromConsumers },
            set: { newValue in
                guard newValue != isHiddenFromConsumers else { return }
                Task { await saveMarketplaceHidden(newValue) }
            }
        )
    }

    private var accountActionsSection: some View {
        Section {
            Button {
                dismissKeyboard()
                showDeleteAccountAlert = true
            } label: {
                Text("Delete Account")
                    .font(.provider(.body, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
        }
    }

    private var deletePasswordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $deletePassword)
                        .textContentType(.password)
                } footer: {
                    Text("Enter your OnCuts Provider password to permanently delete your account.")
                }
            }
            .providerPageNavigationTitle("Confirm Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        deletePassword = ""
                        showDeletePasswordSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        showDeletePasswordSheet = false
                        Task { await performAccountDeletion(password: deletePassword) }
                        deletePassword = ""
                    }
                    .disabled(deletePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func loadFromSession() {
        isHydratingFromServer = true
        defer {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                isHydratingFromServer = false
            }
        }

        let barber = session.barberProfile
        firstName = barber?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? session.authUser?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        lastName = barber?.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? session.authUser?.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        if firstName.isEmpty, lastName.isEmpty, let barber {
            let parts = barber.resolvedDisplayName.split(separator: " ", maxSplits: 1).map(String.init)
            if let first = parts.first { firstName = first }
            if parts.count > 1 { lastName = parts[1] }
        }

        let bio = barber?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        biography = bio.isEmpty ? "" : bio

        instagramHandle = sanitizedInstagramHandle(barber?.instagramHandle ?? "")
        isHiddenFromConsumers = barber?.isHidden == true
        avatarURL = barber?.avatarURL
    }

    private func sanitizedInstagramHandle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private var composedDisplayName: String {
        let joined = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { return joined }
        return session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginEditingProfile() {
        isEditingProfile = true
    }

    @MainActor
    private func commitProfileEdits() async {
        dismissKeyboard()
        let didSave = await saveProfile()
        if didSave {
            isEditingProfile = false
        }
    }

    @MainActor
    @discardableResult
    private func saveProfile() async -> Bool {
        guard let barberId = session.barberProfile?.id else { return false }

        isSaving = true
        defer { isSaving = false }

        do {
            // Preserve specialties managed on Services Offered; Account does not edit them.
            let existingSpecialties = session.barberProfile?.specialties?
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
            try await ProviderAuthService.updateMyBarberProfile(
                barberId: barberId,
                displayName: composedDisplayName,
                bio: biography.trimmingCharacters(in: .whitespacesAndNewlines),
                instagramHandle: sanitizedInstagramHandle(instagramHandle),
                specialties: existingSpecialties
            )
            try await session.refreshProfileAfterSignIn()
            return true
        } catch {
            presentAlert(title: "Couldn't save", message: error.localizedDescription)
            return false
        }
    }

    @MainActor
    private func saveMarketplaceHidden(_ hidden: Bool) async {
        guard let barberId = session.barberProfile?.id else {
            presentAlert(title: "Couldn't update visibility", message: "Operator profile not loaded yet.")
            return
        }
        let previous = isHiddenFromConsumers
        isHiddenFromConsumers = hidden
        session.applyMarketplaceHidden(hidden)
        isSavingVisibility = true
        defer { isSavingVisibility = false }
        do {
            let confirmed = try await ProviderAuthService.updateMarketplaceHidden(
                barberId: barberId,
                isHidden: hidden
            )
            isHiddenFromConsumers = confirmed
            session.applyMarketplaceHidden(confirmed)
            await session.refreshMarketplaceVisibilityFromMe()
            isHiddenFromConsumers = session.barberProfile?.isHidden == true
        } catch {
            isHiddenFromConsumers = previous
            session.applyMarketplaceHidden(previous)
            presentAlert(title: "Couldn't update visibility", message: error.localizedDescription)
        }
    }

    @MainActor
    private func uploadProfilePhoto(from item: PhotosPickerItem) async {
        isUploadingPhoto = true
        defer {
            isUploadingPhoto = false
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                presentAlert(title: "Couldn't upload photo", message: "Choose a valid image file.")
                return
            }
            try await uploadProfilePhoto(image: image)
        } catch {
            presentAlert(title: "Couldn't upload photo", message: error.localizedDescription)
        }
    }

    @MainActor
    private func uploadProfilePhoto(image: UIImage) async {
        let shouldManageUploadState = !isUploadingPhoto
        if shouldManageUploadState {
            isUploadingPhoto = true
        }
        defer {
            if shouldManageUploadState {
                isUploadingPhoto = false
            }
        }

        do {
            guard let jpeg = ProviderAuthService.jpegDataForProfileUpload(from: image) else {
                presentAlert(title: "Couldn't upload photo", message: "Choose a valid image file.")
                return
            }
            let urlString = try await ProviderAuthService.uploadProfilePhoto(jpegData: jpeg)
            avatarURL = ProviderAvatarURL.resolve(urlString)
            try await session.refreshProfileAfterSignIn()
            loadFromSession()
        } catch {
            presentAlert(title: "Couldn't upload photo", message: error.localizedDescription)
        }
    }

    private var canDeleteWithoutPassword: Bool {
        session.authUser?.needsPlatformPassword == true
    }

    @MainActor
    private func beginAccountDeletion() async {
        guard session.authUser?.id != nil else {
            presentAlert(title: "Account unavailable", message: "Sign in again, then try deleting your account.")
            return
        }

        if canDeleteWithoutPassword {
            await performAccountDeletion(password: nil)
        } else {
            showDeletePasswordSheet = true
        }
    }

    @MainActor
    private func performAccountDeletion(password: String?) async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            if canDeleteWithoutPassword {
                try await ProviderDeviceAuthentication.requireDeviceOwnerAuthentication()
            }
            try await session.deleteAccount(password: password)
        } catch let error as ProviderDeviceAuthentication.AuthError {
            if case .cancelled = error { return }
            presentAlert(title: "Couldn't verify identity", message: error.localizedDescription)
        } catch {
            presentAlert(title: "Couldn't delete account", message: error.localizedDescription)
        }
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func dismissKeyboard() {
        focusedField = nil
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }
}

#if canImport(UIKit)
/// Adds a non-canceling tap on the Account hosting view so outside taps dismiss the keyboard
/// without blocking TextField / button hits. Ignores taps that fall inside the visible keyboard.
private struct ProviderAccountKeyboardDismissTapInstaller: UIViewRepresentable {
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        context.coordinator.beginObservingKeyboard()
        DispatchQueue.main.async {
            context.coordinator.install(from: probe)
        }
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.install(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDismiss: () -> Void
        private weak var installedOn: UIView?
        private var tap: UITapGestureRecognizer?
        /// Keyboard frame in screen coordinates; `.null` when hidden.
        private var keyboardFrameInScreen: CGRect = .null
        private var keyboardObservers: [NSObjectProtocol] = []

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func beginObservingKeyboard() {
            guard keyboardObservers.isEmpty else { return }
            let center = NotificationCenter.default
            keyboardObservers = [
                center.addObserver(
                    forName: UIResponder.keyboardWillChangeFrameNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    self?.updateKeyboardFrame(from: note)
                },
                center.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.keyboardFrameInScreen = .null
                },
            ]
        }

        func tearDown() {
            if let existing = tap {
                installedOn?.removeGestureRecognizer(existing)
            }
            tap = nil
            installedOn = nil
            for observer in keyboardObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            keyboardObservers = []
        }

        func install(from probe: UIView) {
            guard let hostView = Self.hostView(for: probe) else { return }
            guard installedOn !== hostView else { return }

            if let existing = tap {
                installedOn?.removeGestureRecognizer(existing)
            }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            hostView.addGestureRecognizer(recognizer)
            tap = recognizer
            installedOn = hostView
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            guard let hostView = installedOn else { return }
            let pointInHost = gesture.location(in: hostView)
            let pointInScreen = hostView.convert(pointInHost, to: nil)
            guard isTapAboveKeyboard(pointInScreen: pointInScreen) else { return }
            onDismiss()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // Never steal taps that land on the visible keyboard (including empty chrome).
            let pointInScreen = touch.location(in: nil)
            guard isTapAboveKeyboard(pointInScreen: pointInScreen) else { return false }

            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView {
                    return false
                }
                let typeName = String(describing: type(of: current))
                if typeName.contains("Keyboard")
                    || typeName.contains("InputSet")
                    || typeName.contains("UIRemoteKeyboard")
                    || typeName.contains("UITextEffects") {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func updateKeyboardFrame(from note: Notification) {
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }
            // A zero / off-screen frame means the keyboard is dismissed.
            let screenBounds = UIScreen.main.bounds
            if frame.isEmpty || frame.minY >= screenBounds.maxY - 1 {
                keyboardFrameInScreen = .null
            } else {
                keyboardFrameInScreen = frame
            }
        }

        private func isTapAboveKeyboard(pointInScreen: CGPoint) -> Bool {
            guard !keyboardFrameInScreen.isNull, !keyboardFrameInScreen.isEmpty else {
                // No keyboard → still allow dismiss of lingering focus by tapping chrome.
                return true
            }
            // Only the content strip above the keyboard may dismiss it.
            return pointInScreen.y < keyboardFrameInScreen.minY - 0.5
        }

        private static func hostView(for probe: UIView) -> UIView? {
            // Prefer the Form's table/collection view so taps on empty chrome dismiss reliably.
            var ancestor: UIView? = probe
            while let node = ancestor {
                if let scroll = firstDescendantScrollView(in: node) {
                    return scroll
                }
                ancestor = node.superview
            }
            return probe.window
        }

        private static func firstDescendantScrollView(in root: UIView) -> UIScrollView? {
            if let table = root as? UITableView { return table }
            if let collection = root as? UICollectionView { return collection }
            if let scroll = root as? UIScrollView { return scroll }
            for child in root.subviews {
                if let found = firstDescendantScrollView(in: child) {
                    return found
                }
            }
            return nil
        }
    }
}
#endif
