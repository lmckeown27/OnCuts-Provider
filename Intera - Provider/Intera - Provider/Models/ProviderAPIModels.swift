import Foundation

// MARK: - Auth / me

struct AuthMeEnvelope: Decodable {
    let success: Bool?
    let data: AuthMeUser?
}

struct AuthMeUser: Decodable {
    let id: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let userType: String?
    let isAdmin: Bool?
    let hasBarberProfile: Bool?
    /// `users."campusId"` — scopes admin filters when present.
    let campusId: String?
    /// From `GET /auth/me` — `true` when the user has not set a CampusCuts password (typical for Sign in with Apple).
    /// Drives account-deletion UX: these accounts may omit the password body after device authentication.
    let needsPlatformPassword: Bool?

    /// `user_type` from API: `student`, `barber`, `admin` (legacy `campus_manager` maps to barber).
    var userTypeLowercased: String { (userType ?? "").lowercased() }

    var isConsumerAccount: Bool {
        resolvedAppRole == .consumer
    }

    /// Legacy DB `CAMPUS_MANAGER` and `campus_manager` user_type are treated as barbers.
    var isBarberRole: Bool {
        if hasBarberProfile == true { return true }
        switch userTypeLowercased {
        case "barber", "campus_manager": return true
        default: return false
        }
    }

    var hasAdminPrivileges: Bool { isAdmin == true || userTypeLowercased == "admin" }

    var resolvedAppRole: AppRole {
        if hasAdminPrivileges { return .admin }
        if isBarberRole { return .barber }
        return .consumer
    }
}

/// Signed-in account role for routing and elevated UI (admin is the only management role).
enum AppRole: Equatable {
    case consumer
    case barber
    case admin
}

struct BarberMeEnvelope: Decodable {
    let success: Bool?
    let data: BarberMeProfile?
    let message: String?
}

struct BarberMeProfile: Decodable, Hashable {
    let id: String
    let userId: String?
    /// Public-facing name (`data.name` from `GET /barbers/me`).
    let name: String?
    /// `users.displayName` when present.
    let displayName: String?
    /// From `users.first_name` / `users.last_name` join (web falls back to these when `name` is empty).
    let firstName: String?
    let lastName: String?
    let isActive: Bool?
    let bio: String?
    let specialties: [String]?
    let instagramHandle: String?
    /// Backend field `profile_picture_url` (sourced from `users."avatarUrl"`). Snake-case decoder turns it
    /// into `profilePictureUrl`. Used by the dashboard header to render the live provider avatar.
    let profilePictureUrl: String?

    var avatarURL: URL? {
        ProviderAvatarURL.resolve(profilePictureUrl)
    }

    /// Best display string for editor seeding (parity with web `BarberProfileEditor` load).
    var resolvedDisplayName: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        let d = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { return d }
        let f = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let l = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { return joined }
        return ""
    }
}

// MARK: - Platform service catalog (`GET /admin/services`)

/// Campus-wide service definitions (Campus Manager / Admin). Matches web `BarberServiceSpecialties` catalog fetch.
struct AdminServicesListEnvelope: Decodable {
    let success: Bool?
    let data: [AdminServiceCatalogItem]?
}

struct AdminServiceCatalogItem: Decodable, Identifiable, Hashable {
    let id: Int
    let slug: String
    let name: String
    let description: String?
    let basePriceCents: Int
    /// Allowed barber price floor / ceiling (cents), from `services` table — set by Campus Manager / Admin.
    let minPriceCents: Int?
    let maxPriceCents: Int?
    let isActive: Bool?
    /// Default / suggested appointment length when the catalog exposes it.
    let defaultDurationMinutes: Int?
    /// Allowed barber duration floor / ceiling (minutes) — set by Campus Manager / Admin.
    let minDurationMinutes: Int?
    let maxDurationMinutes: Int?
}

// MARK: - Barber profile by user (`GET /barbers/user/:userId`) — services & pricing editor

struct BarberUserProfileEnvelope: Decodable {
    let success: Bool?
    let data: BarberUserProfileDTO?
}

struct BarberUserProfileDTO: Decodable {
    let id: String
    let specialties: [String]?
    let pricing: [BarberPricingEntryDTO]?
}

/// One priced service row from `barbers.pricing` JSONB (`name`, `price`, optional `duration_minutes`).
struct BarberPricingEntryDTO: Decodable, Hashable {
    let name: String
    let price: Double
    let durationMinutes: Int?

    init(name: String, price: Double, durationMinutes: Int? = nil) {
        self.name = name
        self.price = price
        self.durationMinutes = durationMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawName = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        name = rawName
        if let d = try? c.decode(Double.self, forKey: .price) {
            price = d
        } else if let i = try? c.decode(Int.self, forKey: .price) {
            price = Double(i)
        } else if let s = try? c.decode(String.self, forKey: .price), let d = Double(s) {
            price = d
        } else {
            price = 0
        }
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case price
        case durationMinutes = "duration_minutes"
    }
}

// MARK: - Bookings simple

struct BookingsSimpleListEnvelope: Decodable {
    let success: Bool?
    let data: BookingsSimpleListData?
    let bookings: [SimpleBookingDTO]?

    var resolvedBookings: [SimpleBookingDTO] {
        data?.bookings ?? bookings ?? []
    }
}

struct BookingsSimpleListData: Decodable {
    let bookings: [SimpleBookingDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decoded: [SimpleBookingDTO] = []
        if var array = try? container.nestedUnkeyedContainer(forKey: .bookings) {
            while !array.isAtEnd {
                let itemDecoder = try array.superDecoder()
                do {
                    decoded.append(try SimpleBookingDTO(from: itemDecoder))
                } catch {
                    #if DEBUG
                    print("[BookingsSimpleListData] Skipped booking decode: \(error)")
                    #endif
                }
            }
        }
        bookings = decoded
    }

    private enum CodingKeys: String, CodingKey {
        case bookings
    }
}

struct BookingSimpleDetailEnvelope: Decodable {
    let booking: SimpleBookingDetailPayload?
}

/// `GET /bookings-simple/:id` — review fields are top-level, unlike the list shape.
struct SimpleBookingDetailPayload: Decodable {
    let id: String
    let consumerId: String?
    let barberId: String?
    let serviceType: String?
    let serviceName: String?
    let priceUsdCents: Int?
    let scheduledTime: Date?
    let status: String?
    let location: String?
    let notes: String?
    let paidAt: Date?
    let paymentRequestedAt: Date?
    let tipAmountCents: Int?
    let totalPaidCents: Int?
    let reviewRating: Double?
    let reviewComment: String?
    let reviewedAt: Date?
    let pendingRescheduleRequest: BookingPendingRescheduleRequestDTO?
    let consumer: SimpleBookingConsumer?
    let barber: SimpleBookingDetailBarber?
    let conversationId: Int?

    func asSimpleBookingDTO() -> SimpleBookingDTO {
        let review: SimpleBookingReview? = reviewRating != nil
            ? SimpleBookingReview(rating: reviewRating, comment: reviewComment, reviewedAt: reviewedAt)
            : nil
        let barberName = barber?.displayName
        return SimpleBookingDTO(
            id: id,
            consumerId: consumerId,
            barberId: barberId,
            serviceType: serviceType,
            priceUsdCents: priceUsdCents,
            scheduledTime: scheduledTime,
            status: status,
            location: location,
            notes: notes,
            serviceName: serviceName,
            review: review,
            paidAt: paidAt,
            paymentRequestedAt: paymentRequestedAt,
            tipAmountCents: tipAmountCents,
            totalPaidCents: totalPaidCents,
            paymentMethod: nil,
            pendingRescheduleRequest: pendingRescheduleRequest,
            consumer: consumer,
            consumerName: nil,
            barber: barber?.asConsumer,
            barberName: barberName,
            conversationId: conversationId
        )
    }
}

