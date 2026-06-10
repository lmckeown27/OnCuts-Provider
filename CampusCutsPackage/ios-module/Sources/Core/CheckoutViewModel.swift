import Combine
import Foundation

#if os(iOS)
import StripePaymentSheet
import UIKit
#endif

// MARK: - API client (bookings-simple)

#if os(iOS)
/// Prefer `StripeAPI.defaultPublishableKey` after `StripeService.setPublishableKey` / `configureFromAppBundle`; otherwise Info.plist.
private func resolvedPublishableKeyTrimmed() -> String {
    if let apiKey = StripeAPI.defaultPublishableKey?.trimmingCharacters(in: .whitespacesAndNewlines),
       apiKey.hasPrefix("pk_") {
        return apiKey
    }
    return Bundle.StripeConfig.publishableKey(for: .main).trimmingCharacters(in: .whitespacesAndNewlines)
}
#endif

#if os(iOS)
private enum CreatePaymentIntentAPI {
    private struct Envelope: Decodable, Sendable {
        let success: Bool?
        let data: DataBlock?
    }

    private struct DataBlock: Decodable, Sendable {
        let clientSecret: String?
        let paymentIntentId: String?
        let customerEphemeralKeySecret: String?
        let customerId: String?
        let ephemeralKey: String?
        let ephemeralKeySecret: String?
        let livemode: Bool?
        /// First 20 chars of server `STRIPE_PUBLISHABLE_KEY`; compared to the app key so wrong-dashboard keys fail before PaymentSheet.
        let stripePublishableKeyPrefix: String?

        enum CodingKeys: String, CodingKey {
            case clientSecret
            case paymentIntentId
            case customerEphemeralKeySecret
            case customerId
            case ephemeralKey
            case ephemeralKeySecret
            case livemode
            case stripePublishableKeyPrefix
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret)
            paymentIntentId = try c.decodeIfPresent(String.self, forKey: .paymentIntentId)
            customerEphemeralKeySecret = try c.decodeIfPresent(String.self, forKey: .customerEphemeralKeySecret)
            customerId = try c.decodeIfPresent(String.self, forKey: .customerId)
            ephemeralKey = try c.decodeIfPresent(String.self, forKey: .ephemeralKey)
            ephemeralKeySecret = try c.decodeIfPresent(String.self, forKey: .ephemeralKeySecret)
            livemode = try c.decodeIfPresent(Bool.self, forKey: .livemode)
            stripePublishableKeyPrefix = try c.decodeIfPresent(String.self, forKey: .stripePublishableKeyPrefix)
        }
    }

    static func fetchConfig(
        bookingID: String,
        stripeAccountID: String?,
        tipAmountCents: Int,
        bearerToken: String?,
        apiBaseURLTrimmed: String
    ) async throws -> PaymentConfig {
        let enc = bookingID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingID
        guard let url = URL(string: apiBaseURLTrimmed + "/bookings-simple/\(enc)/create-payment-intent") else {
            throw URLError(.badURL)
        }
        #if DEBUG
        let pkSnap = StripeAPI.defaultPublishableKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sharedSnap = STPAPIClient.shared.publishableKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clip: (String) -> String = { s in
            if s.isEmpty { return "NONE" }
            if s.count >= 14 { return String(s.prefix(14)) + "…" }
            return s
        }
        print(
            "Stripe checkout: create-payment-intent \(url.absoluteString) defaultKey=\(clip(pkSnap)) sharedClientKey=\(clip(sharedSnap)) stripeAccount=\(STPAPIClient.shared.stripeAccount ?? "nil")"
        )
        #endif
        var body: [String: Any] = [:]
        if tipAmountCents > 0 {
            body["tipAmountCents"] = tipAmountCents
        }
        if let sid = stripeAccountID?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
            body["stripeAccountId"] = sid
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await authorizedJSON(url: url, method: "POST", bearerToken: bearerToken, body: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(Envelope.self, from: responseData)
        guard let d = decoded.data,
              let secret = d.clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty
        else {
            throw NSError(
                domain: "CheckoutViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing payment intent client secret."]
            )
        }
        let ek = d.customerEphemeralKeySecret
            ?? d.ephemeralKeySecret
            ?? d.ephemeralKey
        let cust = d.customerId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let piFromJson = d.paymentIntentId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let pi = piFromJson ?? paymentIntentIdFromClientSecret(secret)
        let pk = resolvedPublishableKeyTrimmed()
        if let lm = d.livemode {
            if lm {
                if !pk.hasPrefix("pk_live") {
                    throw NSError(
                        domain: "CheckoutViewModel",
                        code: -2,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "This PaymentIntent is live (Stripe livemode), but the app’s publishable key is not pk_live_…. PaymentSheet would return HTTP 404. Set STRIPE_PUBLISHABLE_KEY in `Config/StripeKeys.xcconfig` (or on the server for GET /api/v1/stripe/client-config), then Product → Clean Build Folder.",
                        ]
                    )
                }
            } else if !pk.hasPrefix("pk_test") {
                throw NSError(
                    domain: "CheckoutViewModel",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "This PaymentIntent is test mode, but the app’s publishable key is not pk_test_…. Use matching Stripe keys for app and API.",
                    ]
                )
            }
        }
        if let serverPkPrefix = d.stripePublishableKeyPrefix?.trimmingCharacters(in: .whitespacesAndNewlines),
           serverPkPrefix.count >= 12,
           pk.hasPrefix("pk_") {
            let localPrefix = String(pk.prefix(serverPkPrefix.count))
            if localPrefix != serverPkPrefix {
                throw NSError(
                    domain: "CheckoutViewModel",
                    code: -3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The app’s Stripe publishable key does not match this API’s STRIPE_PUBLISHABLE_KEY (usually a different Stripe account than STRIPE_SECRET_KEY). PaymentSheet would return HTTP 404. Use the publishable key from the same Dashboard as your live secret, in `Config/StripeKeys.xcconfig`, then Product → Clean Build Folder—or fix the server env.",
                    ]
                )
            }
        }
        return PaymentConfig(
            paymentIntentClientSecret: secret,
            customerEphemeralKeySecret: ek?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            customerId: cust,
            paymentIntentId: pi,
            paymentIntentLivemode: d.livemode
        )
    }

    private static func authorizedJSON(
        url: URL,
        method: String,
        bearerToken: String?,
        body: Data?
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NSError(
                domain: "CheckoutViewModel",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
        return data
    }
}
#endif

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Stripe PaymentIntent client secrets are `pi_…_secret_…`; the id prefix is always present even when the server omits `paymentIntentId` in JSON.
private func paymentIntentIdFromClientSecret(_ clientSecret: String) -> String? {
    let s = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty, let range = s.range(of: "_secret_") else { return nil }
    let prefix = String(s[..<range.lowerBound])
    return prefix.hasPrefix("pi_") ? prefix : nil
}

