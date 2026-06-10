//
//  CampusCutsClient+ShellBooking.swift
//  CampusCutsModule
//
//  Public API for host apps (e.g. Intera) to load barber services and day availability
//  using the same networking stack as the module.
//

import Foundation

/// One bookable time range for a day (from `GET /barbers/:id/availability`).
public struct CampusCutsDayAvailabilitySlot: Sendable, Hashable {
    public let startTime: String
    public let endTime: String
    public let isAvailable: Bool

    public init(startTime: String, endTime: String, isAvailable: Bool) {
        self.startTime = startTime
        self.endTime = endTime
        self.isAvailable = isAvailable
    }
}

/// Service + price row from `GET /barbers/:id/services` (CampusCuts backend).
public struct CampusCutsBarberServiceRow: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let priceUsd: Int
    public let durationMinutes: Int

    public init(id: Int, name: String, priceUsd: Int, durationMinutes: Int) {
        self.id = id
        self.name = name
        self.priceUsd = priceUsd
        self.durationMinutes = durationMinutes
    }
}

extension CampusCutsClient {
    /// Fetches availability for a calendar day (`date` = `yyyy-MM-dd`).
    public func fetchBarberDayAvailability(barberId: Int, dateYYYYMMDD: String) async throws -> [CampusCutsDayAvailabilitySlot] {
        let api = CampusCutsAPIService(session: session, environment: environment)
        let envelope = try await api.fetchBarberAvailability(barberId: barberId, date: dateYYYYMMDD)
        return envelope.availableSlots.map {
            CampusCutsDayAvailabilitySlot(
                startTime: $0.startTime,
                endTime: $0.endTime,
                isAvailable: $0.isAvailable ?? true
            )
        }
    }

    /// Active services with prices for chip / picker UIs.
    public func fetchBarberServiceRows(barberId: Int) async throws -> [CampusCutsBarberServiceRow] {
        let api = CampusCutsAPIService(session: session, environment: environment)
        let rows = try await api.fetchBarberServices(barberId: barberId)
        return rows
            .filter { $0.isActive != false }
            .map {
                CampusCutsBarberServiceRow(
                    id: $0.id,
                    name: $0.name,
                    priceUsd: Int(round($0.price)),
                    durationMinutes: $0.durationMinutes
                )
            }
    }
}
