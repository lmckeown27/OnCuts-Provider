import SwiftUI

/// Header tray **Requests** inbox: pending booking requests plus the full bookings list (filters, reschedule requests, detail navigation).
struct ProviderRequestsInboxView: View {
    let presentationID: UUID
    @Binding var pendingBookingDetailId: String?

    init(
        presentationID: UUID = UUID(),
        pendingBookingDetailId: Binding<String?> = .constant(nil)
    ) {
        self.presentationID = presentationID
        _pendingBookingDetailId = pendingBookingDetailId
    }

    var body: some View {
        ProviderRequestsInboxContent(
            mode: .full,
            presentationID: presentationID,
            pendingBookingDetailId: $pendingBookingDetailId
        )
    }
}

/// Shared implementation for the unified inbox and the legacy requests-only surface.
struct ProviderRequestsInboxContent: View {
    enum Mode {
        case full
        case requestsOnly
    }

    let mode: Mode
    let presentationID: UUID
    @Binding var pendingBookingDetailId: String?

    init(
        mode: Mode,
        presentationID: UUID = UUID(),
        pendingBookingDetailId: Binding<String?> = .constant(nil)
    ) {
        self.mode = mode
        self.presentationID = presentationID
        _pendingBookingDetailId = pendingBookingDetailId
    }

    @Environment(ProviderSession.self) private var session

    @State private var detailPath = NavigationPath()

    // MARK: - Pending requests

    @State private var triageItems: [RequestTriageItem] = []
    @State private var isRequestsLoading = false
    @State private var requestsErrorText: String?
    @State private var rescheduleBooking: SimpleBookingDTO?
    @State private var expandedRequestId: String?
    @State private var isBookingRequestsExpanded = true

    @State private var acceptConfirmItem: RequestTriageItem?
    @State private var declineConfirmItem: RequestTriageItem?
    @State private var openingMessageRequestId: String?
    @State private var messageOpenErrorText: String?
    @State private var showMessageOpenError = false

    // MARK: - All bookings

    @State private var bookingItems: [SimpleBookingDTO] = []
    @State private var isBookingsLoading = false
    @State private var bookingsErrorText: String?
    @State private var hasLoadedBookings = false
    @State private var hasSettledInboxPresentation = false
    @State private var expandedFilters: Set<ProviderBookingStatusDisplay.Filter> = [.accepted]
    @State private var isRequestedChangesExpanded = true

    private static let bookingsContentWidthRatio: CGFloat = 0.75
    private static let bookingsPageLeadingInset: CGFloat = 16
    private static let bookingRequestsSectionTitle = "Booking Requests"