struct SimpleBookingDetailBarber: Decodable {
    let firstName: String?
    let lastName: String?
    let profileImageUrl: String?

    var displayName: String {
        let joined = "\(firstName ?? "") \(lastName ?? "")".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "Barber" : joined
    }

    var asConsumer: SimpleBookingConsumer {
        SimpleBookingConsumer(firstName: firstName, lastName: lastName, avatar: profileImageUrl)
    }
}

struct SimpleBookingReview: Decodable, Hashable {
    let rating: Double?
    let comment: String?
    let reviewedAt: Date?

    init(rating: Double?, comment: String?, reviewedAt: Date?) {
        self.rating = rating
        self.comment = comment
        self.reviewedAt = reviewedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rating = Self.decodeFlexibleRating(from: container)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        reviewedAt = Self.decodeFlexibleReviewedAt(from: container)
    }

    private enum CodingKeys: String, CodingKey {
        case rating
        case comment
        case reviewedAt
    }

    private static func decodeFlexibleRating(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: .rating) {
            return value
        }
        if let string = try? container.decodeIfPresent(String.self, forKey: .rating),
           let parsed = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .rating) {
            return Double(intValue)
        }
        return nil
    }

    /// `reviewedAt` occasionally arrives in legacy/non-ISO shapes; never fail the whole booking for it.
    private static func decodeFlexibleReviewedAt(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> Date? {
        guard container.contains(.reviewedAt) else { return nil }
        guard let nested = try? container.superDecoder(forKey: .reviewedAt) else { return nil }
        let single = try? nested.singleValueContainer()
        guard let single else { return nil }
        return ProviderBookingScheduleParsing.decodeFlexibleOptionalDate(from: single)
    }
}

/// Consumer-proposed schedule change awaiting barber approval (`booking_reschedule_requests`).
struct BookingPendingRescheduleRequestDTO: Decodable, Hashable {
    let id: String?
    let status: String?
    let proposedScheduledTime: Date?
    let proposedLocation: String?
    let proposedNotes: String?
    let createdAt: Date?
    let updatedAt: Date?
    private let proposedScheduledTimeRaw: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case proposedScheduledTime
        case proposedScheduledTimeSnake = "proposed_scheduled_time"
        case proposedTime = "proposed_time"
        case proposedLocation
        case proposedNotes
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        proposedLocation = try container.decodeIfPresent(String.self, forKey: .proposedLocation)
        proposedNotes = try container.decodeIfPresent(String.self, forKey: .proposedNotes)
        createdAt = ProviderAPIFlexibleDecoding.optionalDate(from: container, forKey: .createdAt)
        updatedAt = ProviderAPIFlexibleDecoding.optionalDate(from: container, forKey: .updatedAt)

        let raw =
            Self.decodeFlexibleString(from: container, forKey: .proposedScheduledTime)
            ?? Self.decodeFlexibleString(from: container, forKey: .proposedScheduledTimeSnake)
            ?? Self.decodeFlexibleString(from: container, forKey: .proposedTime)
        proposedScheduledTimeRaw = raw

        if let raw, let parsed = ProviderBookingScheduleParsing.parseAPIDateString(raw) {
            proposedScheduledTime = parsed
        } else {
            proposedScheduledTime =
                (try? container.decodeIfPresent(Date.self, forKey: .proposedScheduledTime))
                ?? (try? container.decodeIfPresent(Date.self, forKey: .proposedScheduledTimeSnake))
        }
    }

    var isPending: Bool {
        let normalized = (status ?? "pending").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "", "pending":
            return true
        case "declined", "rejected", "cancelled", "canceled", "approved", "accepted", "superseded":
            return false
        default:
            return false
        }
    }

    func formattedProposedSchedule() -> String {
        if let proposedScheduledTime {
            return proposedScheduledTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        }
        if let raw = proposedScheduledTimeRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if let parsed = ProviderBookingScheduleParsing.parseAPIDateString(raw) {
                return parsed.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            }
            return raw
        }
        return "Time TBD"
    }

    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let ms = try? container.decodeIfPresent(Double.self, forKey: key) {
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: ms / (ms > 1_000_000_000_000 ? 1000 : 1)))
        }
        return nil
    }
}

struct SimpleBookingConsumer: Decodable, Hashable {
    let firstName: String?
    let lastName: String?
    let avatar: String?
}

struct SimpleBookingDTO: Decodable, Identifiable, Hashable {
    let id: String
    let consumerId: String?
    let barberId: String?
    let serviceType: String?
    let priceUsdCents: Int?
    let scheduledTime: Date?
    let status: String?
    let location: String?
    let notes: String?
    let serviceName: String?
    let review: SimpleBookingReview?
    let paidAt: Date?
    let paymentRequestedAt: Date?
    let tipAmountCents: Int?
    let totalPaidCents: Int?
    let paymentMethod: String?
    let pendingRescheduleRequest: BookingPendingRescheduleRequestDTO?
    let consumer: SimpleBookingConsumer?
    /// `GET /bookings-simple/campus/:id` returns a single display string instead of `consumer`.
    let consumerName: String?
    let barber: SimpleBookingConsumer?
    /// `GET /bookings-simple/campus/:id` (and barber list) also send `barberName` as a single string.
    let barberName: String?
    /// Thread tied to this booking (`conversations.booking_id`), when one exists.
    let conversationId: Int?

