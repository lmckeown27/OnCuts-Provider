import Foundation
import MapKit
import Observation

/// Autocomplete suggestions for typing a manual discovery place (MKLocalSearchCompleter).
@Observable @MainActor
final class ProviderPlaceSearchCompleter: NSObject {
    var queryFragment = "" {
        didSet {
            let trimmed = queryFragment.trimmingCharacters(in: .whitespacesAndNewlines)
            if suggestionsSuppressed {
                // User started typing again after a selection — reopen suggestions.
                if trimmed != lastSubmittedQuery {
                    suggestionsSuppressed = false
                } else {
                    return
                }
            }
            guard trimmed != lastSubmittedQuery else { return }
            lastSubmittedQuery = trimmed
            if trimmed.isEmpty {
                results = []
                isSearching = false
                completer.queryFragment = ""
            } else {
                isSearching = true
                completer.queryFragment = trimmed
            }
        }
    }

    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var isSearching = false
    /// After a selection, keep the dropdown closed until the query changes again.
    private(set) var suggestionsSuppressed = false

    private let completer = MKLocalSearchCompleter()
    private var lastSubmittedQuery = ""

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func clearResults() {
        results = []
        isSearching = false
    }

    /// Close the dropdown after a place is chosen. Keeps `label` as the settled query so
    /// MapKit won't immediately refill suggestions until the user edits the field.
    func dismissSuggestions(keepingQuery label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestionsSuppressed = true
        results = []
        isSearching = false
        lastSubmittedQuery = trimmed
        queryFragment = trimmed
        completer.queryFragment = ""
    }

    func resolveCoordinates(for completion: MKLocalSearchCompletion) async throws -> (coordinate: CLLocationCoordinate2D, label: String) {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw PlaceSearchError.noResults
        }
        let coordinate = item.placemark.coordinate
        let label = displayLabel(for: completion, mapItem: item)
        return (coordinate, label)
    }

    private func displayLabel(for completion: MKLocalSearchCompletion, mapItem: MKMapItem) -> String {
        let title = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !subtitle.isEmpty {
            return "\(title), \(subtitle)"
        }
        if !title.isEmpty { return title }
        let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return subtitle
    }

    enum PlaceSearchError: LocalizedError {
        case noResults

        var errorDescription: String? {
            switch self {
            case .noResults: return "Couldn’t resolve that place. Try another search."
            }
        }
    }
}

extension ProviderPlaceSearchCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let snapshot = Array(completer.results.prefix(6))
        Task { @MainActor in
            guard !self.suggestionsSuppressed else {
                self.results = []
                self.isSearching = false
                return
            }
            self.results = snapshot
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
            self.isSearching = false
        }
    }
}
