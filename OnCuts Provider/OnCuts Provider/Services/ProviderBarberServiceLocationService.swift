import Foundation

/// Public discovery pin for clients (`GET/PUT /barbers/service-location`).
struct BarberServiceLocationDTO: Decodable, Hashable {
    let serviceLatitude: Double?
    let serviceLongitude: Double?
    let serviceRadiusKm: Double?
    let serviceLocationLabel: String?
    let serviceLocationSource: String?
    let serviceLocationWebOnly: Bool
    let ignoredDeviceUpdate: Bool

    enum CodingKeys: String, CodingKey {
        case serviceLatitude = "service_latitude"
        case serviceLongitude = "service_longitude"
        case serviceRadiusKm = "service_radius_km"
        case serviceLocationLabel = "service_location_label"
        case serviceLocationSource = "service_location_source"
        case serviceLocationWebOnly = "service_location_web_only"
        case ignoredDeviceUpdate = "ignored_device_update"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serviceLatitude = Self.decodeFlexibleDouble(c, forKey: .serviceLatitude)
        serviceLongitude = Self.decodeFlexibleDouble(c, forKey: .serviceLongitude)
        serviceRadiusKm = Self.decodeFlexibleDouble(c, forKey: .serviceRadiusKm)
        serviceLocationLabel = try c.decodeIfPresent(String.self, forKey: .serviceLocationLabel)
        serviceLocationSource = try c.decodeIfPresent(String.self, forKey: .serviceLocationSource)
        serviceLocationWebOnly =
            (try c.decodeIfPresent(Bool.self, forKey: .serviceLocationWebOnly)) ?? false
        ignoredDeviceUpdate =
            (try c.decodeIfPresent(Bool.self, forKey: .ignoredDeviceUpdate)) ?? false
    }

    var hasCoordinates: Bool {
        serviceLatitude != nil && serviceLongitude != nil
    }

    var sourceDisplayName: String {
        switch (serviceLocationSource ?? "").lowercased() {
        case "device": return "This device"
        case "manual": return "Manual place"
        case "campus_default": return "Campus default"
        case "": return "Not set"
        default: return serviceLocationSource ?? "Not set"
        }
    }

    private static func decodeFlexibleDouble(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let d = Double(s) { return d }
        return nil
    }
}

private struct BarberServiceLocationEnvelope: Decodable {
    let success: Bool?
    let data: BarberServiceLocationDTO?
    let message: String?
}

enum ProviderBarberServiceLocationService {
    static func fetch() async throws -> BarberServiceLocationDTO {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/service-location")
        let env = try JSONDecoder().decode(BarberServiceLocationEnvelope.self, from: data)
        guard let pin = env.data else { throw OnCutsHTTPError.decoding }
        return pin
    }

    /// Update the public discovery pin and/or the manual-location lock.
    @discardableResult
    static func update(
        latitude: Double? = nil,
        longitude: Double? = nil,
        label: String? = nil,
        source: String? = nil,
        webOnly: Bool? = nil,
        serviceRadiusKm: Double? = nil
    ) async throws -> BarberServiceLocationDTO {
        var body: [String: Any] = [:]
        if let latitude { body["latitude"] = latitude }
        if let longitude { body["longitude"] = longitude }
        if let label {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { body["label"] = trimmed }
        }
        if let source { body["source"] = source }
        if let webOnly { body["web_only"] = webOnly }
        if let serviceRadiusKm { body["service_radius_km"] = serviceRadiusKm }

        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/service-location",
            method: "PUT",
            jsonBody: body
        )
        let env = try JSONDecoder().decode(BarberServiceLocationEnvelope.self, from: data)
        guard let pin = env.data else { throw OnCutsHTTPError.decoding }
        return pin
    }
}
