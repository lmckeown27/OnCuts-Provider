import Foundation

/// Seeds and tag vocabulary for `ProfileEditViewController` (aligned with web barber profile).
enum ProfileEditDefaults {
    /// Demo asset from product spec; superseded when `BarberMeProfile` has `profilePictureUrl`.
    static let fallbackAvatarURL = URL(string: "https://campuscut-images.s3.us-west-1.amazonaws.com/3e838edb-84b8-440a-85c5-4637f8c335d2-1774914520171.webp")!

    static let selectedSpecialties: [String] = [
        "Buzz Cut", "Line Up", "Haircut", "Taper", "Fade", "Mullet", "Afro Textures",
    ]

    static let unselectedSpecialties: [String] = [
        "Beard Trim", "Hot Shave", "Kids Cut", "Haircut & Fade", "Design/Art",
        "Women's Cut", "Color Treatment", "Perm",
    ]

    static var allSpecialtiesOrdered: [String] { selectedSpecialties + unselectedSpecialties }

    static let bioCharacterLimit = 500
    static let displayNameCharacterLimit = 50
}

struct ProfileEditDraft {
    var displayName: String
    var bio: String
    var instagramUsername: String
    var hideFromConsumers: Bool
    var selectedSpecialties: Set<String>
}

struct ProfileEditInitialState {
    var userId: String
    /// When `true`, the user has no CampusCuts password (typical Sign in with Apple) and may delete after device auth.
    var canDeleteWithoutPassword: Bool
    var barberId: String?
    var avatarURL: URL
    var displayName: String
    var bio: String
    var instagramUsername: String
    var hideFromConsumers: Bool
    var selectedSpecialties: Set<String>

    @MainActor
    init(session: ProviderSession) {
        userId = session.authUser?.id ?? ""
        canDeleteWithoutPassword = session.authUser?.needsPlatformPassword == true
        barberId = session.barberProfile?.id
        let barber = session.barberProfile
        avatarURL = barber?.avatarURL ?? ProfileEditDefaults.fallbackAvatarURL

        // Prefer barber card name; if the API returns only empty strings, fall back to session display name.
        let fromBarber = (barber?.resolvedDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fromSession = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = fromBarber.isEmpty ? fromSession : fromBarber

        let b = barber?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        bio = b.isEmpty ? "Really good at haircuts" : b

        instagramUsername = barber?.instagramHandle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        hideFromConsumers = barber?.isHidden == true

        var tags = Set(ProfileEditDefaults.selectedSpecialties)
        if let remote = barber?.specialties {
            for s in remote { tags.insert(s) }
        }
        selectedSpecialties = tags
    }
}