    var body: some View {
        NavigationStack(path: $detailPath) {
            inboxRoot
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .providerNavigationStackDestinationBackdrop()
                .providerPageNavigationTitle("Bookings")
                .navigationDestination(for: String.self) { bookingId in
                    // One destination type — branching ProgressView → detail inside
                    // `navigationDestination` often never re-evaluates after load (notification deep links).
                    ProviderBookingDetailDestination(
                        bookingId: bookingId,
                        knownBooking: bookingItems.first(where: { $0.id == bookingId }),
                        onResolved: { booking in
                            replaceBookingInItems(booking)
                        },
                        onChanged: {
                            await loadBookings(isUserPullToRefresh: false)
                        }
                    )
                }
        }
        .task(id: presentationID) {
            await loadInitialPresentation()
        }
        .onChange(of: session.barberProfile?.id) { _, newBarberId in
            guard hasSettledInboxPresentation, !(newBarberId ?? "").isEmpty else { return }
            Task {
                if mode == .requestsOnly {
                    await loadRequests(settlesPresentation: false)
                } else {
                    await loadAll(isUserPullToRefresh: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerBookingsChanged)) { _ in
            guard detailPath.isEmpty else { return }
            Task {
                await loadBookings(isUserPullToRefresh: false)
                await loadRequests(settlesPresentation: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerRequestsListShouldRefresh)) { _ in
            Task {
                await loadRequests(settlesPresentation: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProviderAwaitingPaymentTracker.didChangeNotification)) { _ in
            syncCompletedSectionExpansionForAwaitingPayment()
        }
        .onChange(of: pendingBookingDetailId) { _, bookingId in
            openPendingBookingDetailIfPossible(bookingId)
        }
        .onChange(of: bookingItems.count) { _, _ in
            openPendingBookingDetailIfPossible(pendingBookingDetailId)
        }
        .sheet(item: $acceptConfirmItem, onDismiss: { acceptConfirmItem = nil }) { item in
            ProviderApproveBookingConfirmSheet(
                customerName: item.confirmCustomerName,
                scheduleSummary: item.approveScheduleSummary,
                onApprove: {
                    acceptConfirmItem = nil
                    Task { await accept(item) }
                }
            )
        }
        .sheet(item: $declineConfirmItem, onDismiss: { declineConfirmItem = nil }) { item in
            ProviderSubmitDeclineConfirmSheet(
                customerName: item.confirmCustomerName,
                onSubmit: {
                    declineConfirmItem = nil
                    Task { await reject(item) }
                }
            )
        }
        .sheet(item: $rescheduleBooking, onDismiss: { rescheduleBooking = nil }) { booking in
            rescheduleSheet(for: booking)
        }
        .alert("Couldn’t open chat", isPresented: $showMessageOpenError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(messageOpenErrorText ?? "Try again in a moment.")
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
    }

    @ViewBuilder
    private var inboxRoot: some View {
        if !session.hasProviderProfile {
            pullToRefreshScroll {
                ContentUnavailableView(
                    "No barber profile",
                    systemImage: "tray",
                    description: Text("Complete provider onboarding in OnCuts Provider to see booking requests.")
                )
                .foregroundStyle(Color.lavaShellCream)
            }
        } else if mode == .requestsOnly {
            requestsOnlyBody
        } else if shouldGateInboxContent {
            Color.clear
                .overlay {
                    ProgressView()
                        .tint(.providerOlive)
                        .foregroundStyle(Color.lavaShellCream)
                }
        } else if showCombinedEmptyState {
            pullToRefreshScroll {
                ContentUnavailableView(
                    "No requests or bookings",
                    systemImage: "tray",
                    description: Text("Incoming requests and confirmed visits appear here.")
                )
                .foregroundStyle(Color.lavaShellCream)
            }
        } else {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 14) {
                        if !triageItems.isEmpty || requestsErrorText != nil {
                            bookingRequestsSection(containerWidth: geo.size.width)
                        }

                        if let bookingsErrorText, bookingItems.isEmpty, hasLoadedBookings {
                            bookingsErrorRow(text: bookingsErrorText, containerWidth: geo.size.width)
                        } else if !bookingItems.isEmpty {
                            ProviderBookingsDropdownListContent(
                                items: bookingItems.excludingOpenBookingRequests(triageItems: triageItems),
                                expandedFilters: $expandedFilters,
                                isRequestedChangesExpanded: $isRequestedChangesExpanded,
                                containerWidth: geo.size.width
                            )
                        } else if hasLoadedBookings, triageItems.isEmpty == false {
                            bookingsEmptyHintRow(containerWidth: geo.size.width)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                }
                .providerLavaIntegratedListSurface()
                .refreshable { await loadAll(isUserPullToRefresh: true) }
                .animation(ProviderRequestSheetMetrics.triageCardSpring, value: expandedRequestId)
                .animation(ProviderRequestSheetMetrics.triageCardSpring, value: isBookingRequestsExpanded)
                .animation(ProviderRequestSheetMetrics.triageCardSpring, value: expandedFilters)
                .animation(ProviderRequestSheetMetrics.triageCardSpring, value: isRequestedChangesExpanded)
            }
        }
    }

    @ViewBuilder
    private var requestsOnlyBody: some View {
        if let requestsErrorText, triageItems.isEmpty {
            pullToRefreshScroll {
                ContentUnavailableView("Couldn’t load", systemImage: "wifi.exclamationmark", description: Text(requestsErrorText))
                    .foregroundStyle(Color.lavaShellCream)
            }
        } else if triageItems.isEmpty, !isRequestsLoading {
            pullToRefreshScroll {
                ContentUnavailableView("No pending requests", systemImage: "tray", description: Text("You’re all caught up."))
                    .foregroundStyle(Color.lavaShellCream)
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(triageItems) { item in
                        requestTriageCard(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .animation(ProviderRequestSheetMetrics.triageCardSpring, value: expandedRequestId)
            .refreshable { await loadRequests(settlesPresentation: false) }
            .overlay {
                if isRequestsLoading && triageItems.isEmpty {
                    ProgressView()
                        .tint(.providerOlive)
                        .foregroundStyle(Color.lavaShellCream)
                }
            }
        }
    }

    private var shouldGateInboxContent: Bool {
        guard session.hasProviderProfile else { return false }
        return !hasSettledInboxPresentation
    }

    private var showCombinedEmptyState: Bool {
        hasLoadedBookings
            && !isRequestsLoading
            && triageItems.isEmpty
            && bookingItems.isEmpty
            && requestsErrorText == nil
            && bookingsErrorText == nil
    }

    @ViewBuilder
    private func bookingRequestsSection(containerWidth: CGFloat) -> some View {
        let dropdownWidth = containerWidth * Self.bookingsContentWidthRatio

        ProviderBookingsSectionDropdownHeader(
            title: Self.bookingRequestsSectionTitle,
            count: triageItems.count,
            isExpanded: isBookingRequestsExpanded
        ) {
            withAnimation(ProviderRequestSheetMetrics.triageCardSpring) {
                isBookingRequestsExpanded.toggle()
            }
        }
        .bookingsListCardRow(
            contentWidth: dropdownWidth,
            verticalInset: 8,
            leadingInset: Self.bookingsPageLeadingInset
        )

        VStack(spacing: 8) {
            if let requestsErrorText, triageItems.isEmpty {
                Text(requestsErrorText)
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .bookingsListCardRow(
                        contentWidth: nestedContentWidth(containerWidth: containerWidth),
                        verticalInset: 8,
                        leadingInset: Self.bookingsPageLeadingInset + ProviderBookingsDropdownListContent.nestedIndent
                    )
            } else {
                ForEach(triageItems) { item in
                    requestTriageCard(item)
                        .bookingsListCardRow(
                            contentWidth: nestedContentWidth(containerWidth: containerWidth),
                            verticalInset: 8,
                            leadingInset: Self.bookingsPageLeadingInset + ProviderBookingsDropdownListContent.nestedIndent,
                            showsBackground: false
                        )
                }
            }
        }
        .providerAnimatedCollapse(isExpanded: isBookingRequestsExpanded)
    }

    @ViewBuilder
    private func rescheduleSheet(for booking: SimpleBookingDTO) -> some View {
        if let barberId = session.barberProfile?.id {
            ProviderBookingRescheduleSheetView(
                booking: booking,
                barberId: barberId,
                onSave: { date in
                    rescheduleBooking = nil
                    Task { await performReschedule(booking: booking, to: date) }
                },
                onCancel: { rescheduleBooking = nil }
            )
            .providerLavaScreenChrome()
            .presentationDragIndicator(.visible)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "Can’t reschedule",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Complete barber onboarding to reschedule bookings.")
                )
                .providerPageNavigationTitle("Reschedule")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { rescheduleBooking = nil }
                    }
                }
            }
            .providerLavaScreenChrome()
        }
    }

    @ViewBuilder
    private func requestTriageCard(_ item: RequestTriageItem) -> some View {
        ProviderExpandableRequestTriageCard(
            item: item,
            isExpanded: expandedRequestId == item.id,
            onHeaderTap: { toggleExpansion(item.id) },
            onReschedule: { Task { await beginReschedule(for: item) } },
            onAccept: { acceptConfirmItem = item },
            onDecline: {
                declineConfirmItem = item
            },
            isOpeningMessage: openingMessageRequestId == item.id,
            onMessage: { Task { await openMessageThread(for: item) } }
        )
    }

    @ViewBuilder
    private func bookingsErrorRow(text: String, containerWidth: CGFloat) -> some View {
        Text(text)
            .font(.provider(.subheadline))
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .bookingsListCardRow(
                contentWidth: containerWidth * Self.bookingsContentWidthRatio,
                verticalInset: 12,
                leadingInset: Self.bookingsPageLeadingInset
            )
    }

    @ViewBuilder
    private func bookingsEmptyHintRow(containerWidth: CGFloat) -> some View {
        Text("No other bookings yet.")
            .font(.provider(.subheadline))
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .bookingsListCardRow(
                contentWidth: containerWidth * Self.bookingsContentWidthRatio,
                verticalInset: 12,
                leadingInset: Self.bookingsPageLeadingInset
            )
    }

    private func nestedContentWidth(containerWidth: CGFloat) -> CGFloat {
        let leading = Self.bookingsPageLeadingInset + ProviderBookingsDropdownListContent.nestedIndent
        let trailing = Self.bookingsPageLeadingInset
        return max(containerWidth - leading - trailing, 120)
    }

    private func pullToRefreshScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, minHeight: 280)
        }
        .refreshable { await loadAll(isUserPullToRefresh: true) }
    }

