import SwiftUI

/// Barber-facing **Business Analytics** sheet: Performance metrics + Clients directory.
struct ProviderBusinessAnalyticsView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable, Identifiable {
        case performance = "Performance"
        case clients = "Clients"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .performance
    @State private var selectedPeriod: BarberAnalyticsPeriod = .fourWeeks
    @State private var bookings: [SimpleBookingDTO] = []
    @State private var clients: [BarberClient] = []
    @State private var connectStatus: BarberConnectStatusDTO?
    @State private var connectStatusUnknown = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingStripeHub = false
    @State private var selectedClient: BarberClient?

    private var snapshot: BarberBusinessAnalyticsSnapshot {
        ProviderBarberBusinessAnalyticsEngine.buildSnapshot(
            bookings: bookings,
            period: selectedPeriod
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
                            Picker("Section", selection: $tab) {
                                ForEach(Tab.allCases) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            switch tab {
                            case .performance:
                                ProviderBusinessAnalyticsPerformanceView(
                                    snapshot: snapshot,
                                    selectedPeriod: $selectedPeriod,
                                    onOpenStripeHub: { showingStripeHub = true }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .foregroundStyle(Color.lavaShellCream)
            .tint(.providerOlive)
            .providerLavaScreenChrome()
            .task { await load() }
            .refreshable { await load(forceRefresh: true) }
            .sheet(isPresented: $showingStripeHub) {
                NavigationStack {
                    ProviderStripeExpressHubView(
                        connectStatus: connectStatus,
                        connectStatusUnknown: connectStatusUnknown,
                        onRefresh: { await reloadConnectStatus() }
                    )
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedClient) { client in
                NavigationStack {
                    clientDetailSheet(client)
                        .navigationTitle(client.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { selectedClient = nil }
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func clientDetailSheet(_ client: BarberClient) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    if let url = client.profileImageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Circle().fill(Color.providerOlive.opacity(0.25))
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(client.name)
                            .font(.provider(.title3, weight: .bold))
                        if let email = client.email {
                            Text(email)
                                .font(.provider(.caption))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                        }
                    }
                }

                ProviderAnalyticsSectionCard(title: "Client metrics", subtitle: nil) {
                    VStack(spacing: 10) {
                        metricLine("Bookings", value: "\(client.bookingCount)")
                        metricLine("Lifetime volume", value: ProviderAnalyticsFormatting.currency(cents: client.lifetimeVolumeCents))
                        metricLine("Last booking", value: client.formattedLastBooking)
                    }
                }
            }
            .padding(16)
        }
        .providerNavigationStackDestinationBackdrop()
        .foregroundStyle(Color.lavaShellCream)
        .providerLavaScreenChrome()
    }

    private func metricLine(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.provider(.caption))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.provider(.subheadline, weight: .bold))
                .providerAnalyticsMonospacedValue()
        }
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
            async let connectTask: Void = reloadConnectStatus()

            let dashboard = try await dashboardTask
            let conversations = (try? await conversationsTask) ?? []
            _ = await connectTask

            bookings = dashboard.bookings
            var builtClients = ProviderBarberBusinessAnalyticsEngine.buildClients(from: dashboard.bookings)
            builtClients = ProviderBarberBusinessAnalyticsEngine.enrichClients(builtClients, conversations: conversations)
            clients = builtClients
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func reloadConnectStatus() async {
        do {
            connectStatus = try await ProviderBarberPayoutService.fetchConnectStatus()
            connectStatusUnknown = false
        } catch {
            connectStatus = nil
            connectStatusUnknown = true
        }
    }
}
