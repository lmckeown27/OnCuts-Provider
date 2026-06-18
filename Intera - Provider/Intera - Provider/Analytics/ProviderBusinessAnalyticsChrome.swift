import SwiftUI

enum ProviderAnalyticsFormatting {
    static func currency(cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "USD"))
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

struct ProviderAnalyticsMonospacedValue: ViewModifier {
    func body(content: Content) -> some View {
        content.monospacedDigit()
    }
}

extension View {
    func providerAnalyticsMonospacedValue() -> some View {
        modifier(ProviderAnalyticsMonospacedValue())
    }
}

struct ProviderAnalyticsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.provider(.subheadline, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.provider(.caption))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                )
        )
    }
}

struct ProviderAnalyticsScalePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
