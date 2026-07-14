import SwiftUI

/// Barber-facing **Business Analytics**: Performance metrics + Clients directory.
/// Standalone sheet or nested inside Payout Settings (`embedsOwnNavigationStack: false`).
struct ProviderBusinessAnalyticsView: View {
    /// When `false`, content is hosted in a parent `NavigationStack` (Payout Settings nesting).
    var embedsOwnNavigationStack: Bool = true

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

    @Environment(\.colorScheme) private var colorScheme

    /// Timeline-scoped summary (Volume / Bookings / Clients) for the chart window.
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

    /// All-time Card vs Cash — parity with Admin Performance (`status IN COMPLETED/PAID`).
    private var paymentMethodsSnapshot: BarberBusinessAnalyticsSnapshot {
        ProviderBarberBusinessAnalyticsEngine.buildSnapshot(
            bookings: ProviderBarberBusinessAnalyticsEngine.paidBookings(from: bookings),
            period: .all
        )
    }

    var body: some View {
        Group {
            if embedsOwnNavigationStack {
                NavigationStack {
                    analyticsRoot
                }
            } else {
                analyticsRoot
            }
        }
    }

    private var analyticsRoot: some View {
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
                                paymentMethodsSnapshot: paymentMethodsSnapshot,
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
            if embedsOwnNavigationStack {
                ToolbarItem(placement: .principal) {
                    Text("Business Analytics")
                        .font(.provider(.headline, weight: .semibold))
                }
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

    private var sectionTabPicker: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                sectionTabButton(item)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ProviderOliveChromeStyle.adminTabTrackFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ProviderOliveChromeStyle.adminTabTrackStroke(colorScheme), lineWidth: 0.6)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analytics section")
    }

    private func sectionTabButton(_ item: Tab) -> some View {
        let isSelected = tab == item
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                tab = item
            }
        } label: {
            Text(item.rawValue)
                .font(.provider(.subheadline, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(
                    isSelected
                        ? ProviderOliveChromeStyle.adminTabActiveForeground(colorScheme)
                        : ProviderOliveChromeStyle.adminTabInactiveForeground(colorScheme)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ProviderOliveChromeStyle.adminTabActiveFill(colorScheme))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