    private func openPendingBookingDetailIfPossible(_ bookingId: String?) {
        guard let bookingId, !bookingId.isEmpty else { return }
        // Push immediately — destination resolves the booking (list may still be loading).
        detailPath = NavigationPath()
        detailPath.append(bookingId)
        pendingBookingDetailId = nil
    }

    private func syncCompletedSectionExpansionForAwaitingPayment() {
        guard bookingItems.contains(where: \.isCompletedAwaitingConsumerPayment) else { return }
        if !expandedFilters.contains(.completed) {
            expandedFilters.insert(.completed)
        }
    }

    // MARK: - Request interactions

    private func toggleExpansion(_ id: String) {
        withAnimation(ProviderRequestSheetMetrics.triageCardSpring) {
            expandedRequestId = expandedRequestId == id ? nil : id
        }
    }

    @MainActor
    private func beginReschedule(for item: RequestTriageItem) async {
        if let booking = bookingItems.first(where: { $0.id == item.row.bookingId }) {
            rescheduleBooking = booking
            return
        }
        do {
            let booking = try await ProviderBookingsService.fetchBooking(id: item.row.bookingId)
            rescheduleBooking = booking
        } catch {
            requestsErrorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func performReschedule(booking: SimpleBookingDTO, to date: Date) async {
        let keepExpanded = triageItems.first(where: { $0.row.bookingId == booking.id })?.id
        do {
            try await ProviderBookingsService.reschedule(
                id: booking.id,
                scheduledTimeISO: date.campusCutsISO8601String(),
                location: booking.location,
                notes: booking.notes
            )

            let refreshed = (try? await ProviderBookingsService.fetchBooking(id: booking.id))
                ?? booking.updatingScheduledTime(date, clearPendingReschedule: true)
            let merged = mergeRescheduledBooking(refreshed, rescheduledTo: date)
            replaceBookingInItems(merged)

            NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
            NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
            NotificationCenter.default.post(name: .providerBookingsListShouldRefresh, object: nil)

            guard let bid = session.barberProfile?.id else { return }
            triageItems = try await ProviderBookingRequestsService.loadTriageQueue(
                barberTableId: bid,
                bookingsHint: bookingItems
            )
            await loadBookings(isUserPullToRefresh: false)

            if let keepExpanded {
                expandedRequestId = keepExpanded
            }
        } catch {
            requestsErrorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    /// After a barber reschedule on a pending inquiry, the provider's slot overrides any consumer counter-request.
    private func mergeRescheduledBooking(_ booking: SimpleBookingDTO, rescheduledTo: Date) -> SimpleBookingDTO {
        guard booking.statusUpper == "PENDING" else { return booking }
        let scheduled = booking.scheduledTime ?? rescheduledTo
        return booking.updatingScheduledTime(scheduled, clearPendingReschedule: true)
    }

    private func replaceBookingInItems(_ booking: SimpleBookingDTO) {
        if let index = bookingItems.firstIndex(where: { $0.id == booking.id }) {
            bookingItems[index] = booking
        } else {
            bookingItems.append(booking)
        }
    }

    // MARK: - Networking

    private func loadInitialPresentation() async {
        if mode == .requestsOnly {
            await loadRequests(settlesPresentation: true)
        } else {
            await loadAll(isUserPullToRefresh: false)
        }
    }

    private func loadAll(isUserPullToRefresh: Bool) async {
        // Do not flip the gate back to loading on every refresh — remount / notification races
        // were leaving the inbox stuck on the full-screen ProgressView.
        defer {
            if !isUserPullToRefresh {
                hasSettledInboxPresentation = true
            }
        }

        async let bookings: Void = loadBookings(isUserPullToRefresh: isUserPullToRefresh)
        async let freeSlots: Void = refreshCommissionFreeRemaining()
        _ = await (bookings, freeSlots)
        await loadRequests(settlesPresentation: false)
    }

    private func refreshCommissionFreeRemaining() async {
        guard session.hasProviderProfile,
              let userId = session.authUser?.id.trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty else {
            session.setCommissionFreeBookingsRemaining(0)
            return
        }
        do {
            let remaining = try await ProviderBarberServicesService.fetchCommissionFreeBookingsRemaining(
                userId: userId
            )
            try Task.checkCancellation()
            session.setCommissionFreeBookingsRemaining(remaining)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard !providerAllBookingsIsBenignCancellation(error) else { return }
        }
    }

    private func loadRequests(settlesPresentation: Bool) async {
        if settlesPresentation {
            hasSettledInboxPresentation = false
        }
        defer {
            if settlesPresentation {
                hasSettledInboxPresentation = true
            }
        }

        guard let bid = session.barberProfile?.id else {
            triageItems = []
            expandedRequestId = nil
            return
        }
        isRequestsLoading = true
        requestsErrorText = nil
        defer { isRequestsLoading = false }
        do {
            triageItems = try await ProviderBookingRequestsService.loadTriageQueue(
                barberTableId: bid,
                bookingsHint: hasLoadedBookings ? bookingItems : nil
            )
            if let id = expandedRequestId, !triageItems.contains(where: { $0.id == id }) {
                expandedRequestId = nil
            }
        } catch {
            guard !providerAllBookingsIsBenignCancellation(error) else { return }
            requestsErrorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            triageItems = []
        }
    }

    private func loadBookings(isUserPullToRefresh: Bool) async {
        if !isUserPullToRefresh {
            isBookingsLoading = true
        }
        bookingsErrorText = nil
        defer {
            isBookingsLoading = false
            hasLoadedBookings = true
        }
        guard session.hasProviderProfile else {
            bookingItems = []
            return
        }
        do {
            bookingItems = try await ProviderBookingsService.listBookings(role: "barber")
            ProviderAwaitingPaymentTracker.shared.reconcile(with: bookingItems)
            syncCompletedSectionExpansionForAwaitingPayment()
        } catch {
            guard !providerAllBookingsIsBenignCancellation(error) else { return }
            bookingsErrorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            bookingItems = []
        }
    }

    private func accept(_ item: RequestTriageItem) async {
        guard let bid = session.barberProfile?.id else { return }
        isRequestsLoading = true
        defer { isRequestsLoading = false }
        do {
            try await ProviderBookingRequestsService.acceptApplyingConsumerSchedule(
                bookingId: item.row.bookingId,
                barberTableId: bid,
                booking: bookingItems.first(where: { $0.id == item.row.bookingId }),
                message: "Looking forward to seeing you!"
            )
            NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
            NotificationCenter.default.post(name: .providerBookingsListShouldRefresh, object: nil)
            await loadAll(isUserPullToRefresh: false)
        } catch {
            requestsErrorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func openMessageThread(for item: RequestTriageItem) async {
        openingMessageRequestId = item.id
        defer { openingMessageRequestId = nil }

        do {
            let linkedBooking = bookingItems.first(where: { $0.id == item.row.bookingId })
            guard let conversationId = try await ProviderMessagesService.resolveOrStartConversation(
                bookingId: item.row.bookingId,
                booking: linkedBooking,
                request: item.row
            ) else {
                messageOpenErrorText = "No conversation is linked to this booking yet."
                showMessageOpenError = true
                return
            }
            NotificationCenter.default.post(
                name: .onCutsOpenMessagingConversation,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        } catch {
            messageOpenErrorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showMessageOpenError = true
        }
    }

    private func reject(_ item: RequestTriageItem) async {
        guard let bid = session.barberProfile?.id else { return }
        isRequestsLoading = true
        defer { isRequestsLoading = false }
        do {
            try await ProviderBookingRequestsService.reject(
                bookingId: item.row.bookingId,
                barberTableId: bid
            )
            NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
            await loadRequests(settlesPresentation: false)
        } catch {
            requestsErrorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}

/// Resolves a booking for Bookings deep links without relying on `navigationDestination`
/// to swap ProgressView → detail after parent `bookingItems` updates.
private struct ProviderBookingDetailDestination: View {
    let bookingId: String
    let knownBooking: SimpleBookingDTO?
    let onResolved: (SimpleBookingDTO) -> Void
    let onChanged: () async -> Void

    @State private var booking: SimpleBookingDTO?
    @State private var errorText: String?

    private var resolvedBooking: SimpleBookingDTO? {
        booking ?? knownBooking
    }

    var body: some View {
        Group {
            if let resolvedBooking {
                BookingDetailScreen(
                    booking: resolvedBooking,
                    showsStackBackButton: true,
                    onChanged: onChanged
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: ProviderAppearance.shellBase))
            } else if let errorText {
                ContentUnavailableView(
                    "Couldn't open booking",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(errorText)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: ProviderAppearance.shellBase))
            } else {
                ProgressView()
                    .tint(.providerOlive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: ProviderAppearance.shellBase))
            }
        }
        .task(id: bookingId) {
            await resolveBooking()
        }
    }

    private func resolveBooking() async {
        if let knownBooking {
            booking = knownBooking
            onResolved(knownBooking)
            return
        }

        do {
            let fetched = try await ProviderBookingsService.fetchBooking(id: bookingId)
            booking = fetched
            onResolved(fetched)
        } catch {
            if providerAllBookingsIsBenignCancellation(error) { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
