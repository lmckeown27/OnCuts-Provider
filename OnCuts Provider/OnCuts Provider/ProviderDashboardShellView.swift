import SwiftUI
#if os(iOS)
import UIKit
import UserNotifications
#endif

/// Signed-in **service provider** shell modeled on web `BarberPage`: header (Chats · brand · Inbox · Profile) + schedule hub.
struct ProviderDashboardShellView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(ProviderShellNavigationAppearance.self) private var shellNavigationAppearance
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigator = ProviderShellNavigator()
    @State private var stripeOnboardingGate = ProviderStripeOnboardingGate()
    @State private var showingRequestsInbox = false
    @State private var showingBusinessAnalytics = false
    @State private var bookingsInboxPresentationID = UUID()
    @State private var pendingInboxBookingDetailId: String?
    /// Number of *conversations* that have ≥ 1 unread inbound message — not the running total of
    /// unread messages across the inbox. A single thread with five fresh messages still
    /// contributes `+1` to this count, matching the "Chats" pill behavior in the web dashboard.
    @State private var unreadConversationCount = 0
    @State private var pendingRequestCount = 0
    @State private var pendingRescheduleRequestCount = 0
    @State private var hasAwaitingPaymentAttention = false
    @State private var showLocationDeniedGuidance = false

    private var bookingsTrayAttentionCount: Int {
        pendingRequestCount + pendingRescheduleRequestCount
    }

    /// Present only after a background status check confirms Connect is incomplete.
    private var showsPaymentsOnboardingGate: Bool {
        session.hasProviderProfile && stripeOnboardingGate.shouldPresentGuide
    }

    var body: some View {
        shellWithNotificationRouting
    }

    private var shellWithNotificationRouting: some View {
        shellWithLifecycle
            .onReceive(NotificationCenter.default.publisher(for: .onCutsOpenMessagingConversation)) { notification in
                showingRequestsInbox = false
                let conversationId = Self.conversationId(from: notification.userInfo)
                navigator.openMessages(conversationId: conversationId)
                Task { await refreshHeaderCounts() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .providerMessagingUnreadCountShouldRefresh)) { _ in
                Task { await refreshHeaderCounts() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .providerBookingsChanged)) { _ in
                Task { await refreshHeaderCounts() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .providerBookingsListShouldRefresh)) { _ in
                Task { await refreshHeaderCounts() }
                NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .providerRequestsListShouldRefresh)) { _ in
                Task { await refreshHeaderCounts() }
                NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .onCutsOpenRequestsInbox)) { _ in
                navigator.popToHub()
                presentBookingsInbox()
                Task { await refreshHeaderCounts() }
            }
            .onReceive(NotificationCenter.default.publisher(for: ProviderAwaitingPaymentTracker.didChangeNotification)) { _ in
                Task { await refreshHeaderCounts() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .onCutsOpenBookingDetail)) { notification in
                navigator.popToHub()
                pendingInboxBookingDetailId = Self.bookingId(from: notification.userInfo)
                presentBookingsInbox()
                Task { await refreshHeaderCounts() }
                NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
            }
    }

    private var shellWithLifecycle: some View {
        shellWithPresentations
            .onAppear {
                if navigator.isHub {
                    shellNavigationAppearance.clearContainerBackdropImmediately()
                }
            }
            .onChange(of: navigator.isHub) { _, isHub in
                if isHub {
                    shellNavigationAppearance.clearContainerBackdropImmediately()
                    Task { await refreshHeaderCounts() }
                }
            }
            .onChange(of: navigator.stack.count) { _, count in
                handleNavigatorStackCountChange(count)
            }
            .task {
                await bootstrapShell()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, session.hasProviderProfile else { return }
                Task { await stripeOnboardingGate.refresh() }
            }
            .onChange(of: session.hasProviderProfile) { _, hasProfile in
                guard hasProfile else { return }
                Task { await stripeOnboardingGate.refresh() }
            }
    }

    private var shellWithPresentations: some View {
        shellChromeRoot
            .sheet(isPresented: $showingRequestsInbox, onDismiss: {
                pendingInboxBookingDetailId = nil
                Task { await refreshHeaderCounts() }
            }) {
                requestsInboxSheet
            }
            .sheet(isPresented: $showingBusinessAnalytics) {
                ProviderBusinessAnalyticsView()
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: Binding(
                get: { showsPaymentsOnboardingGate },
                set: { _ in
                    // Dismiss only when Connect flags pass (`shouldPresentGuide` becomes false).
                }
            )) {
                ProviderPaymentsOnboardingGuideView(
                    blocking: true,
                    gate: stripeOnboardingGate
                )
            }
            .alert("Location access is off", isPresented: $showLocationDeniedGuidance) {
                locationDeniedAlertActions
            } message: {
                Text("Your location access is turned off. If you wish, go to settings to turn on location access")
            }
    }

    private var shellChromeRoot: some View {
        shellRootLayout
            .foregroundStyle(Color.lavaShellCream)
            .tint(.providerOlive)
            .providerLavaToolbarChrome()
            .environment(navigator)
            .optionalProviderShellNavigatorEnvironment(navigator)
            #if os(iOS)
            .environment(ProviderShellNavigationPopBridge.shared)
            #endif
    }

    private var shellRootLayout: some View {
        GeometryReader { geometry in
            ZStack {
                hubContent
                overlayNavigation(containerWidth: geometry.size.width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var hubContent: some View {
        VStack(spacing: 0) {
            dashboardHeaderBar
            ProviderScheduleDashboardView()
                .providerHubScheduleChrome()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background {
            Color(uiColor: ProviderAppearance.shellBase)
                .ignoresSafeArea()
        }
        .allowsHitTesting(navigator.hubAcceptsTouches)
    }

    @ViewBuilder
    private func overlayNavigation(containerWidth: CGFloat) -> some View {
        if let overlayScreen = navigator.overlayScreen {
            NavigationStack {
                pushedScreenView(overlayScreen)
                    .providerShellNavigationDepthTracking()
            }
            .id(overlayScreen.overlayIdentity)
            .optionalProviderShellNavigatorEnvironment(navigator)
            .providerShellNavigationContainerChrome(
                backdrop: shellNavigationAppearance.navigationContainerBackdropStyle
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: navigator.slideOffsetX(containerWidth: containerWidth))
            .allowsHitTesting(!navigator.isDismissingOverlay || navigator.slideProgress > 0.05)
            .providerShellInteractiveSlide(containerWidth: containerWidth)
        }
    }

    private var requestsInboxSheet: some View {
        ProviderRequestsInboxView(
            presentationID: bookingsInboxPresentationID,
            pendingBookingDetailId: $pendingInboxBookingDetailId
        )
        .id(bookingsInboxPresentationID)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { showingRequestsInbox = false }
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var locationDeniedAlertActions: some View {
        #if os(iOS)
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        #endif
        Button("Not Now", role: .cancel) {}
    }

    private func handleNavigatorStackCountChange(_ count: Int) {
        #if os(iOS)
        if count == 0 {
            ProviderShellNavigationPopBridge.shared.resetHostNavigation()
            ProviderShellNavigationPopBridge.shared.clearEmbeddedNavigation()
        } else if let last = navigator.stack.last, case .route(.messages) = last {
            // Conversation detail depth is tracked via `messagesDetailPath`.
        } else {
            ProviderShellNavigationPopBridge.shared.clearEmbeddedNavigation()
            ProviderShellNavigationPopBridge.shared.resetHostDestinations()
        }
        ProviderNavigationChromeBridge.applySynchronouslyFromKeyWindow()
        #endif
    }

    private func bootstrapShell() async {
        ProviderLocationPermissionBroker.shared.requestWhenInUseIfNeeded {
            showLocationDeniedGuidance = true
        }
        await refreshHeaderCounts()
        // Background Connect check — guide presents only if status comes back incomplete.
        if session.hasProviderProfile {
            await stripeOnboardingGate.refresh()
            await syncDiscoveryLocationIfNeeded()
        }
    }

    /// When manual location is off, keep the public discovery pin fresh from this device.
    private func syncDiscoveryLocationIfNeeded() async {
        do {
            let pin = try await ProviderBarberServiceLocationService.fetch()
            guard !pin.serviceLocationWebOnly else { return }
            _ = try await ProviderServiceLocationSync.syncDeviceLocation()
            NotificationCenter.default.post(name: .providerDiscoveryLocationChanged, object: nil)
        } catch {
            // Non-fatal — account settings surface errors if the operator updates manually.
        }
    }

    /// Fixed header when on the schedule root. Avoids an **empty** `ToolbarItem` set while pushed (which can leave the nav bar broken after pop).
    private var dashboardHeaderBar: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                navigator.pushRoute(ProviderShellRoute.messages)
            } label: {
                HStack(spacing: 6) {
                    NavigationChatsIcon(
                        unreadCount: unreadConversationCount,
                        tint: ProviderOliveChromeStyle.headerIconTint(colorScheme)
                    )
                        .frame(width: 18, height: 18)
                    Text("Chats")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ProviderOliveChromeStyle.headerPillFill(colorScheme), in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if unreadConversationCount > 0 {
                        Text(unreadConversationCount > 99 ? "99+" : "\(unreadConversationCount)")
                            .font(.provider(.caption2, weight: .bold))
                            .padding(4)
                            .background(Color.red.opacity(0.92), in: Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ProviderOliveChromeStyle.headerPillForeground(colorScheme))

            Spacer(minLength: 8)

            if let roleLabel = headerRoleStatusText {
                Button {
                    navigator.pushRoute(ProviderShellRoute.adminDashboard)
                } label: {
                    Text(roleLabel)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ProviderOliveChromeStyle.headerPillFill(colorScheme), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(ProviderOliveChromeStyle.headerPillBorder(colorScheme), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(ProviderOliveChromeStyle.headerPillForeground(colorScheme))
                .accessibilityLabel("Admin dashboard")
            }

            Spacer(minLength: 8)

            HStack(spacing: 22) {
                requestsTrayButton
                profileMenuButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: [])
    }

    /// Shown in the center of the header when the signed-in user has admin privileges.
    private var headerRoleStatusText: String? {
        session.authUser?.hasAdminPrivileges == true ? "Admin" : nil
    }

    private var requestsTrayButton: some View {
        Button(action: presentBookingsInbox) {
            NavigationInboxIcon(
                unreadCount: bookingsTrayAttentionCount,
                tint: ProviderOliveChromeStyle.headerIconTint(colorScheme)
            )
                .frame(width: 22, height: 22)
                .frame(width: 36, height: 36)
                .background(ProviderOliveChromeStyle.headerPillFill(colorScheme), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(ProviderOliveChromeStyle.headerPillBorder(colorScheme), lineWidth: 0.8)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if bookingsTrayAttentionCount > 0 {
                    requestsPendingCountBadge(bookingsTrayAttentionCount)
                        .offset(x: hasAwaitingPaymentAttention ? -10 : 5, y: -5)
                }
                if hasAwaitingPaymentAttention {
                    awaitingPaymentWarningBadge
                        .offset(x: 5, y: -5)
                }
            }
        }
        .accessibilityLabel(bookingsTrayAccessibilityLabel)
    }

    private var bookingsTrayAccessibilityLabel: String {
        var parts: [String] = ["Bookings"]
        if pendingRequestCount > 0 {
            parts.append("\(pendingRequestCount) pending request\(pendingRequestCount == 1 ? "" : "s")")
        }
        if pendingRescheduleRequestCount > 0 {
            parts.append("\(pendingRescheduleRequestCount) schedule change request\(pendingRescheduleRequestCount == 1 ? "" : "s")")
        }
        if hasAwaitingPaymentAttention {
            parts.append("awaiting payment")
        }
        guard parts.count > 1 else { return parts[0] }
        return parts[0] + ", " + parts.dropFirst().joined(separator: ", ")
    }

    /// Yellow warning ticker for completed bookings awaiting consumer payment.
    private var awaitingPaymentWarningBadge: some View {
        Text("!")
            .font(.provider(size: 12, weight: .black))
            .foregroundStyle(Color(white: 0.1))
            .frame(width: 18, height: 18)
            .background(Color(uiColor: ProviderChatDesignTokens.Color.statusYellow), in: Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.lavaShellCream.opacity(0.85), lineWidth: 1.5)
            )
            .accessibilityLabel("Awaiting payment")
    }

    /// Circular ticker for pending booking requests on the header tray control.
    @ViewBuilder
    private func requestsPendingCountBadge(_ count: Int) -> some View {
        let label = count > 99 ? "99+" : "\(count)"
        let text = Text(label)
            .font(.provider(size: 11, weight: .bold))
            .foregroundStyle(.white)

        if count > 9 {
            text
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.92), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.lavaShellCream.opacity(0.85), lineWidth: 1.5)
                )
        } else {
            text
                .frame(minWidth: 18, minHeight: 18)
                .background(Color.red.opacity(0.92), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.lavaShellCream.opacity(0.85), lineWidth: 1.5)
                )
        }
    }

    private var profileMenuButton: some View {
        Menu {
            Section(session.displayName) {
                profileMenuActionButton("Account") {
                    navigator.pushRoute(ProviderShellRoute.account)
                }
                if session.hasProviderProfile {
                    profileMenuActionButton("Business Analytics") {
                        showingBusinessAnalytics = true
                    }
                    profileMenuActionButton("Payout Settings") {
                        navigator.pushRoute(ProviderShellRoute.payoutSettings)
                    }
                }
            }
            if session.authUser?.hasAdminPrivileges == true {
                Section("Admin") {
                    profileMenuActionButton("Admin dashboard") {
                        navigator.pushRoute(ProviderShellRoute.adminDashboard)
                    }
                }
            }
            Section {
                profileMenuActionButton("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
        } label: {
            profileAvatar
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account menu")
    }

    /// Text-only menu rows (no SF Symbol). Stronger type so each row reads as an intentional control within the system menu.
    private func profileMenuActionButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.provider(.body, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        }
    }

    /// Async-loaded provider avatar with the existing `person.crop.circle.fill` SF symbol as a placeholder
    /// + failure fallback. Sized to a 36-pt circle so it visually balances the requests tray control.
    @ViewBuilder
    private var profileAvatar: some View {
        let placeholder = Image(systemName: "person.crop.circle.fill")
            .resizable()
            .symbolRenderingMode(.hierarchical)
            .scaledToFit()
            .foregroundStyle(Color.lavaShellCream)

        Group {
            if let url = session.barberProfile?.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.lavaShellCream.opacity(0.35), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func pushedScreenView(_ screen: ProviderShellScreen) -> some View {
        switch screen {
        case .route(let route):
            shellRouteDestination(route)
        case .booking(let booking):
            BookingDetailScreen(booking: booking, showsShellBackButton: true) {
                await MainActor.run {
                    NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
                }
            }
            .providerPushedDestinationChrome()
            .providerShellBackToolbar()
        }
    }

    @ViewBuilder
    private func shellRouteDestination(_ route: ProviderShellRoute) -> some View {
        switch route {
        case .messages:
            ProviderMessagesInboxView()
                .providerPushedDestinationChrome(for: route)
                .providerShellBackToolbar()
        case .account:
            ProviderProfileContent()
                .providerPushedDestinationChrome(for: route)
                .providerShellBackToolbar()
        case .services:
            ProviderBarberServicesView()
                .providerPushedDestinationChrome(for: route)
                .providerShellBackToolbar()
        case .availability:
            ProviderAvailabilityEditorView()
                .providerPushedDestinationChrome(for: route)
                .providerShellBackToolbar()
        case .weeklyScheduleEditor:
            ProviderAvailabilityEditorView(presentation: .weeklyEditorOnly)
                .providerPushedDestinationChrome(for: route)
                .providerShellBackToolbar()
        case .payoutSettings:
            ProviderPayoutSettingsView()
                .providerPushedDestinationChrome(for: route)
                .providerShellBackToolbar()
        case .adminDashboard:
            ProviderAdminDashboardView()
                .providerPushedDestinationChrome(for: route)
                .providerShellBackToolbar()
        }
    }

    private func refreshHeaderCounts() async {
        var chatUnread = 0
        do {
            let rows = try await ProviderMessagesService.listConversations()
            chatUnread += rows.reduce(0) { partial, row in
                partial + ((row.unreadCount ?? 0) > 0 ? 1 : 0)
            }
        } catch {
            chatUnread = 0
        }

        if session.hasProviderProfile || session.authUser?.hasAdminPrivileges == true {
            chatUnread += await providerRosterUnreadThreadCount()
        }
        unreadConversationCount = chatUnread

        guard let bid = session.barberProfile?.id else {
            pendingRequestCount = 0
            pendingRescheduleRequestCount = 0
            hasAwaitingPaymentAttention = false
            syncApplicationIconBadge()
            return
        }
        async let pendingRequestsTask: Void = loadPendingRequestCount(barberTableId: bid)
        async let pendingReschedulesTask: Void = loadPendingRescheduleRequestCount()
        _ = await (pendingRequestsTask, pendingReschedulesTask)
        syncApplicationIconBadge()
    }

    private func loadPendingRequestCount(barberTableId: String) async {
        do {
            let pending = try await ProviderBookingRequestsService.listPending(barberTableId: barberTableId)
            pendingRequestCount = pending.count
        } catch {
            pendingRequestCount = 0
        }
    }

    private func loadPendingRescheduleRequestCount() async {
        do {
            let bookings = try await ProviderBookingsService.listBookings(role: "barber")
            pendingRescheduleRequestCount = bookings.filter(\.hasPendingRescheduleRequest).count
            ProviderAwaitingPaymentTracker.shared.reconcile(with: bookings)
            hasAwaitingPaymentAttention = bookings.contains(where: \.isCompletedAwaitingConsumerPayment)
        } catch {
            pendingRescheduleRequestCount = 0
            hasAwaitingPaymentAttention = false
        }
    }

    private func providerRosterUnreadThreadCount() async -> Int {
        do {
            let isAdmin = session.authUser?.hasAdminPrivileges == true
            let barbers: [BarberChatRowDTO]
            if isAdmin {
                let campuses = try await ProviderAdminService.listCampuses()
                barbers = try await ProviderBarberChatsService.fetchSupportBarbersAllCampuses(
                    campusIds: campuses.map(\.id)
                )
            } else {
                barbers = try await ProviderBarberChatsService.fetchPeerBarbers(
                    campusId: session.authUser?.campusId
                )
            }
            return barbers.filter { $0.unreadCount > 0 }.count
        } catch {
            return 0
        }
    }

    /// Keeps the home-screen badge aligned with the in-app Chats + Bookings indicators.
    private func syncApplicationIconBadge() {
        #if os(iOS)
        let badge = unreadConversationCount + bookingsTrayAttentionCount
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(badge)
        }
        #endif
    }

    private static func bookingId(from userInfo: [AnyHashable: Any]?) -> String? {
        guard let userInfo else { return nil }
        switch userInfo["bookingId"] {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func conversationId(from userInfo: [AnyHashable: Any]?) -> Int? {
        guard let userInfo else { return nil }
        switch userInfo["conversationId"] {
        case let value as Int: return value
        case let value as Int64: return Int(value)
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    private func presentBookingsInbox() {
        bookingsInboxPresentationID = UUID()
        showingRequestsInbox = true
    }
}
