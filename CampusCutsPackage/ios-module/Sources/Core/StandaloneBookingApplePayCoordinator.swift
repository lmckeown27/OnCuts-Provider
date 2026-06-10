#if os(iOS)
import Foundation
import PassKit
import StripeApplePay
import StripeCore
import UIKit

/// Retained by `CheckoutViewModel` while Apple Pay is active. `STPApplePayContext` holds its delegate weakly.
final class StandaloneBookingApplePayCoordinator: NSObject, ApplePayContextDelegate {
    private let clientSecret: String
    private let merchantDisplayName: String
    private let serviceCents: Int
    private let tipCents: Int
    private let currencyCode: String
    private let applePayMerchantId: String
    private let applePayCountryCode: String
    private let onComplete: (STPApplePayContext.PaymentStatus, Error?) -> Void

    private var applePayContext: STPApplePayContext?

    init(
        clientSecret: String,
        merchantDisplayName: String,
        serviceCents: Int,
        tipCents: Int,
        currencyCode: String,
        applePayMerchantId: String,
        applePayCountryCode: String,
        onComplete: @escaping (STPApplePayContext.PaymentStatus, Error?) -> Void
    ) {
        self.clientSecret = clientSecret
        self.merchantDisplayName = merchantDisplayName
        self.serviceCents = serviceCents
        self.tipCents = tipCents
        self.currencyCode = currencyCode
        self.applePayMerchantId = applePayMerchantId
        self.applePayCountryCode = applePayCountryCode
        self.onComplete = onComplete
        super.init()
    }

    /// - Returns: `false` if Apple Pay cannot be started (device, parental controls, or invalid request).
    func present(from window: UIWindow?) -> Bool {
        let request = StripeAPI.paymentRequest(
            withMerchantIdentifier: applePayMerchantId,
            country: applePayCountryCode,
            currency: currencyCode
        )
        request.paymentSummaryItems = Self.summaryItems(
            merchantLabel: merchantDisplayName,
            serviceCents: serviceCents,
            tipCents: tipCents
        )
        guard let context = STPApplePayContext(paymentRequest: request, delegate: self) else {
            return false
        }
        applePayContext = context
        context.presentApplePay(from: window, completion: nil)
        return true
    }

    func applePayContext(
        _ context: STPApplePayContext,
        didCreatePaymentMethod paymentMethod: StripeAPI.PaymentMethod,
        paymentInformation: PKPayment,
        completion: @escaping STPIntentClientSecretCompletionBlock
    ) {
        completion(clientSecret, nil)
    }

    func applePayContext(
        _ context: STPApplePayContext,
        didCompleteWith status: STPApplePayContext.PaymentStatus,
        error: Error?
    ) {
        applePayContext = nil
        onComplete(status, error)
    }

    private static func summaryItems(
        merchantLabel: String,
        serviceCents: Int,
        tipCents: Int
    ) -> [PKPaymentSummaryItem] {
        func amount(_ cents: Int) -> NSDecimalNumber {
            NSDecimalNumber(value: Double(cents) / 100.0)
        }
        var items: [PKPaymentSummaryItem] = []
        items.append(PKPaymentSummaryItem(label: "Service", amount: amount(serviceCents), type: .final))
        if tipCents > 0 {
            items.append(PKPaymentSummaryItem(label: "Tip", amount: amount(tipCents), type: .final))
        }
        let total = serviceCents + tipCents
        items.append(PKPaymentSummaryItem(label: merchantLabel, amount: amount(total), type: .final))
        return items
    }
}
#endif
