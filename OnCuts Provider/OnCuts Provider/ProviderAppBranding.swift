import Foundation

/// Central OnCuts Provider product identity (mirrors consumer `AppBranding`).
enum ProviderAppBranding {
    static let displayName = "OnCuts Provider"
    static let shortName = "OnCuts"

    static let marketingSiteHost = "oncuts.com"

    static let bundleIdentifier = "com.oncutsprovider.app"

    static let applePayMerchantIdentifier = "merchant.com.oncuts"

    static let loggerSubsystem = "com.oncutsprovider.app"

    static var termsOfServiceURL: URL {
        URL(string: "https://\(marketingSiteHost)/terms")!
    }

    static var privacyPolicyURL: URL {
        URL(string: "https://\(marketingSiteHost)/privacy")!
    }

    enum UserDefaultsKey {
        static let pushAPNsHexToken = "com.oncutsprovider.app.push.apnsHexToken"
        static let pushLastRegisteredToken = "com.oncutsprovider.app.push.lastRegisteredToken"
        static let pushLastRegisteredJWTFingerprint = "com.oncutsprovider.app.push.lastRegisteredJWTFingerprint"
        static let pushLastRegisteredAt = "com.oncutsprovider.app.push.lastRegisteredAt"
        static let pushLogoutSince = "com.oncutsprovider.app.push.logoutSince"

        static let appleSignInSupplementEmail = "com.oncutsprovider.app.apple-sign-in.supplement.email"
        static let appleSignInSupplementFirstName = "com.oncutsprovider.app.apple-sign-in.supplement.firstName"
        static let appleSignInSupplementLastName = "com.oncutsprovider.app.apple-sign-in.supplement.lastName"
    }

    /// Wire payload names shared with the consumer app until backend routing is renamed.
    /// Intentionally still `InteraOpen*` so existing APNs payloads keep working.
    enum PushRoutingPayload {
        static let openMessagingConversation = "InteraOpenMessagingConversation"
        static let openBookingDetail = "InteraOpenBookingDetail"
        static let openRequestsInbox = "InteraOpenRequestsInbox"
    }
}
