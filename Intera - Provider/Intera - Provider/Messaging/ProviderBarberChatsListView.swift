import SwiftUI

/// Roster of barbers on a campus for peer coordination (barbers) or admin support messaging.
struct ProviderBarberChatsRosterView: View {
    @Environment(ProviderSession.self) private var session

    let onOpenConversation: (ConversationRow) -> Void

    @State private var barbers: [BarberChatRowDTO] = []
    @State private var campuses: [AdminCampusDTO] = []
    @State private var selectedCampusId: String?
    @State private var searchQuery = ""
    @State private var isLoading = false
    @State private var isOpeningThread = false
    @State private var errorText: String?
    @State private var openingBarberUserId: String?

    private var isAdmin: Bool { session.authUser?.hasAdminPrivileges == true }
    private var usesSupportInbox: Bool { isAdmin }

    private var sortedCampuses: [AdminCampusDTO] {
        campuses.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var campusScopeLabel: String {
        guard let id = selectedCampusId,
              let campus = campuses.first(where: { $0.id == id }) else {
            return "All Campuses"
        }
        return campus.displayName
    }

    private var filteredBarbers: [BarberChatRowDTO] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return barbers }
        return barbers.filter {
            $0.name.lowercased().contains(query) || $0.email.lowercased().contains(query)
        }
    }

    private var canLoadRoster: Bool {
        if usesSupportInbox {
            return !campuses.isEmpty || isLoading
        }
        return true
    }

    private var showsCampusGroups: Bool {
        usesSupportInbox && selectedCampusId == nil
    }

    private struct BarberChatCampusGroup: Identifiable {
        let id: String
        let title: String
        let barbers: [BarberChatRowDTO]
    }

    private var barberCampusGroups: [BarberChatCampusGroup] {
        var buckets: [String: [BarberChatRowDTO]] = [:]
        for barber in filteredBarbers {
            let key = barber.campusId ?? "__unassigned__"
            buckets[key, default: []].append(barber)
        }

        return buckets.map { campusId, members in
            BarberChatCampusGroup(
                id: campusId,
                title: campusSectionTitle(forCampusId: campusId),
                barbers: members.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted {
            if $0.id == "__unassigned__" { return false }
            if $1.id == "__unassigned__" { return true }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func campusSectionTitle(forCampusId campusId: String) -> String {
        if campusId == "__unassigned__" { return "Unassigned campus" }
        if let campus = campuses.first(where: { $0.id == campusId }) {
            return campus.displayName
        }
        return "Campus"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if usesSupportInbox {
                    campusPickerCard
                } else {
                    Text("Chat with service providers in your area")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                searchField

                if let errorText {
                    Text(errorText)
                        .font(.provider(.footnote))
                        .foregroundStyle(.red)
                }

                rosterContent
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await loadRoster()
        }
        .overlay {
            if isOpeningThread {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Opening chat…")
                        .tint(.providerOlive)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: ProviderAppearance.shellBase))
                        )
                }
            }
        }
        .task {
            await bootstrap()
        }
        .onChange(of: selectedCampusId) { _, _ in
            Task { await loadRoster() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerMessagingUnreadCountShouldRefresh)) { _ in
            Task { await loadRoster() }
        }
    }

    @ViewBuilder
    private var rosterContent: some View {
        if usesSupportInbox && campuses.isEmpty && !isLoading {
            emptyState(
                icon: "building.2",
                message: "No campuses available."
            )
        } else if isLoading && barbers.isEmpty {
            ProgressView()
                .tint(.providerOlive)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if filteredBarbers.isEmpty {
            emptyState(
                icon: "bubble.left.and.bubble.right",
                message: searchQuery.isEmpty
                    ? (showsCampusGroups
                        ? "No providers on any campus yet."
                        : "No other providers in your area yet.")
                    : "No providers found."
            )
        } else if showsCampusGroups {
            LazyVStack(spacing: 16) {
                ForEach(barberCampusGroups) { group in
                    barberCampusSection(group)
                }
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(filteredBarbers) { barber in
                    barberRow(barber)
                }
            }
        }
    }

    private func barberCampusSection(_ group: BarberChatCampusGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                Text("\(group.barbers.count) provider\(group.barbers.count == 1 ? "" : "s")")
                    .font(.provider(.caption2))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )

            ForEach(group.barbers) { barber in
                barberRow(barber)
            }
        }
    }

    private var campusPickerCard: some View {
        Menu {
            Button {
                selectedCampusId = nil
            } label: {
                HStack {
                    Text("All Campuses")
                    if selectedCampusId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if campuses.isEmpty {
                Text("No campuses available")
            } else {
                ForEach(sortedCampuses) { campus in
                    Button {
                        selectedCampusId = campus.id
                    } label: {
                        HStack {
                            Text(campus.displayName)
                            if selectedCampusId == campus.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Text(campusScopeLabel)
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.provider(.caption, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                        .padding(.trailing, 14)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Campus")
        .accessibilityValue(campusScopeLabel)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.lavaShellCreamTertiary)
            TextField("Search providers…", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func barberRow(_ barber: BarberChatRowDTO) -> some View {
        Button {
            Task { await openThread(with: barber) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ProviderSquaredAvatarView(
                    url: barber.avatarURL,
                    fallbackName: barber.name,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(barber.name)
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream)
                            .lineLimit(1)
                        if barber.isActive == false {
                            Text("Hidden")
                                .font(.provider(.caption2, weight: .semibold))
                                .foregroundStyle(Color.lavaShellCream)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red.opacity(0.55)))
                        }
                        Spacer(minLength: 4)
                        if let at = barber.lastMessageAt {
                            Text(BarberChatTimestampParsing.formatListTimestamp(at))
                                .font(.provider(.caption2))
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                        }
                    }

                    Text(barber.email)
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .lineLimit(1)

                    if let preview = barber.lastMessage, !preview.isEmpty {
                        Text(preview)
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .lineLimit(2)
                    } else {
                        Text("No messages yet")
                            .font(.provider(.caption))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                            .italic()
                    }
                }

                if barber.unreadCount > 0 {
                    Text("\(barber.unreadCount)")
                        .font(.provider(.caption2, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.providerOlive))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(isOpeningThread)
        .opacity(openingBarberUserId == barber.userId ? 0.6 : 1)
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Color.lavaShellCreamTertiary)
            Text(message)
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @MainActor
    private func bootstrap() async {
        errorText = nil
        if usesSupportInbox {
            _ = try? await ProviderAuthService.refreshAccessTokenIfPossible()
            do {
                campuses = try await ProviderAdminService.listCampuses()
                await loadRoster()
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        } else {
            selectedCampusId = session.authUser?.campusId
            await loadRoster()
        }
    }

    @MainActor
    private func loadRoster() async {
        guard canLoadRoster else {
            if !usesSupportInbox {
                barbers = []
            }
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorText = nil

        do {
            if usesSupportInbox {
                if let campusId = selectedCampusId {
                    barbers = try await ProviderBarberChatsService.fetchSupportBarbers(campusId: campusId)
                } else {
                    let ids = campuses.map(\.id)
                    barbers = try await ProviderBarberChatsService.fetchSupportBarbersAllCampuses(campusIds: ids)
                }
            } else {
                barbers = try await ProviderBarberChatsService.fetchPeerBarbers(campusId: selectedCampusId)
            }
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            barbers = []
            errorText = msg ?? "Could not load providers (\(code))."
        } catch {
            barbers = []
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func openThread(with barber: BarberChatRowDTO) async {
        guard !isOpeningThread else { return }
        isOpeningThread = true
        openingBarberUserId = barber.userId
        defer {
            isOpeningThread = false
            openingBarberUserId = nil
        }
        errorText = nil

        do {
            let conversationId: Int
            if let existing = barber.conversationId {
                conversationId = existing
            } else if usesSupportInbox {
                conversationId = try await ProviderBarberChatsService.startSupportConversation(
                    barberUserId: barber.userId
                )
            } else {
                conversationId = try await ProviderBarberChatsService.startPeerConversation(
                    otherBarberUserId: barber.userId
                )
            }

            ProviderConversationMessagesPrefetch.prefetch(conversationId: conversationId)
            onOpenConversation(barber.conversationRow(conversationId: conversationId))
            NotificationCenter.default.post(name: .providerMessagingUnreadCountShouldRefresh, object: nil)
        } catch let CampusCutsHTTPError.httpStatus(code, msg) {
            errorText = msg ?? "Could not open chat (\(code))."
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Opens a support thread with a barber from the admin dashboard (detail screen).
@MainActor
enum ProviderBarberChatOpener {
    static func openSupportChat(barberUserId: String) async throws -> Int {
        let conversationId = try await ProviderBarberChatsService.startSupportConversation(barberUserId: barberUserId)
        ProviderConversationMessagesPrefetch.prefetch(conversationId: conversationId)
        NotificationCenter.default.post(
            name: .interaOpenMessagingConversation,
            object: nil,
            userInfo: ["conversationId": conversationId]
        )
        NotificationCenter.default.post(name: .providerMessagingUnreadCountShouldRefresh, object: nil)
        return conversationId
    }
}
