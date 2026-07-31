import Foundation

/// Loads the **campus service catalog** (`GET /admin/services`) and reads/writes barber **specialties + pricing**
/// via `GET /barbers/user/:userId` and `PUT /barbers/:id`, matching web `BarberServiceSpecialties`.
@MainActor
enum ProviderBarberServicesService {
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
        return AdminServiceCatalogFiltering.filtered(active, providerType: providerType)
    }

    static func fetchBarberUserProfile(userId: String) async throws -> BarberUserProfileDTO {
        let enc = userId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? userId
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/user/\(enc)")
        // Prefer a plain decoder: this DTO reads camelCase + snake_case keys explicitly.
        // `convertFromSnakeCase` can drop `commissionFreeBookingsRemaining` when the payload
        // also includes `commission_free_bookings_remaining` (web /barbers/user response).
        let dec = JSONDecoder()
        if let env = try? dec.decode(BarberUserProfileEnvelope.self, from: data),
           let profile = env.data {
            return profile.withCommissionFreeFallback(from: data)
        }
        if let profile = try? dec.decode(BarberUserProfileDTO.self, from: data) {
            return profile.withCommissionFreeFallback(from: data)
        }
        // Last resort: snake decoder (older payloads) + JSON dig for the free-quota field.
        let snake = OnCutsHTTPClient.jsonDecoderSnake()
        if let env = try? snake.decode(BarberUserProfileEnvelope.self, from: data),
           let profile = env.data {
            return profile.withCommissionFreeFallback(from: data)
        }
        throw OnCutsHTTPError.decoding
    }

    /// Lightweight pull of remaining commission-free bookings for the operator hub indicator.
    static func fetchCommissionFreeBookingsRemaining(userId: String) async throws -> Int {
        let profile = try await fetchBarberUserProfile(userId: userId)
        return profile.resolvedCommissionFreeBookingsRemaining
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

    fileprivate static func parseCommissionFreeBookingsRemaining(from data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let payload = (root["data"] as? [String: Any]) ?? root
        let raw =
            payload["commissionFreeBookingsRemaining"]
            ?? payload["commission_free_bookings_remaining"]
        if let n = raw as? Int { return max(0, n) }
        if let n = raw as? Double { return max(0, Int(n)) }
        if let s = raw as? String, let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, n)
        }
        if let n = raw as? NSNumber { return max(0, n.intValue) }
        return nil
    }
}

private extension BarberUserProfileDTO {
    func withCommissionFreeFallback(from data: Data) -> BarberUserProfileDTO {
        if commissionFreeBookingsRemaining != nil { return self }
        guard let parsed = ProviderBarberServicesService.parseCommissionFreeBookingsRemaining(from: data) else {
            return self
        }
        return BarberUserProfileDTO(
            id: id,
            specialties: specialties,
            pricing: pricing,
            providerType: providerType,
            commissionFreeBookingsRemaining: parsed
        )
    }
}
