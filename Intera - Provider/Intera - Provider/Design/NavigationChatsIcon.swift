import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Header/navigation chats glyph from the `DM` asset set (light/dark variants in catalog).
struct NavigationChatsIcon: View {
    let unreadCount: Int
    var tint: Color?

    init(unreadCount: Int, tint: Color? = nil) {
        self.unreadCount = unreadCount
        self.tint = tint
    }

    var body: some View {
        Group {
            if let tint {
                Image("DM")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint)
            } else {
                Image("DM")
                    .resizable()
                    .scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }
}

#if canImport(UIKit)
enum NavigationChatsIconAssets {
    static func image(unreadCount: Int) -> UIImage? {
        UIImage(named: "DM")
    }
}
#endif
