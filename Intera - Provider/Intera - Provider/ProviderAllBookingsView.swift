import SwiftUI

// MARK: - Request cancellation (SwiftUI `.task` / `refreshable` overlap)

/// `NSURLErrorCancelled` (-999) when a prior `URLSession` task is cancelled—**not** a user-visible failure.
func providerAllBookingsIsBenignCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
}

// MARK: - Shared bookings dropdown list (Requests inbox)

extension Array where Element == SimpleBookingDTO {
    /// Bookings awaiting triage in **Booking Requests** should not also appear under **Pending**.
    func excludingOpenBookingRequests(triageItems: [RequestTriageItem]) -> [SimpleBookingDTO] {
        guard !triageItems.isEmpty else { return self }
        let openRequestBookingIds = Set(
            triageItems
                .map(\.row.bookingId)
                .filter { !$0.hasPrefix("conv-") }
        )
        guard !openRequestBookingIds.isEmpty else { return self }
        return filter { !openRequestBookingIds.contains($0.id) }
    }
}

struct ProviderBookingsSectionDropdownHeader: View {
    let title: String
    let count: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Text(title)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.provider(.caption, weight: .bold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.providerElevatedSurface, in: Capsule())
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(ProviderRequestSheetMetrics.triageCardSpring, value: isExpanded)
    }
}

/// Clips expanding/collapsing sections and lets sibling rows slide with the spring animation.
private struct ProviderAnimatedCollapseModifier: ViewModifier {
    let isExpanded: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxHeight: isExpanded ? .infinity : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
    }
}

extension View {
    func providerAnimatedCollapse(isExpanded: Bool) -> some View {
        modifier(ProviderAnimatedCollapseModifier(isExpanded: isExpanded))
    }
}

struct ProviderBookingsDropdownListContent: View {
    let items: [SimpleBookingDTO]
    @Binding var expandedFilters: Set<ProviderBookingStatusDisplay.Filter>
    @Binding var isRequestedChangesExpanded: Bool
    let containerWidth: CGFloat

    static let requestedChangesSectionTitle = "Requested Date/Time Changes"
    static let contentWidthRatio: CGFloat = 0.75
    static let nestedIndent: CGFloat = 24
    static let pageLeadingInset: CGFloat = 16

    private var filtersWithBookings: [ProviderBookingStatusDisplay.Filter] {
        ProviderBookingStatusDisplay.Filter.allCases.filter { filter in
            filter != .all && !bookings(for: filter).isEmpty
        }
    }

    private var bookingsWithPendingReschedule: [SimpleBookingDTO] {
        sortedRescheduleRequestBookings(items.filter(\.hasPendingRescheduleRequest))
    }

    private var hasVisibleSections: Bool {
        !bookingsWithPendingReschedule.isEmpty || !filtersWithBookings.isEmpty
    }

