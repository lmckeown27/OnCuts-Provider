import Foundation

/// Read-only Admin endpoints used by `ProviderAdminDashboardView` (parity with web `AdminDashboard.tsx`).
///
/// Backend mounts these under `/api/v1/admin/...`; all require an `admin` role JWT.
@MainActor
enum ProviderAdminService {
    // MARK: - Platform stats

    static func platformStats() async throws -> AdminPlatformStatsDTO {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "admin/stats")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        struct Env: Decodable {
            let success: Bool?
            let data: AdminPlatformStatsDTO?
        }
        return try dec.decode(Env.self, from: data).data ?? AdminPlatformStatsDTO(
            totalUsers: nil, totalBookings: nil, totalBarbers: nil, totalCampuses: nil
        )
    }

    // MARK: - Campuses

    static func listCampuses() async throws -> [AdminCampusDTO] {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "admin/campuses")
        // Backend returns camelCase (`managerId`, …). A snake_case key strategy can mis-map those keys and fail decoding.
        let dec = JSONDecoder()
        let env = try dec.decode(AdminCampusesEnvelope.self, from: data)
        return env.resolved
    }

    static func aggregatePerformance() async throws -> AdminCampusPerformanceDTO? {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "admin/campuses/aggregate/performance")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try decodeAdminCampusPerformance(from: data, decoder: dec)
    }

    static func campusPerformance(campusId: String) async throws -> AdminCampusPerformanceDTO? {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/campuses/\(campusId)/performance"
        )
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try decodeAdminCampusPerformance(from: data, decoder: dec)
    }

    // MARK: - Time-series metrics (charts)

    /// `GET /admin/campuses/aggregate/metrics?period=daily|weekly|monthly|yearly|…`
    static func aggregateMetrics(period: String) async throws -> AdminMetricsSnapshotDTO {
        let q = period.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? period
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/campuses/aggregate/metrics?period=\(q)"
        )
        let dec = JSONDecoder()
        return try dec.decode(AdminMetricsSnapshotDTO.self, from: data)
    }

    /// `GET /admin/campuses/:id/metrics?period=…`
    static func campusMetrics(campusId: String, period: String) async throws -> AdminMetricsSnapshotDTO {
        let enc = campusId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? campusId
        let q = period.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? period
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/campuses/\(enc)/metrics?period=\(q)"
        )
        let dec = JSONDecoder()
        return try dec.decode(AdminMetricsSnapshotDTO.self, from: data)
    }

    /// Backend sends either `{ success, data: { …metrics } }` or a flat `{ success?, …metrics }` object (same keys as `AdminCampusPerformanceDTO`).
    private static func decodeAdminCampusPerformance(from data: Data, decoder: JSONDecoder) throws -> AdminCampusPerformanceDTO? {
        let envelope = try decoder.decode(AdminCampusPerformanceEnvelope.self, from: data)
        if let nested = envelope.data {
            return nested
        }
        return try decoder.decode(AdminCampusPerformanceDTO.self, from: data)
    }

    static func campusBarbers(campusId: String) async throws -> [AdminBarberDTO] {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/campuses/\(campusId)/barbers"
        )
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminBarbersEnvelope.self, from: data).resolved
    }

    static func allBarbers() async throws -> [AdminBarberDTO] {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "admin/barbers")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminBarbersEnvelope.self, from: data).resolved
    }

    static func barberBookings(barberRecordId: String, page: Int = 1, limit: Int = 50) async throws -> [AdminBarberBookingDTO] {
        let path = "admin/barbers/\(barberRecordId)/bookings?page=\(page)&limit=\(limit)"
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminBarberBookingsEnvelope.self, from: data).resolved
    }

    // MARK: - Users

    static func listUsers(campusId: String? = nil, page: Int = 1, limit: Int = 500) async throws -> [AdminPlatformUserDTO] {
        var parts = ["page=\(page)", "limit=\(limit)"]
        if let campusId, !campusId.isEmpty {
            let enc = campusId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? campusId
            parts.append("campusId=\(enc)")
        }
        let path = "admin/users?" + parts.joined(separator: "&")
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminUsersEnvelope.self, from: data).resolved
    }

    static func userBookings(userId: String, page: Int = 1, limit: Int = 50) async throws -> [AdminConsumerBookingDTO] {
        let path = "admin/users/\(userId)/bookings?page=\(page)&limit=\(limit)"
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminConsumerBookingsEnvelope.self, from: data).resolved
    }

    // MARK: - Barber visibility (admin can toggle isActive via PUT /barbers/:id)

    static func setBarberActive(barberRecordId: String, isActive: Bool) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(barberRecordId)",
            method: "PUT",
            jsonBody: ["is_active": isActive]
        )
    }

    // MARK: - Safety (admin moderation)
    //
    // The web Admin **Safety** tab uses only these four endpoints. Peer blocks (`user_blocks`)
    // are intentionally not exposed here — there is no admin API for arbitrary peer-block
    // tooling today, and support uses SQL when needed.

    /// `GET /admin/moderation/reports?status=&limit=` — UGC reports queue.
    ///
    /// Pass `status = nil` to fetch all statuses (the dashboard's **All** chip omits the query
    /// param entirely). Web defaults to `status=open` and `limit=200`.
    static func listModerationReports(
        status: AdminModerationReportStatus? = .open,
        limit: Int = 200
    ) async throws -> [AdminModerationReportDTO] {
        var parts = ["limit=\(limit)"]
        if let status {
            parts.append("status=\(status.rawValue)")
        }
        let path = "admin/moderation/reports?" + parts.joined(separator: "&")
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminModerationReportsEnvelope.self, from: data).resolved
    }

    /// `GET /admin/moderation/banned-users?category=&limit=` — every user whose `isBanned` is
    /// true, optionally narrowed by `account_category`. Pass `.all` to omit the query param.
    static func listBannedUsers(
        category: AdminBannedUserCategory = .all,
        limit: Int = 200
    ) async throws -> [AdminBannedUserDTO] {
        var parts = ["limit=\(limit)"]
        if category != .all {
            parts.append("category=\(category.rawValue)")
        }
        let path = "admin/moderation/banned-users?" + parts.joined(separator: "&")
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminBannedUsersEnvelope.self, from: data).resolved
    }

    /// `POST /admin/moderation/reports/:reportId/resolve` — body `{ action, notes? }`.
    ///
    /// Web does not currently send `notes`; iOS surfaces it as an optional argument so we can
    /// extend later without a service signature change.
    static func resolveModerationReport(
        reportId: String,
        action: AdminModerationResolveAction,
        notes: String? = nil
    ) async throws {
        var body: [String: Any] = ["action": action.rawValue]
        if let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            body["notes"] = trimmed
        }
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/moderation/reports/\(reportId)/resolve",
            method: "POST",
            jsonBody: body
        )
    }

    /// `POST /admin/users/:userId/unban` — empty body. Reverses `users.isBanned = true`.
    static func unbanUser(userId: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/users/\(userId)/unban",
            method: "POST",
            jsonBody: [:]
        )
    }
}
