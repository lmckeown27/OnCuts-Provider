import Foundation

/// Central OnCuts Provider product identity (mirrors consumer `AppBranding`).
enum ProviderAppBranding {
    static let displayName = "OnCuts Provider"
    static let shortName = "OnCuts"

    static let marketingSiteHost = "pismoplatforms.com"

    /// Platform bundle ID — unchanged until Apple Developer cutover.
    static let bundleIdentifier = "Liam.Intera---Provider"

    static let loggerSubsystem = "com.oncuts.provider"

    static var termsOfServiceURL: URL {
        URL(string: "https://\(marketingSiteHost)/terms")!
    }

    static var privacyPolicyURL: URL {
        URL(string: "https://\(marketingSiteHost)/privacy")!
    }

    enum UserDefaultsKey {
        static let pushAPNsHexToken = "com.oncuts.provider.push.apnsHexToken"
        static let pushLastRegisteredToken = "com.oncuts.provider.push.lastRegisteredToken"
        static let pushLastRegisteredJWTFingerprint = "com.oncuts.provider.push.lastRegisteredJWTFingerprint"
        static let pushLastRegisteredAt = "com.oncuts.provider.push.lastRegisteredAt"
        static let pushLogoutSince = "com.oncuts.provider.push.logoutSince"

        static let appleSignInSupplementEmail = "com.oncuts.provider.apple-sign-in.supplement.email"
        static let appleSignInSupplementFirstName = "com.oncuts.provider.apple-sign-in.supplement.firstName"
        static let appleSignInSupplementLastName = "com.oncuts.provider.apple-sign-in.supplement.lastName"
    }

    /// Wire payload names shared with the consumer app until backend routing is renamed.
    enum PushRoutingPayload {
        static let openMessagingConversation = "InteraOpenMessagingConversation"
        static let openBookingDetail = "InteraOpenBookingDetail"
        static let openRequestsInbox = "InteraOpenRequestsInbox"
    }
}
