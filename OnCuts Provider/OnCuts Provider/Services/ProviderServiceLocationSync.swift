import CoreLocation
import Foundation

/// Syncs the operator's device GPS to the public discovery pin when manual location is off.
enum ProviderServiceLocationSync {
    /// Fetches a one-shot GPS fix and PUTs `source: "device"`.
    /// Returns the server pin (may include `ignoredDeviceUpdate` when web-only is locked).
    @MainActor
    static func syncDeviceLocation(
        timeout: TimeInterval = 15
    ) async throws -> BarberServiceLocationDTO {
        let fetcher = OneShotLocationFetcher(timeout: timeout)
        let location = try await fetcher.fetch()
        let label = await reverseGeocodeLabel(for: location)
        return try await ProviderBarberServiceLocationService.update(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            label: label,
            source: "device"
        )
    }

    /// Turns manual lock on/off. When turning off, immediately refreshes from device GPS.
    @MainActor
    static func setUseManualLocation(_ enabled: Bool) async throws -> BarberServiceLocationDTO {
        if enabled {
            return try await ProviderBarberServiceLocationService.update(webOnly: true)
        }
        // Restore device priority, then overwrite the public pin from this device.
        _ = try await ProviderBarberServiceLocationService.update(webOnly: false)
        return try await syncDeviceLocation()
    }

    @MainActor
    private static func reverseGeocodeLabel(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let place = placemarks.first else { return nil }
            let parts = [place.name, place.locality, place.administrativeArea]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.isEmpty { return nil }
            // Prefer "Name, City" when both exist; otherwise first useful fragment.
            if parts.count >= 2 {
                return "\(parts[0]), \(parts[1])"
            }
            return parts[0]
        } catch {
            return nil
        }
    }
}
