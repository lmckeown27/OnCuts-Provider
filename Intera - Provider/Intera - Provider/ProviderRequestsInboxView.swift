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
    @State private var editingRequestId: String?
    @State private var draftScheduleDate = Date()
    @State private var draftHasConflict = false
    @State private var scheduleEditError: String?
    @State private var isSavingSchedule = false
    @State private var expandedRequestId: String?
    @State private var isBookingRequestsExpanded = true

    @State private var acceptConfirmItem: RequestTriageItem?
    @State private var declineReasonPickerItem: RequestTriageItem?
    @State private var selectedDeclineReason: ProviderDeclineReason?
    @State private var declineOtherReasonText = ""
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
                .navigationTitle("Bookings")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { bookingId in
                    bookingDetailDestination(bookingId: bookingId)
                }
        }
        .task(id: presentationID) {
            if mode == .requestsOnly {
                await loadRequests(settlesPresentation: true)
            } else {
                await loadAll(isUserPullToRefresh: false)
            }
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
            Task { await loadBookings(isUserPullToRefresh: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerRequestsListShouldRefresh)) { _ in
            Task {
                await loadRequests(settlesPresentation: false)
            }
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
        .sheet(item: $declineReasonPickerItem, onDismiss: {
            declineReasonPickerItem = nil
            selectedDeclineReason = nil
            declineOtherReasonText = ""
        }) { item in
            ProviderDeclineReasonPickerSheet(
                selectedReason: $selectedDeclineReason,
                otherReasonText: $declineOtherReasonText,
                onDecline: {
                    declineReasonPickerItem = nil
                    Task {
                        await reject(item)
                        selectedDeclineReason = nil
                        declineOtherReasonText = ""
                    }
                }
            )
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
                    description: Text("Complete barber onboarding on CampusCuts to see booking requests.")
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
                .animation(ProviderRequestSheetMetrics.triageCardSpring, value: editingRequestId)
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
            .animation(ProviderRequestSheetMetrics.triageCardSpring, value: editingRequestId)
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
                    .font(.caption)
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
    private func requestTriageCard(_ item: RequestTriageItem) -> some View {
        ProviderExpandableRequestTriageCard(
            item: item,
            isExpanded: expandedRequestId == item.id,
            isEditingSchedule: editingRequestId == item.id,
            draftScheduleDate: $draftScheduleDate,
            draftHasConflict: $draftHasConflict,
            barberId: session.barberProfile?.id,
            scheduleEditError: editingRequestId == item.id ? scheduleEditError : nil,
            isSavingSchedule: isSavingSchedule && editingRequestId == item.id,
            onHeaderTap: { toggleExpansion(item.id) },
            onBeginEditSchedule: { beginEditingSchedule(item) },
            onCancelEditSchedule: { cancelEditingSchedule() },
            onSaveSchedule: { Task { await saveScheduleEdit(item) } },
            onAccept: { acceptConfirmItem = item },
            onDecline: {
                selectedDeclineReason = nil
                declineOtherReasonText = ""
                declineReasonPickerItem = item
            },
            isOpeningMessage: openingMessageRequestId == item.id,
            onMessage: { Task { await openMessageThread(for: item) } }
        )
    }

    @ViewBuilder
    private func bookingsErrorRow(text: String, containerWidth: CGFloat) -> some View {
        Text(text)
            .font(.subheadline)
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
            .font(.subheadline)
            .foregroundStyle(Color.lavaShellCreamSecondary)
            .bookingsListCardRow(
                contentWidth: containerWidth * Self.bookingsContentWidthRatio,
                verticalInset: 12,
                leadingInset: Self.bookingsPageLeadingInset
            )
    }

    @ViewBuilder
    private func bookingDetailDestination(bookingId: String) -> some View {
        if let booking = bookingItems.first(where: { $0.id == bookingId }) {
            BookingDetailHost(booking: booking) {
                await loadBookings(isUserPullToRefresh: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: ProviderAppearance.shellBase))
        } else {
            ProgressView()
                .tint(.providerOlive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: ProviderAppearance.shellBase))
                .task { await loadBookings(isUserPullToRefresh: false) }
        }
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
        guard bookingItems.contains(where: { $0.id == bookingId }) else { return }
        detailPath = NavigationPath()
        detailPath.append(bookingId)
        pendingBookingDetailId = nil
    }

    // MARK: - Request interactions

    private func toggleExpansion(_ id: String) {
        withAnimation(ProviderRequestSheetMetrics.triageCardSpring) {
            if expandedRequestId == id {
                expandedRequestId = nil
                if editingRequestId == id {
                    editingRequestId = nil
                    scheduleEditError = nil
                }
            } else {
                expandedRequestId = id
                if editingRequestId != nil, editingRequestId != id {
                    editingRequestId = nil
                    scheduleEditError = nil
                }
            }
        }
    }

    private func beginEditingSchedule(_ item: RequestTriageItem) {
        withAnimation(ProviderRequestSheetMetrics.triageCardSpring) {
            expandedRequestId = item.id
            editingRequestId = item.id
            draftScheduleDate = item.requestedStart
            draftHasConflict = false
            scheduleEditError = nil
        }
    }

    private func cancelEditingSchedule() {
        withAnimation(ProviderRequestSheetMetrics.triageCardSpring) {
            editingRequestId = nil
            scheduleEditError = nil
        }
    }

    // MARK: - Networking

    private func loadAll(isUserPullToRefresh: Bool) async {
        if !isUserPullToRefresh {
            hasSettledInboxPresentation = false
        }
        defer {
            if !isUserPullToRefresh {
                hasSettledInboxPresentation = true
            }
        }

        async let requests: Void = loadRequests(settlesPresentation: false)
        async let bookings: Void = loadBookings(isUserPullToRefresh: isUserPullToRefresh)
        _ = await (requests, bookings)
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
            triageItems = try await ProviderBookingRequestsService.loadTriageQueue(barberTableId: bid)
            if let id = expandedRequestId, !triageItems.contains(where: { $0.id == id }) {
                expandedRequestId = nil
                editingRequestId = nil
            }
        } catch {
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
            try await ProviderBookingRequestsService.accept(
                bookingId: item.row.bookingId,
                barberTableId: bid,
                message: "Looking forward to seeing you!"
            )
            NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
            NotificationCenter.default.post(name: .providerBookingsListShouldRefresh, object: nil)
            await loadAll(isUserPullToRefresh: false)
        } catch {
            requestsErrorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func saveScheduleEdit(_ item: RequestTriageItem) async {
        guard editingRequestId == item.id else { return }
        isSavingSchedule = true
        scheduleEditError = nil
        defer { isSavingSchedule = false }
        let keepExpanded = item.id
        do {
            try await ProviderBookingsService.reschedule(
                id: item.row.bookingId,
                scheduledTimeISO: draftScheduleDate.campusCutsISO8601String(),
                location: item.row.location,
                notes: nil
            )
            NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
            NotificationCenter.default.post(name: .providerBookingsListShouldRefresh, object: nil)
            editingRequestId = nil
            await loadRequests(settlesPresentation: false)
            expandedRequestId = keepExpanded
        } catch {
            scheduleEditError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func openMessageThread(for item: RequestTriageItem) async {
        openingMessageRequestId = item.id
        defer { openingMessageRequestId = nil }

        do {
            guard let conversationId = try await ProviderMessagesService.conversationId(
                forBookingId: item.row.bookingId
            ) else {
                messageOpenErrorText = "No conversation is linked to this booking yet."
                showMessageOpenError = true
                return
            }
            NotificationCenter.default.post(
                name: .interaOpenMessagingConversation,
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
        guard let selectedDeclineReason,
              let reasonText = selectedDeclineReason.apiReason(customOtherText: declineOtherReasonText)
        else { return }
        isRequestsLoading = true
        defer { isRequestsLoading = false }
        do {
            try await ProviderBookingRequestsService.reject(
                bookingId: item.row.bookingId,
                barberTableId: bid,
                reason: reasonText
            )
            NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
            await loadRequests(settlesPresentation: false)
        } catch {
            requestsErrorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}
