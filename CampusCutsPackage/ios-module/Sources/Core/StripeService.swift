import Foundation

#if canImport(StripePaymentSheet)
import StripePaymentSheet
#endif

/// Stripe SDK bootstrap — publishable key must be in the app Info.plist as `StripePublishableKey`
/// (e.g. injected via xcconfig at build time). Same as `Bundle.main.infoDictionary?["StripePublishableKey"]`.
public enum StripeService {
    /// Call once at launch with your API root (e.g. `https://campuscut.com/api/v1`). When the host is production
    /// CampusCuts, a bundled `pk_test_…` or an unresolved `$(STRIPE_PUBLISHABLE_KEY)` is **not** applied, so the SDK
    /// never enters the wrong Stripe mode before checkout (avoids live PI + test key 404s).
    public static func applyPublishableKeyAlignedWithAPIHost(apiRootTrimmed: String, bundle: Bundle = .main) {
        #if canImport(StripePaymentSheet)
        let root = apiRootTrimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        let isProductionCampusCuts = root.lowercased().contains("campuscut.com")
        let raw = Bundle.StripeConfig.publishableKey(for: bundle).trimmingCharacters(in: .whitespacesAndNewlines)
        let looksUnresolved = raw.contains("$(") || raw.contains("${")

        if isProductionCampusCuts {
            guard raw.hasPrefix("pk_live"), !looksUnresolved else {
                #if DEBUG
                if looksUnresolved {
                    print("Stripe: production API host but StripePublishableKey looks unresolved (xcconfig → plist). Clean Build Folder.")
                } else if raw.hasPrefix("pk_test") {
                    print("Stripe: production API host but bundle has pk_test — not applying (use pk_live or client-config at checkout).")
                } else if !raw.isEmpty {
                    print("Stripe: production API host but bundle key is not pk_live — not applying.")
                }
                #endif
                return
            }
            setPublishableKey(raw)
            return
        }

        configureFromAppBundle(bundle: bundle)
        #endif
    }

    /// Reads `StripePublishableKey` from `bundle` and sets `StripeAPI.defaultPublishableKey`.
    public static func configureFromAppBundle(bundle: Bundle = .main) {
        #if canImport(StripePaymentSheet)
        let pk = Bundle.StripeConfig.publishableKey(for: bundle)
        guard !pk.isEmpty, pk.hasPrefix("pk_"), !pk.contains("$(") else { return }
        StripeAPI.defaultPublishableKey = pk
        STPAPIClient.shared.stripeAccount = nil
        STPAPIClient.shared.publishableKey = pk
        #endif
    }

    /// Applies a publishable key from app code (e.g. `AppConfiguration`) when it is **not** the same as Info.plist — PaymentSheet uses `STPAPIClient.shared` by default, which **caches** `publishableKey` separately from `StripeAPI.defaultPublishableKey`, so both must stay in sync to avoid live PI + wrong-key 404s.
    public static func setPublishableKey(_ key: String) {
        #if canImport(StripePaymentSheet)
        let pk = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pk.hasPrefix("pk_"), !pk.contains("$(") else { return }
        StripeAPI.defaultPublishableKey = pk
        // `STPAPIClient.shared.publishableKey` returns `_publishableKey` when set, ignoring `StripeAPI.defaultPublishableKey`.
        STPAPIClient.shared.stripeAccount = nil
        STPAPIClient.shared.publishableKey = pk
        #endif
    }

    /// Forward Stripe 3DS / redirect return URLs (matches `PaymentSheet.Configuration.returnURL`).
    @discardableResult
    public static func handleURLCallback(_ url: URL) -> Bool {
        #if canImport(StripePaymentSheet)
        return StripeAPI.handleURLCallback(with: url)
        #else
        return false
        #endif
    }
}
