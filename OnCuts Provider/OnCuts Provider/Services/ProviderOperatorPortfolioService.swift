import Foundation

struct OperatorPortfolioItem: Decodable, Identifiable, Hashable {
    let id: String
    let providerId: String?
    let mediaType: String?
    let mediaUrl: String?
    let thumbnailUrl: String?
    let caption: String?
    let sortOrder: Int?
    let createdAt: Date?
    let specialties: [String]?
    let bookingId: String?
    let isCover: Bool?

    var isVideo: Bool { (mediaType ?? "").lowercased() == "video" }
    var isImage: Bool { !isVideo }

    var primarySpecialtyId: String? {
        specialties?.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func applying(isCover: Bool, specialties nextSpecialties: [String]? = nil) -> OperatorPortfolioItem {
        OperatorPortfolioItem(
            id: id,
            providerId: providerId,
            mediaType: mediaType,
            mediaUrl: mediaUrl,
            thumbnailUrl: thumbnailUrl,
            caption: caption,
            sortOrder: sortOrder,
            createdAt: createdAt,
            specialties: nextSpecialties ?? specialties,
            bookingId: bookingId,
            isCover: isCover
        )
    }
}

struct PortfolioPricingRow {
    var name: String
    var catalogId: String?
    var price: Double
    var durationMinutes: Int?

    var entry: BarberPricingEntryDTO {
        BarberPricingEntryDTO(name: name, price: price, durationMinutes: durationMinutes)
    }
}

struct PortfolioOperatorProfile {
    var providerType: String
    var specialties: [String]
    var pricing: [PortfolioPricingRow]
    var name: String
    var photoURL: URL?
    var instagramHandle: String?
    var weeklySchedule: WeeklyScheduleDTO?
}

struct PortfolioSpecialty: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Double?
}

enum ProviderOperatorPortfolioService {
    static let imageMaxBytes = 8 * 1024 * 1024
    static let videoMaxBytes = 80 * 1024 * 1024
    static let maxPhotosPerBooking = 4
    static let maxVideosPerBooking = 1

