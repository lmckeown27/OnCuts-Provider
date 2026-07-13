import CoreLocation
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Signed-in accounts without a provider (`barbers`) profile: apply or track status.
/// Mirrors the web `BarberApplicationModal` — multi-step form, campus picker, status screens.
struct ProviderConsumerEnrollmentView: View {
    @Environment(ProviderSession.self) private var session

    @State private var phase: Phase = .loading
    @State private var errorText: String?
    @State private var isSubmitting = false
    @State private var showSubmitSuccess = false

    @State private var wizardPage: ApplicationWizardPage = .profession
    @State private var campuses: [AdminCampusDTO] = []
    @State private var campusesLoading = false

    /// Geo-driven campus picker state. The applicant's device location resolves to the closest
    /// OnCuts campuses (top 5 shown as radio options); a "Search manually" affordance falls
    /// back to a name search when none of the nearby suggestions are correct.
    @State private var nearestCampusState: NearestCampusState = .idle
    @State private var showManualCampusSearch = false
    @State private var campusSearchText = ""

    /// Selected `provider_type` from `GET /barber-applications/provider-types`.
    @State private var selectedProfession: ProviderTypeOption?
    @State private var professionOptions: [ProviderTypeOption] = []
    @State private var professionsLoading = false
    @State private var professionsError: String?
    @State private var phoneNumber = ""
    @State private var yearsExperience = ""
    @State private var needsTools: Bool?
    @State private var toolsNeeded = ""
    /// Mirrors the web wizard's "Barber license verification" step: explicit yes/no
    /// declaration (`nil` until the user picks) plus a required attestation checkbox. The backend
    /// rejects the submit if `hasLicense` is missing or non-boolean.
    @State private var licenseDeclared: Bool?
    @State private var licenseNumber = ""
    @State private var licenseAttestation = false
    @State private var selectedSpecialties: Set<String> = []
    /// Live platform catalog names from `GET /admin/services` (active only).
    @State private var specialtyOptions: [String] = []
    @State private var specialtiesCatalogLoading = false
    @State private var specialtiesCatalogError: String?
    @State private var selectedCampusId = ""
    @State private var whyBeBarber = ""
    @State private var availableHours = ""
    @State private var portfolioDescription = ""
    @State private var socialMedia = ""
    @State private var additionalNotes = ""

    @State private var existingApplication: BarberApplicationSummary?

    private let experienceOptions = ProviderBarberApplicationOptions.experienceLevels
    private let availabilityOptions = ProviderBarberApplicationOptions.availabilityLevels

    /// Integrated Workflow content width — matches signed-out auth landing.
    private let contentMaxWidth: CGFloat = 360
    private let horizontalPadding: CGFloat = 24

    enum Phase {
        case loading
        case existingApplication
        case wizard
    }

    /// One input (or review) per page. Conditional pages are omitted from `visibleWizardPages`.
    enum ApplicationWizardPage: Int, CaseIterable, Equatable {
        case profession
        case phone
        case experience
        case tools
        case toolsNeeded
        case specialties
        case licenseDeclared
        case licenseNumber
        case attestation
        case campus
        case whyBeBarber
        case availability
        case social
        case portfolio
        case additionalNotes
        case review
    }

    /// Lifecycle of the geo-driven campus picker.
    enum NearestCampusState: Equatable {
        case idle
        case locating
        case matching
        /// Top-N matches sorted nearest-first (the wizard renders the first 5 as radio options).
        case suggestions([NearestCampusResolver.Match])
        case failed(String, isPermissionDenied: Bool)
    }

    private static let nearestCampusSuggestionLimit = 5

    /// Ordered pages for the current answers (skips toolsNeeded / licenseNumber when not needed).
    private var visibleWizardPages: [ApplicationWizardPage] {
        var pages: [ApplicationWizardPage] = [.profession, .phone, .experience, .tools]
        if needsTools == true {
            pages.append(.toolsNeeded)
        }
        pages.append(.specialties)
        // Professional / Barber license steps temporarily disabled.
        // pages.append(.licenseDeclared)
        // if licenseDeclared == true {
        //     pages.append(.licenseNumber)
        // }
        pages.append(contentsOf: [
            // .attestation, // tied to license verification — re-enable with license steps
            // .campus, // campus step temporarily disabled
            // .whyBeBarber, // Why OnCuts step temporarily disabled
            // .availability, // Availability step temporarily disabled
            .social,
            // .portfolio, // portfolio step temporarily disabled
            // .additionalNotes, // Anything else step temporarily disabled
            .review,
        ])
        return pages
    }

    private var wizardPageIndex: Int {
        visibleWizardPages.firstIndex(of: wizardPage) ?? 0
    }

    /// Application form steps only — profession selection and review are not numbered steps.
    private var numberedWizardPages: [ApplicationWizardPage] {
        visibleWizardPages.filter { $0 != .profession && $0 != .review }
    }

    private var numberedWizardPageIndex: Int {
        numberedWizardPages.firstIndex(of: wizardPage) ?? 0
    }

    private var wizardPageCount: Int {
        numberedWizardPages.count
    }

    private var wizardStepLabel: String {
        wizardPage == .review
            ? "Review"
            : "Step \(numberedWizardPageIndex + 1) of \(wizardPageCount)"
    }

    private var wizardProgressValue: Double {
        wizardPage == .review
            ? Double(max(wizardPageCount, 1))
            : Double(numberedWizardPageIndex + 1)
    }

