import SwiftUI

// MARK: - Expandable triage card

struct ProviderExpandableRequestTriageCard: View {
    let item: RequestTriageItem
    let isExpanded: Bool
    let isEditingSchedule: Bool
    @Binding var draftScheduleDate: Date
    @Binding var draftHasConflict: Bool
    let barberId: String?
    let scheduleEditError: String?
    let isSavingSchedule: Bool
    let onHeaderTap: () -> Void
    let onBeginEditSchedule: () -> Void
    let onCancelEditSchedule: () -> Void
    let onSaveSchedule: () -> Void
    let onAccept: () -> Void
    let onDecline: () -> Void
    let isOpeningMessage: Bool
    let onMessage: () -> Void

    private var displayStart: Date {
        isEditingSchedule ? draftScheduleDate : item.requestedStart
    }

    /// Cached expanded height so reopening animates smoothly and siblings slide instead of jumping.
    @State private var expandedContentHeight: CGFloat = 0

    private var expandedRevealHeight: CGFloat {
        guard isExpanded else { return 0 }
        if isEditingSchedule {
            return max(expandedContentHeight, 520)
        }
        return expandedContentHeight > 0 ? expandedContentHeight : 360
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture(perform: onHeaderTap)

            expandedBody
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: expandedRevealHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
                .overlay(alignment: .topLeading) {
                    if !isEditingSchedule {
                        expandedBody
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                guard height > 0 else { return }
                                expandedContentHeight = height
                            }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    guard isExpanded, isEditingSchedule, height > 0 else { return }
                    expandedContentHeight = max(expandedContentHeight, height)
                }
        }
        .background(Color.providerElevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.providerElevatedSurfaceStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: isEditingSchedule) { _, editing in
            if editing, isExpanded {
                expandedContentHeight = max(expandedContentHeight, 520)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.row.customerName ?? "Customer")
                        .font(.provider(.title3, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                    Text(item.row.serviceDisplayName)
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    if let price = item.row.price {
                        Text(price, format: .currency(code: "USD"))
                            .font(.provider(.headline))
                            .foregroundStyle(Color.lavaShellCream)
                    }
                    Text("\(item.durationMinutes) min")
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                Image(systemName: "chevron.down")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream.opacity(0.6))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(ProviderRequestSheetMetrics.triageCardSpring, value: isExpanded)
                    .padding(.leading, 4)
            }

            scheduledForStrip(editing: isEditingSchedule)
        }
        .padding(14)
    }

    /// Front-of-card schedule summary — date and time must be obvious before expanding.
    private func scheduledForStrip(editing: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Scheduled for")
                    .font(.provider(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .textCase(.uppercase)
                Text(scheduledDateHeadline(for: displayStart))
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lavaShellCream)
                Text(scheduledTimeHeadline(for: displayStart))
                    .font(.provider(.footnote, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream.opacity(0.9))
            }

            Spacer(minLength: 8)

            conflictBadge(editing: editing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.providerOlive.opacity(editing ? 0.28 : 0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.providerOlive.opacity(editing ? 0.85 : 0.35), lineWidth: editing ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scheduled for \(scheduledDateHeadline(for: displayStart)) at \(scheduledTimeHeadline(for: displayStart))")
    }

    private func scheduledDateHeadline(for date: Date) -> String {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        if cal.isDateInToday(day) {
            return "Today"
        }
        if cal.isDateInTomorrow(day) {
            return "Tomorrow"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func scheduledTimeHeadline(for date: Date) -> String {
        if !isEditingSchedule,
           let campusTime = ProviderBookingScheduleParsing.displayWallClockTime(from: item.row) {
            return campusTime
        }
        if !isEditingSchedule, item.row.requestedScheduleInstant == nil {
            let fallback = item.row.formattedRequestedSchedule()
            if fallback != "Time TBD" { return fallback }
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func conflictBadge(editing: Bool) -> some View {
        let conflict = editing ? draftHasConflict : item.hasConflict
        if conflict {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Conflict")
            }
            .font(.provider(.caption, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Color.red.opacity(0.95))
            .background(Color.red.opacity(0.18), in: Capsule())
        } else {
            Text("Slot open")
                .font(.provider(.caption, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(Color.providerOlive)
                .background(Color.providerOlive.opacity(0.22), in: Capsule())
        }
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .overlay(Color(uiColor: ProviderAppearance.separator))

            if isEditingSchedule, let barberId {
                ProviderPendingRequestScheduleEditor(
                    barberId: barberId,
                    bookingId: item.row.bookingId,
                    customerName: item.row.customerName ?? "Customer",
                    serviceType: item.row.serviceDisplayName,
                    selectedDateTime: $draftScheduleDate,
                    hasConflict: $draftHasConflict
                )

                if let scheduleEditError {
                    Text(scheduleEditError)
                        .font(.provider(.caption))
                        .foregroundStyle(.red.opacity(0.9))
                }

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancelEditSchedule)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(isSavingSchedule)

                    Button(isSavingSchedule ? "Saving…" : "Save time") {
                        onSaveSchedule()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.providerOlive)
                    .frame(maxWidth: .infinity)
                    .disabled(isSavingSchedule || draftHasConflict)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scheduledDateHeadline(for: item.requestedStart))
                        .font(.provider(.title3, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                    Text(scheduledTimeHeadline(for: displayStart))
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.surroundingSchedule.isEmpty {
                    Text("Schedule context unavailable for this time.")
                        .font(.provider(.footnote))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(item.surroundingSchedule) { slot in
                            ProviderRequestScheduleContextRow(item: slot)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("Edit time", action: onBeginEditSchedule)
                        .buttonStyle(.bordered)
                        .tint(.providerOlive)
                        .frame(maxWidth: .infinity)

                    Button(isOpeningMessage ? "Opening…" : "Message", action: onMessage)
                        .buttonStyle(.bordered)
                        .tint(.providerOlive)
                        .frame(maxWidth: .infinity)
                        .disabled(isOpeningMessage)
                }

                Divider()
                    .overlay(Color(uiColor: ProviderAppearance.separator))

                HStack(spacing: 12) {
                    Button("Decline", role: .destructive, action: onDecline)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                    Button("Approve", action: onAccept)
                        .buttonStyle(.borderedProminent)
                        .tint(.providerOlive)
                        .frame(maxWidth: .infinity)
                        .disabled(item.hasConflict)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

}

// MARK: - Timeline row

struct ProviderRequestScheduleContextRow: View {
    let item: RequestScheduleContextItem

    var body: some View {
        HStack(spacing: 10) {
            Text(item.timeLabel)
                .font(.provider(.caption, weight: .bold))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .frame(width: 58, alignment: .leading)

            HStack(spacing: 8) {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 6, height: 6)
                Text(item.title)
                    .font(.provider(.footnote))
                    .fontWeight(item.type == .proposed ? .semibold : .regular)
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: item.type == .proposed ? 1 : 0)
            )
        }
    }

    private var badgeColor: Color {
        switch item.type {
        case .booked: return .red.opacity(0.9)
        case .proposed: return .providerOlive
        case .open: return .providerOlive
        }
    }

    private var textColor: Color {
        switch item.type {
        case .booked: return Color.lavaShellCream
        case .proposed: return Color.lavaShellCream
        case .open: return Color.lavaShellCreamSecondary
        }
    }

    private var backgroundColor: Color {
        switch item.type {
        case .booked: return Color.providerScheduleCardFill
        case .proposed: return Color.providerOlive.opacity(0.2)
        case .open: return Color.providerOlive.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch item.type {
        case .proposed: return Color.providerOlive.opacity(0.35)
        case .booked: return Color.providerScheduleCardStroke
        case .open: return Color.clear
        }
    }
}