    init(
        id: String,
        consumerId: String?,
        barberId: String?,
        serviceType: String?,
        priceUsdCents: Int?,
        scheduledTime: Date?,
        status: String?,
        location: String?,
        notes: String?,
        serviceName: String?,
        review: SimpleBookingReview?,
        paidAt: Date?,
        paymentRequestedAt: Date?,
        tipAmountCents: Int?,
        totalPaidCents: Int?,
        paymentMethod: String?,
        pendingRescheduleRequest: BookingPendingRescheduleRequestDTO?,
        consumer: SimpleBookingConsumer?,
        consumerName: String?,
        barber: SimpleBookingConsumer?,
        barberName: String?,
        conversationId: Int?
    ) {
        self.id = id
        self.consumerId = consumerId
        self.barberId = barberId
        self.serviceType = serviceType
        self.priceUsdCents = priceUsdCents
        self.scheduledTime = scheduledTime
        self.status = status
        self.location = location
        self.notes = notes
        self.serviceName = serviceName
        self.review = review
        self.paidAt = paidAt
        self.paymentRequestedAt = paymentRequestedAt
        self.tipAmountCents = tipAmountCents
        self.totalPaidCents = totalPaidCents
        self.paymentMethod = paymentMethod
        self.pendingRescheduleRequest = pendingRescheduleRequest
        self.consumer = consumer
        self.consumerName = consumerName
        self.barber = barber
        self.barberName = barberName
        self.conversationId = conversationId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try ProviderAPIFlexibleDecoding.requiredString(from: container, forKey: .id)
        consumerId = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .consumerId)
        barberId = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .barberId)
        serviceType = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .serviceType)
        priceUsdCents = ProviderAPIFlexibleDecoding.optionalInt(from: container, forKey: .priceUsdCents)
        scheduledTime = ProviderAPIFlexibleDecoding.optionalDate(from: container, forKey: .scheduledTime)
        status = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .status)
        location = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .location)
        notes = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .notes)
        serviceName = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .serviceName)
        review = try? container.decodeIfPresent(SimpleBookingReview.self, forKey: .review)
        paidAt = ProviderAPIFlexibleDecoding.optionalDate(from: container, forKey: .paidAt)
        paymentRequestedAt = ProviderAPIFlexibleDecoding.optionalDate(from: container, forKey: .paymentRequestedAt)
        tipAmountCents = ProviderAPIFlexibleDecoding.optionalInt(from: container, forKey: .tipAmountCents)
        totalPaidCents = ProviderAPIFlexibleDecoding.optionalInt(from: container, forKey: .totalPaidCents)
        paymentMethod = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .paymentMethod)
        pendingRescheduleRequest = try? container.decodeIfPresent(
            BookingPendingRescheduleRequestDTO.self,
            forKey: .pendingRescheduleRequest
        )
        consumer = try? container.decodeIfPresent(SimpleBookingConsumer.self, forKey: .consumer)
        consumerName = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .consumerName)
        barber = try? container.decodeIfPresent(SimpleBookingConsumer.self, forKey: .barber)
        barberName = ProviderAPIFlexibleDecoding.optionalString(from: container, forKey: .barberName)
        conversationId = ProviderAPIFlexibleDecoding.optionalInt(from: container, forKey: .conversationId)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case consumerId
        case barberId
        case serviceType
        case priceUsdCents
        case scheduledTime
        case status
        case location
        case notes
        case serviceName
        case review
        case paidAt
        case paymentRequestedAt
        case tipAmountCents
        case totalPaidCents
        case paymentMethod
        case pendingRescheduleRequest
        case consumer
        case consumerName
        case barber
        case barberName
        case conversationId
    }

    var consumerDisplayName: String {
        if let flat = consumerName?.trimmingCharacters(in: .whitespacesAndNewlines), !flat.isEmpty {
            return flat
        }
        let f = consumer?.firstName ?? ""
        let l = consumer?.lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "Customer" : joined
    }

    /// First + last initial for compact schedule labels (e.g. weekly swimlane cards).
    var consumerInitials: String {
        let first = consumer?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines).first
        let last = consumer?.lastName?.trimmingCharacters(in: .whitespacesAndNewlines).first
        if let first, let last {
            return "\(first)\(last)".uppercased()
        }
        if let first {
            return String(first).uppercased()
        }
        if let last {
            return String(last).uppercased()
        }
        return Self.initialsFromDisplayName(consumerDisplayName)
    }

    private static func initialsFromDisplayName(_ name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let chars = parts.prefix(2).compactMap(\.first)
        let joined = String(chars).uppercased()
        if !joined.isEmpty { return joined }
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    /// Service provider (barber) display name.
    var barberDisplayName: String {
        if let flat = barberName?.trimmingCharacters(in: .whitespacesAndNewlines), !flat.isEmpty {
            return flat
        }
        let f = barber?.firstName ?? ""
        let l = barber?.lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "Barber" : joined
    }

    var statusUpper: String { (status ?? "").uppercased() }

    var isCashPayment: Bool {
        paymentMethod?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "cash"
    }

    /// Completed visit where the provider requested payment and the consumer has not paid yet.
    var isCompletedAwaitingConsumerPayment: Bool {
        guard paidAt == nil else { return false }
        guard ProviderBookingStatusDisplay.normalized(status) == "completed" else { return false }
        if paymentRequestedAt != nil { return true }
        return ProviderAwaitingPaymentTracker.shared.requestedIds.contains(id)
    }

    var hasPendingRescheduleRequest: Bool {
        guard ProviderBookingStatusDisplay.isEligibleForPendingRescheduleRequest(status: status) else {
            return false
        }
        return pendingRescheduleRequest?.isPending == true
    }

    /// Human-readable service label for UI (`Haircut`, not `HAIRCUT`).
    var serviceDisplayName: String {
        ProviderServiceTypeDisplay.name(serviceName: serviceName, serviceType: serviceType)
    }
}

// MARK: - Barber availability (GET /barbers/:id/availability?date=YYYY-MM-DD)

/// One available time window on a given weekday, e.g. `09:00`–`17:00`.
struct BarberAvailabilityIntervalDTO: Decodable, Hashable {
    let id: String?
    let start: String
    let end: String
}

/// A booked / blocked HH:MM window for the queried date.
struct BarberAvailabilityBookedSlotDTO: Decodable, Hashable {
    let start: String
    let end: String
}

/// Discrete bookable slot the backend pre-computed (15-minute granularity on web; mobile only needs hours).
struct BarberAvailabilitySlotDTO: Decodable, Hashable {
    let time: String
    let available: Bool
}

struct BarberAvailabilityDayEnvelope: Decodable {
    let success: Bool?
    let data: BarberAvailabilityDayData?
}

struct BarberAvailabilityDayData: Decodable {
    let date: String?
    let dayOfWeek: String?
    let available: Bool?
    let intervals: [BarberAvailabilityIntervalDTO]?
    let bookedSlots: [BarberAvailabilityBookedSlotDTO]?
    let slots: [BarberAvailabilitySlotDTO]?
}

// MARK: - Weekly schedule editor (PUT /barbers/:id body: { weekly_schedule: WeeklyScheduleDTO })

/// Day-of-week key used by the backend's `weeklySchedule` JSONB column.
///
/// Order is **Sunday → Saturday** to match the JS `Date.getDay()` constants the controller relies on.
enum WeeklyScheduleDayKey: String, CaseIterable, Codable, Hashable, Identifiable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday
    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

struct ScheduleIntervalDTO: Codable, Hashable, Identifiable {
    var id: String
    var start: String
    var end: String

    init(id: String = UUID().uuidString.lowercased(), start: String, end: String) {
        self.id = id
        self.start = start
        self.end = end
    }
}

struct DayScheduleDTO: Codable, Hashable {
    var enabled: Bool
    var intervals: [ScheduleIntervalDTO]

    static let empty = DayScheduleDTO(enabled: false, intervals: [])

    /// Backwards-compatible legacy shape: `{ start, end }` with no `intervals` array.
    private enum CodingKeys: String, CodingKey {
        case enabled, intervals, start, end
    }

    init(enabled: Bool, intervals: [ScheduleIntervalDTO]) {
        self.enabled = enabled
        self.intervals = intervals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        if let parsed = try? c.decode([ScheduleIntervalDTO].self, forKey: .intervals) {
            intervals = parsed
        } else if let start = try? c.decode(String.self, forKey: .start),
                  let end = try? c.decode(String.self, forKey: .end)
        {
            intervals = [ScheduleIntervalDTO(id: "legacy", start: start, end: end)]
        } else {
            intervals = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(intervals, forKey: .intervals)
    }
}

/// `weeklySchedule` payload — keyed by lowercase day name. We model as a struct rather than a free
/// dictionary so the editor view has predictable bindings.
struct WeeklyScheduleDTO: Codable, Hashable {
    var sunday: DayScheduleDTO = .empty
    var monday: DayScheduleDTO = .empty
    var tuesday: DayScheduleDTO = .empty
    var wednesday: DayScheduleDTO = .empty
    var thursday: DayScheduleDTO = .empty
    var friday: DayScheduleDTO = .empty
    var saturday: DayScheduleDTO = .empty

