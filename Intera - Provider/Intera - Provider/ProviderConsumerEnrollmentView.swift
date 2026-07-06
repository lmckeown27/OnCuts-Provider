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

    @State private var wizardStep = 1
    @State private var campuses: [AdminCampusDTO] = []
    @State private var campusesLoading = false

    /// Geo-driven campus picker state. The applicant's device location resolves to the closest
    /// OnCuts campuses (top 5 shown as radio options); a "Search manually" affordance falls
    /// back to a name search when none of the nearby suggestions are correct.
    @State private var nearestCampusState: NearestCampusState = .idle
    @State private var showManualCampusSearch = false
    @State private var campusSearchText = ""

    @State private var phoneNumber = ""
    @State private var yearsExperience = ""
    @State private var needsTools = false
    @State private var toolsNeeded = ""
    /// Mirrors the web wizard's "Barber license verification" step (Step 2 of 4): explicit yes/no
    /// declaration (`nil` until the user picks) plus a required attestation checkbox. The backend
    /// rejects the submit if `hasLicense` is missing or non-boolean.
    @State private var licenseDeclared: Bool?
    @State private var licenseNumber = ""
    @State private var licenseAttestation = false
    @State private var selectedSpecialties: Set<String> = []
    @State private var selectedCampusId = ""
    @State private var whyBeBarber = ""
    @State private var availableHours = ""
    @State private var portfolioDescription = ""
    @State private var socialMedia = ""
    @State private var additionalNotes = ""

    private let totalWizardSteps = 4

    @State private var existingApplication: BarberApplicationSummary?

    private let specialtyOptions = ProviderBarberApplicationOptions.serviceNames
    private let experienceOptions = ProviderBarberApplicationOptions.experienceLevels
    private let availabilityOptions = ProviderBarberApplicationOptions.availabilityLevels

    enum Phase {
        case loading
        case existingApplication
        case wizard
    }

    /// Lifecycle of the geo-driven campus picker on Step 3.
    enum NearestCampusState: Equatable {
        case idle
        case locating
        case matching
        /// Top-N matches sorted nearest-first (the wizard renders the first 5 as radio options).
        case suggestions([NearestCampusResolver.Match])
        case failed(String, isPermissionDenied: Bool)
    }

    private static let nearestCampusSuggestionLimit = 5

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView("Checking your account…")
                        .tint(.providerOlive)
                        .foregroundStyle(Color.lavaShellCream)
                case .existingApplication:
                    applicationStatusView
                case .wizard:
                    wizardContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { Task { await session.signOut() } }
                }
                if phase == .wizard, wizardStep > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            withAnimation { wizardStep -= 1 }
                        }
                    }
                }
            }
            .task { await refreshApplication() }
            .refreshable { await refreshApplication() }
            .alert("Application submitted", isPresented: $showSubmitSuccess) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text("Your OnCuts barber application has been submitted. The OnCuts team will be in touch with you shortly.")
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
    }

    // MARK: - Status (pending / approved / rejected)

    private var applicationStatusView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let existingApplication, let status = existingApplication.status?.lowercased() {
                    let copy = ProviderBarberApplicationOptions.statusCopy(for: status)

                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: copy.symbol)
                            .font(.provider(size: 34))
                            .foregroundStyle(copy.tint)
                        Text(copy.title)
                            .font(.provider(.title2, weight: .semibold))
                        Text(copy.description)
                            .font(.provider(.body))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if let createdAt = existingApplication.createdAt, !createdAt.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Submitted on")
                                .font(.provider(.caption, weight: .semibold))
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                            Text(formattedSubmittedDate(createdAt))
                                .font(.provider(.body, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    supportSection

                    if status == "rejected" {
                        Button {
                            resetWizardForReapply()
                        } label: {
                            Text("Submit a new application")
                                .font(.provider(.headline))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.providerOlive, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(Color.lavaShellCream)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Pull down to refresh for updates.")
                            .font(.provider(.footnote))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Questions about your application?")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Link(destination: URL(string: "mailto:campuscuthelp@gmail.com?subject=OnCuts%20Provider%20Application")!) {
                Label("Contact OnCuts support", systemImage: "envelope")
                    .font(.provider(.footnote, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Wizard

    private var wizardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                wizardHeader

                if let errorText {
                    Text(errorText)
                        .font(.provider(.footnote))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                switch wizardStep {
                case 1: stepOneSections
                case 2: stepTwoSections
                case 3: stepThreeSections
                default: reviewSection
                }

                wizardFooter
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @ViewBuilder
    private func enrollmentSection<Content: View>(
        _ title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lavaShellCream)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func enrollmentCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.35))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }


    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apply to join OnCuts as a barber")
                .font(.provider(.title3, weight: .semibold))
            Text("Step \(wizardStep) of \(totalWizardSteps)")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            ProgressView(value: Double(wizardStep), total: Double(totalWizardSteps))
                .tint(.providerOlive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private var stepOneSections: some View {
        enrollmentCard {
            enrollmentSection("Contact") {
                TextField(phoneNumberPlaceholder, text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .onChange(of: phoneNumber) { _, newValue in
                        let formatted = PhoneNumberInputFormatter.format(
                            newValue,
                            regionCode: currentRegionCode
                        )
                        if formatted != newValue {
                            phoneNumber = formatted
                        }
                    }
            }

            sectionDivider

            enrollmentSection("Experience") {
                Picker("Years of experience", selection: $yearsExperience) {
                    Text("Select experience level").tag("")
                    ForEach(experienceOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .tint(yearsExperience.isEmpty ? Color.lavaShellCreamTertiary : Color.lavaShellCream)
            }

            sectionDivider

            enrollmentSection("Tools") {
                Text("Do you need barber tools?")
                    .font(.provider(.subheadline, weight: .medium))
                HStack(spacing: 12) {
                    toolsChoiceButton(title: "Yes", isSelected: needsTools) {
                        needsTools = true
                    }
                    toolsChoiceButton(title: "No", isSelected: !needsTools) {
                        needsTools = false
                        toolsNeeded = ""
                    }
                }
                if needsTools {
                    TextField("What tools do you need?", text: $toolsNeeded)
                }
            }

            sectionDivider

            enrollmentSection("Services you’ll offer") {
                ForEach(specialtyOptions, id: \.self) { name in
                    Toggle(name, isOn: Binding(
                        get: { selectedSpecialties.contains(name) },
                        set: { on in
                            if on { selectedSpecialties.insert(name) } else { selectedSpecialties.remove(name) }
                        }
                    ))
                }
            }
        }
    }

    /// Step 2 — Barber license verification (mirrors the web `BarberApplicationModal` step 2).
    /// Required yes/no declaration + license number when "yes" + attestation checkbox. No verify
    /// API call here; the values are stored in state and sent on the final `POST /barber-applications`.
    private var stepTwoSections: some View {
        enrollmentCard {
            enrollmentSection("Barber license") {
                Text("Do you have a current barber or cosmetology license?")
                    .font(.provider(.subheadline, weight: .medium))
                HStack(spacing: 12) {
                    toolsChoiceButton(title: "Yes", isSelected: licenseDeclared == true) {
                        licenseDeclared = true
                    }
                    toolsChoiceButton(title: "No", isSelected: licenseDeclared == false) {
                        licenseDeclared = false
                        licenseNumber = ""
                    }
                }
                if licenseDeclared == true {
                    TextField("License number", text: $licenseNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                    Text("Include the issuing state or prefix if your license has one (e.g. CA-1234567).")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                } else if licenseDeclared == false {
                    Text("Some states require proof of licensure before barbering. The OnCuts team may still ask for documentation.")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
            }

            sectionDivider

            enrollmentSection("Attestation") {
                attestationCheckbox
            }
        }
    }

    private var attestationCheckbox: some View {
        Button {
            licenseAttestation.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: licenseAttestation ? "checkmark.square.fill" : "square")
                    .font(.provider(size: 22))
                    .foregroundStyle(licenseAttestation ? Color.providerOlive : Color.lavaShellCreamTertiary)
                Text("I attest that the license information I've provided is accurate to the best of my knowledge. The OnCuts team may verify it before approval.")
                    .font(.provider(.footnote))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(selectedCampusId.isEmpty ? Color.providerOlive : Color.lavaShellCreamTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No campus yet")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                    Text("You can still apply; a manager may assign your campus later.")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (selectedCampusId.isEmpty ? Color.providerOlive.opacity(0.18) : Color.white.opacity(0.06)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
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
                    .tint(Color.lavaShellCream)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loadingTitleForNearestCampus)
                        .font(.provider(.subheadline, weight: .medium))
                    Text("Using your device location to match a OnCuts campus.")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
                            .foregroundStyle(Color.lavaShellCream)
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
                            .foregroundStyle(Color.lavaShellCream)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(
                                Color.providerOlive.opacity(0.85),
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
                            .foregroundStyle(Color.providerOlive)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(isSelected ? Color.providerOlive : Color.lavaShellCreamTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.campus.displayName)
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                    if let line = match.campus.locationLine {
                        Text(line)
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
                    Text(formattedDistance(match.distance))
                        .font(.provider(.caption2))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected ? Color.providerOlive.opacity(0.18) : Color.white.opacity(0.06)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.providerOlive.opacity(0.7) : Color.white.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
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
                        .foregroundStyle(campusSearchText.isEmpty ? Color.lavaShellCreamTertiary : Color.providerOlive)
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
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            campusSearchText.isEmpty
                                ? Color.lavaShellCream.opacity(0.35)
                                : Color.providerOlive.opacity(0.85),
                            lineWidth: campusSearchText.isEmpty ? 1 : 1.5
                        )
                )
            }

            if campusesLoading {
                HStack {
                    ProgressView().controlSize(.small)
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
                        .foregroundStyle(Color.lavaShellCream)
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
                    .foregroundStyle(isSelected ? Color.providerOlive : Color.lavaShellCreamTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(campus.displayName)
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                    if let line = campus.locationLine {
                        Text(line)
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected ? Color.providerOlive.opacity(0.18) : Color.white.opacity(0.06)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.providerOlive.opacity(0.7) : Color.white.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
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

    /// Step 3 — Optional campus + about you. Geo suggestions help applicants who know their school;
    /// providers can skip campus and continue the application.
    private var stepThreeSections: some View {
        enrollmentCard {
            enrollmentSection("Campus (optional)") {
                optionalCampusSkipRow
                nearestCampusCard
                    .task { await detectNearestCampusIfNeeded() }
            }

            sectionDivider

            enrollmentSection("About you") {
                TextField(
                    "",
                    text: $whyBeBarber,
                    prompt: Text("Why do you want to be a OnCuts barber?")
                        .foregroundStyle(Color.lavaShellCreamTertiary),
                    axis: .vertical
                )
                .lineLimit(3 ... 8)
                .paragraphFieldStyle()
            }

            sectionDivider

            enrollmentSection("Availability") {
                Picker("Hours per week", selection: $availableHours) {
                    Text("Select availability").tag("")
                    ForEach(availabilityOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .tint(availableHours.isEmpty ? Color.lavaShellCreamTertiary : Color.lavaShellCream)
            }

            sectionDivider

            enrollmentSection("Social") {
                TextField(
                    "",
                    text: $socialMedia,
                    prompt: Text("Instagram or social link (optional)")
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)
                .paragraphFieldStyle()
            }

            sectionDivider

            enrollmentSection("More details (optional)") {
                TextField(
                    "",
                    text: $portfolioDescription,
                    prompt: Text("Portfolio notes")
                        .foregroundStyle(Color.lavaShellCreamTertiary),
                    axis: .vertical
                )
                .lineLimit(2 ... 4)
                .paragraphFieldStyle()

                TextField(
                    "",
                    text: $additionalNotes,
                    prompt: Text("Anything else?")
                        .foregroundStyle(Color.lavaShellCreamTertiary),
                    axis: .vertical
                )
                .lineLimit(2 ... 4)
                .paragraphFieldStyle()
            }
        }
    }

    private var reviewSection: some View {
        enrollmentCard {
            enrollmentSection("Review") {
                reviewRow("Applicant", applicantName)
                reviewRow("Email", session.authUser?.email ?? "—")
                reviewRow("Phone", phoneNumber.isEmpty ? "—" : phoneNumber)
                reviewRow("Campus", selectedCampusName)
                reviewRow("Experience", experienceLabel(yearsExperience))
                reviewRow("Availability", availabilityLabel(availableHours))
                reviewRow("Tools", needsTools ? (toolsNeeded.isEmpty ? "Needs tools" : "Needs: \(toolsNeeded)") : "Has own tools")
                reviewRow("License", licenseReviewSummary)
                reviewRow("Specialties", Array(selectedSpecialties).sorted().joined(separator: ", "))
                reviewRow("Why OnCuts?", whyBeBarber)
                if !socialMedia.isEmpty { reviewRow("Social", socialMedia) }
            }
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

    private var wizardFooter: some View {
        Group {
            if wizardStep < totalWizardSteps {
                Button {
                    withAnimation { wizardStep += 1 }
                } label: {
                    Text("Continue")
                        .font(.provider(.headline))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.providerOlive.opacity(canProceedCurrentStep ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color.lavaShellCream)
                }
                .buttonStyle(.plain)
                .disabled(!canProceedCurrentStep)
            } else {
                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .tint(Color.lavaShellCream)
                        } else {
                            Text("Submit application")
                                .font(.provider(.headline))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.providerOlive.opacity((isSubmitting || !canSubmit) ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Color.lavaShellCream)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || !canSubmit)
            }
        }
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

    private var canProceedCurrentStep: Bool {
        switch wizardStep {
        case 1:
            return !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !yearsExperience.isEmpty
                && !selectedSpecialties.isEmpty
        case 2:
            // Mirrors web BarberApplicationModal step 2 gate: explicit yes/no + attestation, plus
            // a non-empty license number (≥ 2 chars) when the applicant says they are licensed.
            guard let declared = licenseDeclared, licenseAttestation else { return false }
            if declared {
                return licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            }
            return true
        case 3:
            return !whyBeBarber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !availableHours.isEmpty
        default:
            return true
        }
    }

    private var canSubmit: Bool { canProceedCurrentStep && wizardStep == totalWizardSteps }

    private func toolsChoiceButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.provider(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    isSelected ? Color.providerOlive.opacity(0.55) : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.providerOlive.opacity(0.85) : Color.white.opacity(0.14),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(Color.lavaShellCream)
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
        wizardStep = 1
        errorText = nil
        phase = .wizard
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
                await loadCampusesIfNeeded()
                if selectedSpecialties.isEmpty {
                    selectedSpecialties = ["Haircut"]
                }
                wizardStep = 1
                phase = .wizard
                return
            }
            if status == "approved" {
                await session.retryProviderProfileSync()
                if session.hasProviderProfile { return }
            }
            if ["pending", "under_review", "interview_scheduled", "approved", "rejected"].contains(status) {
                phase = .existingApplication
            } else {
                await loadCampusesIfNeeded()
                phase = .wizard
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await loadCampusesIfNeeded()
            phase = .wizard
        }
    }

    private func submit() async {
        isSubmitting = true
        errorText = nil
        defer { isSubmitting = false }

        // The backend requires `hasLicense` to be an explicit boolean. We never reach submit
        // without the user having answered Step 2, but guard anyway.
        let declared = licenseDeclared ?? false
        let trimmedLicense = licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        var body: [String: Any] = [
            "phoneNumber": PhoneNumberInputFormatter.normalized(
                phoneNumber,
                regionCode: currentRegionCode
            ),
            "yearsExperience": yearsExperience,
            "hasLicense": declared,
            "specialties": Array(selectedSpecialties).sorted(),
            "hasOwnTools": !needsTools,
            "availableHours": availableHours,
            "whyBeBarber": whyBeBarber.trimmingCharacters(in: .whitespacesAndNewlines),
            "portfolioDescription": portfolioDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            "socialMedia": socialMedia.trimmingCharacters(in: .whitespacesAndNewlines),
            "additionalNotes": additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
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
        if needsTools, !toolsNeeded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                // Backend rejected the license declaration — jump the user back to Step 2 so they
                // can correct the answer or license number rather than leaving them on Review.
                withAnimation { wizardStep = 2 }
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

    static let serviceNames: [String] = [
        "Buzz Cut", "Line Up", "Beard Trim", "Haircut", "Taper", "Hot Shave", "Kids Cut",
        "Fade", "Haircut & Fade", "Mullet", "Design/Art", "Afro Textures", "Women's Cut",
        "Color Treatment", "Perm",
    ]

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
                description: "Congratulations! Your application was approved. Pull to refresh — we’ll sync your barber profile automatically.",
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

// MARK: - Input chrome

/// Bordered, padded chrome around free-text inputs (single- or multi-line) so they read as
/// proper, submittable text boxes against the unified card backdrop instead of looking like
/// plain labels.
private struct ParagraphFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.lavaShellCream)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.providerElevatedSurface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.providerElevatedSurfaceStroke, lineWidth: 1)
            )
    }
}

extension View {
    fileprivate func paragraphFieldStyle() -> some View {
        modifier(ParagraphFieldStyle())
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
    static func format(_ raw: String, regionCode: String) -> String {
        let region = regionCode.uppercased()
        let startsWithPlus = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        let digits = raw.filter(\.isNumber)
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
        case 1 ... 3: return "(\(area)"
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
