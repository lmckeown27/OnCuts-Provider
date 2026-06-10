import Foundation

/// Legal copy for in-app consent surfaces. Replace with remote CMS / PDF URL when your pipeline supports it.
public enum CampusCutsLegal {
    public static func getTOS() -> String {
        termsOfServiceSummary
    }

    public static var termsOfServiceSummary: String {
        """
        By using this app, you agree to Intera’s Terms of Service and community expectations for booking, messaging, and payments.

        The full in-app Terms of Service are shown when you create an account. For questions, contact support@intera.com.

        You confirm you are eligible to use the service where you live. Messaging and bookings may generate notifications; adjust preferences in your profile where supported.
        """
    }
}