    private var selectedProfessionKey: String {
        (selectedProfession?.providerType ?? "barber")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var isBeautyPath: Bool {
        selectedProfessionKey == "beauty"
    }

    private var professionLabel: String {
        selectedProfession?.label
            ?? (isBeautyPath ? "Beauty" : "Barber")
    }

    private var experiencePageTitle: String { "Experience" }

    private var experiencePageSubtitle: String {
        isBeautyPath
            ? "How many years of beauty experience do you have?"
            : "How many years have you been barbering?"
    }

    private var toolsPageSubtitle: String {
        isBeautyPath
            ? "Do you need beauty tools or kits?"
            : "Do you need barber tools?"
    }

    private var toolsNeededPlaceholder: String {
        isBeautyPath
            ? "e.g. brushes, products, station kit"
            : "e.g. clippers, shears, cape"
    }

    private var licensePageTitle: String {
        isBeautyPath ? "Professional license" : "Barber license"
    }

    private var licensePageSubtitle: String {
        isBeautyPath
            ? "Do you have a current cosmetology or beauty license?"
            : "Do you have a current barber or cosmetology license?"
    }

    private var licenseNotDeclaredHint: String {
        isBeautyPath
            ? "Some states require proof of licensure before offering beauty services. The OnCuts team may still ask for documentation."
            : "Some states require proof of licensure before barbering. The OnCuts team may still ask for documentation."
    }

    private var whyJoinPageSubtitle: String {
        "Tell us why you want to join as a \(professionLabel.lowercased()) operator."
    }

    private var whyJoinPlaceholder: String {
        "Why do you want to join OnCuts as a \(professionLabel.lowercased())?"
    }

    private var servicesPageSubtitle: String {
        "Select all \(professionLabel.lowercased()) services you offer."
    }

    private var applicationSubmittedMessage: String {
        "Your OnCuts \(professionLabel) application has been submitted. The OnCuts team will be in touch with you shortly."
    }

    private var isFirstWizardPage: Bool {
        wizardPageIndex <= 0
    }

    private var isLastWizardPage: Bool {
        wizardPage == .review
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    loadingView
                case .existingApplication:
                    applicationStatusView
                case .wizard:
                    wizardContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Leave Application") { Task { await session.signOut() } }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .task { await refreshApplication() }
            .refreshable { await refreshApplication() }
            .alert("Application submitted", isPresented: $showSubmitSuccess) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text(applicationSubmittedMessage)
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerBrandGold)
        .providerAuthIntegratedScreenChrome()
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ProgressView("Checking your account…")
                .tint(Color.providerBrandGold)
                .foregroundStyle(Color.lavaShellCream)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status (pending / approved / rejected)

    private var applicationStatusView: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)

