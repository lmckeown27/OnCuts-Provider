import CoreLocation
import Foundation

/// Requests Core Location authorization for the service provider (e.g. discovery on CampusCuts).
/// `CLLocationManagerDelegate` is implemented on `NSObject` so the system permission prompt can appear.
final class ProviderLocationPermissionBroker: NSObject, CLLocationManagerDelegate {
    static let shared = ProviderLocationPermissionBroker()

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Call once when the provider enters the main shell. Only prompts if status is `notDetermined`.
    @MainActor
    func requestWhenInUseIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
}
