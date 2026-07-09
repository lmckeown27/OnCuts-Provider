import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Header/navigation inbox glyph that switches between the empty and filled asset sets.
struct NavigationInboxIcon: View {
    let unreadCount: Int
    var tint: Color?

    init(unreadCount: Int, tint: Color? = nil) {
        self.unreadCount = unreadCount
        self.tint = tint
    }

    private var assetName: String {
        unreadCount > 0 ? "Filled Inbox" : "Empty Inbox"
    }

    var body: some View {
        Group {
            if let tint {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint)
            } else {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }
}

#if canImport(UIKit)
enum NavigationInboxIconAssets {
    static func image(unreadCount: Int) -> UIImage? {
        UIImage(named: unreadCount > 0 ? "Filled Inbox" : "Empty Inbox")
    }
}
#endif
