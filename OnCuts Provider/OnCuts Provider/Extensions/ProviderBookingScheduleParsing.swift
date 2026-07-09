import Foundation

/// Parses booking / request schedule values from CampusCuts API payloads.
enum ProviderBookingScheduleParsing {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let postgresFallback: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let postgresOffsetFallback: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return f
    }()

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Parses API date strings (ISO8601, Postgres timestamps, epoch millis in string form).
    static func parseAPIDateString(_ raw: String?) -> Date? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        if let d = isoFractional.date(from: trimmed) ?? isoPlain.date(from: trimmed) {
            return d
        }
        if let d = postgresOffsetFallback.date(from: trimmed) {
            return d
        }

        let offsetPattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?[+-]\d{2}:\d{2}$"#
        if trimmed.range(of: offsetPattern, options: .regularExpression) != nil {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
            if let d = f.date(from: trimmed) { return d }
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
            if let d = f.date(from: trimmed) { return d }
        }

        if let d = postgresFallback.date(from: trimmed) {
            return d
        }
        if let d = dateOnly.date(from: trimmed) {
            return d
        }

        // Node/Postgres sometimes emits naive ISO-8601 without a timezone suffix.
        let naiveISO = DateFormatter()
        naiveISO.locale = Locale(identifier: "en_US_POSIX")
        naiveISO.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            naiveISO.dateFormat = format
            if let d = naiveISO.date(from: trimmed) { return d }
        }

        if let ms = Double(trimmed), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: ms / 1000)
        }

        return nil
    }

    /// Best-effort decode for optional API date fields that may arrive as strings, epoch numbers, or legacy object wrappers.
    static func decodeFlexibleOptionalDate(from container: SingleValueDecodingContainer) -> Date? {
        if (try? container.decodeNil()) == true { return nil }

        if let string = try? container.decode(String.self) {
            return parseAPIDateString(string)
        }
        if let seconds = try? container.decode(Double.self) {
            return dateFromEpochNumber(seconds)
        }
        if let seconds = try? container.decode(Int.self) {
            return dateFromEpochNumber(TimeInterval(seconds))
        }
        if let seconds = try? container.decode(Int64.self) {
            return dateFromEpochNumber(TimeInterval(seconds))
        }
        if let wrapped = try? container.decode([String: String].self) {
            for key in ["value", "date", "$date", "iso", "timestamp"] {
                if let raw = wrapped[key], let parsed = parseAPIDateString(raw) {
                    return parsed
                }
            }
        }

        return nil
    }

    private static func dateFromEpochNumber(_ raw: TimeInterval) -> Date {
        if raw > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1000)
        }
        return Date(timeIntervalSince1970: raw)
    }

    /// Resolves the consumer's requested appointment instant from a pending request row.
    static func requestedInstant(from row: BookingRequestRow, timeZone: TimeZone = .current) -> Date? {
        let dateRaw = row.requestedDate?.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeRaw = row.requestedTime?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let dateRaw, !dateRaw.isEmpty {
            if let parsed = parseAPIDateString(dateRaw) {
                if let timeRaw, !timeRaw.isEmpty, !looksLikeISODateTime(timeRaw),
                   shouldMergeWallClockTime(into: dateRaw) {
                    if let combined = combineCalendarDate(parsed, timeString: timeRaw, timeZone: timeZone) {
                        return combined
                    }
                }
                return parsed
            }
        }

        if let timeRaw, !timeRaw.isEmpty, let parsed = parseAPIDateString(timeRaw) {
            return parsed
        }

        if let dateRaw, !dateRaw.isEmpty,
           let timeRaw, !timeRaw.isEmpty,
           let combined = combineDateString(dateRaw, timeString: timeRaw, timeZone: timeZone) {
            return combined
        }

        return nil
    }

    /// Campus-local time label from the API (e.g. `"12:45 PM"`), when provided separately from the ISO instant.
    static func displayWallClockTime(from row: BookingRequestRow) -> String? {
        guard let raw = row.requestedTime?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !looksLikeISODateTime(raw)
        else { return nil }
        return raw
    }

    static func formattedRequestedSchedule(from row: BookingRequestRow, timeZone: TimeZone = .current) -> String {
        if let wallClock = displayWallClockTime(from: row),
           let instant = requestedInstant(from: row, timeZone: timeZone) {
            let datePart = instant.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            return "\(datePart) · \(wallClock)"
        }

        if let instant = requestedInstant(from: row, timeZone: timeZone) {
            return instant.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        }

        let parts = [row.requestedDate, row.requestedTime]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        return "Time TBD"
    }

    private static func looksLikeISODateTime(_ value: String) -> Bool {
        value.contains("T") && value.contains("-")
    }

    /// Only merge `requestedTime` into `requestedDate` when the date field is not already a zoned instant.
    private static func shouldMergeWallClockTime(into dateRaw: String) -> Bool {
        if isDateOnlyString(dateRaw) { return true }
        if hasExplicitTimeZone(in: dateRaw) { return false }
        return isNaiveTimestampString(dateRaw)
    }

    private static func isDateOnlyString(_ raw: String) -> Bool {
        raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func hasExplicitTimeZone(in raw: String) -> Bool {
        if raw.hasSuffix("Z") { return true }
        return raw.range(of: #"[\+\-]\d{2}:\d{2}$"#, options: .regularExpression) != nil
    }

    private static func isNaiveTimestampString(_ raw: String) -> Bool {
        raw.range(of: #"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}"#, options: .regularExpression) != nil
    }

    private static func combineCalendarDate(_ date: Date, timeString: String, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        guard let hourMinute = parseHourMinute(timeString) else { return nil }
        var components = day
        components.hour = hourMinute.hour
        components.minute = hourMinute.minute
        components.second = 0
        return calendar.date(from: components)
    }

    private static func combineDateString(_ dateString: String, timeString: String, timeZone: TimeZone) -> Date? {
        guard let base = parseAPIDateString(dateString) ?? dateOnly.date(from: dateString) else {
            return nil
        }
        return combineCalendarDate(base, timeString: timeString, timeZone: timeZone)
    }

    private static func parseHourMinute(_ raw: String) -> (hour: Int, minute: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if trimmed.contains(":") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            for format in ["H:mm", "HH:mm", "h:mm a", "hh:mm a", "h:mma", "hh:mma"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: trimmed.uppercased()) {
                    let cal = Calendar(identifier: .gregorian)
                    return (cal.component(.hour, from: date), cal.component(.minute, from: date))
                }
            }
            let parts = trimmed.split(separator: ":")
            if parts.count >= 2, let h = Int(parts[0]), let m = Int(String(parts[1].prefix(2))) {
                return (h, m)
            }
        }

        return nil
    }
}
