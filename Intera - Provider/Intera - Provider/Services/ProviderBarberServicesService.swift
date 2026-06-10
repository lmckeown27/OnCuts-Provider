import Foundation

/// Loads the **campus service catalog** (`GET /admin/services`) and reads/writes barber **specialties + pricing**
/// via `GET /barbers/user/:userId` and `PUT /barbers/:id`, matching web `BarberServiceSpecialties`.
@MainActor
enum ProviderBarberServicesService {
    static func fetchServiceCatalog() async throws -> [AdminServiceCatalogItem] {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "admin/services")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(AdminServicesListEnvelope.self, from: data)
        let list = env.data ?? []
        return list.filter { ($0.isActive ?? true) }
    }

    static func fetchBarberUserProfile(userId: String) async throws -> BarberUserProfileDTO {
        let enc = userId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? userId
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/user/\(enc)")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BarberUserProfileEnvelope.self, from: data)
        guard let profile = env.data else {
            throw CampusCutsHTTPError.decoding
        }
        return profile
    }

    static func updateBarberServicesAndPricing(
        barberId: String,
        specialties: [String],
        pricing: [BarberPricingEntryDTO]
    ) async throws {
        let enc = barberId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? barberId
        let pricingBody: [[String: Any]] = pricing.map { ["name": $0.name, "price": $0.price] }
        let body: [String: Any] = [
            "specialties": specialties,
            "pricing": pricingBody,
        ]
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(enc)",
            method: "PUT",
            jsonBody: body
        )
    }
}
