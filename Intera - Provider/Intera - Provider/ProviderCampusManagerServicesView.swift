import SwiftUI

/// Campus Manager **Services** tab: same ledger layout as `ProviderBarberServicesView`, but toggling a
/// service adds/removes it from the campus catalog and sets **price / duration ranges** barbers choose within.
struct ProviderCampusManagerServicesView: View {
    @State private var rows: [CampusCatalogEditRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showDeletedServices = false
    @State private var showAddForm = false
    @State private var addServiceName = ""
    @State private var addMinPrice = ""
    @State private var addMaxPrice = ""
    @State private var addMinDuration = ""
    @State private var addMaxDuration = ""
    @State private var addServiceError: String?
    @State private var saving = false
    @State private var toast: String?
    @State private var servicePendingRemoval: CampusCatalogEditRow?

    private let priceBounds = 5 ... 500
    private let durationBounds = 15 ... 240

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

                    Text("Add or remove services barbers can offer, and set the price and duration ranges they may choose within.")
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

            catalogRangeInputRow(
                label: "Price:",
                prefix: "$",
                suffix: nil,
                minText: $addMinPrice,
                maxText: $addMaxPrice,
                isEnabled: true,
                needsCommit: false,
                onConfirm: nil,
                onCancel: nil
            )

            catalogRangeInputRow(
                label: "Time:",
                prefix: nil,
                suffix: "min",
                minText: $addMinDuration,
                maxText: $addMaxDuration,
                isEnabled: true,
                needsCommit: false,
                onConfirm: nil,
                onCancel: nil
            )

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
                catalogRangeInputRow(
                    label: "Price:",
                    prefix: "$",
                    suffix: nil,
                    minText: row.minPriceText,
                    maxText: row.maxPriceText,
                    isEnabled: isAvailable,
                    needsCommit: r.priceNeedsCommit,
                    onConfirm: { Task { await commitPriceRange(slug: r.slug) } },
                    onCancel: { resetPriceDraft(slug: r.slug) }
                )

                catalogRangeInputRow(
                    label: "Time:",
                    prefix: nil,
                    suffix: "min",
                    minText: row.minDurationText,
                    maxText: row.maxDurationText,
                    isEnabled: isAvailable,
                    needsCommit: r.durationNeedsCommit,
                    onConfirm: { Task { await commitDurationRange(slug: r.slug) } },
                    onCancel: { resetDurationDraft(slug: r.slug) }
                )
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
    private func catalogRangeInputRow(
        label: String,
        prefix: String?,
        suffix: String?,
        minText: Binding<String>,
        maxText: Binding<String>,
        isEnabled: Bool,
        needsCommit: Bool,
        onConfirm: (() -> Void)?,
        onCancel: (() -> Void)?
    ) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream.opacity(isEnabled ? 0.62 : 0.38))
                .frame(width: ProviderServicesLedgerStyle.fieldLabelWidth, alignment: .trailing)

            HStack(spacing: 3) {
                if let prefix {
                    Text(prefix)
                        .font(.provider(.caption, weight: .bold))
                        .foregroundStyle(Color.lavaShellCream.opacity(isEnabled ? 0.55 : 0.35))
                }

                catalogRangeField(text: minText, isEnabled: isEnabled, needsCommit: needsCommit)

                Text("–")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream.opacity(isEnabled ? 0.45 : 0.28))

                if let prefix {
                    Text(prefix)
                        .font(.provider(.caption, weight: .bold))
                        .foregroundStyle(Color.lavaShellCream.opacity(isEnabled ? 0.55 : 0.35))
                }

                catalogRangeField(text: maxText, isEnabled: isEnabled, needsCommit: needsCommit)

