import SwiftUI

// MARK: - Expandable triage card

struct ProviderExpandableRequestTriageCard: View {
    let item: RequestTriageItem
    let isExpanded: Bool
    let onHeaderTap: () -> Void
    let onReschedule: () -> Void
    let onAccept: () -> Void
    let onDecline: () -> Void
    let isOpeningMessage: Bool
    let onMessage: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Cached expanded height so reopening animates smoothly and siblings slide instead of jumping.
    @State private var expandedContentHeight: CGFloat = 0

    private var expandedRevealHeight: CGFloat {
        guard isExpanded, expandedContentHeight > 0 else { return 0 }
        return expandedContentHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .contentShape(Rectangle())
                .onTapGesture(perform: onHeaderTap)

            expandableContent
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(height: expandedRevealHeight)
                }
                .frame(height: expandedRevealHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .background(alignment: .topLeading) {
            expandableContent
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    guard height > 0, abs(height - expandedContentHeight) > 0.5 else { return }
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        expandedContentHeight = height
                    }
                }
        }
        .onChange(of: item.id) { _, _ in
            expandedContentHeight = 0
        }
        .background(Color.providerElevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.providerElevatedSurfaceStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

            scheduledForStrip
        }
        .padding(14)
        .animation(nil, value: isExpanded)
    }

    @ViewBuilder
    private var miniScheduleSection: some View {
        if item.surroundingSchedule.isEmpty {
            Text("Schedule context unavailable for this time.")
                .font(.provider(.footnote))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 8) {
                ForEach(item.surroundingSchedule) { slot in
                    ProviderRequestScheduleContextRow(item: slot)
                }
            }
            .compositingGroup()
        }
    }

    /// Front-of-card schedule summary — date and time must be obvious before expanding.
    private var scheduledForStrip: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Scheduled for")
                    .font(.provider(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                Text(scheduledDateHeadline(for: item.requestedStart))
                    .font(.provider(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lavaShellCream)
                Text(scheduledTimeHeadline(for: item.requestedStart))
                    .font(.provider(.footnote, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream.opacity(0.9))
            }

            Spacer(minLength: 8)

            conflictBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.providerOlive.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.providerOlive.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scheduled for \(scheduledDateHeadline(for: item.requestedStart)) at \(scheduledTimeHeadline(for: item.requestedStart))")
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
        date.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private var conflictBadge: some View {
        if item.hasConflict {
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
                .foregroundStyle(slotOpenBadgeForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(slotOpenBadgeBackground, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(slotOpenBadgeBorder, lineWidth: 1)
                )
        }
    }

    private var slotOpenBadgeForeground: Color {
        colorScheme == .dark ? Color.providerOliveLight : Color.providerOlive
    }

    private var slotOpenBadgeBackground: Color {
        colorScheme == .dark
            ? Color.providerOlive.opacity(0.22)
            : Color.providerOliveLight.opacity(0.42)
    }

    private var slotOpenBadgeBorder: Color {
        Color.providerOlive.opacity(colorScheme == .dark ? 0.35 : 0.28)
    }

    private var expandableContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .overlay(Color(uiColor: ProviderAppearance.separator))

            miniScheduleSection

            HStack(spacing: 12) {
                Button(action: onReschedule) {
                    Text("Reschedule")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(rescheduleButtonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(rescheduleButtonBackground, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(rescheduleButtonBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onMessage) {
                    Text(isOpeningMessage ? "Opening…" : "Message")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(messageButtonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(messageButtonBackground, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(messageButtonBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isOpeningMessage)
            }

            Divider()
                .overlay(Color(uiColor: ProviderAppearance.separator))

            HStack(spacing: 12) {
                Button(action: onDecline) {
                    Text("Decline")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            ProviderRequestSheetColors.lavaRed,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onAccept) {
                    Text("Approve")
                        .font(.provider(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(approveButtonBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(item.hasConflict)
                .opacity(item.hasConflict ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .animation(nil, value: isExpanded)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var statusYellow: Color {
        Color(uiColor: ProviderChatDesignTokens.Color.statusYellow)
    }

    private var rescheduleButtonForeground: Color {
        colorScheme == .dark ? Color.lavaShellCream : Color(white: 0.1)
    }

    private var rescheduleButtonBackground: Color {
        colorScheme == .dark
            ? statusYellow.opacity(0.28)
            : statusYellow.opacity(0.52)
    }

    private var rescheduleButtonBorder: Color {
        statusYellow.opacity(colorScheme == .dark ? 0.4 : 0.32)
    }

    private var messageButtonForeground: Color {
        colorScheme == .dark ? Color.lavaShellCream : Color(white: 0.1)
    }

    private var messageButtonBackground: Color {
        colorScheme == .dark
            ? Color.providerOlive.opacity(0.28)
            : Color.providerOlive.opacity(0.52)
    }

    private var messageButtonBorder: Color {
        Color.providerOlive.opacity(colorScheme == .dark ? 0.4 : 0.32)
    }

    private var approveButtonBackground: Color {
        ProviderRequestSheetColors.approveGreen
    }
}

// MARK: - Outlined text

struct ProviderBlackOutlinedText: View {
    let text: String
    var fill: Color = Color.lavaShellCream

    @Environment(\.colorScheme) private var colorScheme

    private static let darkOutlineOffsets: [CGSize] = [
        CGSize(width: -1.5, height: 0), CGSize(width: 1.5, height: 0),
        CGSize(width: 0, height: -1.5), CGSize(width: 0, height: 1.5),
        CGSize(width: -1.5, height: -1.5), CGSize(width: 1.5, height: -1.5),
        CGSize(width: -1.5, height: 1.5), CGSize(width: 1.5, height: 1.5),
    ]

    init(_ text: String, fill: Color = Color.lavaShellCream) {
        self.text = text
        self.fill = fill
    }

    var body: some View {
        if colorScheme == .dark {
            ZStack {
                ForEach(Array(Self.darkOutlineOffsets.enumerated()), id: \.offset) { _, offset in
                    Text(text)
                        .offset(x: offset.width, y: offset.height)
                        .foregroundStyle(.black)
                }
                Text(text)
                    .foregroundStyle(fill)
            }
        } else {
            Text(text)
                .foregroundStyle(fill)
        }
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
