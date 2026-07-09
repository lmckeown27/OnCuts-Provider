import SwiftUI

/// Shared squared avatar styling — matches the Account page profile photo treatment.
enum ProviderSquaredAvatarMetrics {
    /// Account page profile header size.
    static let profileSize: CGFloat = 120
    /// Account page profile corner radius.
    static let profileCornerRadius: CGFloat = 14

    static func cornerRadius(for size: CGFloat) -> CGFloat {
        size * (profileCornerRadius / profileSize)
    }
}

/// Uniform squared profile image with proportional rounded corners and center crop.
struct ProviderSquaredAvatarView: View {
    let url: URL?
    let fallbackName: String
    let size: CGFloat

    private var cornerRadius: CGFloat {
        ProviderSquaredAvatarMetrics.cornerRadius(for: size)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.12))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.lavaShellCream.opacity(0.3), lineWidth: 0.6)
        )
    }

    private var initialsView: some View {
        Text(initials(fallbackName))
            .font(initialsFont)
            .foregroundStyle(Color.lavaShellCream)
    }

    private var initialsFont: Font {
        switch size {
        case 100...:
            return .provider(.title3, weight: .bold)
        case 48..<100:
            return .provider(.headline, weight: .bold)
        default:
            return .provider(.caption, weight: .bold)
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let chars = parts.prefix(2).compactMap { $0.first.map(String.init) }
        let joined = chars.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }
}

/// Async circular avatar with initials fallback — used across bookings, admin, and campus views.
struct AvatarView: View {
    let url: URL?
    let fallbackName: String
    var size: CGFloat? = nil

    var body: some View {
        avatarStack
            .modifier(FixedAvatarSizeModifier(size: size))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.lavaShellCream.opacity(0.3), lineWidth: 0.6))
    }

    private var avatarStack: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
    }

    private var initialsView: some View {
        Text(initials(fallbackName))
            .font(.provider(.caption, weight: .bold))
            .foregroundStyle(Color.lavaShellCream)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let chars = parts.prefix(2).compactMap { $0.first.map(String.init) }
        let joined = chars.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }
}

private struct FixedAvatarSizeModifier: ViewModifier {
    let size: CGFloat?

    func body(content: Content) -> some View {
        if let size {
            content.frame(width: size, height: size)
        } else {
            content
        }
    }
}
