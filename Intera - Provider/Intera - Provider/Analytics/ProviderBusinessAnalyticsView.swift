import SwiftUI

/// Barber-facing **Business Analytics** sheet: Performance metrics + Clients directory.
struct ProviderBusinessAnalyticsView: View {
    @Environment(ProviderSession.self) private var session

    private enum Tab: String, CaseIterable, Identifiable {
        case performance = "Performance"
        case clients = "Clients"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .performance
    @State private var metricsTimeline: BarberPerformanceTimeline = .daily
    @State private var bookings: [SimpleBookingDTO] = []
    @State private var clients: [BarberClient] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedClient: BarberClient?

    private var snapshot: BarberBusinessAnalyticsSnapshot {
        let scopedBookings = ProviderBarberBusinessAnalyticsEngine.bookings(
            in: metricsTimeline,
            from: bookings
        )
        return ProviderBarberBusinessAnalyticsEngine.buildSnapshot(
            bookings: scopedBookings,
            period: .all
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading analytics…")
                        .tint(.providerOlive)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    ContentUnavailableView(
                        "Couldn't load analytics",
                        systemImage: "chart.bar.xaxis",
                        description: Text(loadError)
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            sectionTabPicker

                            switch tab {
                            case .performance:
                                ProviderBusinessAnalyticsPerformanceView(
                                    bookings: bookings,
                                    snapshot: snapshot,
                                    metricsTimeline: $metricsTimeline
                                )
                            case .clients:
                                ProviderBusinessAnalyticsClientsView(clients: clients) { client in
                                    selectedClient = client
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
            .providerNavigationStackDestinationBackdrop()
            .navigationTitle("Business Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Business Analytics")
                        .font(.provider(.headline, weight: .semibold))
                }
            }
            .foregroundStyle(Color.lavaShellCream)
            .tint(.providerOlive)
            .providerLavaScreenChrome()
            .task { await load() }
            .refreshable { await load(forceRefresh: true) }
            .sheet(item: $selectedClient) { client in
                ProviderBusinessAnalyticsClientBookingsView(
                    client: client,
                    bookings: ProviderBarberBusinessAnalyticsEngine.bookings(
                        forClientId: client.id,
                        from: bookings
                    )
                )
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var sectionTabPicker: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                sectionTabButton(item)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analytics section")
    }

    private func sectionTabButton(_ item: Tab) -> some View {
        let isSelected = tab == item
        return Button {
            tab = item
        } label: {
            Text(item.rawValue)
                .font(.provider(.subheadline, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.lavaShellCream : Color.lavaShellCreamSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.providerOlive.opacity(0.55) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func load(forceRefresh: Bool = false) async {
        if !forceRefresh { isLoading = true }
        loadError = nil
        defer { isLoading = false }

        guard let barberId = session.barberProfile?.id else {
            loadError = "Complete barber onboarding to view analytics."
            return
        }

        do {
            async let dashboardTask = ProviderBarberAnalyticsService.loadDashboard(barberId: barberId)
            async let conversationsTask = ProviderBarberAnalyticsService.loadClients()

            let dashboard = try await dashboardTask
            let conversations = (try? await conversationsTask) ?? []

            bookings = dashboard.bookings
            var builtClients = ProviderBarberBusinessAnalyticsEngine.buildClients(from: dashboard.bookings)
            builtClients = ProviderBarberBusinessAnalyticsEngine.enrichClients(builtClients, conversations: conversations)
            clients = builtClients
        } catch {
            loadError = error.localizedDescription
        }
    }
}
