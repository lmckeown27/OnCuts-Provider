import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Header/navigation chats glyph from the `DM` asset set (light/dark variants in catalog).
struct NavigationChatsIcon: View {
    let unreadCount: Int

    var body: some View {
        Image("DM")
            .resizable()
            .scaledToFit()
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
