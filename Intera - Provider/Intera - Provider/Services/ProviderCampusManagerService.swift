import Foundation

/// Endpoints used by `ProviderCampusManagerDashboardView`. The CM dashboard is mostly campus-scoped
/// barber + booking visibility. Many admin endpoints (campus performance / campus barbers) are
/// reusable by campus managers because the backend's role check accepts both.
@MainActor
enum ProviderCampusManagerService {
    /// Campus-scoped barber list. Backend behavior:
    ///   - Admin → uses `/admin/campuses/:id/barbers`
    ///   - Campus Manager → falls back to the public `/barbers?campusId=...&includeHidden=true`
    /// On iOS we always try the admin endpoint first (works for admins + campus managers in current
    /// backend) and degrade to the public listing if 403/404.
    static func campusBarbers(campusId: String) async throws -> [AdminBarberDTO] {
        do {
            return try await ProviderAdminService.campusBarbers(campusId: campusId)
        } catch CampusCutsHTTPError.httpStatus(let code, _) where code == 401 || code == 403 || code == 404 {
            return try await campusBarbersFallback(campusId: campusId)
        }
    }

    private static func campusBarbersFallback(campusId: String) async throws -> [AdminBarberDTO] {
        let path = "barbers?campusId=\(campusId)&includeHidden=true"
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        struct PublicBarbersEnvelope: Decodable {
            let success: Bool?
            let data: PublicBarbersData?
            let barbers: [AdminBarberDTO]?
        }
        struct PublicBarbersData: Decodable {
            let barbers: [AdminBarberDTO]?
        }
        let env = try dec.decode(PublicBarbersEnvelope.self, from: data)
        return env.data?.barbers ?? env.barbers ?? []
    }

    static func campusPerformance(campusId: String) async throws -> AdminCampusPerformanceDTO? {
        try await ProviderAdminService.campusPerformance(campusId: campusId)
    }

    /// Time-series chart data for a campus (`GET /admin/campuses/:id/metrics?period=…`).
    static func campusMetrics(campusId: String, period: String) async throws -> AdminMetricsSnapshotDTO {
        try await ProviderAdminService.campusMetrics(campusId: campusId, period: period)
    }

    /// Campus-scoped bookings list. Mirrors the web `/api/v1/bookings-simple/campus/:campusId` query
    /// used by the Campus Manager dashboard.
    static func campusBookings(
        campusId: String,
        barberFilter: String? = nil,
        paymentFilter: String? = nil,
        statusFilter: String? = nil,
        limit: Int = 100
    ) async throws -> [SimpleBookingDTO] {
        var query = "limit=\(limit)"
        if let barberFilter, !barberFilter.isEmpty { query += "&barberFilter=\(barberFilter)" }
        if let paymentFilter, !paymentFilter.isEmpty { query += "&paymentFilter=\(paymentFilter)" }
        if let statusFilter, !statusFilter.isEmpty { query += "&statusFilter=\(statusFilter)" }
        let path = "bookings-simple/campus/\(campusId)?\(query)"
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BookingsSimpleListEnvelope.self, from: data)
        return env.data?.bookings ?? []
    }

    /// Toggle a barber's visibility (campus managers can hide / unhide barbers in their campus).
    static func setBarberActive(barberRecordId: String, isActive: Bool) async throws {
        try await ProviderAdminService.setBarberActive(barberRecordId: barberRecordId, isActive: isActive)
    }

    /// Lookup the manager's campus name from `/admin/campuses` (admins) or `/campus-manager/campus/:id`
    /// (campus managers / public).
    static func campusInfo(campusId: String) async throws -> AdminCampusDTO? {
        // Admin endpoint first (richer fields).
        if let campus = try? await ProviderAdminService.listCampuses().first(where: { $0.id == campusId }) {
            return campus
        }
        // Public/CM fallback.
        let path = "campus-manager/campus/\(campusId)"
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        struct Env: Decodable {
            let success: Bool?
            let data: EnvData?
        }
        struct EnvData: Decodable {
            let campusManager: CampusManagerInfo?
        }
        struct CampusManagerInfo: Decodable {
            let campusId: String?
            let campusName: String?
        }
        let env = try dec.decode(Env.self, from: data)
        guard let info = env.data?.campusManager else { return nil }
        return AdminCampusDTO(
            id: info.campusId ?? campusId,
            name: info.campusName,
            slug: nil,
            city: nil,
            state: nil,
            managerId: nil,
            managerName: nil
        )
    }

    // MARK: - Platform service types (`/admin/services`)

    /// `GET /admin/services` — catalog for barber pricing UIs; `includeInactive` mirrors web **Show deleted**.
    static func listPlatformServices(includeInactive: Bool) async throws -> [AdminServiceCatalogItem] {
        let q = includeInactive ? "?includeInactive=true" : ""
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "admin/services\(q)")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(AdminServicesListEnvelope.self, from: data)
        return env.data ?? []
    }

    static func createPlatformService(
        name: String,
        description: String?,
        minPriceCents: Int,
        maxPriceCents: Int,
        minDurationMinutes: Int,
        maxDurationMinutes: Int
    ) async throws {
        let basePriceCents = (minPriceCents + maxPriceCents) / 2
        var body: [String: Any] = [
            "name": name,
            "basePriceCents": basePriceCents,
            "minPriceCents": minPriceCents,
            "maxPriceCents": maxPriceCents,
            "minDurationMinutes": minDurationMinutes,
            "maxDurationMinutes": maxDurationMinutes,
        ]
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["description"] = description
        }
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/services",
            method: "POST",
            jsonBody: body
        )
    }

    static func updatePlatformServiceBounds(
        id: Int,
        minPriceCents: Int,
        maxPriceCents: Int,
        minDurationMinutes: Int,
        maxDurationMinutes: Int
    ) async throws {
        let basePriceCents = (minPriceCents + maxPriceCents) / 2
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/services/\(id)",
            method: "PUT",
            jsonBody: [
                "basePriceCents": basePriceCents,
                "minPriceCents": minPriceCents,
                "maxPriceCents": maxPriceCents,
                "minDurationMinutes": minDurationMinutes,
                "maxDurationMinutes": maxDurationMinutes,
            ]
        )
    }

    static func updatePlatformServiceBasePrice(id: Int, basePriceCents: Int) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/services/\(id)",
            method: "PUT",
            jsonBody: ["basePriceCents": basePriceCents]
        )
    }

    static func setPlatformServiceActive(id: Int, isActive: Bool) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/services/\(id)",
            method: "PUT",
            jsonBody: ["isActive": isActive]
        )
    }

    /// Soft-deactivate (`is_active = false`), same as web **Delete**.
    static func deactivatePlatformService(id: Int) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/services/\(id)",
            method: "DELETE"
        )
    }
}
