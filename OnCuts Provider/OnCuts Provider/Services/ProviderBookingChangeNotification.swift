import Foundation

/// Boxes a booking snapshot for `NotificationCenter` (`object` must be a class).
final class ProviderBookingChangeBox: NSObject {
    let booking: SimpleBookingDTO

    init(_ booking: SimpleBookingDTO) {
        self.booking = booking
    }
}

@MainActor
enum ProviderBookingChangeNotification {
    /// Posts `.providerBookingsChanged`, optionally with a local snapshot so the calendar
    /// can drop / update the row immediately before the list refresh lands.
    static func post(booking: SimpleBookingDTO? = nil) {
        if let booking {
            ProviderScheduleBookingOverrides.remember(booking)
            NotificationCenter.default.post(
                name: .providerBookingsChanged,
                object: ProviderBookingChangeBox(booking)
            )
        } else {
            NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
        }
    }

    static func booking(from notification: Notification) -> SimpleBookingDTO? {
        (notification.object as? ProviderBookingChangeBox)?.booking
    }
}
