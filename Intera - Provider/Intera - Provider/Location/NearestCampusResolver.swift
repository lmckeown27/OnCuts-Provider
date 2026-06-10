import CoreLocation
import Foundation
import os.log

/// Resolves the geographically nearest `AdminCampusDTO` to a given device location.
///
/// `AdminCampusDTO` does not currently expose latitude / longitude, so each candidate's
/// `"<name>, <city>, <state>"` is forward-geocoded with `CLGeocoder` and matched against the
/// applicant's `CLLocation`. Geocoded coordinates are cached for the process lifetime so retry
/// loops are instant and so we don't burn through Apple's per-app geocode budget on every step
/// transition.
///
/// Concurrency is bounded to 3 simultaneous geocode requests: Apple's recommendation is a single
/// in-flight request per `CLGeocoder`, but multiple geocoders work in parallel as long as you
/// don't fan out so aggressively that the server-side rate limit starts returning errors. Three
/// at a time hits a good balance for typical campus lists.
@MainActor
enum NearestCampusResolver {
    struct Match: Equatable {
        let campus: AdminCampusDTO
        let distance: CLLocationDistance
    }

    private static var coordinateCache: [String: CLLocationCoordinate2D] = [:]

    /// Returns **all** geocodeable candidates sorted nearest-first. Callers typically `.prefix(N)`
    /// the result — the consumer enrollment flow surfaces the top 5 so the applicant can pick
    /// the right one rather than relying on a single auto-detected match.
    static func resolve(
        userLocation: CLLocation,
        candidates: [AdminCampusDTO],
        bypassCache: Bool = false
    ) async -> [Match] {
        guard !candidates.isEmpty else { return [] }
        if bypassCache {
            coordinateCache.removeAll()
        }

        let coordinates = await geocodeAll(candidates: candidates)
        let matches: [Match] = coordinates.map { campus, coordinate in
            let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return Match(campus: campus, distance: userLocation.distance(from: loc))
        }
        return matches.sorted(by: { $0.distance < $1.distance })
    }

    // MARK: - Geocoding

    private static let log = Logger(subsystem: "com.campuscut.provider", category: "NearestCampusResolver")

    /// Serial geocoding with a short inter-request delay. Parallel requests against `CLGeocoder`
    /// occasionally get silently throttled — and a throttled campus disappears from the match
    /// list entirely, which manifests as "a closer campus is missing from the top 5". Serial is
    /// slower but lossless. For a typical catalog of a few dozen campuses this runs in ~3–6 s
    /// the first time and is instant thereafter from the in-memory cache.
    private static let interRequestDelayNanoseconds: UInt64 = 120_000_000 // 0.12 s

    private static func geocodeAll(
        candidates: [AdminCampusDTO]
    ) async -> [(AdminCampusDTO, CLLocationCoordinate2D)] {
        var results: [(AdminCampusDTO, CLLocationCoordinate2D)] = []
        for campus in candidates {
            let usedServerCoords = (campus.latitude != nil && campus.longitude != nil)
            if let coord = await coordinate(for: campus) {
                results.append((campus, coord))
            } else {
                Self.log.warning("Resolve failed for campus \(campus.id, privacy: .public) [\(campus.displayName, privacy: .public)] — dropped from match candidates")
            }
            // Only throttle when we actually hit `CLGeocoder` — server-provided coordinates
            // resolve in microseconds and there's no rate limit to respect.
            if !usedServerCoords {
                try? await Task.sleep(nanoseconds: Self.interRequestDelayNanoseconds)
            }
        }
        return results
    }