    subscript(day: WeeklyScheduleDayKey) -> DayScheduleDTO {
        get {
            switch day {
            case .sunday: sunday
            case .monday: monday
            case .tuesday: tuesday
            case .wednesday: wednesday
            case .thursday: thursday
            case .friday: friday
            case .saturday: saturday
            }
        }
        set {
            switch day {
            case .sunday: sunday = newValue
            case .monday: monday = newValue
            case .tuesday: tuesday = newValue
            case .wednesday: wednesday = newValue
            case .thursday: thursday = newValue
            case .friday: friday = newValue
            case .saturday: saturday = newValue
            }
        }
    }

    /// JSON-serializable plain dictionary suitable for `[String: Any]` request bodies.
    func jsonObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

struct WeeklyScheduleEnvelope: Decodable {
    let success: Bool?
    let data: WeeklyScheduleData?
}

struct WeeklyScheduleData: Decodable {
    let weeklySchedule: WeeklyScheduleDTO?
}

// MARK: - Time blocks (GET/POST/DELETE /barbers/:id/time-blocks)

struct BarberTimeBlockDTO: Decodable, Hashable, Identifiable {
    let id: String
    let blockDate: String
    let startTime: String
    let endTime: String
    let reason: String?
    let createdAt: Date?
}

struct BarberTimeBlocksEnvelope: Decodable {
    let success: Bool?
    let data: [BarberTimeBlockDTO]?
}

struct BarberTimeBlockSingleEnvelope: Decodable {
    let success: Bool?
    let data: BarberTimeBlockDTO?
}

// MARK: - Google Calendar (auth/google-calendar/*)

/// Raw shape from `/auth/google-calendar/status` (no `success/data` envelope on this endpoint).
struct GoogleCalendarStatusDTO: Decodable, Hashable {
    let connected: Bool
    let connectedAt: Date?
    let syncEnabled: Bool?
}

/// Raw shape from `/auth/google-calendar/connect`.
struct GoogleCalendarAuthURLDTO: Decodable {
    let authUrl: String
}

// MARK: - Admin / Campus-Manager DTOs (parity with web `AdminDashboard.tsx` + `CampusManagerDashboard.tsx`)

/// `/admin/stats` — small unwrapped payload of totals across the platform.
struct AdminPlatformStatsDTO: Decodable, Hashable {
    let totalUsers: Int?
    let totalBookings: Int?
    let totalBarbers: Int?
    let totalCampuses: Int?
}

/// `/admin/campuses` row. Same shape works for the Campus Manager's single-campus lookup, and
/// for the public `GET /api/v1/campus` directory used by the provider enrollment flow.
///
/// `latitude` / `longitude` are populated when the backend returns them (the public `/campus`
/// route selects both columns explicitly); admin and campus-manager routes currently omit them,
/// in which case both fields are `nil` and proximity matching falls back to client-side
/// geocoding via `NearestCampusResolver`.
struct AdminCampusDTO: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let slug: String?
    let city: String?
    let state: String?
    let managerId: String?
    let managerName: String?
    let latitude: Double?
    let longitude: Double?

    var displayName: String { name ?? slug ?? "Campus" }
    var locationLine: String? {
        let parts = [city, state].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, city, state, managerId, managerName, latitude, longitude
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        managerId = try c.decodeIfPresent(String.self, forKey: .managerId)
        managerName = try c.decodeIfPresent(String.self, forKey: .managerName)
        // Postgres `numeric` columns are serialized by `node-postgres` as JSON strings to
        // preserve precision, so latitude/longitude can land as either number or string
        // depending on which route returns them. Accept both shapes defensively.
        latitude = Self.decodeFlexibleDouble(c, key: .latitude)
        longitude = Self.decodeFlexibleDouble(c, key: .longitude)
    }

    init(
        id: String,
        name: String? = nil,
        slug: String? = nil,
        city: String? = nil,
        state: String? = nil,
        managerId: String? = nil,
        managerName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.city = city
        self.state = state
        self.managerId = managerId
        self.managerName = managerName
        self.latitude = latitude
        self.longitude = longitude
    }

    private static func decodeFlexibleDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

struct AdminCampusesEnvelope: Decodable {
    let success: Bool?
    let data: AdminCampusesData?
    let campuses: [AdminCampusDTO]?

    var resolved: [AdminCampusDTO] {
        if let list = data?.campuses { return list }
        if let list = campuses { return list }
        return []
    }
}

struct AdminCampusesData: Decodable {
    let campuses: [AdminCampusDTO]?
}

/// Payload from `GET /admin/campuses/.../performance` (aggregate or per-campus). Matches web `CampusPerformance`;
/// amounts are in **cents** unless noted. Extra keys from the API are ignored by `Decodable`.
struct AdminCampusPerformanceDTO: Decodable, Hashable {
    let totalBarbers: Int?
    let activeBarbers: Int?
    let totalConsumers: Int?
    let totalBookings: Int?
    let completedBookings: Int?
    let cancelledBookings: Int?
    let totalRevenue: Double?           // cents
    let totalPlatformFees: Double?      // cents
    let totalBarberEarnings: Double?    // cents
    let netPlatformRevenue: Double?     // cents
    let totalTips: Double?              // cents
    let cardRevenue: Double?            // cents
    let cardCount: Int?
    let cashRevenue: Double?            // cents
    let cashCount: Int?
    let averageRating: Double?
    let totalReviews: Int?

    // MARK: - Stripe fee breakdown (cents; estimates from backend heuristics)
    let stripeProcessingFees: Double?
    let stripeConnectFees: Double?
    let estimatedStripeFees: Double?
    let activeAccountBilling: Double?
    let volumeBilling: Double?
    let payoutFees: Double?
    let activeConnectAccounts: Int?
    let estimatedPayouts: Int?
    let completedTransactionCount: Int?
}

struct AdminCampusPerformanceEnvelope: Decodable {
    let success: Bool?
    let data: AdminCampusPerformanceDTO?
}

/// One bucket from `GET /admin/campuses/aggregate/metrics` or `.../:campusId/metrics` (`period` query matches web admin).
struct AdminMetricsSeriesPointDTO: Decodable, Hashable, Identifiable {
    let date: String
    let bookings: Int?
    let revenue: Int?
    let users: Int?

    var id: String { date }
}

/// Time-series payload: paid bookings + revenue (`paidAt`) and consumer signups per bucket.
struct AdminMetricsSnapshotDTO: Decodable, Hashable {
    let period: String?
    let data: [AdminMetricsSeriesPointDTO]?
    let totalUsers: Int?
}

/// `/admin/campuses/:id/barbers` (and `/admin/barbers`) row.
struct AdminBarberDTO: Decodable, Hashable, Identifiable {
    let id: String
    let barberRecordId: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let profileImageUrl: String?
    let isActive: Bool?
    let isCampusManager: Bool?
    let campusId: String?
    let campusName: String?
    let hasStripeSetup: Bool?
    let hasStripeAccountOnly: Bool?
    let createdAt: Date?
    let completedBookings: Int?
    let totalVolumeCents: Int?

    var displayName: String {
        let f = firstName ?? ""
        let l = lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty { return joined }
        if let email, !email.isEmpty { return email }
        return "Barber"
    }

    var avatarURL: URL? {
        guard let s = profileImageUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return URL(string: s)
    }
}

struct AdminBarbersEnvelope: Decodable {
    let success: Bool?
    let data: AdminBarbersData?
    let barbers: [AdminBarberDTO]?

