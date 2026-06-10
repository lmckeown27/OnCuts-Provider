import Foundation

public extension Bundle {
    /// Stripe keys and flags read from Info.plist (typically populated via xcconfig / build settings).
    enum StripeConfig {
        /// `StripePublishableKey` — map from `$(STRIPE_PUBLISHABLE_KEY)` in Info.plist / build settings.
        public static func publishableKey(for bundle: Bundle = .main) -> String {
            keyString(forInfoPlistKey: "StripePublishableKey", bundle: bundle)
        }

        /// Convenience for the main bundle (same as `Bundle.main.infoDictionary` lookup).
        public static var publishableKey: String {
            publishableKey(for: .main)
        }

        /// Apple Pay merchant ID (`merchant.…`) if present — `StripeApplePayMerchantId` in Info.plist.
        public static func applePayMerchantId(for bundle: Bundle = .main) -> String? {
            let s = keyString(forInfoPlistKey: "StripeApplePayMerchantId", bundle: bundle)
            return s.isEmpty ? nil : s
        }

        public static var applePayMerchantId: String? {
            applePayMerchantId(for: .main)
        }

        /// Two-letter country for Apple Pay (default `US` when unset/invalid).
        public static func applePayMerchantCountryCode(for bundle: Bundle = .main) -> String {
            let s = keyString(forInfoPlistKey: "StripeApplePayMerchantCountryCode", bundle: bundle)
            return s.count == 2 ? s.uppercased() : "US"
        }

        public static var applePayMerchantCountryCode: String {
            applePayMerchantCountryCode(for: .main)
        }

        public static func isPublishableKeyConfigured(for bundle: Bundle = .main) -> Bool {
            let pk = publishableKey(for: bundle)
            return pk.hasPrefix("pk_")
                && !pk.contains("$(")
                && !pk.contains("NOT_CONFIGURED")
                && !pk.contains("REPLACE")
        }

        public static var isPublishableKeyConfigured: Bool {
            isPublishableKeyConfigured(for: .main)
        }

        private static func keyString(forInfoPlistKey key: String, bundle: Bundle) -> String {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else {
                return ""
            }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
