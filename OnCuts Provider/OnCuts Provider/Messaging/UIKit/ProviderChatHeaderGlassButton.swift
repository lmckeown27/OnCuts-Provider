import UIKit

/// Circular frosted-glass header control matching the Messages shell toolbar (ultra-thin material + adaptive icon tint).
final class ProviderChatHeaderGlassButton: UIButton {
    static let diameter: CGFloat = 36

    private let symbolName: String

    init(symbolName: String) {
        self.symbolName = symbolName
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyConfiguration()

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyConfiguration()
    }

    private func applyConfiguration() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)

        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.image = image
        buttonConfig.baseForegroundColor = ProviderAppearance.primaryText
        buttonConfig.cornerStyle = .capsule
        buttonConfig.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        buttonConfig.background.strokeWidth = 0.5
        buttonConfig.background.strokeColor = ProviderAppearance.scheduleControlStroke
        buttonConfig.background.backgroundColor = Self.chromeFillColor(for: traitCollection)
        buttonConfig.contentInsets = .zero
        configuration = buttonConfig
    }

    private static func chromeFillColor(for traits: UITraitCollection) -> UIColor {
        ProviderAppearance.scheduleControlFill
            .resolvedColor(with: traits)
            .withAlphaComponent(0.55)
    }
}
