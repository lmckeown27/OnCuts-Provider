//
//  CampusCutsClient+ShellProfile.swift
//  CampusCutsModule
//
//  Public profile/booking APIs for host apps (Intera profile, appointments, barber portfolio).
//

import Foundation

// MARK: - Public DTOs

/// One booking row for profile “Upcoming” / “History” lists (`GET /bookings`).
public struct CampusCutsProfileBooking: Sendable, Identifiable, Hashable {
    public let id: Int
    public let serviceName: String
    public let providerName: String
    public let scheduledAt: Date
    public let statusRaw: String

    public init(id: Int, serviceName: String, providerName: String, scheduledAt: Date, statusRaw: String) {
        self.id = id
        self.serviceName = serviceName
        self.providerName = providerName
        self.scheduledAt = scheduledAt
        self.statusRaw = statusRaw
    }
}

/// Review line for barber profile (`GET /barbers/:id/reviews`).
public struct CampusCutsBarberReviewSnippet: Sendable, Identifiable, Hashable {
    public let id: String
    public let authorName: String
    public let rating: Int
    public let body: String
    public let createdAt: Date

    public init(id: String, authorName: String, rating: Int, body: String, createdAt: Date) {
        self.id = id
        self.authorName = authorName
        self.rating = rating
        self.body = body
        self.createdAt = createdAt
    }
}

// MARK: - CampusCutsClient

extension CampusCutsClient {

    /// All bookings for the authenticated user (consumer or barber, per backend scope).
    public func fetchMyBookings() async throws -> [CampusCutsProfileBooking] {
        let api = CampusCutsAPIService(session: session, environment: environment)
        let rows = try await api.fetchBookings()
        return rows.compactMap { Self.mapBookingToProfile($0) }
    }

    /// Best-effort barber row `id` for the signed-in barber (from any booking they own).
    public func inferCurrentBarberId() async throws -> Int? {
        let api = CampusCutsAPIService(session: session, environment: environment)
        let statuses = ["PENDING", "ACCEPTED", "COMPLETED", "REJECTED", "CANCELLED"]
        for st in statuses {
            let rows = try await api.fetchBookings(status: st)
            if let id = rows.first?.barberId { return id }
        }
        let all = try await api.fetchBookings()
        return all.first?.barberId
    }

    /// Portfolio image URLs from `GET /barbers/:id` (`portfolioImages` keys/paths via HTTPS/S3).
    public func fetchBarberPortfolioURLs(barberId: Int) async throws -> [URL] {
        let api = CampusCutsAPIService(session: session, environment: environment)
        let profile = try await api.fetchBarberProfile(barberId: barberId)
        let paths = profile.portfolioImages ?? []
        return paths.compactMap { CampusCutsS3ImageURL.url(forStoredPath: $0) }
    }

    /// Public bio from barber profile (optional).
    public func fetchBarberBio(barberId: Int) async throws -> String? {
        let api = CampusCutsAPIService(session: session, environment: environment)
        let profile = try await api.fetchBarberProfile(barberId: barberId)
        let b = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (b?.isEmpty == false) ? b : nil
    }

    /// Reviews for the barber’s public profile.
    public func fetchBarberReviewSnippets(barberId: Int) async throws -> [CampusCutsBarberReviewSnippet] {
        let api = CampusCutsAPIService(session: session, environment: environment)
        let rows = try await api.fetchBarberReviews(barberId: barberId)
        return rows.map { Self.mapReview($0) }
    }

    // MARK: - Mappers

    private static func mapBookingToProfile(_ b: Booking) -> CampusCutsProfileBooking? {
        guard let at = scheduledDate(bookingDate: b.bookingDate, startTime: b.startTime) else { return nil }
        let service = trimmedNonEmpty(b.serviceName) ?? "Service"
        let provider = trimmedNonEmpty(b.barberBusinessName) ?? trimmedNonEmpty(b.barberName) ?? "Barber"
        return CampusCutsProfileBooking(
            id: b.id,
            serviceName: service,
            providerName: provider,
            scheduledAt: at,
            statusRaw: b.status.rawValue
        )
    }

    private static func scheduledDate(bookingDate: String, startTime: String) -> Date? {
        let d = bookingDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let dp = d.split(separator: "-").compactMap { Int($0) }
        guard dp.count == 3 else { return nil }
        let tp = t.split(separator: ":").compactMap { Int($0) }
        guard let hh = tp.first else { return nil }
        let mm = tp.count > 1 ? tp[1] : 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var dc = DateComponents()
        dc.year = dp[0]
        dc.month = dp[1]
        dc.day = dp[2]
        dc.hour = hh
        dc.minute = mm
        dc.second = 0
        return cal.date(from: dc)
    }

    private static func trimmedNonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func mapReview(_ r: Review) -> CampusCutsBarberReviewSnippet {
        let name = trimmedNonEmpty(r.consumerName) ?? "Client"
        let body = r.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let created = parseAPIDate(r.createdAt) ?? Date()
        return CampusCutsBarberReviewSnippet(
            id: "rev-\(r.id)",
            authorName: name,
            rating: r.rating,
            body: body,
            createdAt: created
        )
    }

    private static func parseAPIDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: trimmed)
    }
}
