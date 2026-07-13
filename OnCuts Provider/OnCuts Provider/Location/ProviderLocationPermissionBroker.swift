import CoreLocation
import Foundation

/// Requests Core Location authorization for the service provider (e.g. discovery on CampusCuts).
/// `CLLocationManagerDelegate` is implemented on `NSObject` so the system permission prompt can appear.
final class ProviderLocationPermissionBroker: NSObject, CLLocationManagerDelegate {
    static let shared = ProviderLocationPermissionBroker()

    /// Avoid repeating the denied-location guidance alert every time the shell appears.
    private static var didNotifyDeniedThisProcess = false

    private let manager = CLLocationManager()
    private var pendingDeniedHandler: (() -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Call once when the provider enters the main shell. Only prompts if status is `notDetermined`.
    /// Invokes `onAccessDenied` when the user refuses (or has already refused) location access.
    @MainActor
    func requestWhenInUseIfNeeded(onAccessDenied: @escaping () -> Void) {
        switch manager.authorizationStatus {
        case .notDetermined:
            pendingDeniedHandler = onAccessDenied
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            notifyDeniedIfNeeded(onAccessDenied)
        default:
            pendingDeniedHandler = nil
        }
    }

    @MainActor
    private func notifyDeniedIfNeeded(_ handler: @escaping () -> Void) {
        guard !Self.didNotifyDeniedThisProcess else { return }
        Self.didNotifyDeniedThisProcess = true
        handler()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted:
                guard let handler = pendingDeniedHandler else { return }
                pendingDeniedHandler = nil
                notifyDeniedIfNeeded(handler)
            case .authorizedWhenInUse, .authorizedAlways:
                pendingDeniedHandler = nil
            default:
                break
            }
        }
    }
}
