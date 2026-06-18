import SwiftUI

/// Campus Manager **Services** tab: same ledger layout as `ProviderBarberServicesView`, but toggling a
/// service adds/removes it from the campus catalog barbers can select from.
struct ProviderCampusManagerServicesView: View {
    @State private var rows: [CampusCatalogEditRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showDeletedServices = false
    @State private var showAddForm = false
    @State private var addServiceName = ""
    @State private var addServicePrice = ""
    @State private var addServiceError: String?
    @State private var saving = false
    @State private var toast: String?
    @State private var servicePendingRemoval: CampusCatalogEditRow?

    private let priceBounds = 5 ... 500

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading services…")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                VStack(spacing: 12) {
                    Text(loadError)
                        .font(.provider(.subheadline))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.lavaShellCream.opacity(0.85))
                    Button("Try again") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.providerOlive)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if let toast {
                        Text(toast)
                            .font(.provider(.caption, weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.providerOlive.opacity(0.45), in: Capsule())
                    }

                    Text("Add or remove services barbers can offer, and set the default base price for each.")
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCream.opacity(0.8))

                    HStack {
                        Text("Show removed")
                            .font(.provider(.subheadline, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $showDeletedServices)
                            .labelsHidden()
                            .tint(.providerOlive)
                    }

                    Button {
                        if showAddForm {
                            showAddForm = false
                            clearAddForm()
                        } else {
                            addServiceError = nil
                            showAddForm = true
                        }
                    } label: {
                        Label(
                            showAddForm ? "Cancel add" : "Add service",
                            systemImage: showAddForm ? "xmark.circle.fill" : "plus.circle.fill"
                        )
                        .font(.provider(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.providerOlive.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Color.lavaShellCream)
                    }
                    .buttonStyle(.plain)

                    if showAddForm {
                        addServiceFormRow
                    }

                    if rows.isEmpty {
                        Text("No services yet. Add a service to make it available for barbers on your campus.")
                            .font(.provider(.footnote))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                    } else {
                        servicesLedger
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: showDeletedServices) { _, _ in
            Task { await load() }
        }
        .confirmationDialog(
            "Remove “\(servicePendingRemoval?.name ?? "")”? Barbers will no longer be able to select this service until you add it back.",
            isPresented: Binding(
                get: { servicePendingRemoval != nil },
                set: { if !$0 { servicePendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let row = servicePendingRemoval {
                    Task { await setCatalogAvailability(row, available: false) }
                }
                servicePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { servicePendingRemoval = nil }
        }
    }

    private var servicesLedger: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(ledgerSections.enumerated()), id: \.element.category) { index, section in
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.category.title)
                        .font(.provider(.caption2, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.lavaShellCream.opacity(0.45))
                        .padding(.top, index == 0 ? 0 : 16)
                        .padding(.bottom, 8)

                    VStack(spacing: 14) {
                        ForEach(section.slugs, id: \.self) { slug in
                            if let idx = rows.firstIndex(where: { $0.slug == slug }) {
                                catalogLedgerRow(row: $rows[idx])
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ledgerSections: [ServiceLedgerSection] {
        let grouped = Dictionary(grouping: rows, by: \.category)
        return ServiceLedgerCategory.displayOrder.compactMap { category in
            guard let sectionRows = grouped[category], !sectionRows.isEmpty else { return nil }
            let slugs = ServiceLedgerRowOrdering.sortSlugs(sectionRows.map(\.slug)) { slug in
                sectionRows.first(where: { $0.slug == slug })?.name ?? slug
            }
            return ServiceLedgerSection(category: category, slugs: slugs)
        }
    }

    private var addServiceFormRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Service name", text: $addServiceName)
                .font(.provider(.body, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )

            HStack(spacing: 6) {
                Text("Price:")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream.opacity(0.62))
                    .frame(width: ProviderServicesLedgerStyle.fieldLabelWidth, alignment: .trailing)
                HStack(spacing: 4) {
                    Text("$")
                        .font(.provider(.subheadline, weight: .bold))
                        .foregroundStyle(Color.lavaShellCream.opacity(0.55))
                    TextField("0", text: $addServicePrice)
                        .keyboardType(.numberPad)
                        .font(.provider(.headline, weight: .bold))
                        .foregroundStyle(Color.lavaShellCream)
                        .multilineTextAlignment(.trailing)
                        .frame(width: ProviderServicesLedgerStyle.fieldInputWidth)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
            }

            if let addServiceError, !addServiceError.isEmpty {
                Text(addServiceError)
                    .font(.provider(.caption))
                    .foregroundStyle(.red)
            }

            Button {
                Task { await submitAddService() }
            } label: {
                Text("Save service")
                    .font(.provider(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.providerOlive.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(saving)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.providerOlive.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.providerOlive.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6]))
        )
    }

    @ViewBuilder
    private func catalogLedgerRow(row: Binding<CampusCatalogEditRow>) -> some View {
        let r = row.wrappedValue
        let isAvailable = r.isAvailable

        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    Task { await toggleCatalogAvailability(slug: r.slug) }
                } label: {
                    Image(systemName: isAvailable ? "checkmark.square.fill" : "square")
                        .font(.provider(.title3))
                        .foregroundStyle(isAvailable ? Color.providerOlive : Color.lavaShellCream.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(saving)

                Text(r.name)
                    .font(.provider(.body, weight: .bold))
                    .foregroundStyle(isAvailable ? Color.lavaShellCream : Color.lavaShellCream.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                catalogPriceInputSlot(row: row, isAvailable: isAvailable)
                catalogDurationDisplay(row: r, isAvailable: isAvailable)
            }
            .layoutPriority(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isAvailable ? Color.providerOlive.opacity(0.14) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isAvailable ? Color.providerOlive.opacity(0.72) : Color.lavaShellCream.opacity(0.14),
                    lineWidth: 2
                )
        )
        .opacity(isAvailable ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: isAvailable)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            if !isAvailable, !saving {
                Task { await toggleCatalogAvailability(slug: r.slug) }
            }
        }
    }

    @ViewBuilder
    private func catalogPriceInputSlot(row: Binding<CampusCatalogEditRow>, isAvailable: Bool) -> some View {
        let r = row.wrappedValue
        HStack(alignment: .center, spacing: 6) {
            Text("Price:")
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream.opacity(isAvailable ? 0.62 : 0.38))
                .frame(width: ProviderServicesLedgerStyle.fieldLabelWidth, alignment: .trailing)

            HStack(spacing: 4) {
                Text("$")
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lavaShellCream.opacity(isAvailable ? 0.55 : 0.35))

                TextField("0", text: row.priceText)
                    .keyboardType(.numberPad)
                    .font(.provider(.headline, weight: .bold))
                    .foregroundStyle(isAvailable ? Color.lavaShellCream : Color.lavaShellCream.opacity(0.45))
                    .multilineTextAlignment(.trailing)
                    .frame(width: ProviderServicesLedgerStyle.fieldInputWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(catalogInputBackground(isAvailable: isAvailable, needsCommit: r.priceNeedsCommit))
                    .overlay(catalogInputBorder(isAvailable: isAvailable, needsCommit: r.priceNeedsCommit))
                    .disabled(!isAvailable || saving)
                    .accessibilityLabel("Default price for \(r.name)")

                if isAvailable, r.priceNeedsCommit {
                    catalogFieldCommitButtons(
                        onConfirm: { Task { await commitPrice(slug: r.slug) } },
                        onCancel: { resetPriceDraft(slug: r.slug) },
                        confirmAccessibilityLabel: "Confirm price",
                        cancelAccessibilityLabel: "Cancel price change"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func catalogDurationDisplay(row: CampusCatalogEditRow, isAvailable: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("Time:")
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream.opacity(isAvailable ? 0.62 : 0.38))
                .frame(width: ProviderServicesLedgerStyle.fieldLabelWidth, alignment: .trailing)

            HStack(spacing: 4) {
                Text("\(row.defaultDurationMinutes)")
                    .font(.provider(.headline, weight: .bold))
                    .foregroundStyle(isAvailable ? Color.lavaShellCream.opacity(0.75) : Color.lavaShellCream.opacity(0.45))
                    .frame(width: ProviderServicesLedgerStyle.fieldInputWidth, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(isAvailable ? 0.06 : 0.03))
                    )

                Text("min")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream.opacity(isAvailable ? 0.55 : 0.35))
            }
        }
    }

    private func catalogInputBackground(isAvailable: Bool, needsCommit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                isAvailable
                    ? Color.white.opacity(needsCommit ? 0.18 : 0.12)
                    : Color.white.opacity(0.03)
            )
    }

    private func catalogInputBorder(isAvailable: Bool, needsCommit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(
                needsCommit ? Color.providerOlive : Color.lavaShellCream.opacity(isAvailable ? 0.22 : 0.1),
                lineWidth: needsCommit ? 2 : 1
            )
    }

    @ViewBuilder
    private func catalogFieldCommitButtons(
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        confirmAccessibilityLabel: String,
        cancelAccessibilityLabel: String
    ) -> some View {
        Button(action: onConfirm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.provider(.title2))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.lavaShellCream, Color.providerOlive)
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .accessibilityLabel(confirmAccessibilityLabel)

        Button(action: onCancel) {
            Image(systemName: "xmark.circle.fill")
                .font(.provider(.title3))
                .foregroundStyle(Color.lavaShellCream.opacity(0.45))
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .accessibilityLabel(cancelAccessibilityLabel)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let catalog = try await ProviderCampusManagerService.listPlatformServices(
                includeInactive: showDeletedServices
            )
            rows = Self.mappedRows(from: catalog)
        } catch {
            loadError = error.localizedDescription
            rows = []
        }
    }

    private func toggleCatalogAvailability(slug: String) async {
        guard let row = rows.first(where: { $0.slug == slug }) else { return }
        if row.isAvailable {
            servicePendingRemoval = row
        } else {
            await setCatalogAvailability(row, available: true)
        }
    }

    private func setCatalogAvailability(_ row: CampusCatalogEditRow, available: Bool) async {
        saving = true
        defer { saving = false }

        do {
            if available {
                try await ProviderCampusManagerService.setPlatformServiceActive(id: row.id, isActive: true)
                toast = "\(row.name) is now available for barbers."
            } else {
                try await ProviderCampusManagerService.deactivatePlatformService(id: row.id)
                toast = "\(row.name) was removed from the catalog."
            }
            await load()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toast = nil
        } catch {
            toast = error.localizedDescription
        }
    }

    private func commitPrice(slug: String) async {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        saving = true
        defer { saving = false }

        let digits = rows[idx].priceText.filter(\.isNumber)
        guard let raw = Int(digits), raw > 0 else { return }
        let clamped = clampPrice(raw)
        rows[idx].committedPriceDollars = clamped
        rows[idx].priceText = "\(clamped)"

        do {
            try await ProviderCampusManagerService.updatePlatformServiceBasePrice(
                id: rows[idx].id,
                basePriceCents: clamped * 100
            )
            toast = clamped != raw ? "Price must be $\(priceBounds.lowerBound)–$\(priceBounds.upperBound); saved $\(clamped)." : "Saved."
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toast = nil
        } catch {
            toast = error.localizedDescription
            await load()
        }
    }

    private func resetPriceDraft(slug: String) {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        rows[idx].priceText = "\(rows[idx].committedPriceDollars)"
    }

    private func submitAddService() async {
        addServiceError = nil
        let name = addServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            addServiceError = "Service name is required."
            return
        }
        let raw = addServicePrice.replacingOccurrences(of: ",", with: ".")
        guard let dollars = Double(raw.trimmingCharacters(in: .whitespaces)), dollars > 0 else {
            addServiceError = "Enter a valid base price."
            return
        }
        let cents = Int((dollars * 100).rounded())

        saving = true
        defer { saving = false }

        do {
            try await ProviderCampusManagerService.createPlatformService(
                name: name,
                description: nil,
                basePriceCents: cents
            )
            showAddForm = false
            clearAddForm()
            await load()
            toast = "\(name) added."
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toast = nil
        } catch let CampusCutsHTTPError.httpStatus(_, msg) {
            addServiceError = msg ?? "Could not add service."
        } catch {
            addServiceError = error.localizedDescription
        }
    }

    private func clearAddForm() {
        addServiceName = ""
        addServicePrice = ""
        addServiceError = nil
    }

    private func clampPrice(_ value: Int) -> Int {
        min(priceBounds.upperBound, max(priceBounds.lowerBound, value))
    }

    private static func mappedRows(from catalog: [AdminServiceCatalogItem]) -> [CampusCatalogEditRow] {
        catalog.map { item in
            let baseDollars = clampStatic(max(1, item.basePriceCents / 100), min: 5, max: 500)
            let duration = clampStatic(item.defaultDurationMinutes ?? 45, min: 15, max: 240)
            return CampusCatalogEditRow(
                id: item.id,
                slug: item.slug,
                name: item.name,
                category: ServiceLedgerCategorizer.category(slug: item.slug, name: item.name),
                isAvailable: item.isActive ?? true,
                priceText: "\(baseDollars)",
                committedPriceDollars: baseDollars,
                defaultDurationMinutes: duration
            )
        }
    }

    private static func clampStatic(_ value: Int, min lo: Int, max hi: Int) -> Int {
        min(hi, max(lo, value))
    }
}

private struct CampusCatalogEditRow: Identifiable, Hashable {
    let id: Int
    let slug: String
    let name: String
    let category: ServiceLedgerCategory
    var isAvailable: Bool
    var priceText: String
    var committedPriceDollars: Int
    let defaultDurationMinutes: Int

    var parsedPriceDollars: Int? {
        let digits = priceText.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    var priceNeedsCommit: Bool {
        guard isAvailable else { return false }
        guard let parsed = parsedPriceDollars else { return false }
        return parsed != committedPriceDollars
    }
}
