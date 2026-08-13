import Foundation

/// Read Admin endpoints used by `ProviderAdminDashboardView` (parity with web `AdminDashboard.tsx`).
///
/// Backend mounts these under `/api/v1/admin/...`; all require an `admin` role JWT.
@MainActor
enum ProviderAdminService {
    // MARK: - Platform stats

    static func platformStats() async throws -> AdminPlatformStatsDTO {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "admin/stats")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        struct Env: Decodable {
            let success: Bool?
            let data: AdminPlatformStatsDTO?
        }
        return try dec.decode(Env.self, from: data).data ?? AdminPlatformStatsDTO(
            totalUsers: nil, totalBookings: nil, totalBarbers: nil, totalCampuses: nil
        )
    }

    // MARK: - Platform settings (commission % / on-off + Controls toggles)

    /// `GET /admin/platform-settings`
    static func fetchPlatformSettings() async throws -> AdminPlatformSettingsDTO {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "admin/platform-settings")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(AdminPlatformSettingsEnvelope.self, from: data)
        if let data = env.data { return data }
        return try dec.decode(AdminPlatformSettingsDTO.self, from: data)
    }

    /// Convenience for Performance — commission percent only.
    static func fetchPlatformFeePercent() async throws -> Double {
        let settings = try await fetchPlatformSettings()
        return settings.platformFeePercent ?? 15
    }

    /// `PUT /admin/platform-settings` — partial body; only supplied keys are updated.
    @discardableResult
    static func updatePlatformSettings(_ body: [String: Any]) async throws -> AdminPlatformSettingsDTO {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/platform-settings",
            method: "PUT",
            jsonBody: body
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(AdminPlatformSettingsEnvelope.self, from: data)
        if let data = env.data { return data }
        return (try? dec.decode(AdminPlatformSettingsDTO.self, from: data))
            ?? AdminPlatformSettingsDTO(
                platformFeePercent: body["platformFeePercent"] as? Double,
                platformCommissionEnabled: body["platformCommissionEnabled"] as? Bool,
                kickbackPercent: body["kickbackPercent"] as? Double,
                feeBurden: body["feeBurden"] as? String,
                cashPaymentEnabled: body["cashPaymentEnabled"] as? Bool,
                consumerHomeMode: body["consumerHomeMode"] as? String
            )
    }

    /// `PUT /admin/platform-settings` body `{ platformFeePercent }`
    static func updatePlatformSettings(platformFeePercent: Double) async throws -> Double {
        let rounded = (platformFeePercent * 100).rounded() / 100
        let saved = try await updatePlatformSettings(["platformFeePercent": rounded])
        return saved.platformFeePercent ?? rounded
    }

    /// `PUT /admin/platform-settings` — fee %, on/off, burden, and optional kickback.
    @discardableResult
    static func updatePlatformCommission(
        platformFeePercent: Double? = nil,
        platformCommissionEnabled: Bool? = nil,
        feeBurden: AdminFeeBurden? = nil,
        kickbackPercent: Double? = nil
    ) async throws -> AdminPlatformSettingsDTO {
        var body: [String: Any] = [:]
        if let platformFeePercent {
            body["platformFeePercent"] = (platformFeePercent * 100).rounded() / 100
        }
        if let platformCommissionEnabled {
            body["platformCommissionEnabled"] = platformCommissionEnabled
        }
        if let feeBurden {
            body["feeBurden"] = feeBurden.rawValue
        }
        if let kickbackPercent {
            body["kickbackPercent"] = (kickbackPercent * 100).rounded() / 100
        }
        guard !body.isEmpty else {
            return try await fetchPlatformSettings()
        }
        return try await updatePlatformSettings(body)
    }

    static func updatePlatformCommissionEnabled(_ enabled: Bool) async throws -> AdminPlatformSettingsDTO {
        try await updatePlatformSettings(["platformCommissionEnabled": enabled])
    }

    static func updateCashPaymentEnabled(_ enabled: Bool) async throws -> AdminPlatformSettingsDTO {
        try await updatePlatformSettings(["cashPaymentEnabled": enabled])
    }

    static func updateConsumerHomeMode(_ mode: AdminConsumerHomeMode) async throws -> AdminPlatformSettingsDTO {
        try await updatePlatformSettings(["consumerHomeMode": mode.rawValue])
    }

    // MARK: - Notification templates

    static func listNotificationTemplates() async throws -> [AdminNotificationTemplateDTO] {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "admin/notification-templates")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        if let env = try? dec.decode(AdminNotificationTemplatesEnvelope.self, from: data),
           let list = env.data {
            return list
        }
        return (try? dec.decode([AdminNotificationTemplateDTO].self, from: data)) ?? []
    }

    static func createNotificationTemplate(
        title: String,
        body: String,
        audience: AdminNotificationAudience,
        label: String? = nil
    ) async throws -> AdminNotificationTemplateDTO {
        var payload: [String: Any] = [
            "title": title,
            "body": body,
            "audience": audience.rawValue,
        ]
        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["label"] = label
        }
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/notification-templates",
            method: "POST",
            jsonBody: payload
        )
        return try decodeNotificationTemplate(from: data)
    }

    static func updateNotificationTemplate(
        id: String,
        label: String? = nil,
        title: String? = nil,
        body: String? = nil,
        audience: AdminNotificationAudience? = nil,
        enabled: Bool? = nil
    ) async throws -> AdminNotificationTemplateDTO {
        var payload: [String: Any] = [:]
        if let label { payload["label"] = label }
        if let title { payload["title"] = title }
        if let body { payload["body"] = body }
        if let audience { payload["audience"] = audience.rawValue }
        if let enabled { payload["enabled"] = enabled }
        let enc = id.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? id
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/notification-templates/\(enc)",
            method: "PATCH",
            jsonBody: payload
        )
        return try decodeNotificationTemplate(from: data)
    }

    static func deleteNotificationTemplate(id: String) async throws {
        let enc = id.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? id
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/notification-templates/\(enc)",
            method: "DELETE"
        )
    }

    static func sendNotificationTemplate(id: String) async throws -> AdminNotificationSendResultDTO {
        let enc = id.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? id
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/notification-templates/\(enc)/send",
            method: "POST"
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        if let env = try? dec.decode(AdminNotificationSendEnvelope.self, from: data),
           let result = env.data {
            return result
        }
        return (try? dec.decode(AdminNotificationSendResultDTO.self, from: data))
            ?? AdminNotificationSendResultDTO(queued: nil, audience: nil)
    }

    private static func decodeNotificationTemplate(from data: Data) throws -> AdminNotificationTemplateDTO {
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        if let env = try? dec.decode(AdminNotificationTemplateEnvelope.self, from: data),
           let row = env.data {
            return row
        }
        return try dec.decode(AdminNotificationTemplateDTO.self, from: data)
    }

    // MARK: - Campuses

    static func listCampuses() async throws -> [AdminCampusDTO] {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "admin/campuses")
        // Backend returns camelCase (`managerId`, …). A snake_case key strategy can mis-map those keys and fail decoding.
        let dec = JSONDecoder()
        let env = try dec.decode(AdminCampusesEnvelope.self, from: data)
        return env.resolved
    }

    static func aggregatePerformance() async throws -> AdminCampusPerformanceDTO? {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "admin/campuses/aggregate/performance")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try decodeAdminCampusPerformance(from: data, decoder: dec)
    }

    static func campusPerformance(campusId: String) async throws -> AdminCampusPerformanceDTO? {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/campuses/\(campusId)/performance"
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try decodeAdminCampusPerformance(from: data, decoder: dec)
    }

    // MARK: - Time-series metrics (charts)

    /// `GET /admin/campuses/aggregate/metrics?period=daily|weekly|monthly|yearly|…`
    static func aggregateMetrics(period: String) async throws -> AdminMetricsSnapshotDTO {
        let q = period.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? period
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/campuses/aggregate/metrics?period=\(q)"
        )
        let dec = JSONDecoder()
        return try dec.decode(AdminMetricsSnapshotDTO.self, from: data)
    }

    /// `GET /admin/campuses/:id/metrics?period=…`
    static func campusMetrics(campusId: String, period: String) async throws -> AdminMetricsSnapshotDTO {
        let enc = campusId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? campusId
        let q = period.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? period
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/campuses/\(enc)/metrics?period=\(q)"
        )
        let dec = JSONDecoder()
        return try dec.decode(AdminMetricsSnapshotDTO.self, from: data)
    }

    // MARK: - List-mode metrics events

    /// `GET …/metrics/events/options?granularity=&type=`
    static func metricsEventsOptions(
        campusId: String?,
        granularity: String,
        type: String,
        withinStart: String? = nil,
        withinEnd: String? = nil
    ) async throws -> [AdminMetricsListWindowOptionDTO] {
        var parts = [
            "granularity=\(granularity.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? granularity)",
            "type=\(type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? type)",
        ]
        if let withinStart, let withinEnd {
            let s = withinStart.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? withinStart
            let e = withinEnd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? withinEnd
            parts.append("withinStart=\(s)")
            parts.append("withinEnd=\(e)")
        }
        let base: String
        if let campusId {
            let enc = campusId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? campusId
            base = "admin/campuses/\(enc)/metrics/events/options"
        } else {
            base = "admin/campuses/aggregate/metrics/events/options"
        }
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "\(base)?\(parts.joined(separator: "&"))"
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminMetricsEventsOptionsEnvelope.self, from: data).options ?? []
    }

    /// `GET …/metrics/events?type=bookings|signups` with either `period=snapshot_all` or start/end.
    static func metricsBookingEvents(
        campusId: String?,
        start: String?,
        end: String?
    ) async throws -> [AdminMetricsBookingEventDTO] {
        let env = try await fetchMetricsEvents(campusId: campusId, type: "bookings", start: start, end: end)
        return (env.events ?? []).compactMap { $0.asBookingEvent() }
    }

    static func metricsSignupEvents(
        campusId: String?,
        start: String?,
        end: String?
    ) async throws -> [AdminMetricsSignupEventDTO] {
        let env = try await fetchMetricsEvents(campusId: campusId, type: "signups", start: start, end: end)
        return (env.events ?? []).compactMap { $0.asSignupEvent() }
    }

    private static func fetchMetricsEvents(
        campusId: String?,
        type: String,
        start: String?,
        end: String?
    ) async throws -> AdminMetricsEventsEnvelope {
        var parts = ["type=\(type)"]
        if let start, let end, !start.isEmpty, !end.isEmpty {
            let s = start.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? start
            let e = end.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? end
            parts.append("start=\(s)")
            parts.append("end=\(e)")
        } else {
            parts.append("period=snapshot_all")
        }
        let base: String
        if let campusId {
            let enc = campusId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? campusId
            base = "admin/campuses/\(enc)/metrics/events"
        } else {
            base = "admin/campuses/aggregate/metrics/events"
        }
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "\(base)?\(parts.joined(separator: "&"))"
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminMetricsEventsEnvelope.self, from: data)
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
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/campuses/\(campusId)/barbers"
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminBarbersEnvelope.self, from: data).resolved
    }

    static func allBarbers() async throws -> [AdminBarberDTO] {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "admin/barbers")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminBarbersEnvelope.self, from: data).resolved
    }

    static func barberBookings(barberRecordId: String, page: Int = 1, limit: Int = 50) async throws -> [AdminBarberBookingDTO] {
        let path = "admin/barbers/\(barberRecordId)/bookings?page=\(page)&limit=\(limit)"
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminBarberBookingsEnvelope.self, from: data).resolved
    }

    // MARK: - Campus bookings (`GET /bookings-simple/campus/:campusId`)

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
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BookingsSimpleListEnvelope.self, from: data)
        return env.data?.bookings ?? []
    }

    // MARK: - Platform service catalog (`/admin/services`)

    static func listPlatformServices(
        includeInactive: Bool,
        providerType: String? = nil
    ) async throws -> [AdminServiceCatalogItem] {
        var parts: [String] = []
        if includeInactive {
            parts.append("includeInactive=true")
        }
        if let providerType {
            let trimmed = providerType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty,
               let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                parts.append("providerType=\(encoded)")
            }
        }
        let q = parts.isEmpty ? "" : "?\(parts.joined(separator: "&"))"
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "admin/services\(q)")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(AdminServicesListEnvelope.self, from: data)
        let list = env.data ?? []
        return AdminServiceCatalogFiltering.filtered(list, providerType: providerType)
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
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
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
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
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

    static func setPlatformServiceActive(id: Int, isActive: Bool) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/services/\(id)",
            method: "PUT",
            jsonBody: ["isActive": isActive]
        )
    }

    static func deactivatePlatformService(id: Int) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/services/\(id)",
            method: "DELETE"
        )
    }

    // MARK: - Users

    static func listUsers(campusId: String? = nil, page: Int = 1, limit: Int = 500) async throws -> [AdminPlatformUserDTO] {
        var parts = ["page=\(page)", "limit=\(limit)"]
        if let campusId, !campusId.isEmpty {
            let enc = campusId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? campusId
            parts.append("campusId=\(enc)")
        }
        let path = "admin/users?" + parts.joined(separator: "&")
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminUsersEnvelope.self, from: data).resolved
    }

    static func userBookings(userId: String, page: Int = 1, limit: Int = 50) async throws -> [AdminConsumerBookingDTO] {
        let path = "admin/users/\(userId)/bookings?page=\(page)&limit=\(limit)"
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(AdminConsumerBookingsEnvelope.self, from: data).resolved
    }

    // MARK: - Barber visibility (admin can toggle isActive via PUT /barbers/:id)

    static func setBarberActive(barberRecordId: String, isActive: Bool) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(barberRecordId)",
            method: "PUT",
            jsonBody: ["is_active": isActive]
        )
    }

    // MARK: - Barber commission (admin)

    /// `PUT /admin/barbers/:barberRecordId/commission`
    ///
    /// Sets commission-free quota + kickback %. Platform fee rate is global
    /// (`/admin/platform-settings`), not per-provider.
    static func updateBarberCommission(
        barberRecordId: String,
        commissionFreeBookingsRemaining: Int,
        kickbackPercent: Double
    ) async throws -> AdminBarberCommissionDTO {
        let body: [String: Any] = [
            "commissionFreeBookingsRemaining": commissionFreeBookingsRemaining,
            "kickbackPercent": kickbackPercent,
        ]
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/barbers/\(barberRecordId)/commission",
            method: "PUT",
            jsonBody: body
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(AdminBarberCommissionEnvelope.self, from: data)
        if let nested = env.data { return nested }
        return try dec.decode(AdminBarberCommissionDTO.self, from: data)
    }

    /// `PUT /admin/barbers/commission/bulk`
    ///
    /// - Parameters:
    ///   - scope: `"all"` or `"selected"`
    ///   - barberRecordIds: required when `scope == "selected"`
    static func bulkUpdateBarberCommission(
        scope: String,
        barberRecordIds: [String]? = nil,
        commissionFreeBookingsRemaining: Int? = nil,
        kickbackPercent: Double? = nil
    ) async throws -> Int {
        var body: [String: Any] = ["scope": scope]
        if let barberRecordIds {
            body["barberRecordIds"] = barberRecordIds
        }
        if let commissionFreeBookingsRemaining {
            body["commissionFreeBookingsRemaining"] = commissionFreeBookingsRemaining
        }
        if let kickbackPercent {
            body["kickbackPercent"] = (kickbackPercent * 100).rounded() / 100
        }
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/barbers/commission/bulk",
            method: "PUT",
            jsonBody: body
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        if let env = try? dec.decode(AdminBulkCommissionEnvelope.self, from: data) {
            return env.data?.updatedCount ?? env.updatedCount ?? barberRecordIds?.count ?? 0
        }
        return barberRecordIds?.count ?? 0
    }

    // MARK: - Safety (admin moderation)
    //
    // Nested under Users on the web Admin dashboard (Users → Safety). Uses these endpoints.
    // Peer blocks (`user_blocks`) are intentionally not exposed — there is no admin UI for them.

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
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
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
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
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
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/moderation/reports/\(reportId)/resolve",
            method: "POST",
            jsonBody: body
        )
    }

    /// `POST /admin/users/:userId/unban` — empty body. Reverses `users.isBanned = true`.
    static func unbanUser(userId: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "admin/users/\(userId)/unban",
            method: "POST",
            jsonBody: [:]
        )
    }
}
