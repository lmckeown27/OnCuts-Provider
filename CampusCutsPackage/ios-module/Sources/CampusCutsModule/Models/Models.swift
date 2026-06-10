//
//  Models.swift
//  CampusCutsModule
//
//  Internal data models matching the CampusCuts backend API responses.
//

import Foundation

// MARK: - Barber Models

internal struct Barber: Codable, Identifiable {
    let id: Int
    let userId: Int
    let businessName: String
    let bio: String?
    let profileImageUrl: String?
    let campusId: Int
    let campusName: String?
    let rating: Double?
    let reviewCount: Int?
    let isAvailableNow: Bool?
    let completedBookings: Int?
}

internal struct BarberProfile: Codable {
    let id: Int
    let userId: Int
    let businessName: String
    let bio: String?
    let profileImageUrl: String?
    let campusId: Int
    let campusName: String?
    let rating: Double?
    let reviewCount: Int?
    let services: [BarberService]?
    let availability: [DayAvailability]?
    let portfolioImages: [String]?
}

internal struct BarberAvailability: Codable {
    let date: String
    let availableSlots: [TimeSlot]
    let bookedSlots: [TimeSlot]
    let blockedSlots: [TimeSlot]
}

internal struct TimeSlot: Codable, Identifiable {
    var id: String { "\(startTime)-\(endTime)" }
    let startTime: String
    let endTime: String
    let isAvailable: Bool?
}

internal struct DayAvailability: Codable {
    let dayOfWeek: Int
    let startTime: String
    let endTime: String
    let isAvailable: Bool
}

// MARK: - Service Models

internal struct BarberService: Codable, Identifiable {
    let id: Int
    let barberId: Int
    let name: String
    let description: String?
    let price: Double
    let durationMinutes: Int
    let isActive: Bool?
}

// MARK: - Booking Models

internal struct Booking: Codable, Identifiable {
    let id: Int
    let consumerId: Int
    let consumerName: String?
    let consumerEmail: String?
    let barberId: Int
    let barberName: String?
    let barberBusinessName: String?
    let barberProfileImage: String?
    let serviceId: Int
    let serviceName: String?
    let servicePrice: Double?
    let bookingDate: String
    let startTime: String
    let endTime: String
    let status: BookingStatus
    let totalAmount: Double?
    let tipAmount: Double?
    let paymentMethod: String?
    let paymentStatus: String?
    let notes: String?
    let cancellationReason: String?
    let createdAt: String
    let updatedAt: String?
}

internal enum BookingStatus: String, Codable {
    case pending = "PENDING"
    case accepted = "ACCEPTED"
    case rejected = "REJECTED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case noShow = "NO_SHOW"
}

internal struct CreateBookingRequest: Codable {
    let barberId: Int
    let serviceId: Int
    let bookingDate: String
    let startTime: String
    let notes: String?
    let paymentMethod: String
}

// MARK: - Message Models

internal struct Message: Codable, Identifiable {
    let id: Int
    let bookingId: Int
    let senderId: Int
    let senderName: String?
    let senderRole: String
    let content: String
    let createdAt: String
    let isRead: Bool?
}

// MARK: - Campus Models

internal struct Campus: Codable, Identifiable {
    let id: Int
    let name: String
    let city: String?
    let state: String?
    let timezone: String?
    let isActive: Bool?
}

// MARK: - Review Models

internal struct Review: Codable, Identifiable {
    let id: Int
    let bookingId: Int
    let barberId: Int
    let consumerId: Int
    let consumerName: String?
    let rating: Int
    let comment: String?
    let createdAt: String
}

// MARK: - API Response Wrappers

internal struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let message: String?
    let error: String?
}

internal struct PaginatedResponse<T: Codable>: Codable {
    let items: [T]
    let total: Int
    let page: Int
    let pageSize: Int
    let totalPages: Int
}

