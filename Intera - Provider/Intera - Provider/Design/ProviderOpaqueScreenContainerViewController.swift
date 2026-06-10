#if os(iOS)
import UIKit

/// Wraps a child view controller in a full-screen opaque fill. Use for UIKit screens hosted in
/// SwiftUI `NavigationStack` so the root hub lava never shows through the bottom safe area.
final class ProviderOpaqueScreenContainerViewController: UIViewController {
    private let content: UIViewController
    private let fillColor: UIColor

    init(content: UIViewController, fillColor: UIColor) {
        self.content = content
        self.fillColor = fillColor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = fillColor

        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        content.didMove(toParent: self)
    }
}
#endif
