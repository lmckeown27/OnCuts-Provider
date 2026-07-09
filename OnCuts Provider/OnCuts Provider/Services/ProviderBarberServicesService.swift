import Foundation

/// Loads the **campus service catalog** (`GET /admin/services`) and reads/writes barber **specialties + pricing**
/// via `GET /barbers/user/:userId` and `PUT /barbers/:id`, matching web `BarberServiceSpecialties`.
@MainActor
enum ProviderBarberServicesService {
    static func fetchServiceCatalog() async throws -> [AdminServiceCatalogItem] {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "admin/services")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(AdminServicesListEnvelope.self, from: data)
        let list = env.data ?? []
        return list.filter { ($0.isActive ?? true) }
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