    static func list(barberId: String) async throws -> [OperatorPortfolioItem] {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(encoded(barberId))/operator-portfolio"
        )
        let env = try OnCutsHTTPClient.jsonDecoderSnake().decode(ListEnvelope.self, from: data)
        return env.data ?? []
    }

    static func sectionOrder(barberId: String) async throws -> [String] {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(encoded(barberId))/operator-portfolio/section-order"
        )
        let env = try OnCutsHTTPClient.jsonDecoderSnake().decode(OrderEnvelope.self, from: data)
        return env.data?.specialtyIds ?? []
    }

    static func saveSectionOrder(barberId: String, specialtyIds: [String]) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(encoded(barberId))/operator-portfolio/section-order",
            method: "PUT",
            jsonBody: ["specialtyIds": specialtyIds]
        )
    }

    static func upload(
        barberId: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        specialtyId: String,
        isCover: Bool = false,
        bookingId: String? = nil
    ) async throws -> OperatorPortfolioItem {
        let kind = isVideoFile(mimeType: mimeType, fileName: fileName) ? "video" : "image"
        let limit = kind == "video" ? videoMaxBytes : imageMaxBytes
        if fileData.count > limit {
            throw OnCutsHTTPError.httpStatus(
                400,
                kind == "video" ? "Videos must be 80 MB or smaller" : "Photos must be 8 MB or smaller"
            )
        }
        if isCover && kind == "video" {
            throw OnCutsHTTPError.httpStatus(400, "A cover must be a photo")
        }
        let specialtiesJSON = String(
            data: try JSONSerialization.data(withJSONObject: [specialtyId]),
            encoding: .utf8
        ) ?? "[]"
        var fields = ["specialties": specialtiesJSON]
        if isCover { fields["is_cover"] = "true" }
        if let bookingId, !bookingId.isEmpty { fields["booking_id"] = bookingId }
        let data = try await OnCutsHTTPClient.uploadMultipart(
            path: "barbers/\(encoded(barberId))/operator-portfolio",
            fieldName: "media",
            fileName: fileName,
            mimeType: mimeType,
            fileData: fileData,
            textFields: fields
        )
        let env = try OnCutsHTTPClient.jsonDecoderSnake().decode(ItemEnvelope.self, from: data)
        guard let item = env.data else { throw OnCutsHTTPError.decoding }
        return item
    }

    /// Retag without sending `is_cover`, so the server keeps the current cover flag.
    static func retag(barberId: String, itemId: String, specialtyIds: [String]) async throws -> OperatorPortfolioItem {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(encoded(barberId))/operator-portfolio/\(encoded(itemId))",
            method: "PATCH",
            jsonBody: ["specialties": specialtyIds]
        )
        let env = try OnCutsHTTPClient.jsonDecoderSnake().decode(ItemEnvelope.self, from: data)
        guard let item = env.data else { throw OnCutsHTTPError.decoding }
        return item
    }

    static func setCover(barberId: String, itemId: String, specialtyId: String) async throws -> OperatorPortfolioItem {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(encoded(barberId))/operator-portfolio/\(encoded(itemId))",
            method: "PATCH",
            jsonBody: ["specialties": [specialtyId], "is_cover": true]
        )
        let env = try OnCutsHTTPClient.jsonDecoderSnake().decode(ItemEnvelope.self, from: data)
        guard let item = env.data else { throw OnCutsHTTPError.decoding }
        return item
    }

    static func deleteItem(barberId: String, itemId: String) async throws {
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(encoded(barberId))/operator-portfolio/\(encoded(itemId))",
            method: "DELETE"
        )
    }

    static func isVideoFile(mimeType: String, fileName: String) -> Bool {
        if mimeType.lowercased().hasPrefix("video/") { return true }
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ext == "mp4" || ext == "webm" || ext == "mov"
    }

    /// `GET /barbers/:id` — profile fields the portfolio modal uses. Ignores legacy `portfolio_images`.
    static func fetchOperatorProfile(barberId: String) async throws -> PortfolioOperatorProfile {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/\(encoded(barberId))")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OnCutsHTTPError.decoding
        }
        let payload = (root["data"] as? [String: Any]) ?? root
        let providerType = string(payload["provider_type"]) ?? string(payload["providerType"]) ?? "barber"
        let specialties = stringList(payload["specialties"])
        let pricing = pricingEntries(payload["pricing"])
        let first = string(payload["first_name"]) ?? string(payload["firstName"]) ?? ""
        let last = string(payload["last_name"]) ?? string(payload["lastName"]) ?? ""
        let joined = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        let name = string(payload["name"])
            ?? string(payload["display_name"])
            ?? string(payload["displayName"])
            ?? (joined.isEmpty ? "Operator" : joined)
        let photo = string(payload["profile_picture_url"]) ?? string(payload["profilePictureUrl"])
        let instagram = string(payload["instagram_handle"]) ?? string(payload["instagramHandle"])
        var weekly: WeeklyScheduleDTO?
        if let schedule = payload["weekly_schedule"] ?? payload["weeklySchedule"],
           JSONSerialization.isValidJSONObject(schedule),
           let scheduleData = try? JSONSerialization.data(withJSONObject: schedule) {
            weekly = try? OnCutsHTTPClient.jsonDecoderSnake().decode(WeeklyScheduleDTO.self, from: scheduleData)
        }
        return PortfolioOperatorProfile(
            providerType: providerType.lowercased() == "beauty" ? "beauty" : "barber",
            specialties: specialties,
            pricing: pricing,
            name: name,
            photoURL: photo.flatMap(URL.init(string:)),
            instagramHandle: instagram,
            weeklySchedule: weekly
        )
    }

    static func containsBooking(barberId: String, bookingId: String) async throws -> Bool {
        let items = try await list(barberId: barberId)
        return items.contains { $0.bookingId == bookingId }
    }

    static func message(from error: Error) -> String {
        if let http = error as? OnCutsHTTPError, case .httpStatus(_, let raw) = http, let raw {
            if let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let text = object["error"] as? String, !text.isEmpty { return text }
                if let nested = object["error"] as? [String: Any],
                   let text = nested["message"] as? String, !text.isEmpty { return text }
                if let text = object["message"] as? String, !text.isEmpty { return text }
            }
            if !raw.hasPrefix("{"), !raw.isEmpty { return raw }
        }
        return (error as? LocalizedError)?.errorDescription ?? "Could not update your portfolio."
    }

    static func offeredSections(catalog: [AdminServiceCatalogItem], profile: PortfolioOperatorProfile) -> [PortfolioSpecialty] {
        let kind = profile.providerType
        var offered = Set(profile.specialties.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var prices: [String: Double] = [:]
        for entry in profile.pricing {
            if !entry.name.isEmpty {
                let key = entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                offered.insert(key)
                prices[key] = entry.price
            }
            if let catalogId = entry.catalogId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !catalogId.isEmpty {
                prices[catalogId] = entry.price
            }
        }
        return catalog.compactMap { item in
            let type = (item.providerType ?? "barber").lowercased()
            guard type == kind else { return nil }
            let nameKey = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let slugKey = item.slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard offered.contains(nameKey) || offered.contains(slugKey) else { return nil }
            return PortfolioSpecialty(id: item.slug, name: item.name, price: prices[nameKey] ?? prices[slugKey])
        }
    }

    static func orderedSpecialties(_ specialties: [PortfolioSpecialty], savedOrder: [String], items: [OperatorPortfolioItem]) -> [PortfolioSpecialty] {
        var byId: [String: PortfolioSpecialty] = [:]
        for specialty in specialties { byId[specialty.id] = specialty }
        for item in items {
            guard let id = item.primarySpecialtyId, byId[id] == nil else { continue }
            byId[id] = PortfolioSpecialty(id: id, name: id, price: nil)
        }
        let known = Set(byId.keys)
        var ordered: [PortfolioSpecialty] = []
        var seen = Set<String>()
        for id in savedOrder where known.contains(id) && seen.insert(id).inserted {
            if let specialty = byId[id] { ordered.append(specialty) }
        }
        for specialty in specialties where seen.insert(specialty.id).inserted {
            ordered.append(specialty)
        }
        for item in items {
            guard let id = item.primarySpecialtyId, seen.insert(id).inserted, let specialty = byId[id] else { continue }
            ordered.append(specialty)
        }
        return ordered
    }

    static func cover(in items: [OperatorPortfolioItem], specialtyId: String) -> OperatorPortfolioItem? {
        let photos = items.filter { $0.primarySpecialtyId == specialtyId && $0.isImage }
        if let marked = photos.first(where: { $0.isCover == true }) { return marked }
        return photos.max { lhs, rhs in
            let left = lhs.createdAt ?? .distantPast
            let right = rhs.createdAt ?? .distantPast
            if left != right { return left < right }
            return (lhs.sortOrder ?? 0) < (rhs.sortOrder ?? 0)
        }
    }

    static func items(in items: [OperatorPortfolioItem], specialtyId: String) -> [OperatorPortfolioItem] {
        let section = items.filter { $0.primarySpecialtyId == specialtyId }
        guard let cover = cover(in: items, specialtyId: specialtyId) else { return section }
        return [cover] + section.filter { $0.id != cover.id }
    }

    /// Keys the server uses when a dropped specialty deletes portfolio rows.
    static func matchKeys(name: String, slug: String) -> Set<String> {
        let aliases: [String: [String]] = [
            "buzz cut": ["buzz-cut"],
            "line up": ["lineup", "line-up"],
            "beard trim": ["beard-trim"],
            "haircut": ["haircut"],
            "taper": ["taper"],
            "hot shave": ["hot-shave"],
            "kids cut": ["kids-cut"],
            "fade": ["fade"],
            "mullet": ["mullet"],
            "design/art": ["design", "design-art", "designart"],
            "afro textures": ["afro", "afro-textures"],
            "color treatment": ["color", "color-treatment"],
            "perm": ["perm"],
            "braids": ["braids"],
            "makeup": ["makeup"],
            "nails": ["nails"],
            "lashes": ["lashes"],
            "tanning": ["tanning"],
        ]
        var keys = Set<String>()
        for raw in [name, slug] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }
            keys.insert(trimmed)
            keys.insert(trimmed.replacingOccurrences(of: " ", with: "-"))
            keys.formUnion(aliases[trimmed] ?? [])
        }
        keys.remove("")
        return keys
    }

    private static func string(_ raw: Any?) -> String? {
        guard let text = raw as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringList(_ raw: Any?) -> [String] {
        if let values = raw as? [String] { return values }
        if let values = raw as? [Any] {
            return values.compactMap { string($0) }
        }
        return []
    }

    private static func pricingEntries(_ raw: Any?) -> [PortfolioPricingRow] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let name = string(row["name"]) ?? ""
            let catalogId = string(row["id"])
            guard !name.isEmpty || catalogId != nil else { return nil }
            let price: Double
            if let value = row["price"] as? Double { price = value }
            else if let value = row["price"] as? Int { price = Double(value) }
            else if let value = row["price"] as? NSNumber { price = value.doubleValue }
            else { price = 0 }
            let duration = (row["duration_minutes"] as? Int) ?? (row["durationMinutes"] as? Int)
            return PortfolioPricingRow(name: name, catalogId: catalogId, price: price, durationMinutes: duration)
        }
    }

    private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private struct ListEnvelope: Decodable {
        let data: [OperatorPortfolioItem]?
    }

    private struct ItemEnvelope: Decodable {
        let data: OperatorPortfolioItem?
    }

    private struct OrderEnvelope: Decodable {
        let data: OrderData?
        struct OrderData: Decodable {
            let specialtyIds: [String]?
        }
    }
}

enum ProviderPortfolioPromptMemory {
    private static var dismissed = Set<String>()

    static func wasDismissed(_ bookingId: String) -> Bool {
        dismissed.contains(bookingId)
    }

    static func dismiss(_ bookingId: String) {
        dismissed.insert(bookingId)
    }
}
