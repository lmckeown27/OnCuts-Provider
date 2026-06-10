import Foundation

// MARK: - API envelopes (web `barber-payout.service` / `barber-connect.service`)

private struct BarberPayoutAPIEnvelope<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
}

struct BarberPayoutSummaryDTO: Decodable, Hashable {
    let hasBarberProfile: Bool
    let ledgerTotalDollars: Double
    let ledgerPendingDollars: Double
    let ledgerPaidOutDollars: Double
    let bookingEstimatedBarberCents: Int
    let paidBookingsCount: Int
    let recent30DBarberCents: Int
    let displayTotalDollars: Double

    var usesLedger: Bool { ledgerTotalDollars > 0 }

    enum CodingKeys: String, CodingKey {
        case hasBarberProfile = "has_barber_profile"
        case ledgerTotalDollars = "ledger_total_dollars"
        case ledgerPendingDollars = "ledger_pending_dollars"
        case ledgerPaidOutDollars = "ledger_paid_out_dollars"
        case bookingEstimatedBarberCents = "booking_estimated_barber_cents"
        case paidBookingsCount = "paid_bookings_count"
        case recent30DBarberCents = "recent_30d_barber_cents"
        case displayTotalDollars = "display_total_dollars"
    }
}

struct BarberConnectStatusDTO: Decodable, Hashable {
    let hasAccount: Bool
    let accountId: String?
    let detailsSubmitted: Bool?
    let chargesEnabled: Bool?
    let payoutsEnabled: Bool?

    private enum CK: String, CodingKey {
        case has_account
        case account_id
        case detailsSubmitted
        case details_submitted
        case chargesEnabled
        case charges_enabled
        case payoutsEnabled
        case payouts_enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        hasAccount = try c.decode(Bool.self, forKey: .has_account)
        accountId = try c.decodeIfPresent(String.self, forKey: .account_id)
        detailsSubmitted =
            try c.decodeIfPresent(Bool.self, forKey: .detailsSubmitted)
            ?? c.decodeIfPresent(Bool.self, forKey: .details_submitted)
        chargesEnabled =
            try c.decodeIfPresent(Bool.self, forKey: .chargesEnabled)
            ?? c.decodeIfPresent(Bool.self, forKey: .charges_enabled)
        payoutsEnabled =
            try c.decodeIfPresent(Bool.self, forKey: .payoutsEnabled)
            ?? c.decodeIfPresent(Bool.self, forKey: .payouts_enabled)
    }
}

private struct BarberConnectOnboardingBodyDTO: Decodable {
    let accountId: String
    let onboardingUrl: String

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case onboardingUrl = "onboarding_url"
    }
}

private struct BarberConnectDashboardBodyDTO: Decodable {
    let dashboardUrl: String

    enum CodingKeys: String, CodingKey {
        case dashboardUrl = "dashboard_url"
    }
}

private enum ProviderBarberPayoutJSON {
    static let decoder: JSONDecoder = { JSONDecoder() }()
}

enum ProviderBarberPayoutService {
    static func fetchPayoutSummary() async throws -> BarberPayoutSummaryDTO {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "barber/payout/summary")
        let env = try ProviderBarberPayoutJSON.decoder.decode(BarberPayoutAPIEnvelope<BarberPayoutSummaryDTO>.self, from: data)
        guard let summary = env.data else {
            throw CampusCutsHTTPError.decoding
        }
        return summary
    }

    static func fetchConnectStatus() async throws -> BarberConnectStatusDTO {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "barber/connect/status")
        let env = try ProviderBarberPayoutJSON.decoder.decode(BarberPayoutAPIEnvelope<BarberConnectStatusDTO>.self, from: data)
        guard let status = env.data else {
            throw CampusCutsHTTPError.decoding
        }
        return status
    }

    /// Stripe-hosted Connect onboarding or account-update link (same as web `POST /barber/connect/create`).
    static func createConnectOnboardingURL() async throws -> URL {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "barber/connect/create",
            method: "POST",
            jsonBody: [:]
        )
        let env = try ProviderBarberPayoutJSON.decoder.decode(BarberPayoutAPIEnvelope<BarberConnectOnboardingBodyDTO>.self, from: data)
        guard let body = env.data, let url = URL(string: body.onboardingUrl) else {
            throw CampusCutsHTTPError.decoding
        }
        return url
    }

    /// Stripe Express dashboard login URL (same as web `GET /barber/connect/dashboard`).
    static func fetchStripeDashboardURL() async throws -> URL {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "barber/connect/dashboard")
        let env = try ProviderBarberPayoutJSON.decoder.decode(BarberPayoutAPIEnvelope<BarberConnectDashboardBodyDTO>.self, from: data)
        guard let body = env.data, let url = URL(string: body.dashboardUrl) else {
            throw CampusCutsHTTPError.decoding
        }
        return url
    }
}
