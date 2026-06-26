#if os(iOS) || os(visionOS)
import FirebaseMessaging
import UIKit
import UserNotifications
#endif
import SwiftUI
import os

private let pushLog = Logger(subsystem: "com.campuscuts.intera-provider", category: "push")

/// Hosts the small pieces of UIKit/Foundation lifecycle that SwiftUI doesn't model directly:
///
///   * Google Sign-In configuration (`GoogleSignInAppSupport.configure()`).
///   * Firebase Messaging bootstrap **only when** `GoogleService-Info.plist` carries the
///     Firebase metadata. The current plist is Sign-In-only, so the configure call is gated by
///     `ProviderFirebaseBootstrap.configureIfPossible()` to avoid the Firebase SDK aborting at
///     launch.
///   * APNs permission prompt + remote registration. Server delivery is APNs-driven (hex token
///     → `/notifications/register-device`); the FCM token is captured if Firebase is wired up
///     so we can switch delivery channels later without an app update.
///   * Foreground push presentation (`willPresent` → banner + badge + sound) and tap routing
///     (`didReceive` → `ProviderPushPayloadRouter` → `NotificationCenter` post → SwiftUI
///     observer reacts).
///   * Cold-start payload handoff (`launchOptions[.remoteNotification]`).
final class InteraProviderAppDelegate: NSObject {}

#if os(iOS) || os(visionOS)
extension InteraProviderAppDelegate: UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        GoogleSignInAppSupport.configure()

        // Configure Firebase if (and only if) the bundled plist has Firebase keys. Sign-In-only
        // plists are accepted silently — push still works through raw APNs.
        ProviderFirebaseBootstrap.configureIfPossible()

        UNUserNotificationCenter.current().delegate = self
        if ProviderFirebaseBootstrap.firebaseAvailable {
            Messaging.messaging().delegate = self
        }

        // Permission prompt is fired from `RootView`'s task so it surfaces after the user has
        // landed inside the app rather than blocking sign-in. From here we just make sure that
        // **if** the permission was already granted previously, the app is registered for
        // remote pushes immediately on cold launch so iOS can re-deliver the token.
        Task { @MainActor in
            await Self.registerForRemoteNotificationsIfAuthorized(application)
        }

        // Route any cold-start payload (tapping a notification from the tray with the app
        // killed) into the in-app router. The router posts `Notification.Name`s that SwiftUI
        // observers translate into navigation.
        ProviderPushPayloadRouter.dispatch(launchOptions: launchOptions)

        return true
    }

    // MARK: - APNs token lifecycle

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        pushLog.notice("didRegisterForRemoteNotifications: APNs delivered token (\(hex.count) hex chars)")
        if ProviderFirebaseBootstrap.firebaseAvailable {
            Messaging.messaging().apnsToken = deviceToken
        }
        Task { @MainActor in
            await ProviderPushDeviceRegistration.onAPNsTokenReceived(hex)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Most common cause on simulator: the simulator's host macOS doesn't support push
        // notifications, so iOS can't get an APNs token. On real devices this usually means
        // the provisioning profile is missing the push capability or the device has no
        // network. The next launch / permission re-grant will retry.
        pushLog.error("didFailToRegisterForRemoteNotifications: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Public helpers

    /// Asks the user for `alert + badge + sound` and, if granted, calls
    /// `registerForRemoteNotifications()`. Idempotent — safe to call from `.task` on a SwiftUI
    /// root view.
    @MainActor
    static func requestNotificationAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            pushLog.notice("requestAuthorization: granted=\(granted, privacy: .public)")
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            pushLog.error("requestAuthorization: error=\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Quietly re-registers the device for remote pushes if the user has previously granted
    /// permission. Used on launch so iOS re-emits a fresh APNs token after upgrades / restores.
    @MainActor
    private static func registerForRemoteNotificationsIfAuthorized(_ application: UIApplication) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        pushLog.notice("registerForRemoteNotificationsIfAuthorized: authorizationStatus=\(settings.authorizationStatus.rawValue, privacy: .public)")
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            application.registerForRemoteNotifications()
        default:
            break
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate (foreground display + tap)

extension InteraProviderAppDelegate: UNUserNotificationCenterDelegate {
    /// Foreground delivery: show the system banner + badge + sound like the lock-screen
    /// version. Mirrors consumer-app behavior so providers don't miss a booking ping just
    /// because they happen to be on the dashboard.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Even before the user taps, refresh badges + unread counts so the inbox UI doesn't
        // lag behind. Navigation (Messages overlay, bookings sheet, etc.) only happens on tap.
        let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            ProviderPushPayloadRouter.refreshFromForegroundDelivery(userInfo: userInfo)
        }
        completionHandler([.banner, .badge, .sound, .list])
    }

    /// User tapped the notification (foreground, background, or cold start). Route into the
    /// in-app navigation pipeline.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            ProviderPushPayloadRouter.dispatch(response: response)
            completionHandler()
        }
    }
}

// MARK: - MessagingDelegate (only active when Firebase is fully configured)

extension InteraProviderAppDelegate: MessagingDelegate {
    /// Captures the FCM token. We don't currently forward it to the backend — CampusCuts sends
    /// pushes via direct APNs using the hex token from `register-device`. If you ever want to
    /// switch delivery to FCM (e.g., to support Android with one server-side codepath), POST
    /// this to a new endpoint here and pivot the backend in tandem.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        #if DEBUG
        if let fcmToken {
            print("[push] fcm token (debug only):", String(fcmToken.prefix(12)) + "…")
        }
        #endif
    }
}
#endif