// MARK: - View model

/// Orchestrates `POST …/create-payment-intent`, builds `PaymentSheet`, and maps `PaymentSheetResult` to `CheckoutDestination`.
@MainActor
public final class CheckoutViewModel: ObservableObject {
    public let merchantDisplayName: String
    public let stripeReturnURL: String

#if os(iOS)
    @Published public private(set) var paymentSheet: PaymentSheet?
    private var standaloneApplePayCoordinator: StandaloneBookingApplePayCoordinator?
#endif
    @Published public private(set) var destination: CheckoutDestination = .idle
    /// Set when the sheet completes successfully — use for server `confirm-payment` if your flow requires it.
    @Published public private(set) var lastCompletedPaymentIntentId: String?

    public init(
        merchantDisplayName: String = "CampusCuts",
        stripeReturnURL: String = "campuscuts://stripe-redirect"
    ) {
        self.merchantDisplayName = merchantDisplayName
        self.stripeReturnURL = stripeReturnURL
    }

    /// Loads PaymentIntent params from the backend, configures PaymentSheet (including Connect / 3DS return URL), and presents the sheet.
#if os(iOS)
    /// - Parameter publishableKeyValidatedByHost: When set (e.g. from `GET …/stripe/client-config` + plist), applied **before** loading the PaymentIntent so livemode checks and PaymentSheet cannot fall back to a stale or plist-only `pk_test_` key.
    /// - Parameter paymentSheetIncludesApplePay: When `false`, PaymentSheet is card-only; use `presentStandaloneApplePay` for Apple Pay.
    public func fetchPaymentParams(
        bookingID: String,
        stripeAccountID: String?,
        tipAmountCents: Int = 0,
        bearerToken: String?,
        apiBaseURLTrimmed: String,
        publishableKeyValidatedByHost: String? = nil,
        paymentSheetIncludesApplePay: Bool = false
    ) async throws -> PaymentConfig {
        destination = .idle
        lastCompletedPaymentIntentId = nil
        paymentSheet = nil
        if let hostKey = publishableKeyValidatedByHost?.trimmingCharacters(in: .whitespacesAndNewlines),
           hostKey.hasPrefix("pk_") {
            StripeService.setPublishableKey(hostKey)
        }
        let config = try await CreatePaymentIntentAPI.fetchConfig(
            bookingID: bookingID,
            stripeAccountID: stripeAccountID,
            tipAmountCents: tipAmountCents,
            bearerToken: bearerToken,
            apiBaseURLTrimmed: apiBaseURLTrimmed
        )
        let pk = resolvedPublishableKeyTrimmed()
        guard pk.hasPrefix("pk_"), !pk.contains("$(") else {
            throw NSError(
                domain: "CheckoutViewModel",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Missing or invalid Stripe publishable key before PaymentSheet."]
            )
        }
        StripeService.setPublishableKey(pk)
        var sheetConfig = PaymentSheet.Configuration()
        // Use a dedicated API client for this sheet so we never read a stale `STPAPIClient.shared._publishableKey`
        // from another feature; keep `stripeAccount` nil because PIs are created on the platform (destination charges).
        let sheetAPIClient = STPAPIClient(publishableKey: pk)
        sheetAPIClient.stripeAccount = nil
        sheetConfig.apiClient = sheetAPIClient
        sheetConfig.merchantDisplayName = merchantDisplayName
        sheetConfig.allowsDelayedPaymentMethods = false
        sheetConfig.returnURL = stripeReturnURL
        // Card (and saved wallet cards) only — hide Link + bank debit in the sheet. Apple Pay uses `presentStandaloneApplePay`.
        sheetConfig.link = PaymentSheet.LinkConfiguration(display: .never)
        sheetConfig.paymentMethodOrder = ["card"]
        if paymentSheetIncludesApplePay,
           let merchantId = Bundle.StripeConfig.applePayMerchantId, !merchantId.isEmpty, !merchantId.contains("$(")
        {
            sheetConfig.applePay = .init(
                merchantId: merchantId,
                merchantCountryCode: Bundle.StripeConfig.applePayMerchantCountryCode
            )
        }
        if let cust = config.customerId,
           let ek = config.customerEphemeralKeySecret, !ek.isEmpty
        {
            sheetConfig.customer = PaymentSheet.CustomerConfiguration(id: cust, ephemeralKeySecret: ek)
        }
        let sheet = PaymentSheet(
            paymentIntentClientSecret: config.paymentIntentClientSecret,
            configuration: sheetConfig
        )
        paymentSheet = sheet
        return config
    }

