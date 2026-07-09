import Foundation

/// Formats backend service enum values (`HAIRCUT`, `BEARD_TRIM`) for UI display (`Haircut`, `Beard Trim`).
enum ProviderServiceTypeDisplay {
    static func name(serviceName: String?, serviceType: String?, fallback: String = "Service") -> String {
        if let trimmed = trimmedNonEmpty(serviceName) {
            return format(trimmed, fallback: trimmed)
        }
        if let trimmed = trimmedNonEmpty(serviceType) {
            return format(trimmed, fallback: fallback)
        }
        return fallback
    }

    /// Formats a single raw service label; leaves human-readable values unchanged.
    static func format(_ raw: String?, fallback: String = "Service") -> String {
        guard let trimmed = trimmedNonEmpty(raw) else { return fallback }
        guard looksLikeBackendEnum(trimmed) else { return trimmed }
        return trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func looksLikeBackendEnum(_ value: String) -> Bool {
        if value.contains("_") { return true }
        return value == value.uppercased() && value.contains(where: \.isLetter)
    }
}
