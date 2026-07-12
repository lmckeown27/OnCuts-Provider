import Foundation

enum ProviderAuthEmailValidation {
    private static let pattern =
        #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#

    static func isValid(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Reject institutional `.edu` addresses on Operator auth.
    static func isSchoolEmail(_ raw: String) -> Bool {
        let normalized = Self.normalized(raw)
        guard let at = normalized.lastIndex(of: "@") else { return false }
        let domain = normalized[normalized.index(after: at)...]
        return domain == "edu" || domain.hasSuffix(".edu")
    }

    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
