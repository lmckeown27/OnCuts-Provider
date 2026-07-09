import Foundation

struct ServiceLedgerSection: Hashable {
    let category: ServiceLedgerCategory
    let slugs: [String]
}

enum ServiceLedgerCategory: String, Hashable {
    case haircuts
    case beardAndGrooming
    case textureAndDesign
    case colorAndTreatments
    case other

    var title: String {
        switch self {
        case .haircuts: "Haircuts"
        case .beardAndGrooming: "Beard & Grooming"
        case .textureAndDesign: "Texture & Design"
        case .colorAndTreatments: "Color & Treatments"
        case .other: "Other Services"
        }
    }

    static let displayOrder: [ServiceLedgerCategory] = [
        .haircuts, .beardAndGrooming, .textureAndDesign, .colorAndTreatments, .other,
    ]
}

enum ServiceLedgerCategorizer {
    static func category(slug: String, name: String) -> ServiceLedgerCategory {
        let haystack = "\(slug) \(name)".lowercased()
        if haystack.contains("beard")
            || haystack.contains("shave")
            || haystack.contains("lineup")
            || haystack.contains("line-up")
            || haystack.contains("line up") {
            return .beardAndGrooming
        }
        if haystack.contains("color")
            || haystack.contains("perm")
            || haystack.contains("treatment")
            || haystack.contains("dye") {
            return .colorAndTreatments
        }
        if haystack.contains("design")
            || haystack.contains("afro")
            || haystack.contains("texture")
            || haystack.contains("art") {
            return .textureAndDesign
        }
        if haystack.contains("hair")
            || haystack.contains("fade")
            || haystack.contains("cut")
            || haystack.contains("buzz")
            || haystack.contains("taper")
            || haystack.contains("mullet")
            || haystack.contains("kids")
            || haystack.contains("women") {
            return .haircuts
        }
        return .other
    }
}

enum ProviderServicesLedgerStyle {
    static let fieldLabelWidth: CGFloat = 48
    static let fieldInputWidth: CGFloat = 52
    static let rangeFieldInputWidth: CGFloat = 40
}

enum ServiceLedgerRowOrdering {
    static func sortSlugs(_ slugs: [String], nameForSlug: (String) -> String) -> [String] {
        slugs.sorted { lhs, rhs in
            if isHaircutBuzzCutPair(lhs, rhs) {
                return normalizedSlug(lhs) == "haircut"
            }
            return nameForSlug(lhs).localizedCaseInsensitiveCompare(nameForSlug(rhs)) == .orderedAscending
        }
    }

    static func normalizedSlug(_ slug: String) -> String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isHaircutBuzzCutPair(_ lhs: String, _ rhs: String) -> Bool {
        Set([normalizedSlug(lhs), normalizedSlug(rhs)]) == ["haircut", "buzz-cut"]
    }
}
