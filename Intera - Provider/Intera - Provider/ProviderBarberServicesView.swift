import SwiftUI

/// In-app **Services & Pricing** editor: campus catalog from `GET /admin/services` + barber `specialties` / `pricing`
/// from `GET /barbers/user/:userId`, persisted with `PUT /barbers/:id` (same contract as web `BarberServiceSpecialties`).
struct ProviderBarberServicesView: View {
    @Environment(ProviderSession.self) private var session

    @State private var rows: [ServiceEditRow] = []
    /// `barbers.id` from the last successful `GET /barbers/user/:userId` (used for `PUT /barbers/:id`).
    @State private var barberRecordIdForSave: String?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saving = false
    @State private var toast: String?

    private let priceBounds = 5 ... 500
    private let durationBounds = 15 ... 240

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.providerOlive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                Text("No campus services are configured yet. A Campus Manager or Admin can add services in the dashboard.")
                    .font(.provider(.subheadline))
                    .foregroundStyle(Color.lavaShellCream.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let toast {
                            Text(toast)
                                .font(.provider(.caption, weight: .semibold))
                                .foregroundStyle(Color.lavaShellCream)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.providerOlive.opacity(0.45), in: Capsule())
                        }

                        Text("Choose the services you offer, then set a price and duration for each one.")
                            .font(.provider(.subheadline))
                            .foregroundStyle(Color.lavaShellCream.opacity(0.8))