    private static func coordinate(for campus: AdminCampusDTO) async -> CLLocationCoordinate2D? {
        // 1) Prefer server-provided coordinates from `GET /api/v1/campus`.
        //
        // The backend stores `campuses.latitude` / `campuses.longitude` and the public campus
        // route selects them explicitly. When present, they are authoritative — instant, exact,
        // and immune to the geocoder failure modes that previously caused closer campuses to be
        // skipped. We treat `(0, 0)` as a sentinel for "no fix" since that's where unseeded
        // numeric defaults sometimes land (and it's in the middle of the Atlantic, so it would
        // mis-rank anything in the catalog).
        if let lat = campus.latitude, let lng = campus.longitude, !(lat == 0 && lng == 0) {
            Self.log.debug("Using server coordinates for \(campus.id, privacy: .public) [\(campus.displayName, privacy: .public)]: (\(lat), \(lng))")
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        // 2) Fall back to client-side geocoding for legacy / admin routes that omit lat/long.
        let key = cacheKey(for: campus)
        if let cached = coordinateCache[key] { return cached }
        guard let query = geocodeQuery(for: campus) else {
            Self.log.warning("Skipping campus \(campus.id, privacy: .public) — no server coords and empty city/state/name; cannot resolve")
            return nil
        }
        Self.log.debug("Falling back to CLGeocoder for \(campus.id, privacy: .public) [\(campus.displayName, privacy: .public)]: \"\(query, privacy: .public)\"")

        // One geocode attempt + one retry. `CLGeocoder` errors are usually transient (rate-limit
        // or network), so a single retry with a short backoff recovers most of them without
        // doubling the request rate against Apple's per-app budget in steady state.
        if let coord = await geocodeOnce(query: query) {
            coordinateCache[key] = coord
            return coord
        }
        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 s
        if let coord = await geocodeOnce(query: query) {
            coordinateCache[key] = coord
            return coord
        }
        return nil
    }

    private static func geocodeOnce(query: String) async -> CLLocationCoordinate2D? {
        // Per Apple guidance, use a fresh geocoder per request — a single `CLGeocoder` only
        // allows one in-flight call at a time, and reusing one across calls can compound errors.
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(query)
            if let coord = placemarks.first?.location?.coordinate {
                return coord
            }
            Self.log.warning("Geocoder returned no placemarks for query: \(query, privacy: .public)")
            return nil
        } catch {
            Self.log.warning("Geocode error for query \"\(query, privacy: .public)\": \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func geocodeQuery(for campus: AdminCampusDTO) -> String? {
        let city = (campus.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let state = (campus.state ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (campus.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // City + state is the most reliable proximity signal. Free-text campus names like
        // "Cal Poly SLO" or "CSU LA" are dangerous to feed straight into `CLGeocoder`: Apple
        // Maps' POI index treats the same shorthand as multiple campuses (e.g. "Cal Poly" can
        // resolve to Pomona near Los Angeles instead of San Luis Obispo), which then poisons
        // the distance comparison and picks the wrong nearest campus. Cities, by contrast,
        // geocode deterministically — so we lead with them whenever they are present.
        //
        // We also append a country hint ("USA") whenever the state code looks like a US state.
        // Without it, ambiguous city names ("Springfield", "Columbus", "Portland") can resolve
        // to an arbitrary jurisdiction abroad and then look very far away in distance ranking.
        if !city.isEmpty {
            return joinedAddress([city, state], countryHintFor: state)
        }
        // No city on the DTO — fall back to name + state. Worse than city, but better than
        // dropping the campus from consideration entirely.
        if !name.isEmpty {
            return joinedAddress([name, state], countryHintFor: state)
        }
        return nil
    }

    private static func joinedAddress(_ parts: [String], countryHintFor state: String) -> String {
        var components = parts.filter { !$0.isEmpty }
        if isLikelyUSStateCode(state) {
            components.append("USA")
        }
        return components.joined(separator: ", ")
    }

    /// Returns true for the 50 US state codes + DC + common US territories. We use this only to
    /// decide whether to append a `"USA"` country hint to the geocode query — not for validation.
    private static func isLikelyUSStateCode(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard s.count == 2 else { return false }
        return Self.usStateCodes.contains(s)
    }

    private static let usStateCodes: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
        "DC", "PR", "VI", "GU", "AS", "MP",
    ]

    /// Cache key intentionally derives from the resolved query string, not the raw DTO fields,
    /// so any change to `geocodeQuery` (e.g. dropping the campus name) automatically invalidates
    /// previously cached — and possibly wrong — coordinates without a manual cache bump.
    private static func cacheKey(for campus: AdminCampusDTO) -> String {
        geocodeQuery(for: campus) ?? "__invalid__\(campus.id)"
    }
}