    var resolved: [AdminBarberDTO] {
        if let list = data?.barbers { return list }
        if let list = barbers { return list }
        return []
    }
}

struct AdminBarbersData: Decodable {
    let barbers: [AdminBarberDTO]?
}

/// `/admin/barbers/:id/bookings` row (parity with web `BarberBooking` interface).
struct AdminBarberBookingDTO: Decodable, Hashable, Identifiable {
    let id: String
    let serviceType: String?
    let priceCents: Int?
    let tipCents: Int?
    let totalPaidCents: Int?
    let status: String?
    let paymentMethod: String?
    let scheduledTime: Date?
    let createdAt: Date?
    let paidAt: Date?
    let reviewRating: Double?
    let reviewText: String?
    let consumerId: String?
    let consumerFirstName: String?
    let consumerLastName: String?
    let consumerEmail: String?
    let consumerAvatar: String?
    let messageCount: Int?

    var consumerDisplayName: String {
        let f = consumerFirstName ?? ""
        let l = consumerLastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty { return joined }
        return consumerEmail ?? "Customer"
    }

    var serviceDisplayName: String {
        ProviderServiceTypeDisplay.format(serviceType)
    }
}

struct AdminBarberBookingsEnvelope: Decodable {
    let success: Bool?
    let data: AdminBarberBookingsData?
    let bookings: [AdminBarberBookingDTO]?

    var resolved: [AdminBarberBookingDTO] {
        if let list = data?.bookings { return list }
        if let list = bookings { return list }
        return []
    }
}

struct AdminBarberBookingsData: Decodable {
    let bookings: [AdminBarberBookingDTO]?
}

/// `/admin/users/:id/bookings` row (consumer-side view of bookings).
struct AdminConsumerBookingDTO: Decodable, Hashable, Identifiable {
    let id: String
    let serviceType: String?
    let priceCents: Int?
    let tipCents: Int?
    let totalPaidCents: Int?
    let status: String?
    let paymentMethod: String?
    let scheduledTime: Date?
    let createdAt: Date?
    let paidAt: Date?
    let reviewRating: Double?
    let reviewText: String?
    let barberRecordId: String?
    let barberUserId: String?
    let barberFirstName: String?
    let barberLastName: String?
    let barberEmail: String?
    let barberAvatar: String?

    var barberDisplayName: String {
        let f = barberFirstName ?? ""
        let l = barberLastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty { return joined }
        return barberEmail ?? "Barber"
    }

    var serviceDisplayName: String {
        ProviderServiceTypeDisplay.format(serviceType)
    }
}

struct AdminConsumerBookingsEnvelope: Decodable {
    let success: Bool?
    let data: AdminConsumerBookingsData?
    let bookings: [AdminConsumerBookingDTO]?

    var resolved: [AdminConsumerBookingDTO] {
        if let list = data?.bookings { return list }
        if let list = bookings { return list }
        return []
    }
}

struct AdminConsumerBookingsData: Decodable {
    let bookings: [AdminConsumerBookingDTO]?
}

/// `/admin/users` row.
struct AdminPlatformUserDTO: Decodable, Hashable, Identifiable {
    let id: String
    let firstName: String?
    let lastName: String?
    let email: String?
    let role: String?
    let avatarUrl: String?
    let campusName: String?
    let createdAt: Date?
    let isActive: Bool?
    let customerNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, firstName, lastName, email, role, avatarUrl, campusName, createdAt, isActive, customerNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        campusName = try c.decodeIfPresent(String.self, forKey: .campusName)
        createdAt = Self.decodeOptionalDate(c, forKey: .createdAt)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive)
        customerNumber = Self.decodeOptionalIntLenient(c, forKey: .customerNumber)
    }

    private static func decodeOptionalDate(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        guard c.contains(key) else { return nil }
        guard (try? c.decodeNil(forKey: key)) != true else { return nil }
        return (try? c.decode(Date.self, forKey: key)) ?? nil
    }