    /// Presents the sheet prepared by `fetchPaymentParams`. Call from a button handler after `fetchPaymentParams` succeeds.
    public func presentPaymentSheet(
        from presenter: UIViewController,
        paymentConfig: PaymentConfig
    ) {
        guard let sheet = paymentSheet else { return }
        sheet.present(from: presenter) { [weak self] result in
            Task { @MainActor in
                self?.handle(result: result, paymentConfig: paymentConfig)
            }
        }
    }

    private func handle(result: PaymentSheetResult, paymentConfig: PaymentConfig) {
        paymentSheet = nil
        switch result {
        case .completed:
            lastCompletedPaymentIntentId =
                paymentConfig.paymentIntentId
                ?? paymentIntentIdFromClientSecret(paymentConfig.paymentIntentClientSecret)
            destination = .success
        case .canceled:
            destination = .idle
        case .failed(let error):
            destination = .failed(error.localizedDescription)
        }
    }

    /// Presents Stripe’s native Apple Pay sheet (not PaymentSheet). Call after `fetchPaymentParams` succeeds.
    /// - Returns: `false` if Apple Pay isn’t configured, the device can’t pay, or Stripe couldn’t start the sheet.
    @discardableResult
    public func presentStandaloneApplePay(
        from window: UIWindow?,
        paymentConfig: PaymentConfig,
        serviceCents: Int,
        tipCents: Int,
        currencyCode: String = "USD"
    ) -> Bool {
        standaloneApplePayCoordinator = nil
        guard let merchantId = Bundle.StripeConfig.applePayMerchantId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !merchantId.isEmpty,
              !merchantId.contains("$(")
        else {
            return false
        }
        let country = Bundle.StripeConfig.applePayMerchantCountryCode
        let coord = StandaloneBookingApplePayCoordinator(
            clientSecret: paymentConfig.paymentIntentClientSecret,
            merchantDisplayName: merchantDisplayName,
            serviceCents: serviceCents,
            tipCents: tipCents,
            currencyCode: currencyCode.uppercased(),
            applePayMerchantId: merchantId,
            applePayCountryCode: country
        ) { [weak self] status, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.standaloneApplePayCoordinator = nil
                switch status {
                case .success:
                    self.lastCompletedPaymentIntentId =
                        paymentConfig.paymentIntentId
                        ?? paymentIntentIdFromClientSecret(paymentConfig.paymentIntentClientSecret)
                    self.destination = .success
                case .userCancellation:
                    self.destination = .idle
                case .error:
                    let msg = error?.localizedDescription ?? "Apple Pay couldn’t complete this payment."
                    self.destination = .failed(msg)
                }
            }
        }
        guard coord.present(from: window) else {
            return false
        }
        standaloneApplePayCoordinator = coord
        return true
    }

#else
    public func fetchPaymentParams(
        bookingID: String,
        stripeAccountID: String?,
        tipAmountCents: Int = 0,
        bearerToken: String?,
        apiBaseURLTrimmed: String,
        publishableKeyValidatedByHost: String? = nil,
        paymentSheetIncludesApplePay: Bool = false
    ) async throws -> PaymentConfig {
        throw NSError(
            domain: "CheckoutViewModel",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "In-app Stripe checkout is only available on iOS."]
        )
    }

    public func presentPaymentSheet(from presenter: Any, paymentConfig: PaymentConfig) {}
#endif

    public func resetNavigation() {
        destination = .idle
    }
}
