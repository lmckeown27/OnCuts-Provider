import SwiftUI

/// Async circular avatar with initials fallback — used across bookings, admin, and campus views.
struct AvatarView: View {
    let url: URL?
    let fallbackName: String

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.lavaShellCream.opacity(0.3), lineWidth: 0.6))
    }

    private var initialsView: some View {
        Text(initials(fallbackName))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.lavaShellCream)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let chars = parts.prefix(2).compactMap { $0.first.map(String.init) }
        let joined = chars.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }
}
