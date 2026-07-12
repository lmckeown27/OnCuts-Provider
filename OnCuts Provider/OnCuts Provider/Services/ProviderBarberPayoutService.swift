import Foundation

// MARK: - API envelopes (web `barber-payout.service` / `barber-connect.service`)

private struct BarberPayoutAPIEnvelope<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
    let error: BarberConnectAPIErrorBody?
    let code: String?
    let message: String?
}

private struct BarberConnectAPIErrorBody: Decodable {
    let message: String?
    let code: String?
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
    /// Saved `acct_*` is invalid for the current Stripe platform — CTA should reset.
    let needsReconnect: Bool
    let staleAccountCleared: Bool

    private enum CK: String, CodingKey {
        case has_account
        case account_id
        case detailsSubmitted
        case details_submitted
        case chargesEnabled
        case charges_enabled
        case payoutsEnabled
        case payouts_enabled
        case needsReconnect
        case needs_reconnect
        case staleAccountCleared
        case stale_account_cleared
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
        needsReconnect =
            (try c.decodeIfPresent(Bool.self, forKey: .needsReconnect)
                ?? c.decodeIfPresent(Bool.self, forKey: .needs_reconnect))
            ?? false
        staleAccountCleared =
            (try c.decodeIfPresent(Bool.self, forKey: .staleAccountCleared)
                ?? c.decodeIfPresent(Bool.self, forKey: .stale_account_cleared))
            ?? false
    }

    init(
        hasAccount: Bool,
        accountId: String? = nil,
        detailsSubmitted: Bool? = nil,
        chargesEnabled: Bool? = nil,
        payoutsEnabled: Bool? = nil,
        needsReconnect: Bool = false,
        staleAccountCleared: Bool = false
    ) {
        self.hasAccount = hasAccount
        self.accountId = accountId
        self.detailsSubmitted = detailsSubmitted
        self.chargesEnabled = chargesEnabled
        self.payoutsEnabled = payoutsEnabled
        self.needsReconnect = needsReconnect
        self.staleAccountCleared = staleAccountCleared
    }
}

enum BarberStripeConnectStatus {
    /// Web `isBarberStripeFullyConnected` — all five must pass. Missing status ⇒ not connected.
    static func isFullyConnected(_ status: BarberConnectStatusDTO?) -> Bool {
        guard let status else { return false }
        return status.hasAccount
            && status.detailsSubmitted == true
            && status.chargesEnabled == true
            && status.payoutsEnabled == true
            && !status.needsReconnect
    }
}

private struct BarberConnectOnboardingBodyDTO: Decodable {
    let accountId: String?
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

enum BarberConnectPlatformError: LocalizedError {
    case platformProfileIncomplete
    case platformNotEnabled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .platformProfileIncomplete:
            return "Stripe Connect isn’t fully enabled on the OnCuts platform yet. An OnCuts owner needs to finish platform setup in the Stripe Dashboard before operators can onboard."
        case .platformNotEnabled:
            return "Stripe Connect isn’t enabled for this OnCuts environment. Contact an OnCuts owner to enable Connect."
        case .message(let text):
            return text
        }
    }

    var disablesCTA: Bool {
        switch self {
        case .platformProfileIncomplete, .platformNotEnabled:
            return true
        case .message:
            return false
        }
    }

    static func parse(from error: Error) -> BarberConnectPlatformError? {
        guard let http = error as? OnCutsHTTPError,
              case .httpStatus(_, let raw) = http,
              let raw,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let code = ((obj["code"] as? String)
            ?? ((obj["error"] as? [String: Any])?["code"] as? String)
            ?? "")
            .uppercased()
        let message = ((obj["message"] as? String)
            ?? ((obj["error"] as? [String: Any])?["message"] as? String)
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if code.contains("STRIPE_CONNECT_PLATFORM_PROFILE_INCOMPLETE")
            || message.uppercased().contains("STRIPE_CONNECT_PLATFORM_PROFILE_INCOMPLETE") {
            return .platformProfileIncomplete
        }
        if code.contains("STRIPE_CONNECT_PLATFORM_NOT_ENABLED")
            || code.contains("NOT_ENABLED")
            || message.uppercased().contains("STRIPE_CONNECT_PLATFORM_NOT_ENABLED") {
            return .platformNotEnabled
        }
        if !message.isEmpty {
            return .message(message)
        }
        return nil
    }
}

private enum ProviderBarberPayoutJSON {
    static let decoder: JSONDecoder = { JSONDecoder() }()
}

enum ProviderBarberPayoutService {
    static func fetchPayoutSummary() async throws -> BarberPayoutSummaryDTO {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "barber/payout/summary")
        let env = try ProviderBarberPayoutJSON.decoder.decode(BarberPayoutAPIEnvelope<BarberPayoutSummaryDTO>.self, from: data)
        guard let summary = env.data else {
            throw OnCutsHTTPError.decoding
        }
        return summary
    }

    static func fetchConnectStatus() async throws -> BarberConnectStatusDTO {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "barber/connect/status")
        let env = try ProviderBarberPayoutJSON.decoder.decode(BarberPayoutAPIEnvelope<BarberConnectStatusDTO>.self, from: data)
        guard let status = env.data else {
            throw OnCutsHTTPError.decoding
        }
        return status
    }

    /// Stripe-hosted Connect onboarding or account-update link (same as web `POST /barber/connect/create`).
    static func createConnectOnboardingURL() async throws -> URL {
        try await postOnboardingURL(path: "barber/connect/create")
    }

    /// Refresh Account Link for an existing incomplete Express account.
    static func refreshConnectOnboardingURL() async throws -> URL {
        try await postOnboardingURL(path: "barber/connect/refresh")
    }

    /// Clear a stale `acct_*` and create a fresh Express account + Account Link.
    static func resetConnectOnboardingURL() async throws -> URL {
        try await postOnboardingURL(path: "barber/connect/reset")
    }

    /// Stripe Express dashboard login URL (same as web `GET /barber/connect/dashboard`).
    static func fetchStripeDashboardURL() async throws -> URL {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "barber/connect/dashboard")
        let env = try ProviderBarberPayoutJSON.decoder.decode(BarberPayoutAPIEnvelope<BarberConnectDashboardBodyDTO>.self, from: data)
        guard let body = env.data, let url = URL(string: body.dashboardUrl) else {
            throw OnCutsHTTPError.decoding
        }
        return url
    }

    /// Opens the correct Account Link for the current Connect status (create / refresh / reset).
    static func onboardingURL(for status: BarberConnectStatusDTO?) async throws -> URL {
        if status?.needsReconnect == true {
            return try await resetConnectOnboardingURL()
        }
        if status?.hasAccount == true {
            return try await refreshConnectOnboardingURL()
        }
        return try await createConnectOnboardingURL()
    }

    private static func postOnboardingURL(path: String) async throws -> URL {
        do {
            let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
                path: path,
                method: "POST",
                jsonBody: [:]
            )
            let env = try ProviderBarberPayoutJSON.decoder.decode(
                BarberPayoutAPIEnvelope<BarberConnectOnboardingBodyDTO>.self,
                from: data
            )
            guard let body = env.data, let url = URL(string: body.onboardingUrl) else {
                throw OnCutsHTTPError.decoding
            }
            return url
        } catch {
            if let platform = BarberConnectPlatformError.parse(from: error) {
                throw platform
            }
            throw error
        }
    }
}
