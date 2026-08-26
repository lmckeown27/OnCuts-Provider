import Foundation
import Observation

/// Platform payment timing — mirrors web `PaymentTimingMode` / `GET platform/frontend-config`.
enum PaymentTimingMode: String, Equatable, Sendable {
    /// Consumer pays after accept; Mark Complete requires `PAID`.
    case onAccept = "on_accept"
    /// Accept confirms only; Mark Complete from unpaid `ACCEPTED`; pay after complete.
    case afterComplete = "after_complete"

    var paysOnAccept: Bool { self == .onAccept }

    static func parse(_ raw: String?) -> PaymentTimingMode {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "after_complete"
            ? .afterComplete
            : .onAccept
    }
}

struct ProviderFrontendConfigDTO: Equatable, Sendable {
    var paymentTimingMode: PaymentTimingMode

    static let `default` = ProviderFrontendConfigDTO(paymentTimingMode: .onAccept)
}

/// Synchronous read for booking helpers (kept in sync by `ProviderFrontendConfigStore`).
enum ProviderPaymentTiming {
    nonisolated(unsafe) private static var cached: PaymentTimingMode = .onAccept

    nonisolated static var mode: PaymentTimingMode { cached }

    @MainActor
    static func set(_ mode: PaymentTimingMode) {
        cached = mode
    }
}

/// Cached `GET /platform/frontend-config` for operator booking CTAs and badges.
@Observable
@MainActor
final class ProviderFrontendConfigStore {
    static let shared = ProviderFrontendConfigStore()

    private(set) var config: ProviderFrontendConfigDTO = .default
    private(set) var lastFetchedAt: Date?

    var paymentTimingMode: PaymentTimingMode { config.paymentTimingMode }

    private init() {}

    func resetToDefault() {
        config = .default
        lastFetchedAt = nil
        ProviderPaymentTiming.set(.onAccept)
    }

    /// Refresh from the API. Failures keep the last known (or default) value.
    func refresh(force: Bool = false) async {
        if !force, let lastFetchedAt, Date().timeIntervalSince(lastFetchedAt) < 30 {
            return
        }
        do {
            let next = try await ProviderFrontendConfigService.fetch()
            config = next
            lastFetchedAt = Date()
            ProviderPaymentTiming.set(next.paymentTimingMode)
        } catch {
            // Keep prior / default — operator CTAs fall back to pay-on-accept.
        }
    }
}

enum ProviderFrontendConfigService {
    private struct Envelope: Decodable {
        let success: Bool?
        let data: Payload?
    }

    private struct Payload: Decodable {
        let paymentTimingMode: String?
    }

    static func fetch() async throws -> ProviderFrontendConfigDTO {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "platform/frontend-config")
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        guard let payload = env.data else {
            throw OnCutsHTTPError.decoding
        }
        return ProviderFrontendConfigDTO(
            paymentTimingMode: PaymentTimingMode.parse(payload.paymentTimingMode)
        )
    }
}