    var body: some View {
        Group {
            if !bookingsWithPendingReschedule.isEmpty {
                requestedChangesSection
            }

            ForEach(filtersWithBookings) { filter in
                filterSection(filter)
            }

            if !hasVisibleSections {
                ForEach(sortedBookings(items)) { booking in
                    bookingNavigationLink(booking)
                        .bookingsListCardRow(
                            contentWidth: containerWidth * Self.contentWidthRatio,
                            verticalInset: 12,
                            leadingInset: Self.pageLeadingInset
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var requestedChangesSection: some View {
        let dropdownWidth = containerWidth * Self.contentWidthRatio

        ProviderBookingsSectionDropdownHeader(
            title: Self.requestedChangesSectionTitle,
            count: bookingsWithPendingReschedule.count,
            isExpanded: isRequestedChangesExpanded
        ) {
            withAnimation(ProviderRequestSheetMetrics.triageCardSpring) {
                isRequestedChangesExpanded.toggle()
            }
        }
        .bookingsListCardRow(
            contentWidth: dropdownWidth,
            verticalInset: 8,
            leadingInset: Self.pageLeadingInset
        )

        VStack(spacing: 8) {
            ForEach(bookingsWithPendingReschedule) { booking in
                bookingNavigationLink(booking) {
                    rescheduleRequestBookingRow(booking)
                }
                .bookingsListCardRow(
                    contentWidth: nestedBookingContentWidth,
                    verticalInset: 8,
                    leadingInset: Self.pageLeadingInset + Self.nestedIndent
                )
            }
        }
        .providerAnimatedCollapse(isExpanded: isRequestedChangesExpanded)
    }

    @ViewBuilder
    private func filterSection(_ filter: ProviderBookingStatusDisplay.Filter) -> some View {
        let isExpanded = expandedFilters.contains(filter)
        let dropdownWidth = containerWidth * Self.contentWidthRatio

        ProviderBookingsSectionDropdownHeader(
            title: filter.title,
            count: bookings(for: filter).count,
            isExpanded: isExpanded
        ) {
            withAnimation(ProviderRequestSheetMetrics.triageCardSpring) {
                if isExpanded {
                    expandedFilters.remove(filter)
                } else {
                    expandedFilters.insert(filter)
                }
            }
        }
        .bookingsListCardRow(
            contentWidth: dropdownWidth,
            verticalInset: 8,
            leadingInset: Self.pageLeadingInset
        )

        VStack(spacing: 8) {
            ForEach(bookings(for: filter)) { booking in
                bookingNavigationLink(booking) {
                    bookingRow(booking)
                }
                .bookingsListCardRow(
                    contentWidth: nestedBookingContentWidth,
                    verticalInset: 8,
                    leadingInset: Self.pageLeadingInset + Self.nestedIndent
                )
            }
        }
        .providerAnimatedCollapse(isExpanded: isExpanded)
    }

    private var nestedBookingContentWidth: CGFloat {
        let leading = Self.pageLeadingInset + Self.nestedIndent
        let trailing = Self.pageLeadingInset
        return max(containerWidth - leading - trailing, 120)
    }

    private func bookingNavigationLink<Label: View>(
        _ booking: SimpleBookingDTO,
        @ViewBuilder label: () -> Label
    ) -> some View {
        NavigationLink(value: booking.id) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bookingNavigationLink(_ booking: SimpleBookingDTO) -> some View {
        bookingNavigationLink(booking) {
            bookingRow(booking)
        }
    }

    private func bookingRow(_ booking: SimpleBookingDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(booking.consumerDisplayName)
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
            Text(booking.serviceDisplayName)
                .font(.provider(.subheadline))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            HStack {
                Text(booking.statusDisplayTitle)
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(booking.statusDisplayTint, in: Capsule())
                Spacer(minLength: 0)
                Text(booking.formattedSchedule())
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rescheduleRequestBookingRow(_ booking: SimpleBookingDTO) -> some View {
        let proposed = booking.pendingRescheduleRequest?.formattedProposedSchedule() ?? "Time TBD"

        return VStack(alignment: .leading, spacing: 6) {
            Text(booking.consumerDisplayName)
                .font(.provider(.title3, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
            Text(booking.serviceDisplayName)
                .font(.provider(.subheadline))
                .foregroundStyle(Color.lavaShellCreamSecondary)

            HStack {
                Text(booking.statusDisplayTitle)
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(booking.statusDisplayTint, in: Capsule())
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Current: \(booking.formattedSchedule())")
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                Text("Requested: \(proposed)")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.providerOlive)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bookings(for filter: ProviderBookingStatusDisplay.Filter) -> [SimpleBookingDTO] {
        sortedBookings(items.filter { filter.matches($0) && !$0.hasPendingRescheduleRequest })
    }

    private func sortedBookings(_ bookings: [SimpleBookingDTO]) -> [SimpleBookingDTO] {
        bookings.sorted { lhs, rhs in
            let left = lhs.scheduledTime ?? .distantPast
            let right = rhs.scheduledTime ?? .distantPast
            return left > right
        }
    }

    private func sortedRescheduleRequestBookings(_ bookings: [SimpleBookingDTO]) -> [SimpleBookingDTO] {
        bookings.sorted { lhs, rhs in
            let left = lhs.pendingRescheduleRequest?.proposedScheduledTime ?? lhs.scheduledTime ?? .distantPast
            let right = rhs.pendingRescheduleRequest?.proposedScheduledTime ?? rhs.scheduledTime ?? .distantPast
            return left > right
        }
    }
}

// MARK: - Bookings list card layout (background matches 75% content width)

private struct ProviderBookingsListCardRowModifier: ViewModifier {
    let contentWidth: CGFloat
    let verticalInset: CGFloat
    let leadingInset: CGFloat
    var showsBackground: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, verticalInset)
            .background {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.providerElevatedSurface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.providerElevatedSurfaceStroke, lineWidth: 0.5)
                        }
                }
            }
            .frame(width: contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, leadingInset)
            .listRowInsets(EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension View {
    func bookingsListCardRow(
        contentWidth: CGFloat,
        verticalInset: CGFloat,
        leadingInset: CGFloat = 0,
        showsBackground: Bool = true
    ) -> some View {
        modifier(
            ProviderBookingsListCardRowModifier(
                contentWidth: contentWidth,
                verticalInset: verticalInset,
                leadingInset: leadingInset,
                showsBackground: showsBackground
            )
        )
    }
}