                    if let existingApplication, let status = existingApplication.status?.lowercased() {
                        let copy = ProviderBarberApplicationOptions.statusCopy(for: status)

                        VStack(spacing: 14) {
                            Image(systemName: copy.symbol)
                                .font(.provider(size: 40))
                                .foregroundStyle(copy.tint)
                            Text(copy.title)
                                .font(.provider(.title2, weight: .semibold))
                                .multilineTextAlignment(.center)
                            Text(copy.description)
                                .font(.provider(.body))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)

                        if let createdAt = existingApplication.createdAt, !createdAt.isEmpty {
                            VStack(spacing: 6) {
                                Text("Submitted on")
                                    .font(.provider(.caption, weight: .semibold))
                                    .foregroundStyle(Color.lavaShellCreamTertiary)
                                Text(formattedSubmittedDate(createdAt))
                                    .font(.provider(.body, weight: .medium))
                            }
                        }

                        supportSection

                        if status == "rejected" {
                            Button {
                                resetWizardForReapply()
                            } label: {
                                Text("Submit a new application")
                                    .font(.provider(.headline, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .foregroundStyle(Color.providerOnBrandGold)
                                    .background(Color.providerBrandGold, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Pull down to refresh for updates.")
                                .font(.provider(.footnote))
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                .padding(.horizontal, horizontalPadding)
                .contentShape(Rectangle())
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var supportSection: some View {
        VStack(spacing: 8) {
            Text("Questions about your application?")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .multilineTextAlignment(.center)
            Link(destination: URL(string: "mailto:campuscuthelp@gmail.com?subject=OnCuts%20Provider%20Application")!) {
                Label("Contact OnCuts support", systemImage: "envelope")
                    .font(.provider(.footnote, weight: .medium))
                    .foregroundStyle(Color.providerBrandGold)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Wizard

    private var wizardContent: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissKeyboard() }

                    if wizardPage != .profession {
                        wizardHeader
                            .contentShape(Rectangle())
                            .onTapGesture { dismissKeyboard() }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.provider(.footnote))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    pageContent
                        .frame(
                            maxWidth: .infinity,
                            alignment: wizardPage == .profession ? .center : .leading
                        )

                    wizardFooter

                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissKeyboard() }
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                .padding(.horizontal, horizontalPadding)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: needsTools) { _, needs in
            if needs != true, wizardPage == .toolsNeeded {
                wizardPage = .specialties
            }
            if needs != true {
                toolsNeeded = ""
            }
        }
        .onChange(of: licenseDeclared) { _, declared in
            if declared != true, wizardPage == .licenseNumber {
                wizardPage = .attestation
            }
            if declared != true {
                licenseNumber = ""
            }
        }
    }

    private func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    private var wizardHeader: some View {
        VStack(spacing: 8) {
            Text("Apply to be an OnCuts Operator")
                .font(.provider(.title3, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(wizardStepLabel)
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            ProgressView(
                value: wizardProgressValue,
                total: Double(max(wizardPageCount, 1))
            )
            .tint(Color.providerBrandGold)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch wizardPage {
        case .profession:
            professionPage
        case .phone:
            phonePage
        case .experience:
            experiencePage
        case .tools:
            toolsPage
        case .toolsNeeded:
            toolsNeededPage
        case .specialties:
            specialtiesPage
        case .licenseDeclared:
            licenseDeclaredPage
        case .licenseNumber:
            licenseNumberPage
        case .attestation:
            attestationPage
        case .campus:
            campusPage
        case .whyBeBarber:
            whyBeBarberPage
        case .availability:
            availabilityPage
        case .social:
            socialPage
        case .portfolio:
            portfolioPage
        case .additionalNotes:
            additionalNotesPage
        case .review:
            reviewPage
        }
    }

    // MARK: - Pages

    private var professionPage: some View {
        VStack(spacing: 20) {
            Text("Which profession do you wish to apply for?")
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if professionsLoading, professionOptions.isEmpty {
                ProgressView()
                    .tint(Color.providerBrandGold)
            } else if let professionsError, professionOptions.isEmpty {
                VStack(spacing: 12) {
                    Text(professionsError)
                        .font(.provider(.footnote))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await loadProfessionOptions(forceRefresh: true) }
                    } label: {
                        Text("Try again")
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.providerOnBrandGold)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.providerBrandGold, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else if professionOptions.isEmpty {
                Text("No professions available.")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            } else {
                HStack(spacing: 12) {
                    ForEach(professionOptions) { profession in
                        choiceButton(
                            title: profession.label,
                            isSelected: selectedProfession?.providerType == profession.providerType
                        ) {
                            guard selectedProfession?.providerType != profession.providerType else { return }
                            selectedProfession = profession
                            selectedSpecialties = []
                            specialtyOptions = []
                            specialtiesCatalogError = nil
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            await loadProfessionOptions()
        }
    }

    private var phonePage: some View {
        pageSection(title: "Phone number", subtitle: "How can we reach you about your application?") {
            enrollmentTextField(
                placeholder: phoneNumberPlaceholder,
                text: $phoneNumber,
                keyboard: .phonePad,
                usesTelephoneContentType: true
            )
            .onChange(of: phoneNumber) { oldValue, newValue in
                let formatted = PhoneNumberInputFormatter.format(
                    newValue,
                    previous: oldValue,
                    regionCode: currentRegionCode
                )
                if formatted != newValue {
                    phoneNumber = formatted
                }
            }
        }
    }

    private var experiencePage: some View {
        pageSection(title: experiencePageTitle, subtitle: experiencePageSubtitle) {
            VStack(spacing: 10) {
                ForEach(experienceOptions, id: \.value) { option in
                    choiceButton(
                        title: option.label,
                        isSelected: yearsExperience == option.value
                    ) {
                        yearsExperience = option.value
                    }
                }
            }
        }
    }

    private var toolsPage: some View {
        pageSection(title: "Tools", subtitle: toolsPageSubtitle) {
            HStack(spacing: 12) {
                choiceButton(title: "Yes", isSelected: needsTools == true) {
                    needsTools = true
                }
                choiceButton(title: "No", isSelected: needsTools == false) {
                    needsTools = false
                    toolsNeeded = ""
                }
            }
        }
    }

    private var toolsNeededPage: some View {
        pageSection(title: "Tools needed", subtitle: "What tools do you need? (optional)") {
            enrollmentTextField(placeholder: toolsNeededPlaceholder, text: $toolsNeeded)
        }
    }

    private var specialtiesPage: some View {
        pageSection(title: "Services you’ll offer", subtitle: servicesPageSubtitle) {
            if specialtiesCatalogLoading, specialtyOptions.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.providerBrandGold)
                    Text("Loading services…")
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    Spacer(minLength: 0)
                }
            } else if let specialtiesCatalogError, specialtyOptions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(specialtiesCatalogError)
                        .font(.provider(.footnote))
                        .foregroundStyle(.red)
                    Button {
                        Task { await loadSpecialtyCatalog(forceRefresh: true) }
                    } label: {
                        Text("Try again")
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.providerOnBrandGold)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.providerBrandGold, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else if specialtyOptions.isEmpty {
                Text("No \(professionLabel.lowercased()) services are configured yet. An Admin can add them in the Admin dashboard.")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(specialtyOptions, id: \.self) { name in
                        let isOn = selectedSpecialties.contains(name)
                        choiceButton(title: name, isSelected: isOn) {
                            if isOn {
                                selectedSpecialties.remove(name)
                            } else {
                                selectedSpecialties.insert(name)
                            }
                        }
                    }
                }
            }
        }
        .task(id: selectedProfessionKey) {
            await loadSpecialtyCatalog(forceRefresh: true)
        }
    }

    private var licenseDeclaredPage: some View {
        pageSection(
            title: licensePageTitle,
            subtitle: licensePageSubtitle
        ) {
            HStack(spacing: 12) {
                choiceButton(title: "Yes", isSelected: licenseDeclared == true) {
                    licenseDeclared = true
                }
                choiceButton(title: "No", isSelected: licenseDeclared == false) {
                    licenseDeclared = false
                    licenseNumber = ""
                }
            }
            if licenseDeclared == false {
                Text(licenseNotDeclaredHint)
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
        }
    }

    private var licenseNumberPage: some View {
        pageSection(
            title: "License number",
            subtitle: "Include the issuing state or prefix if your license has one (e.g. CA-1234567)."
        ) {
            enrollmentTextField(placeholder: "License number", text: $licenseNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
        }
    }

    private var attestationPage: some View {
        pageSection(title: "Attestation", subtitle: "Please confirm before continuing.") {
            attestationCheckbox
        }
    }

    private var attestationCheckbox: some View {
        Button {
            licenseAttestation.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: licenseAttestation ? "checkmark.square.fill" : "square")
                    .font(.provider(size: 22))
                    .foregroundStyle(licenseAttestation ? Color.providerBrandGold : Color.lavaShellCreamTertiary)
                Text("I attest that the license information I've provided is accurate to the best of my knowledge. The OnCuts team may verify it before approval.")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var campusPage: some View {
        pageSection(
            title: "Campus (optional)",
            subtitle: "Pick a nearby campus if you have one, or continue without one."
        ) {
            optionalCampusSkipRow
            nearestCampusCard
                .task { await detectNearestCampusIfNeeded() }
        }
    }

    private var whyBeBarberPage: some View {
        pageSection(title: "Why OnCuts?", subtitle: whyJoinPageSubtitle) {
            enrollmentMultilineField(
                placeholder: whyJoinPlaceholder,
                text: $whyBeBarber,
                lineLimit: 3 ... 8
            )
        }
    }

    private var availabilityPage: some View {
        pageSection(title: "Availability", subtitle: "How many hours per week can you work?") {
            VStack(spacing: 10) {
                ForEach(availabilityOptions, id: \.value) { option in
                    choiceButton(
                        title: option.label,
                        isSelected: availableHours == option.value
                    ) {
                        availableHours = option.value
                    }
                }
            }
        }
    }

    private var socialPage: some View {
        pageSection(title: "Social (optional)", subtitle: "Instagram or social link.") {
            enrollmentTextField(
                placeholder: "Instagram or social link",
                text: $socialMedia,
                keyboard: .URL
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
        }
    }

    private var portfolioPage: some View {
        pageSection(title: "Portfolio", subtitle: "Optional notes about your work.") {
            enrollmentMultilineField(
                placeholder: "Portfolio notes",
                text: $portfolioDescription,
                lineLimit: 2 ... 4
            )
        }
    }

    private var additionalNotesPage: some View {
        pageSection(title: "Anything else?", subtitle: "Optional notes for the OnCuts team.") {
            enrollmentMultilineField(
                placeholder: "Anything else?",
                text: $additionalNotes,
                lineLimit: 2 ... 4
            )
        }
    }

    private var reviewPage: some View {
        pageSection(title: "Review", subtitle: "Confirm your details, then submit.") {
            VStack(alignment: .leading, spacing: 12) {
                reviewRow("Applicant", applicantName)
                reviewRow("Email", session.authUser?.email ?? "—")
                reviewRow("Profession", selectedProfession?.label ?? "—")
                reviewRow("Phone", phoneNumber.isEmpty ? "—" : phoneNumber)
                // reviewRow("Campus", selectedCampusName) // campus step temporarily disabled
                reviewRow("Experience", experienceLabel(yearsExperience))
                // reviewRow("Availability", availabilityLabel(availableHours)) // Availability step temporarily disabled
                reviewRow(
                    "Tools",
                    {
                        switch needsTools {
                        case .some(true):
                            return toolsNeeded.isEmpty ? "Needs tools" : "Needs: \(toolsNeeded)"
                        case .some(false):
                            return "Has own tools"
                        case .none:
                            return "—"
                        }
                    }()
                )
                // reviewRow("License", licenseReviewSummary) // license steps temporarily disabled
                reviewRow("Specialties", Array(selectedSpecialties).sorted().joined(separator: ", "))
                // reviewRow("Why OnCuts?", whyBeBarber) // Why OnCuts step temporarily disabled
                if !socialMedia.isEmpty { reviewRow("Social", socialMedia) }
                // if !portfolioDescription.isEmpty { reviewRow("Portfolio", portfolioDescription) }
                // if !additionalNotes.isEmpty { reviewRow("Notes", additionalNotes) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var licenseReviewSummary: String {
        switch licenseDeclared {
        case .some(true):
            let trimmed = licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Licensed (no number provided)" : "Licensed · \(trimmed)"
        case .some(false):
            return "Not licensed"
        case .none:
            return "—"
        }
    }

    // MARK: - Campus picker (optional; geo-suggested + manual fallback)

    private var optionalCampusSkipRow: some View {
        Button {
            selectedCampusId = ""
            showManualCampusSearch = false
            campusSearchText = ""
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedCampusId.isEmpty ? "largecircle.fill.circle" : "circle")
                    .font(.provider(size: 22))
                    .foregroundStyle(selectedCampusId.isEmpty ? Color.providerBrandGold : Color.lavaShellCreamTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No campus yet")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(selectedCampusId.isEmpty ? Color.providerOnBrandGold : Color.lavaShellCream)
                    Text("You can still apply; a manager may assign your campus later.")
                        .font(.provider(.caption))
                        .foregroundStyle(
                            selectedCampusId.isEmpty
                                ? Color.providerOnBrandGold.opacity(0.75)
                                : Color.lavaShellCreamTertiary
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (selectedCampusId.isEmpty ? Color.providerBrandGold : Color.white.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var nearestCampusCard: some View {
        if showManualCampusSearch {
            manualCampusSearchCard
        } else {
            geoSuggestionsCard
        }
    }

    @ViewBuilder
    private var geoSuggestionsCard: some View {
        switch nearestCampusState {
        case .idle, .locating, .matching:
            HStack(alignment: .top, spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.providerBrandGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loadingTitleForNearestCampus)
                        .font(.provider(.subheadline, weight: .medium))
                    Text("Using your device location to match an OnCuts campus.")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .suggestions(let matches):
            VStack(alignment: .leading, spacing: 10) {
                Text("Tap a campus if you have one, or choose “No campus yet” above.")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                ForEach(matches, id: \.campus.id) { match in
                    campusSuggestionRow(match)
                }
                Button {
                    enterManualCampusSearch()
                } label: {
                    HStack(spacing: 6) {
                        Text("Don’t see your campus?")
                            .font(.provider(.footnote))
                            .foregroundStyle(Color.lavaShellCream)
                        Text("Search for it")
                            .font(.provider(.footnote, weight: .semibold))
                            .foregroundStyle(Color.providerBrandGold)
                            .underline()
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .failed(let reason, let isPermissionDenied):
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCream)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Button {
                        Task { await detectNearestCampusIfNeeded(forceRetry: true) }
                    } label: {
                        Text("Try again")
                            .font(.provider(.footnote, weight: .semibold))
                            .foregroundStyle(Color.providerOnBrandGold)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(
                                Color.providerBrandGold,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)

                    if isPermissionDenied {
                        Button {
                            openLocationSettings()
                        } label: {
                            Text("Open Settings")
                                .font(.provider(.footnote, weight: .semibold))
                                .foregroundStyle(Color.lavaShellCream)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.lavaShellCream.opacity(0.45), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        enterManualCampusSearch()
                    } label: {
                        Text("Search manually")
                            .font(.provider(.footnote, weight: .semibold))
                            .foregroundStyle(Color.providerBrandGold)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func campusSuggestionRow(_ match: NearestCampusResolver.Match) -> some View {
        let isSelected = selectedCampusId == match.campus.id
        return Button {
            selectedCampusId = match.campus.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.provider(size: 22))
                    .foregroundStyle(isSelected ? Color.providerOnBrandGold : Color.lavaShellCreamTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.campus.displayName)
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.providerOnBrandGold : Color.lavaShellCream)
                    if let line = match.campus.locationLine {
                        Text(line)
                            .font(.provider(.caption))
                            .foregroundStyle(
                                isSelected
                                    ? Color.providerOnBrandGold.opacity(0.75)
                                    : Color.lavaShellCreamSecondary
                            )
                    }
                    Text(formattedDistance(match.distance))
                        .font(.provider(.caption2))
                        .foregroundStyle(
                            isSelected
                                ? Color.providerOnBrandGold.opacity(0.65)
                                : Color.lavaShellCreamTertiary
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected ? Color.providerBrandGold : Color.white.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var manualCampusSearchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Type your campus name")
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                Text("Search by school, city, or state.")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.provider(size: 17, weight: .medium))
                        .foregroundStyle(
                            campusSearchText.isEmpty
                                ? Color.lavaShellCreamTertiary
                                : Color.providerBrandGold
                        )
                    TextField(
                        "",
                        text: $campusSearchText,
                        prompt: Text("e.g. Cal Poly San Luis Obispo")
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    )
                    .textFieldStyle(.plain)
                    .font(.provider(.body))
                    .foregroundStyle(Color.lavaShellCream)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    if !campusSearchText.isEmpty {
                        Button {
                            campusSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            campusSearchText.isEmpty
                                ? Color.white.opacity(0.22)
                                : Color.providerBrandGold.opacity(0.85),
                            lineWidth: campusSearchText.isEmpty ? 0.8 : 1.5
                        )
                )
            }

            if campusesLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.providerBrandGold)
                    Text("Loading campuses…")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
            } else if campusSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Start typing to find your campus.")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            } else if filteredCampuses.isEmpty {
                Text("No campuses match your search.")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            } else {
                ForEach(filteredCampuses) { campus in
                    manualCampusRow(campus)
                }
            }

            if case .suggestions = nearestCampusState {
                Button {
                    leaveManualCampusSearch()
                } label: {
                    Label("Back to nearby campuses", systemImage: "location.fill")
                        .font(.provider(.footnote, weight: .semibold))
                        .foregroundStyle(Color.providerBrandGold)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func manualCampusRow(_ campus: AdminCampusDTO) -> some View {
        let isSelected = selectedCampusId == campus.id
        return Button {
            selectedCampusId = campus.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.provider(size: 22))
                    .foregroundStyle(isSelected ? Color.providerOnBrandGold : Color.lavaShellCreamTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(campus.displayName)
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.providerOnBrandGold : Color.lavaShellCream)
                    if let line = campus.locationLine {
                        Text(line)
                            .font(.provider(.caption))
                            .foregroundStyle(
                                isSelected
                                    ? Color.providerOnBrandGold.opacity(0.75)
                                    : Color.lavaShellCreamSecondary
                            )
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected ? Color.providerBrandGold : Color.white.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredCampuses: [AdminCampusDTO] {
        let q = campusSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return campuses.filter { campus in
            let name = campus.displayName.lowercased()
            let slug = (campus.slug ?? "").lowercased()
            let city = (campus.city ?? "").lowercased()
            let state = (campus.state ?? "").lowercased()
            return name.contains(q) || slug.contains(q) || city.contains(q) || state.contains(q)
        }
        .prefix(40)
        .map { $0 }
    }

    private var loadingTitleForNearestCampus: String {
        switch nearestCampusState {
        case .matching: return "Matching the closest campuses…"
        case .locating: return "Finding your location…"
        default: return "Finding your nearest OnCuts campuses…"
        }
    }

    private func enterManualCampusSearch() {
        showManualCampusSearch = true
        Task { await loadCampusesIfNeeded() }
    }

    private func leaveManualCampusSearch() {
        showManualCampusSearch = false
        campusSearchText = ""
    }

    private func detectNearestCampusIfNeeded(forceRetry: Bool = false) async {
        if !forceRetry {
            if case .suggestions = nearestCampusState { return }
            if case .locating = nearestCampusState { return }
            if case .matching = nearestCampusState { return }
        }

        await loadCampusesIfNeeded()
        guard !campuses.isEmpty else {
            nearestCampusState = .failed(
                "We couldn’t load the list of OnCuts campuses. Please try again.",
                isPermissionDenied: false
            )
            return
        }

        nearestCampusState = .locating
        let fetcher = OneShotLocationFetcher()
        let userLocation: CLLocation
        do {
            userLocation = try await fetcher.fetch()
        } catch let err as OneShotLocationFetcher.FetchError {
            let denied: Bool
            if case .permissionDenied = err { denied = true } else { denied = false }
            nearestCampusState = .failed(
                err.errorDescription ?? "Couldn’t read your location.",
                isPermissionDenied: denied
            )
            return
        } catch {
            nearestCampusState = .failed(
                error.localizedDescription,
                isPermissionDenied: false
            )
            return
        }

        nearestCampusState = .matching
        let allMatches = await NearestCampusResolver.resolve(
            userLocation: userLocation,
            candidates: campuses,
            bypassCache: forceRetry
        )
        let topMatches = Array(allMatches.prefix(Self.nearestCampusSuggestionLimit))
        guard !topMatches.isEmpty else {
            nearestCampusState = .failed(
                "We couldn’t match a campus to your location. Please try again or search manually.",
                isPermissionDenied: false
            )
            return
        }

        // Pre-select the closest campus so the wizard's Continue button is enabled by default;
        nearestCampusState = .suggestions(topMatches)
    }

    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .medium
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return formatter.string(from: measurement)
    }

    private func openLocationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Footer / navigation

    private var wizardFooter: some View {
        VStack(spacing: 12) {
            if isLastWizardPage {
                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .tint(Color.providerOnBrandGold)
                        } else {
                            Text("Submit application")
                                .font(.provider(.headline, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(Color.providerOnBrandGold)
                    .background(
                        Color.providerBrandGold.opacity((isSubmitting || !canSubmit) ? 0.45 : 1),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || !canSubmit)
            } else {
                Button {
                    goToNextPage()
                } label: {
                    Text("Continue")
                        .font(.provider(.headline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(Color.providerOnBrandGold)
                        .background(
                            Color.providerBrandGold.opacity(canProceedCurrentPage ? 1 : 0.45),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canProceedCurrentPage)
            }

            if !isFirstWizardPage {
                Button {
                    goToPreviousPage()
                } label: {
                    Text("Back")
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
        }
    }

    private func goToNextPage() {
        let pages = visibleWizardPages
        guard let idx = pages.firstIndex(of: wizardPage), idx + 1 < pages.count else { return }
        withAnimation { wizardPage = pages[idx + 1] }
    }

    private func goToPreviousPage() {
        let pages = visibleWizardPages
        guard let idx = pages.firstIndex(of: wizardPage), idx > 0 else { return }
        withAnimation { wizardPage = pages[idx - 1] }
    }

    // MARK: - Shared chrome

    @ViewBuilder
    private func pageSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.provider(.title3, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                Text(subtitle)
                    .font(.provider(.subheadline))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum EnrollmentKeyboard {
        case `default`
        case phonePad
        case URL
    }

    @ViewBuilder
    private func enrollmentTextField(
        placeholder: String,
        text: Binding<String>,
        keyboard: EnrollmentKeyboard = .default,
        usesTelephoneContentType: Bool = false
    ) -> some View {
        let base = TextField(placeholder, text: text)
            .font(.provider(.body))
            .foregroundStyle(Color.lavaShellCream)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
            )

        #if os(iOS)
        base
            .keyboardType({
                switch keyboard {
                case .default: return .default
                case .phonePad: return .phonePad
                case .URL: return .URL
                }
            }())
            .textContentType(usesTelephoneContentType ? .telephoneNumber : nil)
        #else
        base
        #endif
    }

    private func enrollmentMultilineField(
        placeholder: String,
        text: Binding<String>,
        lineLimit: ClosedRange<Int>
    ) -> some View {
        TextField(
            "",
            text: text,
            prompt: Text(placeholder).foregroundStyle(Color.lavaShellCreamTertiary),
            axis: .vertical
        )
        .lineLimit(lineLimit)
        .font(.provider(.body))
        .foregroundStyle(Color.lavaShellCream)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
        )
    }

    private func choiceButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.provider(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    isSelected ? Color.providerBrandGold : Color.white.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .foregroundStyle(isSelected ? Color.providerOnBrandGold : Color.lavaShellCream)
        }
        .buttonStyle(.plain)
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCreamTertiary)
            Text(value)
                .font(.provider(.body))
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var currentRegionCode: String {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier ?? "US"
        } else {
            return Locale.current.regionCode ?? "US"
        }
    }

    private var phoneNumberPlaceholder: String {
        PhoneNumberInputFormatter.placeholder(for: currentRegionCode)
    }

    private var applicantName: String {
        let f = session.authUser?.firstName ?? ""
        let l = session.authUser?.lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "—" : joined
    }

    private var selectedCampusName: String {
        guard !selectedCampusId.isEmpty else { return "None (optional)" }
        return campuses.first(where: { $0.id == selectedCampusId })?.displayName ?? selectedCampusId
    }

    private var canProceedCurrentPage: Bool {
        switch wizardPage {
        case .profession:
            return selectedProfession != nil && !professionOptions.isEmpty
        case .phone:
            return !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .experience:
            return !yearsExperience.isEmpty
        case .tools:
            return needsTools != nil
        case .toolsNeeded:
            return true
        case .specialties:
            return !specialtyOptions.isEmpty && !selectedSpecialties.isEmpty
        case .licenseDeclared:
            return licenseDeclared != nil
        case .licenseNumber:
            return licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        case .attestation:
            return licenseAttestation
        case .campus:
            return true
        case .whyBeBarber:
            return !whyBeBarber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .availability:
            return !availableHours.isEmpty
        case .social, .portfolio, .additionalNotes:
            return true
        case .review:
            return canSubmit
        }
    }

    private var canSubmit: Bool {
        selectedProfession != nil
            && !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !yearsExperience.isEmpty
            && needsTools != nil
            && !selectedSpecialties.isEmpty
            // License steps temporarily disabled — re-enable with licenseDeclared / attestation pages.
            // && licenseDeclared != nil
            // && licenseAttestation
            // && (
            //     licenseDeclared != true
            //         || licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            // )
            // Why OnCuts step temporarily disabled.
            // && !whyBeBarber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Availability step temporarily disabled.
            // && !availableHours.isEmpty
    }

    private func experienceLabel(_ value: String) -> String {
        experienceOptions.first(where: { $0.value == value })?.label ?? value
    }

    private func availabilityLabel(_ value: String) -> String {
        availabilityOptions.first(where: { $0.value == value })?.label ?? value
    }

    private func formattedSubmittedDate(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            return date.formatted(date: .long, time: .omitted)
        }
        return raw
    }

    private func resetWizardForReapply() {
        existingApplication = nil
        wizardPage = .profession
        selectedProfession = nil
        errorText = nil
        phase = .wizard
    }

    private func loadProfessionOptions(forceRefresh: Bool = false) async {
        if !forceRefresh, !professionOptions.isEmpty, !professionsLoading { return }
        professionsLoading = true
        professionsError = nil
        defer { professionsLoading = false }
        do {
            let rows = try await ProviderBarberApplicationService.fetchProviderTypes()
            professionOptions = rows
            if let selected = selectedProfession,
               !rows.contains(where: { $0.providerType == selected.providerType }) {
                selectedProfession = nil
            }
        } catch {
            professionsError =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            if professionOptions.isEmpty {
                // Match production-supported provider_type values if the endpoint is unreachable.
                professionOptions = [
                    ProviderTypeOption(providerType: "barber", label: "Barber"),
                    ProviderTypeOption(providerType: "beauty", label: "Beauty"),
                ]
            }
        }
    }

    private func loadSpecialtyCatalog(forceRefresh: Bool = false) async {
        if !forceRefresh, !specialtyOptions.isEmpty, !specialtiesCatalogLoading { return }
        specialtiesCatalogLoading = true
        specialtiesCatalogError = nil
        defer { specialtiesCatalogLoading = false }
        let providerType = selectedProfessionKey
        do {
            let catalog = try await ProviderBarberServicesService.fetchServiceCatalog(
                providerType: providerType
            )
            let names = catalog
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            applySpecialtyOptions(names.isEmpty ? fallbackSpecialtyNames(for: providerType) : names)
        } catch {
            specialtiesCatalogError =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            if specialtyOptions.isEmpty {
                // Last-resort offline fallback so applicants aren't blocked if the catalog call fails.
                applySpecialtyOptions(fallbackSpecialtyNames(for: providerType))
            }
        }
    }

    private func fallbackSpecialtyNames(for providerType: String) -> [String] {
        providerType == "beauty"
            ? ProviderBarberApplicationOptions.beautyServiceNames
            : ProviderBarberApplicationOptions.barberServiceNames
    }

    private func applySpecialtyOptions(_ names: [String]) {
        specialtyOptions = names
        // Drop any stale selections that are no longer in the live catalog.
        selectedSpecialties = Set(selectedSpecialties.filter { selected in
            names.contains { $0.caseInsensitiveCompare(selected) == .orderedSame }
        })
    }

    private func loadCampusesIfNeeded() async {
        guard campuses.isEmpty, !campusesLoading else { return }
        campusesLoading = true
        defer { campusesLoading = false }
        do {
            campuses = try await ProviderCampusCatalogService.listCampuses()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshApplication() async {
        phase = .loading
        errorText = nil
        do {
            let row = try await ProviderBarberApplicationService.fetchMyApplication()
            existingApplication = row
            guard let row, let status = row.status?.lowercased(), !status.isEmpty else {
                await enterFreshApplicationWizard()
                return
            }
            if status == "approved" {
                await session.retryProviderProfileSync()
                if session.hasProviderProfile { return }
                // Demoted (or never activated) operators still have an approved application row,
                // but must not see "Application approved" — treat them like a first-time applicant.
                existingApplication = nil
                await enterFreshApplicationWizard()
                return
            }
            if ["pending", "under_review", "interview_scheduled", "rejected"].contains(status) {
                phase = .existingApplication
            } else {
                await enterFreshApplicationWizard()
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await enterFreshApplicationWizard()
        }
    }

    private func enterFreshApplicationWizard() async {
        await loadCampusesIfNeeded()
        await loadProfessionOptions()
        await loadSpecialtyCatalog()
        wizardPage = .profession
        phase = .wizard
    }

    private func submit() async {
        isSubmitting = true
        errorText = nil
        defer { isSubmitting = false }

        // The backend requires `hasLicense` to be an explicit boolean. We never reach submit
        // without the user having answered the license pages, but guard anyway.
        let declared = licenseDeclared ?? false
        let trimmedLicense = licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        let notes = additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let professionTitle = selectedProfession?.label
        let notesWithProfession: String = {
            guard let professionTitle, !professionTitle.isEmpty else { return notes }
            if notes.isEmpty { return "Profession: \(professionTitle)" }
            return "Profession: \(professionTitle)\n\n\(notes)"
        }()

        var body: [String: Any] = [
            "phoneNumber": phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            "yearsExperience": yearsExperience,
            "hasLicense": declared,
            "specialties": Array(selectedSpecialties).sorted(),
            "hasOwnTools": needsTools != true,
            // Backend still requires availableHours; step is hidden so send a placeholder when empty.
            "availableHours": availableHours.isEmpty ? "Not provided" : availableHours,
            // Backend still requires whyBeBarber; step is hidden so send a placeholder when empty.
            "whyBeBarber": {
                let trimmed = whyBeBarber.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Not provided" : trimmed
            }(),
            "portfolioDescription": portfolioDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            "socialMedia": socialMedia.trimmingCharacters(in: .whitespacesAndNewlines),
            "additionalNotes": notesWithProfession,
        ]
        if let selectedProfession {
            body["providerType"] = selectedProfession.providerType
            body["providerTypeLabel"] = selectedProfession.label
            body["profession"] = selectedProfession.providerType
            body["professionLabel"] = selectedProfession.label
        }
        let campusTrimmed = selectedCampusId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !campusTrimmed.isEmpty {
            body["campusId"] = campusTrimmed
        }
        if declared {
            body["licenseNumber"] = trimmedLicense
        } else {
            // Web parity: send explicit null so the row clears any stale value when reapplying.
            body["licenseNumber"] = NSNull()
        }
        if needsTools == true, !toolsNeeded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["toolsNeeded"] = toolsNeeded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            try await ProviderBarberApplicationService.submitApplication(body: body)
            showSubmitSuccess = true
            await refreshApplication()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let lower = message.lowercased()
            if lower.contains("pending application") || lower.contains("already have a pending") {
                existingApplication = BarberApplicationSummary(
                    id: "pending",
                    status: "pending",
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    yearsExperience: yearsExperience,
                    specialties: Array(selectedSpecialties),
                    availableHours: availableHours,
                    whyBeBarber: whyBeBarber
                )
                phase = .existingApplication
            } else if lower.contains("haslicense") || lower.contains("license") {
                // Backend rejected the license declaration — jump back so they can correct it.
                withAnimation { wizardPage = .licenseDeclared }
                errorText = message
            } else {
                errorText = message
            }
        }
    }
}

enum ProviderBarberApplicationOptions {
    struct LabeledValue: Hashable {
        let value: String
        let label: String
    }

    struct StatusCopy {
        let title: String
        let description: String
        let symbol: String
        let tint: Color
    }

    static let barberServiceNames: [String] = [
        "Buzz Cut", "Line Up", "Beard Trim", "Haircut", "Taper", "Hot Shave", "Kids Cut",
        "Fade", "Haircut & Fade", "Mullet", "Design/Art", "Afro Textures", "Women's Cut",
        "Color Treatment", "Perm",
    ]

    /// Offline / empty-catalog fallback when applying on the Beauty path.
    /// Keep in sync with `services.provider_type = 'beauty'` in production.
    static let beautyServiceNames: [String] = [
        "Braids", "Lashes", "Makeup", "Nails", "Tanning",
    ]

    /// Backward-compatible alias used by older call sites.
    static var serviceNames: [String] { barberServiceNames }

    static let experienceLevels: [LabeledValue] = [
        LabeledValue(value: "less-than-1", label: "Less than 1 year"),
        LabeledValue(value: "1-2", label: "1–2 years"),
        LabeledValue(value: "3-5", label: "3–5 years"),
        LabeledValue(value: "5-plus", label: "5+ years"),
    ]

    static let availabilityLevels: [LabeledValue] = [
        LabeledValue(value: "5-10", label: "5–10 hours/week"),
        LabeledValue(value: "10-20", label: "10–20 hours/week"),
        LabeledValue(value: "20-30", label: "20–30 hours/week"),
        LabeledValue(value: "30-plus", label: "30+ hours/week"),
    ]

    static func statusCopy(for status: String) -> StatusCopy {
        switch status {
        case "pending":
            return StatusCopy(
                title: "Application under review",
                description: "Your application has been submitted and is being reviewed by the OnCuts team.",
                symbol: "hourglass",
                tint: .yellow
            )
        case "under_review":
            return StatusCopy(
                title: "Application under review",
                description: "Your application is actively being reviewed. The OnCuts team will reach out with next steps.",
                symbol: "doc.text.magnifyingglass",
                tint: .blue
            )
        case "interview_scheduled":
            return StatusCopy(
                title: "Interview scheduled",
                description: "Great news — an interview has been scheduled. Check your email for details.",
                symbol: "calendar.badge.clock",
                tint: .green
            )
        case "approved":
            return StatusCopy(
                title: "Application approved",
                description: "Congratulations! Your application was approved. Pull to refresh — we’ll sync your operator profile automatically.",
                symbol: "checkmark.seal.fill",
                tint: .green
            )
        case "rejected":
            return StatusCopy(
                title: "Application not approved",
                description: "Your application wasn’t approved at this time. You can submit a new application when you’re ready.",
                symbol: "xmark.circle",
                tint: .red
            )
        default:
            return StatusCopy(
                title: "Application update",
                description: "Status: \(status.replacingOccurrences(of: "_", with: " ").capitalized). Pull to refresh for updates.",
                symbol: "doc.text",
                tint: Color.lavaShellCreamSecondary
            )
        }
    }
}

// MARK: - Region-aware phone number formatting

/// Lightweight on-the-fly phone number formatter.
///
/// Avoids a third-party dependency (libPhoneNumber / PhoneNumberKit) for what is, in practice, a
/// single signup field. Region detection comes from `Locale.current`, with NANP countries getting
/// the familiar `(NNN) NNN-NNNN` grouping and everything else falling back to a calling-code
/// prefixed space-grouped form so international applicants still get a recognizable shape.
enum PhoneNumberInputFormatter {
    /// Country calling code lookup for the regions we hand-format. Anything not in this table
    /// falls back to the generic space-grouped formatter using whatever the user typed for the
    /// country prefix.
    private static let callingCodes: [String: String] = [
        "US": "1", "CA": "1", "MX": "52",
        "GB": "44", "IE": "353",
        "AU": "61", "NZ": "64",
        "FR": "33", "DE": "49", "ES": "34", "IT": "39", "NL": "31",
        "BR": "55", "AR": "54",
        "IN": "91", "JP": "81", "KR": "82", "CN": "86",
    ]

    static func placeholder(for regionCode: String) -> String {
        switch regionCode.uppercased() {
        case "US", "CA": return "(555) 555-5555"
        case "GB": return "07700 900123"
        case "AU": return "0412 345 678"
        case "DE": return "01512 3456789"
        case "FR": return "06 12 34 56 78"
        case "IN": return "98765 43210"
        default: return "Phone number"
        }
    }

    /// Live-format the user's typed value into a human-friendly phone string for the given region.
    /// - Parameter previous: Prior field value (from `onChange`); used so backspacing over
    ///   formatting characters like `)` still deletes into the area-code digits.
    static func format(_ raw: String, previous: String? = nil, regionCode: String) -> String {
        let region = regionCode.uppercased()
        let startsWithPlus = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        var digits = raw.filter(\.isNumber)

        // Backspace over punctuation (e.g. deleting `)` from `(555)`) does not change the digit
        // count, so without this the formatter would immediately re-insert the punctuation.
        if let previous {
            let prevDigits = previous.filter(\.isNumber)
            if raw.count < previous.count, digits.count == prevDigits.count, !digits.isEmpty {
                digits = String(digits.dropLast())
            }
        }

        guard !digits.isEmpty else { return "" }

        if startsWithPlus {
            return formatInternational(digits)
        }

        switch region {
        case "US", "CA":
            return formatNANP(digits)
        case "GB":
            return formatGroups(digits, groups: [5, 6])
        case "AU":
            return formatGroups(digits, groups: [4, 3, 3])
        case "DE":
            return formatGroups(digits, groups: [5, 7])
        case "FR":
            return formatGroups(digits, groups: [2, 2, 2, 2, 2])
        case "IN":
            return formatGroups(digits, groups: [5, 5])
        default:
            return formatGroups(digits, groups: [3, 3, 4])
        }
    }

    /// Normalize a formatted phone number to an E.164-ish string (`+<country><digits>`) for the
    /// API. Defensive: if the user pasted an international number with `+`, keep it; otherwise
    /// prepend the calling code for their detected region when one is known.
    static func normalized(_ raw: String, regionCode: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return "" }
        if trimmed.hasPrefix("+") {
            return "+\(digits)"
        }
        let region = regionCode.uppercased()
        if let cc = callingCodes[region] {
            // Avoid double-prefixing a NANP number the user typed with the leading `1`.
            if region == "US" || region == "CA", digits.count == 11, digits.hasPrefix("1") {
                return "+\(digits)"
            }
            return "+\(cc)\(digits)"
        }
        return "+\(digits)"
    }

    // MARK: - Private formatters

    private static func formatNANP(_ digits: String) -> String {
        // Strip a leading country code `1` so the user can type "1 555…" or "555…" identically.
        var d = digits
        if d.count > 10, d.hasPrefix("1") {
            d = String(d.dropFirst())
        }
        let limited = String(d.prefix(10))
        let area = limited.prefix(3)
        let mid = limited.dropFirst(3).prefix(3)
        let end = limited.dropFirst(6)

        switch limited.count {
        case 0: return ""
        // Keep the area code open while editing the first two digits so backspace can move
        // through `(555)` → `(55` → `(5` without the closing paren snapping back.
        case 1 ... 2: return "(\(area)"
        case 3: return "(\(area))"
        case 4 ... 6: return "(\(area)) \(mid)"
        default: return "(\(area)) \(mid)-\(end)"
        }
    }

    private static func formatGroups(_ digits: String, groups: [Int]) -> String {
        var remaining = Substring(digits)
        var parts: [String] = []
        for size in groups {
            guard !remaining.isEmpty else { break }
            let take = min(size, remaining.count)
            parts.append(String(remaining.prefix(take)))
            remaining = remaining.dropFirst(take)
        }
        if !remaining.isEmpty {
            parts.append(String(remaining))
        }
        return parts.joined(separator: " ")
    }

    private static func formatInternational(_ digits: String) -> String {
        // `+CC NNN NNN NNNN` style: first 1–3 digits as the country code, then 3-3-4 grouping.
        guard !digits.isEmpty else { return "+" }
        let ccLength = min(3, max(1, digits.count > 10 ? digits.count - 10 : (digits.count > 7 ? 2 : 1)))
        let cc = digits.prefix(ccLength)
        let rest = digits.dropFirst(ccLength)
        if rest.isEmpty { return "+\(cc)" }
        return "+\(cc) \(formatGroups(String(rest), groups: [3, 3, 4]))"
    }
}
