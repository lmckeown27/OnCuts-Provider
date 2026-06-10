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

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.providerOlive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 12) {
                    Text(loadError)
                        .font(.subheadline)
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
                    .font(.subheadline)
                    .foregroundStyle(Color.lavaShellCream.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let toast {
                            Text(toast)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.lavaShellCream)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.providerOlive.opacity(0.45), in: Capsule())
                        }

                        Text("Select services and set your prices. Offerings and base prices come from your campus service list.")
                            .font(.subheadline)
                            .foregroundStyle(Color.lavaShellCream.opacity(0.8))

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 148), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach($rows) { $row in
                                serviceCard(row: $row)
                            }
                        }
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
        .navigationTitle("Services & Pricing")
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

    @ViewBuilder
    private func serviceCard(row: Binding<ServiceEditRow>) -> some View {
        let r = row.wrappedValue
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    Task { await toggleOffered(slug: r.slug) }
                } label: {
                    Image(systemName: r.isOffered ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(r.isOffered ? Color.providerOlive : Color.lavaShellCream.opacity(0.45))
                }
                .buttonStyle(.plain)
                .disabled(saving)

                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .fixedSize(horizontal: false, vertical: true)
                    if !r.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(r.description)
                            .font(.caption2)
                            .foregroundStyle(Color.lavaShellCream.opacity(0.55))
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }

            if r.isOffered {
                HStack(spacing: 8) {
                    Text("$")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.lavaShellCream.opacity(0.55))

                    TextField("Price", text: row.priceText)
                        .keyboardType(.numberPad)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.lavaShellCream)
                        .frame(minWidth: 48, maxWidth: 72)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(r.priceNeedsCommit ? 0.14 : 0.08))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    r.priceNeedsCommit ? Color.providerOlive : Color.lavaShellCream.opacity(0.2),
                                    lineWidth: r.priceNeedsCommit ? 2 : 1
                                )
                        }
                        .disabled(saving)
                        .accessibilityLabel("Price for \(r.name)")

                    if r.priceNeedsCommit {
                        Button {
                            Task { await commitPrice(slug: r.slug) }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.lavaShellCream, Color.providerOlive)
                        }
                        .buttonStyle(.plain)
                        .disabled(saving)
                        .accessibilityLabel("Confirm price")

                        Button {
                            resetPriceDraft(slug: r.slug)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.lavaShellCream.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .disabled(saving)
                        .accessibilityLabel("Cancel price change")
                    }
                }

                if r.priceNeedsCommit {
                    Text("Tap the checkmark to save this price.")
                        .font(.caption2)
                        .foregroundStyle(Color.lavaShellCream.opacity(0.6))
                }
            } else {
                Text("+ Add")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.providerOlive)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(r.isOffered ? Color.providerOlive.opacity(0.18) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    r.isOffered ? Color.providerOlive.opacity(0.55) : Color.lavaShellCream.opacity(0.15),
                    lineWidth: 2
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !r.isOffered, !saving {
                Task { await toggleOffered(slug: r.slug) }
            }
        }
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
        } else {
            next.committedPriceDollars = next.suggestedDollars
            next.priceText = "\(next.suggestedDollars)"
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

    private func clampPrice(_ v: Int) -> Int {
        min(priceBounds.upperBound, max(priceBounds.lowerBound, v))
    }

    private func persistAndRefresh(from state: [ServiceEditRow]) async {
        guard let barberId = barberIdForAPI else {
            toast = "Could not determine your barber profile. Pull to refresh."
            return
        }
        let specialties = state.filter(\.isOffered).map(\.name)
        let pricing: [BarberPricingEntryDTO] = state.filter(\.isOffered).map {
            BarberPricingEntryDTO(name: $0.name, price: Double($0.committedPriceDollars))
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
        for p in barber.pricing ?? [] {
            priceByName[p.name.lowercased()] = p.price
        }

        return catalog.map { item in
            let offered = specLower.contains(item.name.lowercased())
            let suggestedRaw = max(1, item.basePriceCents / 100)
            let suggested = max(5, min(500, suggestedRaw))
            let saved = priceByName[item.name.lowercased()]
            let initialDollars = clampStatic(
                Int((saved ?? Double(suggested)).rounded()),
                min: 5,
                max: 500
            )
            return ServiceEditRow(
                slug: item.slug,
                name: item.name,
                description: item.description ?? "",
                suggestedDollars: suggested,
                isOffered: offered,
                priceText: offered ? "\(initialDollars)" : "\(suggested)",
                committedPriceDollars: offered ? initialDollars : suggested
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
    let description: String
    let suggestedDollars: Int
    var isOffered: Bool
    var priceText: String
    var committedPriceDollars: Int

    var id: String { slug }

    var parsedPriceDollars: Int? {
        let digits = priceText.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    var priceNeedsCommit: Bool {
        guard isOffered else { return false }
        guard let p = parsedPriceDollars else { return false }
        return p != committedPriceDollars
    }
}
