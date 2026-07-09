import Foundation

/// Reads the barber's weekly schedule + booked windows for a single calendar day.
///
/// Mirrors the web `GET /api/v1/barbers/:id/availability?date=YYYY-MM-DD` consumed by
/// `AvailableTimePickerDropdown` and `BarberPage`'s Daily view (`getBarberAvailability` controller).
@MainActor
enum ProviderAvailabilityService {
    static func getDayAvailability(
        barberId: String,
        date: Date,
        timeZone: TimeZone = .current
    ) async throws -> BarberAvailabilityDayData {
        let dateString = Self.yyyyMMdd(date, timeZone: timeZone)
        let encoded = dateString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dateString
        let path = "barbers/\(barberId)/availability?date=\(encoded)"
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BarberAvailabilityDayEnvelope.self, from: data)
        return env.data ?? BarberAvailabilityDayData(
            date: dateString,
            dayOfWeek: nil,
            available: false,
            intervals: [],
            bookedSlots: [],
            slots: []
        )
    }

    private static func yyyyMMdd(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
