import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Native SwiftUI barber account management — public identity, specialties, visibility, and account safety.
struct BarberAccountControlView: View {
    @Environment(ProviderSession.self) private var session

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var biography = ""
    @State private var instagramHandle = ""
    @State private var isProfileVisible = true
    @State private var specialties: [String] = []
    @State private var showingSpecialtyPicker = false

    @State private var avatarURL: URL?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoLibraryPicker = false
    @State private var showCameraPicker = false
    @State private var isSaving = false
    @State private var isUploadingPhoto = false
    @State private var isHydratingFromServer = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var showSignOutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showDeletePasswordSheet = false
    @State private var deletePassword = ""
    @State private var isDeletingAccount = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private let profileAvatarSize: CGFloat = ProviderSquaredAvatarMetrics.profileSize
    private let profileCameraButtonSize: CGFloat = 32

    var body: some View {
        Form {
            profileHeaderSection
            coreDetailsSection
            specialtiesSection
            visibilitySection
            accountActionsSection
        }
        .providerLavaIntegratedFormSurface()
        .disabled(isSaving || isDeletingAccount || isUploadingPhoto)
        .overlay {
            if isSaving || isUploadingPhoto || isDeletingAccount {
                ProgressView()
                    .tint(.providerOlive)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sign Out") {
                    showSignOutAlert = true
                }
                .font(.provider(.body, weight: .semibold))
                .foregroundStyle(Color.red)
            }
        }
        .onAppear(perform: loadFromSession)
        .onDisappear {
            autosaveTask?.cancel()
        }
        .onChange(of: session.barberProfile?.id) { _, _ in
            loadFromSession()
        }
        .onChange(of: firstName) { _, _ in scheduleAutosave() }
        .onChange(of: lastName) { _, _ in scheduleAutosave() }
        .onChange(of: biography) { _, _ in scheduleAutosave() }
        .onChange(of: instagramHandle) { _, _ in scheduleAutosave() }
        .onChange(of: isProfileVisible) { _, _ in scheduleAutosave() }
        .onChange(of: specialties) { _, _ in scheduleAutosave() }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await uploadProfilePhoto(from: item) }
        }
        .sheet(isPresented: $showingSpecialtyPicker) {
            BarberSpecialtyPickerView(selectedSpecialties: $specialties)
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
            HStack {
                Spacer()
                Menu {
                    profilePhotoMenuActions
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        avatarView
                        profileCameraBadge
                            .allowsHitTesting(false)
                    }
                    .frame(width: profileAvatarSize, height: profileAvatarSize)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuOrder(.fixed)
                .accessibilityLabel("Change profile photo")
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
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
        Section("Public Identity") {
            TextField("First Name", text: $firstName)
                .textContentType(.givenName)
                .autocorrectionDisabled()

            TextField("Last Name", text: $lastName)
                .textContentType(.familyName)
                .autocorrectionDisabled()

            VStack(alignment: .leading, spacing: 6) {
                Text("About You")
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .underline()
                TextEditor(text: $biography)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 4) {
                Text("@")
                    .font(.provider(.body, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Instagram", text: $instagramHandle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
            }
        }
    }

    private var specialtiesSection: some View {
        Section("Specialties") {
            ProviderWrappingChipFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(specialties, id: \.self) { specialty in
                    specialtyChip(specialty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            Button {
                showingSpecialtyPicker = true
            } label: {
                HStack(spacing: 10) {
                    Text("Add specialty")
                        .font(.provider(.body))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .providerOliveOutlined()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add specialty from campus services")
        }
    }

    private func specialtyChip(_ specialty: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(specialty)
                .font(.provider(.subheadline, weight: .medium))
                .providerOliveOutlined()
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                specialties.removeAll { $0.caseInsensitiveCompare(specialty) == .orderedSame }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(specialty)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var visibilitySection: some View {
        Section("Visibility") {
            Toggle(isOn: $isProfileVisible) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isProfileVisible ? "Visible to Public" : "Hidden from Public")
                        .font(.provider(.body, weight: .semibold))
                    Text("Hiding your profile stops public search discovery. Pending bookings are not affected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var accountActionsSection: some View {
        Section {
            Button {
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
                    Text("Enter your CampusCuts password to permanently delete your account.")
                }
            }
            .navigationTitle("Confirm Password")
            .navigationBarTitleDisplayMode(.inline)
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
        isProfileVisible = barber?.isActive ?? true

        if let remote = barber?.specialties?.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
           !remote.isEmpty {
            specialties = remote
        } else {
            specialties = []
        }

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

    private func scheduleAutosave() {
        guard !isHydratingFromServer, session.hasProviderProfile else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await saveProfile()
        }
    }

    @MainActor
    private func saveProfile() async {
        guard let barberId = session.barberProfile?.id else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await ProviderAuthService.updateMyBarberProfile(
                barberId: barberId,
                displayName: composedDisplayName,
                bio: biography.trimmingCharacters(in: .whitespacesAndNewlines),
                instagramHandle: sanitizedInstagramHandle(instagramHandle),
                specialties: specialties,
                isActive: isProfileVisible
            )
            try await session.refreshProfileAfterSignIn()
        } catch {
            presentAlert(title: "Couldn't save", message: error.localizedDescription)
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
}
