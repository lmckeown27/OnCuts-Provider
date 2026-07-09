import UIKit
import OnCutsModule

/// Loads a remote profile image into a `UIImageView`, with cancellation for cell reuse.
final class ProviderRemoteAvatarLoader {
    private var task: URLSessionDataTask?

    func load(
        into imageView: UIImageView,
        storedPath: String?,
        fallbackSystemImage: String = "person.fill",
        fallbackTint: UIColor = ProviderChatDesignTokens.Color.previewText
    ) {
        task?.cancel()
        imageView.contentMode = .scaleAspectFill
        imageView.image = UIImage(systemName: fallbackSystemImage)
        imageView.tintColor = fallbackTint

        guard let url = ProviderAvatarURL.resolve(storedPath) else { return }

        task = URLSession.shared.dataTask(with: url) { [weak imageView] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                imageView?.contentMode = .scaleAspectFill
                imageView?.image = image
                imageView?.tintColor = nil
            }
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
