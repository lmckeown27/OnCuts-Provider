import FirebaseCore
import Foundation

/// Safe wrapper around `FirebaseApp.configure()`.
///
/// Why this exists: the bundled `GoogleService-Info.plist` is currently the **Google Sign-In**
/// flavor (`CLIENT_ID` + `REVERSED_CLIENT_ID` + `BUNDLE_ID` only) — it does **not** contain the
/// Firebase metadata (`API_KEY`, `GCM_SENDER_ID`, `PROJECT_ID`, `STORAGE_BUCKET`, …) that
/// `FirebaseApp.configure()` requires. Calling `configure()` with that incomplete plist crashes
/// on launch.
///
/// This helper:
///   1. Loads the plist (`GoogleService-Info` or `FirebaseService-Info` if you ever split it).
///   2. Verifies the Firebase-specific keys exist.
///   3. Only then calls `FirebaseApp.configure()`.
///
/// If Firebase isn't fully configured, push notifications **still work** — registration is
/// driven by the raw APNs hex token via `POST /notifications/register-device`. Firebase
/// Messaging is supplementary (it gives us an FCM token we could optionally forward to the
/// server later if we ever want FCM-driven delivery for cross-platform parity).
///
/// To enable Firebase Messaging, drop a complete `GoogleService-Info.plist` from the Firebase
/// console (Project Settings → iOS app) into the app target — no code change required.
@MainActor
enum ProviderFirebaseBootstrap {
    private(set) static var isConfigured = false

    /// Reads the plist, decides whether Firebase has the metadata it needs, and configures the
    /// SDK if so. Idempotent — safe to call multiple times from launch / scene activation.
    static func configureIfPossible() {
        guard !isConfigured else { return }
        guard FirebaseApp.app() == nil else {
            isConfigured = true
            return
        }
        guard let options = loadOptionsIfFirebaseEnabled() else { return }
        FirebaseApp.configure(options: options)
        isConfigured = FirebaseApp.app() != nil
    }

    /// `true` once a complete Firebase config has been applied (controls whether we attempt to
    /// set the `Messaging.delegate` and forward APNs tokens to FCM).
    static var firebaseAvailable: Bool { isConfigured }

    // MARK: - Internals

    /// Returns `FirebaseOptions` only when the plist carries the Firebase keys. Returns `nil`
    /// (without logging or crashing) if the plist is the Sign-In-only variant.
    private static func loadOptionsIfFirebaseEnabled() -> FirebaseOptions? {
        // Try the canonical Firebase plist name first, then fall back to GoogleService-Info
        // (used today for Google Sign-In; will gain Firebase keys if you replace it).
        for name in ["GoogleService-Info"] {
            guard let path = Bundle.main.path(forResource: name, ofType: "plist"),
                  let dict = NSDictionary(contentsOfFile: path) as? [String: Any]
            else { continue }
            let apiKey = (dict["API_KEY"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let gcmSender = (dict["GCM_SENDER_ID"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let googleAppID = (dict["GOOGLE_APP_ID"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let projectID = (dict["PROJECT_ID"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !apiKey.isEmpty, !gcmSender.isEmpty, !googleAppID.isEmpty else { continue }
            // Build options manually so we never rely on Firebase's plist auto-loader hitting
            // the incomplete file and erroring out.
            let options = FirebaseOptions(googleAppID: googleAppID, gcmSenderID: gcmSender)
            options.apiKey = apiKey
            if !projectID.isEmpty { options.projectID = projectID }
            options.bundleID = Bundle.main.bundleIdentifier ?? options.bundleID
            if let storageBucket = (dict["STORAGE_BUCKET"] as? String)?.trimmingCharacters(in: .whitespaces),
               !storageBucket.isEmpty
            {
                options.storageBucket = storageBucket
            }
            if let clientID = (dict["CLIENT_ID"] as? String)?.trimmingCharacters(in: .whitespaces),
               !clientID.isEmpty
            {
                options.clientID = clientID
            }
            if let databaseURL = (dict["DATABASE_URL"] as? String)?.trimmingCharacters(in: .whitespaces),
               !databaseURL.isEmpty
            {
                options.databaseURL = databaseURL
            }
            return options
        }
        return nil
    }
}
