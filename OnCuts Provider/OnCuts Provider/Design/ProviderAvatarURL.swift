import Foundation
import OnCutsModule

/// Resolves stored avatar paths (S3 keys or full HTTPS URLs) for remote image loading.
enum ProviderAvatarURL {
    static func resolve(_ storedPath: String?) -> URL? {
        OnCutsS3ImageURL.url(forStoredPath: storedPath)
    }
}

extension SimpleBookingDTO {
    var consumerAvatarURL: URL? {
        ProviderAvatarURL.resolve(consumer?.avatar)
    }
}

extension SimpleBookingConsumer {
    var avatarURL: URL? {
        ProviderAvatarURL.resolve(avatar)
    }
}

extension AdminBarberBookingDTO {
    var consumerAvatarURL: URL? {
        ProviderAvatarURL.resolve(consumerAvatar)
    }
}

extension ConversationOtherUser {
    var avatarURL: URL? {
        ProviderAvatarURL.resolve(profilePicture)
    }
}