    private static func decodeOptionalIntLenient(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        guard c.contains(key) else { return nil }
        guard (try? c.decodeNil(forKey: key)) != true else { return nil }
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key) {
            return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    var displayName: String {
        let f = firstName ?? ""
        let l = lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty { return joined }
        return email ?? "User"
    }

    var avatarURL: URL? {
        guard let s = avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var prettyRole: String { (role ?? "").replacingOccurrences(of: "_", with: " ").capitalized }
}

struct AdminUsersEnvelope: Decodable {
    let success: Bool?
    let data: AdminUsersData?
    let users: [AdminPlatformUserDTO]?
    let pagination: AdminPagination?

    var resolved: [AdminPlatformUserDTO] {
        if let list = data?.users { return list }
        if let list = users { return list }
        return []
    }
}

struct AdminUsersData: Decodable {
    let users: [AdminPlatformUserDTO]?
    let pagination: AdminPagination?
}

struct AdminPagination: Decodable, Hashable {
    let page: Int?
    let limit: Int?
    let total: Int?
    let pages: Int?
}

// MARK: - Booking requests

struct BookingRequestsPendingEnvelope: Decodable {
    let success: Bool?
    let requests: [BookingRequestRow]?
}

struct BookingRequestRow: Decodable, Identifiable, Hashable {
    let bookingId: String
    let customerId: String?
    let customerName: String?
    let serviceType: String?
    let requestedDate: String?
    let requestedTime: String?
    let location: String?
    let status: String?
    let price: Double?

    var id: String { bookingId }

    var titleLine: String {
        let svc = serviceDisplayName
        let who = customerName ?? "Customer"
        return "\(svc) · \(who)"
    }

    /// Human-readable service label for UI (`Haircut`, not `HAIRCUT`).
    var serviceDisplayName: String {
        ProviderServiceTypeDisplay.format(serviceType)
    }

    /// Consumer's requested appointment time when present on the row.
    var requestedScheduleInstant: Date? {
        ProviderBookingScheduleParsing.requestedInstant(from: self)
    }

    func formattedRequestedSchedule() -> String {
        ProviderBookingScheduleParsing.formattedRequestedSchedule(from: self)
    }
}

// MARK: - Messages

struct ConversationsEnvelope: Decodable {
    let success: Bool?
    let data: ConversationsPage?
}

struct ConversationsPage: Decodable {
    let conversations: [ConversationRow]
}

struct ConversationOtherUser: Decodable, Hashable {
    let id: String?
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let profilePicture: String?

    init(
        id: String?,
        firstName: String? = nil,
        lastName: String? = nil,
        displayName: String? = nil,
        profilePicture: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
        self.profilePicture = profilePicture
    }
}

struct ConversationRow: Decodable, Identifiable, Hashable {
    let id: Int
    let bookingId: String?
    let booking: ConversationBookingSummary?
    let unreadCount: Int?
    let lastMessage: ConversationLastMessage?
    let otherUser: ConversationOtherUser?

    init(
        id: Int,
        bookingId: String? = nil,
        booking: ConversationBookingSummary? = nil,
        unreadCount: Int? = nil,
        lastMessage: ConversationLastMessage? = nil,
        otherUser: ConversationOtherUser? = nil
    ) {
        self.id = id
        self.bookingId = bookingId
        self.booking = booking
        self.unreadCount = unreadCount
        self.lastMessage = lastMessage
        self.otherUser = otherUser
    }
}

struct ConversationBookingSummary: Decodable, Hashable {
    let id: String?
    let serviceName: String?
    let scheduledTime: Date?
    let status: String?

    var statusUpper: String { (status ?? "").uppercased() }

    var serviceDisplayName: String {
        ProviderServiceTypeDisplay.format(serviceName)
    }
}

struct ConversationLastMessage: Decodable, Hashable {
    let content: String?
    let time: Date?
    /// User ID (UUID string) of the participant who sent this last message.
    ///
    /// Backend returns it on every conversation row (see `message.service.getUserConversations` —
    /// the `last_message_sender_id` SELECT, surfaced as `senderId` in the JSON response). We use
    /// it on the inbox to color each row's direction indicator: light green when the *other*
    /// party sent the latest message (you have something waiting), dark green when *you* sent it
    /// (ball is in their court). `nil` only on conversations with no messages yet.
    let senderId: String?

    init(content: String? = nil, time: Date? = nil, senderId: String? = nil) {
        self.content = content
        self.time = time
        self.senderId = senderId
    }
}

struct MessagesEnvelope: Decodable {
    let success: Bool?
    let data: MessagesPage?
}

struct MessagesPage: Decodable {
    let messages: [ChatMessageDTO]
}

struct ChatMessageDTO: Decodable, Identifiable, Hashable {
    let id: Int
    let content: String?
    let senderId: String?
    let createdAt: Date?
    let isOwn: Bool?
    let messageType: String?
    let mediaUrl: String?
    let metadata: ChatMessageMetadataDTO?

    init(
        id: Int,
        content: String?,
        senderId: String?,
        createdAt: Date?,
        isOwn: Bool?,
        messageType: String?,
        mediaUrl: String?,
        metadata: ChatMessageMetadataDTO?
    ) {
        self.id = id
        self.content = content
        self.senderId = senderId
        self.createdAt = createdAt
        self.isOwn = isOwn
        self.messageType = messageType
        self.mediaUrl = mediaUrl
        self.metadata = metadata
    }

    /// Optimistic outbound row shown while a send request is in flight.
    static func pendingOutbound(id: Int, text: String) -> ChatMessageDTO {
        ChatMessageDTO(
            id: id,
            content: text,
            senderId: nil,
            createdAt: Date(),
            isOwn: true,
            messageType: "text",
            mediaUrl: nil,
            metadata: nil
        )
    }

    /// Optimistic outbound image row shown while upload + send are in flight.
    static func pendingOutboundImage(id: Int) -> ChatMessageDTO {
        ChatMessageDTO(
            id: id,
            content: nil,
            senderId: nil,
            createdAt: Date(),
            isOwn: true,
            messageType: "image",
            mediaUrl: nil,
            metadata: nil
        )
    }

    var isBookingRequest: Bool {
        messageType == "booking_request" || messageType == "booking-request"
    }

    var isImage: Bool {
        let type = (messageType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type == "image"
    }
}

struct ChatMessageMetadataDTO: Decodable, Hashable {
    let bookingId: String?
    let serviceName: String?
    let appointmentDate: String?
    let appointmentTime: String?
    let status: String?
    let customerName: String?
}

extension ChatMessageMetadataDTO {
    var serviceDisplayName: String {
        ProviderServiceTypeDisplay.format(serviceName)
    }
}

struct BlockedConsumersEnvelope: Decodable {
    let success: Bool?
    let data: [BlockedConsumerRow]?
}

struct BlockedConsumerRow: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String?
    let blockedAt: Date?
}

// MARK: - Barber Chats (peer + admin support rosters)

/// Row from `GET /messages/barber-chats/barbers` or `GET /messages/cm-barber/conversations`.
struct BarberChatRowDTO: Decodable, Hashable, Identifiable {
    let userId: String
    let barberId: String
    let name: String
    let firstName: String?
    let lastName: String?
    let avatarUrl: String?
    let email: String
    let isCampusManager: Bool?
    let conversationId: Int?
    let lastMessage: String?
    let lastMessageAt: String?
    let unreadCount: Int
    /// Populated client-side when merging per-campus admin rosters.
    let campusId: String?
    /// Whether the barber is visible to consumers (`barbers.isActive`).
    let isActive: Bool?

    var id: String { userId }

    var avatarURL: URL? {
        guard let raw = avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    init(
        userId: String,
        barberId: String,
        name: String,
        firstName: String?,
        lastName: String?,
        avatarUrl: String?,
        email: String,
        isCampusManager: Bool?,
        conversationId: Int?,
        lastMessage: String?,
        lastMessageAt: String?,
        unreadCount: Int,
        campusId: String? = nil,
        isActive: Bool? = nil
    ) {
        self.userId = userId
        self.barberId = barberId
        self.name = name
        self.firstName = firstName
        self.lastName = lastName
        self.avatarUrl = avatarUrl
        self.email = email
        self.isCampusManager = isCampusManager
        self.conversationId = conversationId
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
        self.campusId = campusId
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        barberId = try container.decode(String.self, forKey: .barberId)
        name = try container.decode(String.self, forKey: .name)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        email = try container.decode(String.self, forKey: .email)
        isCampusManager = try container.decodeIfPresent(Bool.self, forKey: .isCampusManager)
        conversationId = try container.decodeIfPresent(Int.self, forKey: .conversationId)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        lastMessageAt = try container.decodeIfPresent(String.self, forKey: .lastMessageAt)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        campusId = try container.decodeIfPresent(String.self, forKey: .campusId)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
    }

    func tagged(campusId: String) -> BarberChatRowDTO {
        BarberChatRowDTO(
            userId: userId,
            barberId: barberId,
            name: name,
            firstName: firstName,
            lastName: lastName,
            avatarUrl: avatarUrl,
            email: email,
            isCampusManager: isCampusManager,
            conversationId: conversationId,
            lastMessage: lastMessage,
            lastMessageAt: lastMessageAt,
            unreadCount: unreadCount,
            campusId: campusId,
            isActive: isActive
        )
    }

    func conversationRow(conversationId: Int) -> ConversationRow {
        ConversationRow(
            id: conversationId,
            bookingId: nil,
            booking: nil,
            unreadCount: unreadCount,
            lastMessage: ConversationLastMessage(
                content: lastMessage,
                time: BarberChatTimestampParsing.parse(lastMessageAt),
                senderId: nil
            ),
            otherUser: ConversationOtherUser(
                id: userId,
                firstName: firstName,
                lastName: lastName,
                displayName: name,
                profilePicture: avatarUrl
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case userId, barberId, name, firstName, lastName, avatarUrl, email
        case isCampusManager, conversationId, lastMessage, lastMessageAt, unreadCount, campusId, isActive
    }
}

struct BarberChatsListEnvelope: Decodable {
    let success: Bool?
    let data: BarberChatsListData?
}

struct BarberChatsListData: Decodable {
    let barbers: [BarberChatRowDTO]?
}

struct StartBarberChatConversationEnvelope: Decodable {
    let success: Bool?
    let data: StartBarberChatConversationData?
}

struct StartBarberChatConversationData: Decodable {
    let conversation: StartBarberChatConversationRef?
}

struct StartBarberChatConversationRef: Decodable {
    let id: Int
    let otherUserId: String?
    let isNew: Bool?
}

enum BarberChatTimestampParsing {
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return isoFrac.date(from: raw) ?? isoBasic.date(from: raw)
    }

    static func formatListTimestamp(_ raw: String?) -> String {
        guard let date = parse(raw) else { return "" }
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let dayDiff = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if dayDiff < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Barber applications (Campus Manager / Admin queue)

/// Status enum for `GET /api/v1/barber-applications` rows.
///
/// Backend allows any-to-any transitions across these five values (validation is enum-only —
/// there is no server-side state machine). Web Campus Manager UI only sends `approved` /
/// `rejected` today; `under_review` and `interview_scheduled` exist in the schema but the web
/// dashboard treats interview scheduling as an out-of-band contact action rather than a
/// status change.
enum BarberApplicationStatus: String, Codable, Hashable, CaseIterable {
    case pending
    case underReview = "under_review"
    case interviewScheduled = "interview_scheduled"
    case approved
    case rejected

    var displayLabel: String {
        switch self {
        case .pending: "Pending"
        case .underReview: "Under review"
        case .interviewScheduled: "Interview scheduled"
        case .approved: "Approved"
        case .rejected: "Rejected"
        }
    }
}

/// Provenance of an application row.
///
/// Mirrors `application_type` from the union in the list query — `regular` rows live in
/// `barber_applications` (signed-in user), `guest` rows live in `guest_barber_applications`
/// (landing-page submissions before account creation).
enum BarberApplicationOrigin: String, Codable, Hashable {
    case regular
    case guest
}

/// One row from `GET /api/v1/barber-applications`.
///
/// Snake-case fields from the controller's UNION SELECT are decoded directly. `reviewedAt`
/// and `interviewScheduledAt` come back `null` for guest rows even when set, because the
/// guest table doesn't carry those columns; treat as nil-safe metadata only.
///
/// `portfolioDescription`, `toolsNeeded`, `reviewNotes`, `reviewedBy`, and `updatedAt` are
/// intentionally absent — the backend list SELECT does not return them today.
struct BarberApplicationListRowDTO: Decodable, Identifiable, Hashable {
    let id: String
    let userId: String?
    let status: String
    let yearsExperience: String?
    let hasLicense: Bool?
    let licenseNumber: String?
    let specialties: [String]?
    let hasOwnTools: Bool?
    let availableHours: String?
    let whyBeBarber: String?
    let phoneNumber: String?
    let socialMedia: String?
    let additionalNotes: String?
    let createdAt: Date?
    let reviewedAt: Date?
    let interviewScheduledAt: Date?
    let email: String?
    let firstName: String?
    let lastName: String?
    let campusName: String?
    let campusId: String?
    let applicationType: String?

    var origin: BarberApplicationOrigin { BarberApplicationOrigin(rawValue: applicationType ?? "regular") ?? .regular }
    var statusEnum: BarberApplicationStatus? { BarberApplicationStatus(rawValue: status) }

    var displayName: String {
        let f = firstName ?? ""
        let l = lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty { return joined }
        return email ?? "Applicant"
    }

    /// Mirrors web Campus Manager filter (`pending` plus approved guests without an account).
    /// These are the rows that actually need a manager action.
    var isActionableInAdminApplicationQueue: Bool {
        if status == BarberApplicationStatus.pending.rawValue { return true }
        if status == BarberApplicationStatus.approved.rawValue,
           origin == .guest,
           (userId ?? "").isEmpty
        {
            return true
        }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case status
        case yearsExperience
        case hasLicense
        case licenseNumber
        case specialties
        case hasOwnTools
        case availableHours
        case whyBeBarber
        case phoneNumber
        case socialMedia
        case additionalNotes
        case createdAt
        case reviewedAt
        case interviewScheduledAt
        case email
        case firstName
        case lastName
        case campusName
        case campusId
        case applicationType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        status = (try? c.decode(String.self, forKey: .status)) ?? "pending"
        if let text = try c.decodeIfPresent(String.self, forKey: .yearsExperience) {
            yearsExperience = text
        } else if let number = try c.decodeIfPresent(Int.self, forKey: .yearsExperience) {
            yearsExperience = String(number)
        } else {
            yearsExperience = nil
        }
        hasLicense = try c.decodeIfPresent(Bool.self, forKey: .hasLicense)
        licenseNumber = try c.decodeIfPresent(String.self, forKey: .licenseNumber)
        specialties = try c.decodeIfPresent([String].self, forKey: .specialties)
        hasOwnTools = try c.decodeIfPresent(Bool.self, forKey: .hasOwnTools)
        availableHours = try c.decodeIfPresent(String.self, forKey: .availableHours)
        whyBeBarber = try c.decodeIfPresent(String.self, forKey: .whyBeBarber)
        phoneNumber = try c.decodeIfPresent(String.self, forKey: .phoneNumber)
        socialMedia = try c.decodeIfPresent(String.self, forKey: .socialMedia)
        additionalNotes = try c.decodeIfPresent(String.self, forKey: .additionalNotes)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        reviewedAt = try c.decodeIfPresent(Date.self, forKey: .reviewedAt)
        interviewScheduledAt = try c.decodeIfPresent(Date.self, forKey: .interviewScheduledAt)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        campusName = try c.decodeIfPresent(String.self, forKey: .campusName)
        campusId = try c.decodeIfPresent(String.self, forKey: .campusId)
        applicationType = try c.decodeIfPresent(String.self, forKey: .applicationType)
    }
}

struct BarberApplicationsListEnvelope: Decodable {
    let success: Bool?
    let data: BarberApplicationsListData?
}

struct BarberApplicationsListData: Decodable {
    let applications: [BarberApplicationListRowDTO]?
    let pagination: BarberApplicationsPagination?
}

/// Pagination block for `GET /api/v1/barber-applications` — distinct from `AdminPagination`
/// because this endpoint emits `totalPages` (camelCase preserved by the snake-case decoder)
/// rather than `pages` like the admin users route.
struct BarberApplicationsPagination: Decodable, Hashable {
    let page: Int?
    let limit: Int?
    let total: Int?
    let totalPages: Int?
}

// MARK: - Admin moderation (Safety)
//
// The Admin **Safety** tab surfaces platform `users."isBanned"` — distinct from peer
// `user_blocks` (consumer-blocked-barber relationships, scoped to the blocker's own settings)
// and `users."isBlocked"` (a legacy sign-in gate not used in the admin dashboard). Web web
// only renders banned users + UGC reports here; we mirror that scope.
//
// Endpoints used by the Safety tab:
//   GET  /api/v1/admin/moderation/reports?status=…&limit=…
//   GET  /api/v1/admin/moderation/banned-users?category=…&limit=…
//   POST /api/v1/admin/moderation/reports/:reportId/resolve
//   POST /api/v1/admin/users/:userId/unban

/// Status of a UGC content report. Backend supports `open`, `dismissed`, `resolved` and the
/// web admin defaults to `open`.
enum AdminModerationReportStatus: String, Codable, Hashable, CaseIterable {
    case open
    case dismissed
    case resolved

    var displayLabel: String {
        switch self {
        case .open: "Open"
        case .dismissed: "Dismissed"
        case .resolved: "Resolved"
        }
    }
}

/// Actions an admin can take when resolving a report. The backend treats `ban_reported_user`
/// and `remove_message_and_ban` as the ban-causing actions (`users.isBanned = true` + booking
/// cleanup). Web admin uses only these four values today.
enum AdminModerationResolveAction: String, Codable, Hashable {
    case dismiss
    case removeMessage = "remove_message"
    case banReportedUser = "ban_reported_user"
    case removeMessageAndBan = "remove_message_and_ban"

    var displayLabel: String {
        switch self {
        case .dismiss: "Dismiss"
        case .removeMessage: "Remove message"
        case .banReportedUser: "Ban user"
        case .removeMessageAndBan: "Remove + ban"
        }
    }

    /// Causes a ban (used to gate confirmation copy + destructive button role).
    var bansUser: Bool {
        switch self {
        case .banReportedUser, .removeMessageAndBan: true
        case .dismiss, .removeMessage: false
        }
    }

    var systemImage: String {
        switch self {
        case .dismiss: "xmark.circle"
        case .removeMessage: "trash"
        case .banReportedUser: "nosign"
        case .removeMessageAndBan: "exclamationmark.octagon"
        }
    }
}

/// Server-side category labels for banned users. `all` is the unfiltered request (no `category`
/// query param sent). Order matches the chips on web.
enum AdminBannedUserCategory: String, Codable, Hashable, CaseIterable, Identifiable {
    case all
    case serviceProvider = "service_provider"
    case consumer
    case admin
    case other

    var id: String { rawValue }

    /// Filter chip label.
    var chipLabel: String {
        switch self {
        case .all: "All"
        case .serviceProvider: "Service providers"
        case .consumer: "Consumers"
        case .admin: "Admins"
        case .other: "Other"
        }
    }

    /// Singular label shown next to a banned user row.
    var rowLabel: String {
        switch self {
        case .all: "Account"
        case .serviceProvider: "Service provider"
        case .consumer: "Consumer"
        case .admin: "Admin"
        case .other: "Other"
        }
    }
}

/// Row returned by `GET /admin/moderation/banned-users`. Mirrors the SELECT used by the web
/// banned-users list (snake_case in JSON, converted to camelCase by the decoder).
///
/// `account_category` is the same enum string as `AdminBannedUserCategory` (minus `all`).
/// `barber_is_active` is only meaningful when `has_barber_profile` is true.
struct AdminBannedUserDTO: Decodable, Identifiable, Hashable {
    let id: String
    let firstName: String?
    let lastName: String?
    let email: String?
    let role: String?
    let accountCategory: String?
    let campusName: String?
    let hasBarberProfile: Bool?
    let barberIsActive: Bool?
    let openReportCount: Int?
    let updatedAt: Date?

    var displayName: String {
        let f = firstName ?? ""
        let l = lastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty { return joined }
        return email ?? "Account"
    }

    var categoryEnum: AdminBannedUserCategory? {
        AdminBannedUserCategory(rawValue: accountCategory ?? "")
    }

    var categoryLabel: String {
        categoryEnum?.rowLabel ?? (accountCategory?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Account")
    }

    /// User-facing description of the barber-listing state. Returns nil when the user has no
    /// barber profile (no listing state to surface).
    var barberListingStateLabel: String? {
        guard hasBarberProfile == true else { return nil }
        return (barberIsActive == true) ? "Barber listing active" : "Barber listing inactive"
    }
}

struct AdminBannedUsersEnvelope: Decodable {
    let success: Bool?
    let data: AdminBannedUsersData?
    let bannedUsers: [AdminBannedUserDTO]?

    var resolved: [AdminBannedUserDTO] {
        if let list = data?.bannedUsers { return list }
        if let list = bannedUsers { return list }
        return []
    }
}

struct AdminBannedUsersData: Decodable {
    let bannedUsers: [AdminBannedUserDTO]?
}

/// One row from `GET /admin/moderation/reports`.
///
/// User identities can arrive either flattened (`reporter_user_id`, `reporter_first_name`, …)
/// or nested under `reporter` / `reported_user` keyed objects, depending on the exact controller
/// SELECT shape — we decode both defensively. Unknown fields are ignored. The action / notes
/// for resolved or dismissed reports live in `resolution_action` / `resolution_notes`.
struct AdminModerationReportDTO: Decodable, Identifiable, Hashable {
    let id: String
    let status: String
    let reason: String?
    let description: String?
    let subjectType: String?
    let subjectId: String?
    let subjectContent: String?

    let reportedUserId: String?
    let reportedUserFirstName: String?
    let reportedUserLastName: String?
    let reportedUserEmail: String?

    let reporterUserId: String?
    let reporterFirstName: String?
    let reporterLastName: String?
    let reporterEmail: String?

    let createdAt: Date?
    let resolvedAt: Date?
    let resolutionAction: String?
    let resolutionNotes: String?

    var statusEnum: AdminModerationReportStatus? { AdminModerationReportStatus(rawValue: status) }

    var isOpen: Bool { statusEnum == .open }

    var reportedUserDisplayName: String {
        let f = reportedUserFirstName ?? ""
        let l = reportedUserLastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty { return joined }
        if let email = reportedUserEmail, !email.isEmpty { return email }
        return "Reported account"
    }

    var reporterDisplayName: String {
        let f = reporterFirstName ?? ""
        let l = reporterLastName ?? ""
        let joined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty { return joined }
        if let email = reporterEmail, !email.isEmpty { return email }
        return "Reporter"
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, reason, description, subjectType, subjectId, subjectContent
        case reportedUser, reportedUserId, reportedUserFirstName, reportedUserLastName, reportedUserEmail
        case reporter, reporterUserId, reporterFirstName, reporterLastName, reporterEmail
        case createdAt, resolvedAt, resolutionAction, resolutionNotes
    }

    private struct NestedUserRef: Decodable {
        let id: String?
        let firstName: String?
        let lastName: String?
        let email: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = (try? c.decode(String.self, forKey: .status)) ?? "open"
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        subjectType = try? c.decodeIfPresent(String.self, forKey: .subjectType)
        subjectId = try? c.decodeIfPresent(String.self, forKey: .subjectId)
        subjectContent = try? c.decodeIfPresent(String.self, forKey: .subjectContent)

        // Prefer nested objects when the API joins user rows under `reported_user` / `reporter`;
        // fall back to flat columns (`reported_user_id`, …) for SELECTs that flatten.
        if let nested = try? c.decodeIfPresent(NestedUserRef.self, forKey: .reportedUser) {
            reportedUserId = nested.id
            reportedUserFirstName = nested.firstName
            reportedUserLastName = nested.lastName
            reportedUserEmail = nested.email
        } else {
            reportedUserId = try? c.decodeIfPresent(String.self, forKey: .reportedUserId)
            reportedUserFirstName = try? c.decodeIfPresent(String.self, forKey: .reportedUserFirstName)
            reportedUserLastName = try? c.decodeIfPresent(String.self, forKey: .reportedUserLastName)
            reportedUserEmail = try? c.decodeIfPresent(String.self, forKey: .reportedUserEmail)
        }

        if let nested = try? c.decodeIfPresent(NestedUserRef.self, forKey: .reporter) {
            reporterUserId = nested.id
            reporterFirstName = nested.firstName
            reporterLastName = nested.lastName
            reporterEmail = nested.email
        } else {
            reporterUserId = try? c.decodeIfPresent(String.self, forKey: .reporterUserId)
            reporterFirstName = try? c.decodeIfPresent(String.self, forKey: .reporterFirstName)
            reporterLastName = try? c.decodeIfPresent(String.self, forKey: .reporterLastName)
            reporterEmail = try? c.decodeIfPresent(String.self, forKey: .reporterEmail)
        }

        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        resolvedAt = try? c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        resolutionAction = try? c.decodeIfPresent(String.self, forKey: .resolutionAction)
        resolutionNotes = try? c.decodeIfPresent(String.self, forKey: .resolutionNotes)
    }
}

struct AdminModerationReportsEnvelope: Decodable {
    let success: Bool?
    let data: AdminModerationReportsData?
    let reports: [AdminModerationReportDTO]?

    var resolved: [AdminModerationReportDTO] {
        if let list = data?.reports { return list }
        if let list = reports { return list }
        return []
    }
}

struct AdminModerationReportsData: Decodable {
    let reports: [AdminModerationReportDTO]?
}
