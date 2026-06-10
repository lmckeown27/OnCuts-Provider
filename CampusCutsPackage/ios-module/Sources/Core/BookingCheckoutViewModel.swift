import Combine
import Foundation

#if os(iOS)
import StripePaymentSheet
import SwiftUI

/// Drives `StripeManager` + `PaymentSheet` for native checkout; prevents a second charge after success.
@MainActor
public final class BookingCheckoutViewModel: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case loading
        case ready
        case bookingConfirmed
        case failed(String)
    }

    private let stripeManager: StripeManager
    private let apiBaseURLTrimmed: String
    private let bookingId: String
    /// Total for display and for `StripeManager` (`amount` in JSON).
    public let amountCents: Int
    private let stripeAccountId: String
    private let bearerToken: String?
    private let applePayMerchantId: String?
    private let applePayCountryCode: String
    private let merchantDisplayName: String
    private let stripeReturnURL: String

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var paymentSheet: PaymentSheet?
    @Published public var isPresentingPaymentSheet = false
    /// After a successful sheet completion — do not present checkout again.
    @Published public private(set) var hasCompletedPayment = false

    public init(
        apiBaseURLTrimmed: String,
        bookingId: String,
        amountCents: Int,
        stripeAccountId: String,
        bearerToken: String?,
        stripeManager: StripeManager = StripeManager(),
        applePayMerchantId: String? = nil,
        applePayCountryCode: String? = nil,
        merchantDisplayName: String = "CampusCuts",
        stripeReturnURL: String = "campuscuts://stripe-redirect"
    ) {
        self.apiBaseURLTrimmed = trimApiBaseURL(apiBaseURLTrimmed)
        self.bookingId = bookingId
        self.amountCents = amountCents
        self.stripeAccountId = stripeAccountId
        self.bearerToken = bearerToken
        self.stripeManager = stripeManager
        self.applePayMerchantId = applePayMerchantId ?? Bundle.StripeConfig.applePayMerchantId
        self.applePayCountryCode = applePayCountryCode ?? Bundle.StripeConfig.applePayMerchantCountryCode
        self.merchantDisplayName = merchantDisplayName
        self.stripeReturnURL = stripeReturnURL
    }

    /// Loads client secrets via `StripeManager` and builds `PaymentSheet` (Apple Pay when merchant ID is set).
    public func loadPaymentSession() async {
        guard !hasCompletedPayment else { return }
        if phase == .ready, paymentSheet != nil { return }
        guard Bundle.StripeConfig.isPublishableKeyConfigured else {
            phase = .failed("Missing or invalid Stripe publishable key in Info.plist.")
            return
        }
        StripeService.setPublishableKey(Bundle.StripeConfig.publishableKey)
        phase = .loading
        paymentSheet = nil
        let result = await stripeManager.createPaymentIntent(
            apiBaseURLTrimmed: apiBaseURLTrimmed,
            bookingId: bookingId,
            amountCents: amountCents,
            stripeAccountId: stripeAccountId,
            bearerToken: bearerToken
        )
        switch result {
        case .success(let config):
            var sheetConfiguration = PaymentSheet.Configuration()
            sheetConfiguration.merchantDisplayName = merchantDisplayName
            sheetConfiguration.returnURL = stripeReturnURL
            sheetConfiguration.allowsDelayedPaymentMethods = false
            if let cust = config.customerId,
               let ek = config.customerEphemeralKeySecret, !ek.isEmpty
            {
                sheetConfiguration.customer = PaymentSheet.CustomerConfiguration(
                    id: cust,
                    ephemeralKeySecret: ek
                )
            }
            if let mid = applePayMerchantId, !mid.isEmpty {
                sheetConfiguration.applePay = .init(
                    merchantId: mid,
                    merchantCountryCode: applePayCountryCode
                )
            }
            let sheet = PaymentSheet(
                paymentIntentClientSecret: config.paymentIntentClientSecret,
                configuration: sheetConfiguration
            )
            paymentSheet = sheet
            phase = .ready
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
    }

    public func handlePaymentSheetResult(_ result: PaymentSheetResult) {
        isPresentingPaymentSheet = false
        switch result {
        case .completed:
            hasCompletedPayment = true
            paymentSheet = nil
            phase = .bookingConfirmed
        case .canceled:
            if !hasCompletedPayment {
                phase = paymentSheet != nil ? .ready : .idle
            }
        case .failed(let error):
            phase = .failed(error.localizedDescription)
        }
    }
}

private func trimApiBaseURL(_ raw: String) -> String {
    raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}

#endif
