import SwiftUI

// MARK: - Card navigation press feedback

struct ProviderChatCardNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Thread card

struct ProviderChatThreadCard: View {
    let thread: ProviderChatThread

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameHeader
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            sectionDivider

            serviceDetailsSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            sectionDivider

            messageRibbon
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if thread.hasUnread {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.providerMessageUnreadAccent.opacity(0.45), lineWidth: 1.5)
            }
        }
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
    }

    private var nameHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(thread.titleLine)
                .font(.provider(.headline, weight: .bold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if thread.hasUnread {
                Text(thread.unreadBadgeLabel)
                    .font(.provider(.caption, weight: .bold))
                    .foregroundStyle(Color(red: 26 / 255, green: 28 / 255, blue: 38 / 255))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.providerMessageUnreadAccent))
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
    }

    private var serviceDetailsSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.appointmentTime)
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(thread.isToday ? Color.providerBrandAccent : Color.secondary)
                Text(thread.appointmentDayLabel)
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(thread.isToday ? Color.providerBrandAccent : Color.secondary)
                Text(thread.appointmentDateLabel)
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
            .fixedSize(horizontal: true, vertical: true)

            Spacer(minLength: 8)

            Text(thread.bookingStatusTitle)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.providerElevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.providerElevatedSurfaceStroke.opacity(0.65), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var messagePreviewText: some View {
        let label = Text(thread.lastMessage)
            .font(.provider(.subheadline, weight: thread.hasUnread ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.tail)

        if thread.hasUnread {
            label
                .foregroundStyle(Color.lavaShellCream)
        } else {
            label
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
    }

    private var messageRibbon: some View {
        HStack(alignment: .center, spacing: 6) {
            if thread.hasUnread {
                Circle()
                    .fill(Color.providerMessageUnreadAccent)
                    .frame(width: 9, height: 9)
            }

            messagePreviewText
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.provider(.caption, weight: .bold))
                .foregroundStyleProviderShellIcon()
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Inbox list

struct ProviderChatInboxListView: View {
    let threads: [ProviderChatThread]
    let isLoading: Bool
    let errorText: String?
    let onRefresh: () async -> Void

    var body: some View {
        Group {
            if isLoading, threads.isEmpty {
                ProgressView()
                    .tint(.providerBrandAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText, threads.isEmpty {
                inboxMessage(
                    title: "Couldn't load messages",
                    subtitle: errorText
                )
            } else if threads.isEmpty {
                inboxMessage(
                    title: "No conversations yet",
                    subtitle: "You'll receive conversations here when a customer books an appointment with you."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(threads) { thread in
                            NavigationLink(value: thread.conversationId) {
                                ProviderChatThreadCard(thread: thread)
                            }
                            .buttonStyle(ProviderChatCardNavigationButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .refreshable {
            await onRefresh()
        }
    }

    private func inboxMessage(title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.provider(.title3, weight: .bold))
                .foregroundStyle(Color.lavaShellCream)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.provider(.subheadline))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
