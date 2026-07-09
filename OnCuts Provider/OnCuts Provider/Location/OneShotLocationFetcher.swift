import CoreLocation
import Foundation

#if os(iOS)
import UIKit
#endif

/// Bridges `CLLocationManager`'s delegate callbacks to a single async/await location fix.
///
/// Used by the provider enrollment flow to auto-pick the nearest CampusCuts campus instead of
/// asking the applicant to search manually. Holds its own `CLLocationManager` so the singleton
/// `ProviderLocationPermissionBroker` stays untouched, and self-times-out after `timeout` seconds
/// so the UI never sits on an indefinite spinner if Core Location stalls (e.g. simulator with no
/// simulated location, low-signal indoors, etc.).
@MainActor
final class OneShotLocationFetcher: NSObject {
    enum FetchError: LocalizedError {
        case permissionDenied
        case servicesDisabled
        case timedOut
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Location access is off. Enable it in Settings to detect your campus automatically."
            case .servicesDisabled:
                return "Location services are disabled on this device."
            case .timedOut:
                return "Couldn’t get a location fix in time. Please try again."
            case .underlying(let err):
                return err.localizedDescription
            }
        }
    }

    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var watchdog: Task<Void, Never>?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.manager = CLLocationManager()
        self.timeout = timeout
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Returns a single fresh location fix, requesting authorization first if undetermined.
    /// Throws `FetchError` on denial, system service disabled, timeout, or underlying CL errors.
    func fetch() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocation, Error>) in
            self.continuation = cont
            startWatchdog()

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.failure(FetchError.permissionDenied))
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            @unknown default:
                finish(.failure(FetchError.permissionDenied))
            }
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let seconds = timeout
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.fireTimeout()
        }
    }

    private func fireTimeout() {
        finish(.failure(FetchError.timedOut))
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        watchdog?.cancel()
        watchdog = nil
        guard let cont = continuation else { return }
        continuation = nil
        switch result {
        case .success(let loc):
            cont.resume(returning: loc)
        case .failure(let err):
            cont.resume(throwing: err)
        }
    }
}

extension OneShotLocationFetcher: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                self.finish(.failure(FetchError.permissionDenied))
            case .notDetermined:
                break
            @unknown default:
                self.finish(.failure(FetchError.permissionDenied))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor [weak self] in
            guard let self, let loc = last else { return }
            self.finish(.success(loc))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(.failure(FetchError.underlying(error)))
        }
    }
}
