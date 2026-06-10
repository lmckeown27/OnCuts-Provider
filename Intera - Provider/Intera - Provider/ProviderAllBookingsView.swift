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

struct ProviderBookingsSectionDropdownHeader: View {
    let title: String
    let count: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.providerElevatedSurface, in: Capsule())
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            withAnimation(.easeInOut(duration: 0.2)) {
                isRequestedChangesExpanded.toggle()
            }
        }
        .bookingsListCardRow(
            contentWidth: dropdownWidth,
            verticalInset: 8,
            leadingInset: Self.pageLeadingInset
        )

        if isRequestedChangesExpanded {
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
            withAnimation(.easeInOut(duration: 0.2)) {
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

        if isExpanded {
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream)
            Text(booking.serviceDisplayName)
                .font(.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
            HStack {
                Text(booking.statusDisplayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(booking.statusDisplayTint, in: Capsule())
                Spacer(minLength: 0)
                Text(booking.formattedSchedule())
                    .font(.caption)
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream)
            Text(booking.serviceDisplayName)
                .font(.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)

            HStack {
                Text(booking.statusDisplayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(booking.statusDisplayTint, in: Capsule())
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Current: \(booking.formattedSchedule())")
                    .font(.caption)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                Text("Requested: \(proposed)")
                    .font(.caption.weight(.semibold))
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

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, verticalInset)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.providerElevatedSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.providerElevatedSurfaceStroke, lineWidth: 0.5)
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
        leadingInset: CGFloat = 0
    ) -> some View {
        modifier(
            ProviderBookingsListCardRowModifier(
                contentWidth: contentWidth,
                verticalInset: verticalInset,
                leadingInset: leadingInset
            )
        )
    }
}
