import Foundation

/// Lenient JSON helpers for CampusCuts API payloads that may mix strings, numbers, and date formats.
enum ProviderAPIFlexibleDecoding {
    static func requiredString<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> String {
        if let value = optionalString(from: container, forKey: key) {
            return value
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected a string-compatible value."
        )
    }

    static func optionalString<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> String? {
        guard container.contains(key) else { return nil }
        guard (try? container.decodeNil(forKey: key)) != true else { return nil }
        if let value = try? container.decode(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return String(Int(value))
        }
        return nil
    }

    static func optionalInt<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Int? {
        guard container.contains(key) else { return nil }
        guard (try? container.decodeNil(forKey: key)) != true else { return nil }
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value) }
        if let raw = try? container.decode(String.self, forKey: key) {
            return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func optionalDouble<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Double? {
        guard container.contains(key) else { return nil }
        guard (try? container.decodeNil(forKey: key)) != true else { return nil }
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let raw = try? container.decode(String.self, forKey: key) {
            return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func optionalDate<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Date? {
        guard container.contains(key) else { return nil }
        guard (try? container.decodeNil(forKey: key)) != true else { return nil }
        if let value = try? container.decode(Date.self, forKey: key) {
            return value
        }
        guard let nested = try? container.superDecoder(forKey: key),
              let single = try? nested.singleValueContainer()
        else { return nil }
        return ProviderBookingScheduleParsing.decodeFlexibleOptionalDate(from: single)
    }
}
