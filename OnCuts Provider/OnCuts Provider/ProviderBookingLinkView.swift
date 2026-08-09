import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Lets the signed-in operator copy their public web booking page URL for clients.
/// URL shape matches web `BarberProfileEditor`: `/web/consumer/book/:barberId` (`barbers.id`).
struct ProviderBookingLinkView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?

    private var bookingURL: URL? {
        guard let id = session.barberProfile?.id else { return nil }
        return AppConfiguration.consumerBookingPageURL(barberId: id)
    }

    private var bookingURLString: String? {
        bookingURL?.absoluteString
    }

    private static let usageTips: [String] = [
        "Attach it to your Instagram profile for ease of booking",
        "Text or message it to clients when they ask how to book",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let bookingURLString {
                    Text("This webpage is directly linked with the OnCuts Provider app. When a client books on the webpage, you will get a notification in the app.")
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    linkCard(urlString: bookingURLString)
                    usageTipsList
                } else {
                    Text("Your booking link isn’t available yet. Finish setting up your operator profile, then try again.")
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .providerNavigationStackDestinationBackdrop()
        .providerPageNavigationTitle("Booking Link")
        .toolbar(.visible, for: .navigationBar)
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
        }
    }

    private func linkCard(urlString: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(urlString)
                .font(.provider(.body, weight: .bold))
                .foregroundStyle(Color.lavaShellCream)
                .textSelection(.enabled)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Your booking page link")
                .accessibilityValue(urlString)

            HStack(spacing: 10) {
                Button {
                    copyLink(urlString)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.provider(.subheadline, weight: .semibold))
                        Text(didCopy ? "Copied" : "Copy link")
                            .font(.provider(.subheadline, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(ProviderOliveChromeStyle.adminAccentPillForeground(colorScheme))
                    .background(
                        ProviderOliveChromeStyle.adminAccentPillFill(colorScheme),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(didCopy ? "Link copied" : "Copy booking link")

                if let bookingURL {
                    ShareLink(item: bookingURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.provider(.subheadline, weight: .semibold))
                            Text("Share")
                                .font(.provider(.subheadline, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.lavaShellCream)
                        .background(
                            Color.white.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var usageTipsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.usageTips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 10) {
                    Text("•")
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                    Text(tip)
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ideas for your booking link")
    }

    private func copyLink(_ urlString: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = urlString
        #endif
        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { didCopy = false }
        }
    }
}
