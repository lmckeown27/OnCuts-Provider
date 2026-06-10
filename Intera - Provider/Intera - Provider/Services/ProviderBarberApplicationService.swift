import Foundation

struct BarberApplicationMyEnvelope: Decodable {
    let success: Bool?
    let data: BarberApplicationSummary?
    let message: String?
}

struct BarberApplicationSummary: Decodable {
    let id: String?
    let status: String?
    let createdAt: String?
    let yearsExperience: String?
    let specialties: [String]?
    let availableHours: String?
    let whyBeBarber: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        specialties = try c.decodeIfPresent([String].self, forKey: .specialties)
        availableHours = try c.decodeIfPresent(String.self, forKey: .availableHours)
        whyBeBarber = try c.decodeIfPresent(String.self, forKey: .whyBeBarber)
        if let text = try c.decodeIfPresent(String.self, forKey: .yearsExperience) {
            yearsExperience = text
        } else if let number = try c.decodeIfPresent(Int.self, forKey: .yearsExperience) {
            yearsExperience = String(number)
        } else {
            yearsExperience = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, createdAt, yearsExperience, specialties, availableHours, whyBeBarber
    }

    init(
        id: String? = nil,
        status: String? = nil,
        createdAt: String? = nil,
        yearsExperience: String? = nil,
        specialties: [String]? = nil,
        availableHours: String? = nil,
        whyBeBarber: String? = nil
    ) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.yearsExperience = yearsExperience
        self.specialties = specialties
        self.availableHours = availableHours
        self.whyBeBarber = whyBeBarber
    }
}

/// Result of a manager-facing applications list call. The pagination block is preserved so
/// the dashboard can show "page X of Y" or fetch additional pages if we need to in the future.
struct BarberApplicationsListResult {
    let applications: [BarberApplicationListRowDTO]
    let pagination: BarberApplicationsPagination?
}

@MainActor
enum ProviderBarberApplicationService {
    static func fetchMyApplication() async throws -> BarberApplicationSummary? {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "barber-applications/my-application")
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(BarberApplicationMyEnvelope.self, from: data).data
    }

    static func submitApplication(body: [String: Any]) async throws {
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "barber-applications",
            method: "POST",
            jsonBody: body
        )
    }

    // MARK: - Campus Manager / Admin queue

    /// `GET /api/v1/barber-applications` — UNION of regular + guest applications.
    ///
    /// The backend list route does **not** auto-scope by JWT campus, so the caller must always
    /// pass `campusId` (the manager's campus from `users.campusId`) to avoid returning every
    /// campus's queue. Admins may pass any campus id or `nil` to see everything.
    static func listApplications(
        campusId: String?,
        status: BarberApplicationStatus? = nil,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> BarberApplicationsListResult {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let campusId, !campusId.isEmpty {
            items.append(URLQueryItem(name: "campusId", value: campusId))
        }
        if let status {
            items.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        var comps = URLComponents()
        comps.queryItems = items
        let query = comps.percentEncodedQuery ?? ""
        let path = "barber-applications" + (query.isEmpty ? "" : "?\(query)")

        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(BarberApplicationsListEnvelope.self, from: data)
        return BarberApplicationsListResult(
            applications: env.data?.applications ?? [],
            pagination: env.data?.pagination
        )
    }

    /// `PUT /api/v1/barber-applications/:id/status` — sets a new status.
    ///
    /// `reviewNotes` and `interviewScheduledAt` are accepted for regular applications only;
    /// the backend silently ignores them on guest rows.
    static func updateApplicationStatus(
        id: String,
        status: BarberApplicationStatus,
        reviewNotes: String? = nil,
        interviewScheduledAt: Date? = nil
    ) async throws {
        var body: [String: Any] = ["status": status.rawValue]
        if let notes = reviewNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            body["reviewNotes"] = notes
        }
        if let interviewScheduledAt {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            body["interviewScheduledAt"] = fmt.string(from: interviewScheduledAt)
        }
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "barber-applications/\(id)/status",
            method: "PUT",
            jsonBody: body
        )
    }
}
