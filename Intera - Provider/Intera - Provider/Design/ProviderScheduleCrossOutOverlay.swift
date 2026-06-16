import SwiftUI

struct ProviderScheduleDiagonalCrossOut: View {
    var lineColor: Color = Color.lavaShellCreamSecondary.opacity(0.38)

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 7
            Path { path in
                var x = -proxy.size.height
                while x < proxy.size.width + proxy.size.height {
                    path.move(to: CGPoint(x: x, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: x + proxy.size.height, y: 0))
                    x += spacing
                }
            }
            .stroke(lineColor, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

struct ProviderScheduleEntireDayCrossOutOverlay: View {
    var cornerRadius: CGFloat = 10
    var lineColor: Color = Color.providerOlive.opacity(0.44)

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.providerOlive.opacity(0.06))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.providerOlive.opacity(0.24), lineWidth: 0.5)
            }
            .overlay {
                ProviderScheduleDiagonalCrossOut(lineColor: lineColor)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel("Day blocked off")
    }
}