                        servicesLedger
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.clear)
        .providerNavigationStackDestinationBackdrop()
        .navigationTitle("Services")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .task {
            await load()
        }
        .refreshable {
            await load()
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
                                serviceLedgerRow(row: $rows[idx])
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

    @ViewBuilder
    private func serviceLedgerRow(row: Binding<ServiceEditRow>) -> some View {
        let r = row.wrappedValue
        let isActive = r.isOffered

        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    Task { await toggleOffered(slug: r.slug) }
                } label: {
                    Image(systemName: isActive ? "checkmark.square.fill" : "square")
                        .font(.provider(.title3))
                        .foregroundStyle(isActive ? Color.providerOlive : Color.lavaShellCream.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(saving)

                Text(r.name)
                    .font(.provider(.body, weight: .bold))
                    .foregroundStyle(isActive ? Color.lavaShellCream : Color.lavaShellCream.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                priceInputSlot(row: row, isActive: isActive)
                durationInputSlot(row: row, isActive: isActive)
            }
            .layoutPriority(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? Color.providerOlive.opacity(0.14) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isActive ? Color.providerOlive.opacity(0.72) : Color.lavaShellCream.opacity(0.14),
                    lineWidth: 2
                )
        )
        .opacity(isActive ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            if !isActive, !saving {
                Task { await toggleOffered(slug: r.slug) }
            }
        }
    }

    @ViewBuilder
    private func priceInputSlot(row: Binding<ServiceEditRow>, isActive: Bool) -> some View {
        let r = row.wrappedValue
        HStack(alignment: .center, spacing: 6) {
            Text("Price:")
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream.opacity(isActive ? 0.62 : 0.38))
                .frame(width: ProviderServicesLedgerStyle.fieldLabelWidth, alignment: .trailing)

            HStack(spacing: 4) {
                Text("$")
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lavaShellCream.opacity(isActive ? 0.55 : 0.35))

                TextField("0", text: row.priceText)
                    .keyboardType(.numberPad)
                    .font(.provider(.headline, weight: .bold))
                    .foregroundStyle(isActive ? Color.lavaShellCream : Color.lavaShellCream.opacity(0.45))
                    .multilineTextAlignment(.trailing)
                    .frame(width: ProviderServicesLedgerStyle.fieldInputWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(serviceInputBackground(isActive: isActive, needsCommit: r.priceNeedsCommit))
                    .overlay(serviceInputBorder(isActive: isActive, needsCommit: r.priceNeedsCommit))
                    .disabled(!isActive || saving)
                    .accessibilityLabel("Price for \(r.name)")

                if isActive, r.priceNeedsCommit {
                    serviceFieldCommitButtons(
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
    private func durationInputSlot(row: Binding<ServiceEditRow>, isActive: Bool) -> some View {
        let r = row.wrappedValue
        HStack(alignment: .center, spacing: 6) {
            Text("Time:")
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream.opacity(isActive ? 0.62 : 0.38))
                .frame(width: ProviderServicesLedgerStyle.fieldLabelWidth, alignment: .trailing)

            HStack(spacing: 4) {
                TextField("0", text: row.durationText)
                    .keyboardType(.numberPad)
                    .font(.provider(.headline, weight: .bold))
                    .foregroundStyle(isActive ? Color.lavaShellCream : Color.lavaShellCream.opacity(0.45))
                    .multilineTextAlignment(.trailing)
                    .frame(width: ProviderServicesLedgerStyle.fieldInputWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(serviceInputBackground(isActive: isActive, needsCommit: r.durationNeedsCommit))
                    .overlay(serviceInputBorder(isActive: isActive, needsCommit: r.durationNeedsCommit))
                    .disabled(!isActive || saving)
                    .accessibilityLabel("Duration in minutes for \(r.name)")

                Text("min")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream.opacity(isActive ? 0.55 : 0.35))

                if isActive, r.durationNeedsCommit {
                    serviceFieldCommitButtons(
                        onConfirm: { Task { await commitDuration(slug: r.slug) } },
                        onCancel: { resetDurationDraft(slug: r.slug) },
                        confirmAccessibilityLabel: "Confirm duration",
                        cancelAccessibilityLabel: "Cancel duration change"
                    )
                }
            }
        }
    }

    private func serviceInputBackground(isActive: Bool, needsCommit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                isActive
                    ? Color.white.opacity(needsCommit ? 0.18 : 0.12)
                    : Color.white.opacity(0.03)
            )
    }

    private func serviceInputBorder(isActive: Bool, needsCommit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(
                needsCommit ? Color.providerOlive : Color.lavaShellCream.opacity(isActive ? 0.22 : 0.1),
                lineWidth: needsCommit ? 2 : 1
            )
    }

    @ViewBuilder
    private func serviceFieldCommitButtons(
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

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        guard let userId = session.authUser?.id else {
            loadError = "You need to be signed in."
            return
        }

        do {
            async let catalogTask = ProviderBarberServicesService.fetchServiceCatalog()
            async let barberTask = ProviderBarberServicesService.fetchBarberUserProfile(userId: userId)
            let (catalog, barber) = try await (catalogTask, barberTask)
            barberRecordIdForSave = barber.id
            rows = Self.mergedRows(catalog: catalog, barber: barber)
        } catch {
            loadError = error.localizedDescription
            rows = []
            barberRecordIdForSave = nil
        }
    }

    private var barberIdForAPI: String? { barberRecordIdForSave ?? session.barberProfile?.id }

    private func toggleOffered(slug: String) async {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        saving = true
        defer { saving = false }

        var next = rows[idx]
        next.isOffered.toggle()
        if next.isOffered {
            let base = next.committedPriceDollars > 0 ? next.committedPriceDollars : next.suggestedDollars
            next.committedPriceDollars = clampPrice(base)
            next.priceText = "\(next.committedPriceDollars)"
            let baseDuration = next.committedDurationMinutes > 0
                ? next.committedDurationMinutes
                : next.suggestedDurationMinutes
            next.committedDurationMinutes = clampDuration(baseDuration)
            next.durationText = "\(next.committedDurationMinutes)"
        } else {
            next.committedPriceDollars = next.suggestedDollars
            next.priceText = "\(next.suggestedDollars)"
            next.committedDurationMinutes = next.suggestedDurationMinutes
            next.durationText = "\(next.suggestedDurationMinutes)"
        }
        rows[idx] = next

        await persistAndRefresh(from: rows)
    }

    private func commitPrice(slug: String) async {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        saving = true
        defer { saving = false }

        let digits = rows[idx].priceText.filter(\.isNumber)
        guard let raw = Int(digits) else { return }
        let clamped = clampPrice(raw)
        rows[idx].committedPriceDollars = clamped
        rows[idx].priceText = "\(clamped)"
        await persistAndRefresh(from: rows)
        toast = clamped != raw ? "Price must be $\(priceBounds.lowerBound)–$\(priceBounds.upperBound); saved $\(clamped)." : "Saved."
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        toast = nil
    }

    private func resetPriceDraft(slug: String) {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        rows[idx].priceText = "\(rows[idx].committedPriceDollars)"
    }

    private func commitDuration(slug: String) async {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        saving = true
        defer { saving = false }

        let digits = rows[idx].durationText.filter(\.isNumber)
        guard let raw = Int(digits) else { return }
        let clamped = clampDuration(raw)
        rows[idx].committedDurationMinutes = clamped
        rows[idx].durationText = "\(clamped)"
        await persistAndRefresh(from: rows)
        toast = clamped != raw
            ? "Duration must be \(durationBounds.lowerBound)–\(durationBounds.upperBound) minutes; saved \(clamped) min."
            : "Saved."
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        toast = nil
    }

    private func resetDurationDraft(slug: String) {
        guard let idx = rows.firstIndex(where: { $0.slug == slug }) else { return }
        rows[idx].durationText = "\(rows[idx].committedDurationMinutes)"
    }

    private func clampPrice(_ v: Int) -> Int {
        min(priceBounds.upperBound, max(priceBounds.lowerBound, v))
    }

    private func clampDuration(_ v: Int) -> Int {
        min(durationBounds.upperBound, max(durationBounds.lowerBound, v))
    }

    private func persistAndRefresh(from state: [ServiceEditRow]) async {
        guard let barberId = barberIdForAPI else {
            toast = "Could not determine your barber profile. Pull to refresh."
            return
        }
        let specialties = state.filter(\.isOffered).map(\.name)
        let pricing: [BarberPricingEntryDTO] = state.filter(\.isOffered).map {
            BarberPricingEntryDTO(
                name: $0.name,
                price: Double($0.committedPriceDollars),
                durationMinutes: $0.committedDurationMinutes
            )
        }
        do {
            try await ProviderBarberServicesService.updateBarberServicesAndPricing(
                barberId: barberId,
                specialties: specialties,
                pricing: pricing
            )
            try? await session.refreshProfileAfterSignIn()
        } catch {
            toast = error.localizedDescription
            await load()
        }
    }

    private static func mergedRows(
        catalog: [AdminServiceCatalogItem],
        barber: BarberUserProfileDTO
    ) -> [ServiceEditRow] {
        let specLower = Set((barber.specialties ?? []).map { $0.lowercased() })
        var priceByName: [String: Double] = [:]
        var durationByName: [String: Int] = [:]
        for p in barber.pricing ?? [] {
            priceByName[p.name.lowercased()] = p.price
            if let durationMinutes = p.durationMinutes {
                durationByName[p.name.lowercased()] = durationMinutes
            }
        }

        return catalog.map { item in
            let offered = specLower.contains(item.name.lowercased())
            let suggestedRaw = max(1, item.basePriceCents / 100)
            let suggested = max(5, min(500, suggestedRaw))
            let suggestedDuration = clampStatic(
                item.defaultDurationMinutes ?? 45,
                min: 15,
                max: 240
            )
            let saved = priceByName[item.name.lowercased()]
            let initialDollars = clampStatic(
                Int((saved ?? Double(suggested)).rounded()),
                min: 5,
                max: 500
            )
            let savedDuration = durationByName[item.name.lowercased()]
            let initialDuration = clampStatic(
                savedDuration ?? suggestedDuration,
                min: 15,
                max: 240
            )
            return ServiceEditRow(
                slug: item.slug,
                name: item.name,
                category: ServiceLedgerCategorizer.category(slug: item.slug, name: item.name),
                suggestedDollars: suggested,
                suggestedDurationMinutes: suggestedDuration,
                isOffered: offered,
                priceText: offered ? "\(initialDollars)" : "\(suggested)",
                committedPriceDollars: offered ? initialDollars : suggested,
                durationText: offered ? "\(initialDuration)" : "\(suggestedDuration)",
                committedDurationMinutes: offered ? initialDuration : suggestedDuration
            )
        }
    }

    private static func clampStatic(_ v: Int, min lo: Int, max hi: Int) -> Int {
        min(hi, max(lo, v))
    }
}

private struct ServiceEditRow: Identifiable, Hashable {
    let slug: String
    let name: String
    let category: ServiceLedgerCategory
    let suggestedDollars: Int
    let suggestedDurationMinutes: Int
    var isOffered: Bool
    var priceText: String
    var committedPriceDollars: Int
    var durationText: String
    var committedDurationMinutes: Int

    var id: String { slug }

    var parsedPriceDollars: Int? {
        let digits = priceText.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    var parsedDurationMinutes: Int? {
        let digits = durationText.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    var priceNeedsCommit: Bool {
        guard isOffered else { return false }
        guard let p = parsedPriceDollars else { return false }
        return p != committedPriceDollars
    }

    var durationNeedsCommit: Bool {
        guard isOffered else { return false }
        guard let duration = parsedDurationMinutes else { return false }
        return duration != committedDurationMinutes
    }
}
