import SwiftUI

/// Picks profile specialties from the same campus service catalog as **Services & Pricing**.
struct BarberSpecialtyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSpecialties: [String]

    @State private var catalog: [AdminServiceCatalogItem] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private let gridColumns = [GridItem(.adaptive(minimum: 148), spacing: 12)]

    var body: some View {
        NavigationStack {
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
                            Task { await loadCatalog() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.providerOlive)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if catalog.isEmpty {
                    Text("No campus services are configured yet. A Campus Manager or Admin can add services in the dashboard.")
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCream.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Choose from your campus service list. Selected specialties appear on your public profile.")
                                .font(.provider(.subheadline))
                                .foregroundStyle(Color.lavaShellCream.opacity(0.8))

                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(catalog) { service in
                                    serviceCard(service)
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
            .navigationTitle("Add Specialty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.provider(.body, weight: .semibold))
                }
            }
            .foregroundStyle(Color.lavaShellCream)
            .tint(.providerOlive)
            .providerLavaScreenChrome()
            .task {
                await loadCatalog()
            }
            .refreshable {
                await loadCatalog()
            }
        }
    }

    @ViewBuilder
    private func serviceCard(_ service: AdminServiceCatalogItem) -> some View {
        let selected = isSelected(service.name)
        Button {
            toggleSpecialty(service.name)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.provider(.title3))
                        .foregroundStyle(selected ? Color.providerOlive : Color.lavaShellCream.opacity(0.45))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name)
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let description = service.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !description.isEmpty {
                            Text(description)
                                .font(.provider(.caption2))
                                .foregroundStyle(Color.lavaShellCream.opacity(0.55))
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.providerOlive.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? Color.providerOlive.opacity(0.55) : Color.lavaShellCream.opacity(0.15),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ name: String) -> Bool {
        selectedSpecialties.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func toggleSpecialty(_ name: String) {
        if let index = selectedSpecialties.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            selectedSpecialties.remove(at: index)
        } else {
            selectedSpecialties.append(name)
        }
    }

    @MainActor
    private func loadCatalog() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let items = try await ProviderBarberServicesService.fetchServiceCatalog()
            catalog = items.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            loadError = error.localizedDescription
            catalog = []
        }
    }
}
