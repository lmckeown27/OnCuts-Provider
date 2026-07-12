import Foundation

/// Loads the **campus service catalog** (`GET /admin/services`) and reads/writes barber **specialties + pricing**
/// via `GET /barbers/user/:userId` and `PUT /barbers/:id`, matching web `BarberServiceSpecialties`.
@MainActor
enum ProviderBarberServicesService {
    /// Known Beauty catalog names — used when the API omits `providerType` on rows.
    private static let knownBeautyServiceNames: Set<String> = [
        "braids", "lashes", "makeup", "nails", "tanning",
    ]

    static func fetchServiceCatalog(providerType: String? = nil) async throws -> [AdminServiceCatalogItem] {
        var path = "admin/services"
        if let providerType {
            let trimmed = providerType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty,
               let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "?providerType=\(encoded)"
            }
        }
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(AdminServicesListEnvelope.self, from: data)
        let list = env.data ?? []
        let active = list.filter { ($0.isActive ?? true) }
        guard let providerType else { return active }
        let key = providerType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return active }

        // 1) Prefer explicit `provider_type` on each row (never mix Barber + Beauty).
        let typed = active.filter {
            ($0.providerType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }
        if !typed.isEmpty { return typed }

        // 2) Legacy responses that omit `providerType` on every row.
        let anyTyped = active.contains {
            !($0.providerType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !anyTyped else { return typed }

        if key == "beauty" {
            // Narrow a mixed/untyped catalog to known Beauty services only.
            return active.filter {
                knownBeautyServiceNames.contains(
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            }
        }

        // Barber path: drop known Beauty names so they never appear in the Barber funnel.
        return active.filter {
            !knownBeautyServiceNames.contains(
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        }
    }

    static func fetchBarberUserProfile(userId: String) async throws -> BarberUserProfileDTO {
        let enc = userId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? userId
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/user/\(enc)")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BarberUserProfileEnvelope.self, from: data)
        guard let profile = env.data else {
            throw OnCutsHTTPError.decoding
        }
        return profile
    }

    static func updateBarberServicesAndPricing(
        barberId: String,
        specialties: [String],
        pricing: [BarberPricingEntryDTO]
    ) async throws {
        let enc = barberId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? barberId
        let pricingBody: [[String: Any]] = pricing.map { entry in
            var row: [String: Any] = ["name": entry.name, "price": entry.price]
            if let durationMinutes = entry.durationMinutes {
                row["duration_minutes"] = durationMinutes
            }
            return row
        }
        let body: [String: Any] = [
            "specialties": specialties,
            "pricing": pricingBody,
        ]
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(enc)",
            method: "PUT",
            jsonBody: body
        )
    }
}
