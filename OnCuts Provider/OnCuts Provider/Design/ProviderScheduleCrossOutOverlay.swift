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

struct ProviderScheduleCrossOutOverlay: View {
    var cornerRadius: CGFloat = 0
    var showsBorder: Bool = false
    var lineColor: Color = Color.providerScheduleEntireDayCrossOutLine

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.providerScheduleEntireDayCrossOutFill)
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.providerScheduleEntireDayCrossOutStroke, lineWidth: 0.5)
                }
            }
            .overlay {
                ProviderScheduleDiagonalCrossOut(lineColor: lineColor)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct ProviderScheduleEntireDayCrossOutOverlay: View {
    var cornerRadius: CGFloat = 10
    var lineColor: Color = Color.providerScheduleEntireDayCrossOutLine

    var body: some View {
        ProviderScheduleCrossOutOverlay(
            cornerRadius: cornerRadius,
            showsBorder: true,
            lineColor: lineColor
        )
        .accessibilityLabel("Day blocked off")
    }
}
