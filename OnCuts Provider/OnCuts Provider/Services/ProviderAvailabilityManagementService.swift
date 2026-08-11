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
        try await fetchAvailability(barberId: barberId).weeklySchedule
    }

    /// `GET /barbers/:id/availability` — weekly hours plus booking slot interval.
    static func fetchAvailability(barberId: String) async throws -> (
        weeklySchedule: WeeklyScheduleDTO,
        bookingSlotIntervalMinutes: Int
    ) {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/\(barberId)/availability")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(WeeklyScheduleEnvelope.self, from: data)
        let schedule = env.data?.weeklySchedule ?? WeeklyScheduleDTO()
        let interval = env.data?.resolvedBookingSlotIntervalMinutes
            ?? BookingSlotIntervalMinutesPreset.resolved(
                ProviderMarketplaceVisibility.int(
                    in: data,
                    camelKey: "bookingSlotIntervalMinutes",
                    snakeKey: "booking_slot_interval_minutes"
                )
            )
        return (schedule, interval)
    }

    /// Owner-only: how far apart client bookable start times are (`15`, `30`, `45`).
    @discardableResult
    static func updateBookingSlotIntervalMinutes(barberId: String, minutes: Int) async throws -> Int {
        let resolved = BookingSlotIntervalMinutesPreset.resolved(minutes)
        let enc = barberId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? barberId
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(enc)",
            method: "PUT",
            jsonBody: [
                "booking_slot_interval_minutes": resolved,
                "bookingSlotIntervalMinutes": resolved,
            ]
        )
        return ProviderMarketplaceVisibility.int(
            in: data,
            camelKey: "bookingSlotIntervalMinutes",
            snakeKey: "booking_slot_interval_minutes"
        ) ?? resolved
    }

    static func updateWeeklySchedule(barberId: String, schedule: WeeklyScheduleDTO) async throws {
        let body: [String: Any] = [
            // Backend column key is snake_case (`weekly_schedule`) — see `barber.controller.ts`.
            "weekly_schedule": try schedule.jsonObject(),
        ]
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
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
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
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
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(barberId)/time-blocks",
            method: "POST",
            jsonBody: body,
            acceptableStatuses: 200 ..< 300
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try? dec.decode(BarberTimeBlockSingleEnvelope.self, from: data).data
    }

    static func deleteTimeBlock(barberId: String, blockId: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(barberId)/time-blocks/\(blockId)",
            method: "DELETE"
        )
    }

    // MARK: - Google Calendar

    static func googleCalendarStatus() async throws -> GoogleCalendarStatusDTO {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "auth/google-calendar/status")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        return try dec.decode(GoogleCalendarStatusDTO.self, from: data)
    }

    static func googleCalendarConnectURL() async throws -> URL {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "auth/google-calendar/connect")
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let payload = try dec.decode(GoogleCalendarAuthURLDTO.self, from: data)
        guard let url = URL(string: payload.authUrl) else {
            throw OnCutsHTTPError.invalidURL
        }
        return url
    }

    static func googleCalendarDisconnect() async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "auth/google-calendar/disconnect",
            method: "DELETE"
        )
    }

    static func googleCalendarUpdateSyncEnabled(_ enabled: Bool) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "auth/google-calendar/sync-settings",
            method: "PUT",
            jsonBody: ["syncEnabled": enabled]
        )
    }

    static func googleCalendarBusyTimes(startDate: Date, endDate: Date) async throws -> [ProviderWeeklyScheduleBusyInterval] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        let path = "auth/google-calendar/busy-times?startDate=\(start)&endDate=\(end)"
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        struct Payload: Decodable {
            let busyTimes: [Interval]?
            struct Interval: Decodable {
                let start: Date
                let end: Date
            }
        }
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let payload = try dec.decode(Payload.self, from: data)
        return (payload.busyTimes ?? []).map { ProviderWeeklyScheduleBusyInterval(start: $0.start, end: $0.end) }
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
        var bookingSlotIntervalMinutes: Int?
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
        snap.bookingSlotIntervalMinutes = weeklyResult.2
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

    private static func loadWeekly(barberId: String) async -> (WeeklyScheduleDTO?, String?, Int?) {
        do {
            let availability = try await ProviderAvailabilityManagementService.fetchAvailability(barberId: barberId)
            return (availability.weeklySchedule, nil, availability.bookingSlotIntervalMinutes)
        } catch {
            return (nil, (error as? LocalizedError)?.errorDescription ?? "Could not load schedule.", nil)
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
