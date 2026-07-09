import Foundation

struct PublicCampusListEnvelope: Decodable {
    let success: Bool?
    let data: [AdminCampusDTO]?
}

/// Public campus directory (`GET /campus`) — used by the provider application flow.
@MainActor
enum ProviderCampusCatalogService {
    private static let hiddenCampusNames: Set<String> = ["gmail", "icloud"]

    static func listCampuses(search: String? = nil) async throws -> [AdminCampusDTO] {
        var path = "campus"
        if let search {
            let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let enc = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
                path += "?search=\(enc)"
            }
        }
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: path)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try dec.decode(PublicCampusListEnvelope.self, from: data).data ?? []
        return rows
            .filter { campus in
                let key = (campus.name ?? campus.slug ?? "").lowercased()
                return !hiddenCampusNames.contains(key)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
