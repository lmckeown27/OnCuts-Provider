import Foundation
import LocalAuthentication

/// Device-owner check before sensitive actions (e.g. account deletion without a CampusCuts password).
enum ProviderDeviceAuthentication {
    enum AuthError: LocalizedError {
        case unavailable
        case failed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Face ID, Touch ID, or your device passcode is required to delete your account."
            case .failed:
                return "Authentication failed. Try again."
            case .cancelled:
                return "Authentication was cancelled."
            }
        }
    }

    static func requireDeviceOwnerAuthentication(
        reason: String = "Confirm your identity to delete your account"
    ) async throws {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            if policyError != nil {
                throw AuthError.unavailable
            }
            throw AuthError.unavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                    return
                }
                if let laError = error as? LAError, laError.code == .userCancel || laError.code == .appCancel {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.failed)
                }
            }
        }
    }
}
