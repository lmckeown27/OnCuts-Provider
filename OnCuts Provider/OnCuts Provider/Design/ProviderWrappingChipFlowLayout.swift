import SwiftUI

/// Left-to-right chip flow that wraps to the next row when a tag no longer fits.
struct ProviderWrappingChipFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let maxWidth = proposal.width ?? .infinity
        let frames = arrangedFrames(maxWidth: maxWidth, subviews: subviews)
        let contentWidth = frames.map(\.maxX).max() ?? 0
        let contentHeight = frames.map(\.maxY).max() ?? 0
        return CGSize(
            width: proposal.width ?? contentWidth,
            height: contentHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrangedFrames(maxWidth: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private struct ArrangedFrame {
        var minX: CGFloat
        var minY: CGFloat
        var width: CGFloat
        var height: CGFloat

        var maxX: CGFloat { minX + width }
        var maxY: CGFloat { minY + height }
    }

    private func arrangedFrames(maxWidth: CGFloat, subviews: Subviews) -> [ArrangedFrame] {
        var frames: [ArrangedFrame] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            var available = max(0, maxWidth - x)
            let intrinsic = subview.sizeThatFits(.unspecified)

            if x > 0, intrinsic.width > available {
                y += rowHeight + verticalSpacing
                x = 0
                rowHeight = 0
                available = maxWidth
            }

            let measureWidth = min(intrinsic.width, available)
            let size = subview.sizeThatFits(ProposedViewSize(width: measureWidth, height: nil))

            frames.append(ArrangedFrame(minX: x, minY: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }

        return frames
    }
}
