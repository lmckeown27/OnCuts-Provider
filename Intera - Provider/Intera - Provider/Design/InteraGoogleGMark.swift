import SwiftUI

/// Standard Google multicolor “G” from the **`GoogleGLogo`** asset (product icon set from Google’s `gstatic` branding).
struct InteraGoogleGMark: View {
    var size: CGFloat = 20

    var body: some View {
        Image("GoogleGLogo")
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
