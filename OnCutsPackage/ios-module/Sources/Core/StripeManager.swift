import Foundation

/// Calls `POST …/create-payment-intent` with a JSON body for Stripe Connect checkout.
public final class StripeManager: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Must match `POST /api/v1/bookings-simple/:id/create-payment-intent` (booking id is interpolated when calling).
        public var createPaymentIntentPathTemplate: String

        public init(createPaymentIntentPathTemplate: String = "/bookings-simple/%@/create-payment-intent") {
            self.createPaymentIntentPathTemplate = createPaymentIntentPathTemplate
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// POST body: `tipAmountCents` (optional), `stripeAccountId` (optional). Server derives amount from the booking.
    /// Response `data`: `clientSecret` (or `paymentIntent`), optional `customerEphemeralKeySecret` / `ephemeralKey`, `customerId` / `customer`.
    public func createPaymentIntent(
        apiBaseURLTrimmed: String,
        bookingId: String,
        amountCents: Int,
        stripeAccountId: String,
        bearerToken: String?
    ) async -> Result<PaymentConfig, Error> {
        let trimmed = apiBaseURLTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        let path = String(format: configuration.createPaymentIntentPathTemplate, enc)
        let pathNormalized = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: trimmed + pathNormalized) else {
            return .failure(URLError(.badURL))
        }
        var body: [String: Any] = [:]
        if amountCents > 0 {
            body["tipAmountCents"] = amountCents
        }
        let sid = stripeAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sid.isEmpty {
            body["stripeAccountId"] = sid
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let responseData = try await Self.authorizedPOST(url: url, bearerToken: bearerToken, body: data)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let envelope = try decoder.decode(CreateIntentEnvelope.self, from: responseData)
            let payload = envelope.payload
            let secret = payload.clientSecret ?? payload.paymentIntent
            guard let pi = secret?.trimmingCharacters(in: .whitespacesAndNewlines), !pi.isEmpty else {
                return .failure(
                    NSError(
                        domain: "StripeManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing clientSecret or paymentIntent in response."]
                    )
                )
            }
            let ek = (payload.customerEphemeralKeySecret ?? payload.ephemeralKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let cus = (payload.customerId ?? payload.customer)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let piid = payload.paymentIntentId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let config = PaymentConfig(
                paymentIntentClientSecret: pi,
                customerEphemeralKeySecret: ek,
                customerId: cus,
                paymentIntentId: piid ?? paymentIntentIdFromClientSecret(pi),
                paymentIntentLivemode: nil
            )
            return .success(config)
        } catch {
            return .failure(error)
        }
    }

    private static func authorizedPOST(url: URL, bearerToken: String?, body: Data) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
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
            throw NSError(domain: "StripeManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return data
    }
}

private struct CreateIntentEnvelope: Decodable {
    let success: Bool?
    let data: Payload?
    let paymentIntent: String?
    let clientSecret: String?
    let ephemeralKey: String?
    let customerEphemeralKeySecret: String?
    let customer: String?
    let customerId: String?
    let paymentIntentId: String?

    struct Payload: Decodable {
        let paymentIntent: String?
        let clientSecret: String?
        let ephemeralKey: String?
        let customerEphemeralKeySecret: String?
        let customer: String?
        let customerId: String?
        let paymentIntentId: String?
    }

    var payload: Payload {
        if let data {
            return data
        }
        return Payload(
            paymentIntent: paymentIntent,
            clientSecret: clientSecret,
            ephemeralKey: ephemeralKey,
            customerEphemeralKeySecret: customerEphemeralKeySecret,
            customer: customer,
            customerId: customerId,
            paymentIntentId: paymentIntentId
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private func paymentIntentIdFromClientSecret(_ clientSecret: String) -> String? {
    let s = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty, let range = s.range(of: "_secret_") else { return nil }
    let prefix = String(s[..<range.lowerBound])
    return prefix.hasPrefix("pi_") ? prefix : nil
}
