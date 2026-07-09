import Foundation

/// Server response used to configure Stripe PaymentSheet (PaymentIntent + optional Customer for saved payment methods).
public struct PaymentConfig: Sendable, Equatable {
    public let paymentIntentClientSecret: String
    public let customerEphemeralKeySecret: String?
    public let customerId: String?
    public let paymentIntentId: String?
    /// From `POST …/create-payment-intent` when the server includes it; use to match `pk_live_` vs `pk_test_`.
    public let paymentIntentLivemode: Bool?

    public init(
        paymentIntentClientSecret: String,
        customerEphemeralKeySecret: String? = nil,
        customerId: String? = nil,
        paymentIntentId: String? = nil,
        paymentIntentLivemode: Bool? = nil
    ) {
        self.paymentIntentClientSecret = paymentIntentClientSecret
        self.customerEphemeralKeySecret = customerEphemeralKeySecret
        self.customerId = customerId
        self.paymentIntentId = paymentIntentId
        self.paymentIntentLivemode = paymentIntentLivemode
    }
}

/// UI routing after PaymentSheet finishes (SwiftUI / UIKit hosts observe this).
public enum CheckoutDestination: Equatable, Sendable {
    case idle
    case success
    case failed(String)
}
