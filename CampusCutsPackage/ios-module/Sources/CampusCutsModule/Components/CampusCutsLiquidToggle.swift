import SwiftUI

/// Frosted consent control for legal steps; matches OnCuts liquid-glass surfaces.
/// Uses an explicit `Button` instead of `Toggle` so taps are not disrupted by window-level
/// gesture recognizers (which often fail to classify SwiftUI `UISwitch` views as `UIControl`).
public struct CampusCutsLiquidToggle: View {
    @Binding private var isOn: Bool
    private let title: String

    public init(isOn: Binding<Bool>, title: String) {
        self._isOn = isOn
        self.title = title
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Accepted" : "Not accepted")
        .accessibilityAddTraits(.isButton)
    }
}