                if let suffix {
                    Text(suffix)
                        .font(.provider(.caption2, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream.opacity(isEnabled ? 0.55 : 0.35))
                }

                if isEnabled, needsCommit, let onConfirm, let onCancel {
                    catalogFieldCommitButtons(
                        onConfirm: onConfirm,
                        onCancel: onCancel,
                        confirmAccessibilityLabel: "Confirm \(label) range",
                        cancelAccessibilityLabel: "Cancel \(label) range change"
                    )
                }
            }
        }
    }

    private func catalogRangeField(text: Binding<String>, isEnabled: Bool, needsCommit: Bool) -> some View {
        TextField("0", text: text)
            .keyboardType(.numberPad)
            .font(.provider(.subheadline, weight: .bold))
            .foregroundStyle(isEnabled ? Color.lavaShellCream : Color.lavaShellCream.opacity(0.45))
            .multilineTextAlignment(.trailing)
            .frame(width: ProviderServicesLedgerStyle.rangeFieldInputWidth)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(catalogInputBackground(isAvailable: isEnabled, needsCommit: needsCommit))
            .overlay(catalogInputBorder(isAvailable: isEnabled, needsCommit: needsCommit))
            .disabled(!isEnabled || saving)
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
                .font(.provider(.title3))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.lavaShellCream, Color.providerOlive)
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .accessibilityLabel(confirmAccessibilityLabel)

        Button(action: onCancel) {
            Image(systemName: "xmark.circle.fill")
                .font(.provider(.title2))
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

    private func commitPriceRange(slug: String) async {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        guard let parsed = parsePriceRange(from: rows[idx]) else {
            toast = "Enter a valid price range (min ≤ max, $5–$500)."
            return
        }

        saving = true
        defer { saving = false }

        rows[idx].committedMinPriceDollars = parsed.min
        rows[idx].committedMaxPriceDollars = parsed.max
        rows[idx].minPriceText = "\(parsed.min)"
        rows[idx].maxPriceText = "\(parsed.max)"

        do {
            try await ProviderCampusManagerService.updatePlatformServiceBounds(
                id: rows[idx].id,
                minPriceCents: parsed.min * 100,
                maxPriceCents: parsed.max * 100,
                minDurationMinutes: rows[idx].committedMinDurationMinutes,
                maxDurationMinutes: rows[idx].committedMaxDurationMinutes
            )
            toast = "Price range saved."
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toast = nil
        } catch {
            toast = error.localizedDescription
            await load()
        }
    }

    private func commitDurationRange(slug: String) async {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        guard let parsed = parseDurationRange(from: rows[idx]) else {
            toast = "Enter a valid duration range (min ≤ max, 15–240 min)."
            return
        }

        saving = true
        defer { saving = false }

        rows[idx].committedMinDurationMinutes = parsed.min
        rows[idx].committedMaxDurationMinutes = parsed.max
        rows[idx].minDurationText = "\(parsed.min)"
        rows[idx].maxDurationText = "\(parsed.max)"

        do {
            try await ProviderCampusManagerService.updatePlatformServiceBounds(
                id: rows[idx].id,
                minPriceCents: rows[idx].committedMinPriceDollars * 100,
                maxPriceCents: rows[idx].committedMaxPriceDollars * 100,
                minDurationMinutes: parsed.min,
                maxDurationMinutes: parsed.max
            )
            toast = "Duration range saved."
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toast = nil
        } catch {
            toast = error.localizedDescription
            await load()
        }
    }

    private func resetPriceDraft(slug: String) {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        rows[idx].minPriceText = "\(rows[idx].committedMinPriceDollars)"
        rows[idx].maxPriceText = "\(rows[idx].committedMaxPriceDollars)"
    }

    private func resetDurationDraft(slug: String) {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        rows[idx].minDurationText = "\(rows[idx].committedMinDurationMinutes)"
        rows[idx].maxDurationText = "\(rows[idx].committedMaxDurationMinutes)"
    }

    private func submitAddService() async {
        addServiceError = nil
        let name = addServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            addServiceError = "Service name is required."
            return
        }

        guard let minPrice = Int(addMinPrice.filter(\.isNumber)),
              let maxPrice = Int(addMaxPrice.filter(\.isNumber)),
              minPrice >= priceBounds.lowerBound,
              maxPrice <= priceBounds.upperBound,
              minPrice <= maxPrice
        else {
            addServiceError = "Enter a valid price range ($5–$500, min ≤ max)."
            return
        }

        guard let minDuration = Int(addMinDuration.filter(\.isNumber)),
              let maxDuration = Int(addMaxDuration.filter(\.isNumber)),
              minDuration >= durationBounds.lowerBound,
              maxDuration <= durationBounds.upperBound,
              minDuration <= maxDuration
        else {
            addServiceError = "Enter a valid duration range (15–240 min, min ≤ max)."
            return
        }

        saving = true
        defer { saving = false }

        do {
            try await ProviderCampusManagerService.createPlatformService(
                name: name,
                description: nil,
                minPriceCents: minPrice * 100,
                maxPriceCents: maxPrice * 100,
                minDurationMinutes: minDuration,
                maxDurationMinutes: maxDuration
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
        addMinPrice = ""
        addMaxPrice = ""
        addMinDuration = ""
        addMaxDuration = ""
        addServiceError = nil
    }

    private func parsePriceRange(from row: CampusCatalogEditRow) -> (min: Int, max: Int)? {
        guard let minVal = Int(row.minPriceText.filter(\.isNumber)),
              let maxVal = Int(row.maxPriceText.filter(\.isNumber)),
              minVal >= priceBounds.lowerBound,
              maxVal <= priceBounds.upperBound,
              minVal <= maxVal
        else { return nil }
        return (minVal, maxVal)
    }

    private func parseDurationRange(from row: CampusCatalogEditRow) -> (min: Int, max: Int)? {
        guard let minVal = Int(row.minDurationText.filter(\.isNumber)),
              let maxVal = Int(row.maxDurationText.filter(\.isNumber)),
              minVal >= durationBounds.lowerBound,
              maxVal <= durationBounds.upperBound,
              minVal <= maxVal
        else { return nil }
        return (minVal, maxVal)
    }

    private static func mappedRows(from catalog: [AdminServiceCatalogItem]) -> [CampusCatalogEditRow] {
        catalog.map { item in
            let baseDollars = max(1, item.basePriceCents / 100)
            let minDollars = item.minPriceCents.map { max(1, $0 / 100) }
                ?? clampStatic(Int((Double(baseDollars) * 0.8).rounded()), min: 5, max: 500)
            let maxDollars = item.maxPriceCents.map { max(1, $0 / 100) }
                ?? clampStatic(Int((Double(baseDollars) * 1.5).rounded()), min: 5, max: 500)
            let resolvedMinPrice = min(minDollars, maxDollars)
            let resolvedMaxPrice = max(minDollars, maxDollars)

            let defaultDuration = item.defaultDurationMinutes ?? 45
            let minDuration = item.minDurationMinutes
                ?? clampStatic(defaultDuration - 15, min: 15, max: 240)
            let maxDuration = item.maxDurationMinutes
                ?? clampStatic(defaultDuration + 15, min: 15, max: 240)
            let resolvedMinDuration = min(minDuration, maxDuration)
            let resolvedMaxDuration = max(minDuration, maxDuration)

            return CampusCatalogEditRow(
                id: item.id,
                slug: item.slug,
                name: item.name,
                category: ServiceLedgerCategorizer.category(slug: item.slug, name: item.name),
                isAvailable: item.isActive ?? true,
                minPriceText: "\(resolvedMinPrice)",
                maxPriceText: "\(resolvedMaxPrice)",
                committedMinPriceDollars: resolvedMinPrice,
                committedMaxPriceDollars: resolvedMaxPrice,
                minDurationText: "\(resolvedMinDuration)",
                maxDurationText: "\(resolvedMaxDuration)",
                committedMinDurationMinutes: resolvedMinDuration,
                committedMaxDurationMinutes: resolvedMaxDuration
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
    var minPriceText: String
    var maxPriceText: String
    var committedMinPriceDollars: Int
    var committedMaxPriceDollars: Int
    var minDurationText: String
    var maxDurationText: String
    var committedMinDurationMinutes: Int
    var committedMaxDurationMinutes: Int

    var priceNeedsCommit: Bool {
        guard isAvailable else { return false }
        guard let parsed = parsedPriceRange else { return false }
        return parsed.min != committedMinPriceDollars || parsed.max != committedMaxPriceDollars
    }

    var durationNeedsCommit: Bool {
        guard isAvailable else { return false }
        guard let parsed = parsedDurationRange else { return false }
        return parsed.min != committedMinDurationMinutes || parsed.max != committedMaxDurationMinutes
    }

    private var parsedPriceRange: (min: Int, max: Int)? {
        guard let minVal = Int(minPriceText.filter(\.isNumber)),
              let maxVal = Int(maxPriceText.filter(\.isNumber))
        else { return nil }
        return (minVal, maxVal)
    }

    private var parsedDurationRange: (min: Int, max: Int)? {
        guard let minVal = Int(minDurationText.filter(\.isNumber)),
              let maxVal = Int(maxDurationText.filter(\.isNumber))
        else { return nil }
        return (minVal, maxVal)
    }
}
