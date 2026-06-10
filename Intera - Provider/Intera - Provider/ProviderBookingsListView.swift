import SwiftUI

// MARK: - Request cancellation (SwiftUI `.task` / `refreshable` overlap)

private func providerBookingsListIsBenignCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
}

struct ProviderBookingsListView: View {
    @Environment(ProviderSession.self) private var session
    @State private var items: [SimpleBookingDTO] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if !session.hasProviderProfile {
                    ContentUnavailableView(
                        "No barber profile",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Complete your CampusCuts barber setup on the web, then pull to refresh on the Profile tab.")
                    )
                    .foregroundStyle(Color.lavaShellCream)
                } else if let errorText, items.isEmpty {
                    ContentUnavailableView("Couldn’t load", systemImage: "wifi.exclamationmark", description: Text(errorText))
                        .foregroundStyle(Color.lavaShellCream)
                } else if items.isEmpty, !isLoading {
                    ContentUnavailableView("No bookings", systemImage: "calendar", description: Text("New requests appear here."))
                        .foregroundStyle(Color.lavaShellCream)
                } else {
                    List {
                        ForEach(items) { booking in
                            NavigationLink(value: booking) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(booking.consumerDisplayName)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(Color.lavaShellCream)
                                    Text(booking.serviceDisplayName)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.lavaShellCreamSecondary)
                                    HStack {
                                        Text(booking.statusUpper)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.thinMaterial, in: Capsule())
                                        Spacer(minLength: 0)
                                        Text(booking.formattedSchedule())
                                            .font(.caption)
                                            .foregroundStyle(Color.lavaShellCreamSecondary)
                                    }
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .providerLavaIntegratedListRowBackground(horizontalInset: 12, verticalInset: 12)
                        }
                    }
                    .listRowSpacing(14)
                    .providerLavaIntegratedListSurface()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Bookings")
            .navigationDestination(for: SimpleBookingDTO.self) { booking in
                BookingDetailHost(booking: booking, onChanged: { await load(isUserPullToRefresh: false) })
            }
            .refreshable { await load(isUserPullToRefresh: true) }
            .overlay {
                if isLoading && items.isEmpty {
                    ProgressView()
                        .tint(.providerOlive)
                        .foregroundStyle(Color.lavaShellCream)
                }
            }
            .task(id: session.barberProfile?.id ?? "") {
                await load(isUserPullToRefresh: false)
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
    }

    private func load(isUserPullToRefresh: Bool) async {
        if !isUserPullToRefresh {
            isLoading = true
        }
        errorText = nil
        defer { isLoading = false }
        guard session.hasProviderProfile else {
            items = []
            return
        }
        do {
            items = try await ProviderBookingsService.listBookings(role: "barber")
        } catch {
            guard !providerBookingsListIsBenignCancellation(error) else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            items = []
        }
    }
}
