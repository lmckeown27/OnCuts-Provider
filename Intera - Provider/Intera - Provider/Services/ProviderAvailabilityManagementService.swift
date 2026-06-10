import Foundation

/// CRUD for the provider's weekly schedule, one-off date blocks, and Google Calendar wiring.
///
/// Mirrors the same endpoints the web `BarberPage` modal + Google Calendar UI use:
///   - Weekly schedule: `GET /barbers/:id/availability` and `PUT /barbers/:id` (body `weekly_schedule`)
///   - Time blocks: `GET/POST/DELETE /barbers/:id/time-blocks`
///   - Google Calendar: `GET /auth/google-calendar/{status,connect}`, `DELETE …/disconnect`
@MainActor
enum ProviderAvailabilityManagementService {
    // MARK: - Weekly schedule

    static func fetchWeeklySchedule(barberId: String) async throws -> WeeklyScheduleDTO {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/\(barberId)/availability")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(WeeklyScheduleEnvelope.self, from: data)
        return env.data?.weeklySchedule ?? WeeklyScheduleDTO()
    }

    static func updateWeeklySchedule(barberId: String, schedule: WeeklyScheduleDTO) async throws {
        let body: [String: Any] = [
            // Backend column key is snake_case (`weekly_schedule`) — see `barber.controller.ts`.
            "weekly_schedule": try schedule.jsonObject(),
        ]
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(barberId)",
            method: "PUT",
            jsonBody: body
        )
    }

    // MARK: - Time blocks

    static func listTimeBlocks(
        barberId: String,
        startDate: String? = nil,
        endDate: String? = nil
    ) async throws -> [BarberTimeBlockDTO] {
        var query: [String] = []
        if let startDate { query.append("startDate=\(startDate)") }
        if let endDate { query.append("endDate=\(endDate)") }
        var path = "barbers/\(barberId)/time-blocks"
        if !query.isEmpty { path += "?" + query.joined(separator: "&") }
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BarberTimeBlocksEnvelope.self, from: data)
        return env.data ?? []
    }

    static func createTimeBlock(
        barberId: String,
        blockDate: String,
        startTime: String,
        endTime: String,
        reason: String?
    ) async throws -> BarberTimeBlockDTO? {
        var body: [String: Any] = [
            "blockDate": blockDate,
            "startTime": startTime,
            "endTime": endTime,
        ]
        if let reason, !reason.isEmpty { body["reason"] = reason }
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(barberId)/time-blocks",
            method: "POST",
            jsonBody: body,
            acceptableStatuses: 200 ..< 300
        )
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try? dec.decode(BarberTimeBlockSingleEnvelope.self, from: data).data
    }

    static func deleteTimeBlock(barberId: String, blockId: String) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(barberId)/time-blocks/\(blockId)",
            method: "DELETE"
        )
    }

    // MARK: - Google Calendar

    static func googleCalendarStatus() async throws -> GoogleCalendarStatusDTO {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "auth/google-calendar/status")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(GoogleCalendarStatusDTO.self, from: data)
    }

    static func googleCalendarConnectURL() async throws -> URL {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "auth/google-calendar/connect")
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let payload = try dec.decode(GoogleCalendarAuthURLDTO.self, from: data)
        guard let url = URL(string: payload.authUrl) else {
            throw CampusCutsHTTPError.invalidURL
        }
        return url
    }

    static func googleCalendarDisconnect() async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "auth/google-calendar/disconnect",
            method: "DELETE"
        )
    }

    static func googleCalendarUpdateSyncEnabled(_ enabled: Bool) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "auth/google-calendar/sync-settings",
            method: "PUT",
            jsonBody: ["syncEnabled": enabled]
        )
    }
}

// MARK: - Manage Availability prefetch

/// Starts parallel fetches before navigation so the editor can paint immediately.
@MainActor
enum ProviderAvailabilityEditorPrefetch {
    struct Snapshot {
        var calendarStatus: GoogleCalendarStatusDTO?
        var calendarError: String?
        var weekly: WeeklyScheduleDTO?
        var weeklyError: String?
        var timeBlocks: [BarberTimeBlockDTO]?
        var blocksError: String?
    }

    private static var barberId: String?
    private static var snapshot: Snapshot?
    private static var loadTask: Task<Snapshot, Never>?

    static func begin(barberId: String) {
        guard self.barberId != barberId || loadTask == nil else { return }
        self.barberId = barberId
        snapshot = nil
        loadTask?.cancel()
        loadTask = Task { await buildSnapshot(barberId: barberId) }
    }

    static func takeSnapshot(for barberId: String) async -> Snapshot? {
        guard self.barberId == barberId else { return nil }
        let snap: Snapshot?
        if let snapshot {
            snap = snapshot
        } else if let loadTask {
            snap = await loadTask.value
        } else {
            snap = nil
        }
        reset()
        return snap
    }

    private static func reset() {
        barberId = nil
        snapshot = nil
        loadTask = nil
    }

    private static func buildSnapshot(barberId: String) async -> Snapshot {
        var snap = Snapshot()
        async let calendar = loadCalendar()
        async let weekly = loadWeekly(barberId: barberId)
        async let blocks = loadBlocks(barberId: barberId)
        let (calendarResult, weeklyResult, blocksResult) = await (calendar, weekly, blocks)
        snap.calendarStatus = calendarResult.0
        snap.calendarError = calendarResult.1
        snap.weekly = weeklyResult.0
        snap.weeklyError = weeklyResult.1
        snap.timeBlocks = blocksResult.0
        snap.blocksError = blocksResult.1
        if !Task.isCancelled {
            snapshot = snap
        }
        return snap
    }

    private static func loadCalendar() async -> (GoogleCalendarStatusDTO?, String?) {
        do {
            return (try await ProviderAvailabilityManagementService.googleCalendarStatus(), nil)
        } catch {
            return (nil, (error as? LocalizedError)?.errorDescription ?? "Could not load Google Calendar status.")
        }
    }

    private static func loadWeekly(barberId: String) async -> (WeeklyScheduleDTO?, String?) {
        do {
            return (try await ProviderAvailabilityManagementService.fetchWeeklySchedule(barberId: barberId), nil)
        } catch {
            return (nil, (error as? LocalizedError)?.errorDescription ?? "Could not load schedule.")
        }
    }

    private static func loadBlocks(barberId: String) async -> ([BarberTimeBlockDTO]?, String?) {
        do {
            let list = try await ProviderAvailabilityManagementService.listTimeBlocks(barberId: barberId)
            return (list, nil)
        } catch {
            return (nil, (error as? LocalizedError)?.errorDescription ?? "Could not load time blocks.")
        }
    }
}
