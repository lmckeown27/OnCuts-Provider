import { useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import MainChairLogo from '../../assets/logos/Main_Chair.webp';

export default function PrivacyPolicyPage() {
  const navigate = useNavigate();
  const lastUpdated = "March 4, 2026";

  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);

  const handleBack = () => {
    // Check if there's history to go back to
    if (window.history.length > 1) {
      navigate(-1);
    } else {
      // Fallback to homepage if no history
      navigate('/');
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200 sticky top-0 z-10">
        <div className="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-3 hover:opacity-80 transition-opacity">
            <img src={MainChairLogo} alt="CampusCut" className="h-10 w-auto" />
            <span className="text-xl font-bold text-gray-900">CampusCut</span>
          </Link>
          <button 
            onClick={handleBack}
            className="flex items-center gap-2 text-gray-600 hover:text-gray-900 transition-colors"
          >
            <ArrowLeft className="w-4 h-4" />
            Back
          </button>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-4xl mx-auto px-4 py-12">
        <div className="bg-white rounded-lg shadow p-8 md:p-12">
          <h1 className="text-3xl font-bold text-gray-900 mb-2">Privacy Policy</h1>
          <p className="text-gray-500 mb-8">Last Updated: {lastUpdated}</p>

          <div className="space-y-8 text-gray-700 leading-relaxed">
            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">1. Introduction</h2>
              <p>
                CampusCut is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our platform, website, and mobile applications (collectively, the "Service").
              </p>
              <p className="mt-3">
                Please read this Privacy Policy carefully. By using the Service, you agree to the collection and use of information in accordance with this policy.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">2. Information We Collect</h2>
              
              <p className="font-semibold mt-4 mb-2">2.1 Information You Provide</p>
              <ul className="list-disc pl-6 space-y-1">
                <li>Account Information: Name, email address, password (encrypted)</li>
                <li>Profile Information: Profile photo, bio, campus affiliation</li>
                <li>Barber-Specific Information: Services offered, pricing, availability, portfolio images, business location</li>
                <li>Booking Information: Appointment dates, times, services requested, special instructions</li>
                <li>Payment Information: Payment method details (processed securely by Stripe)</li>
                <li>Communications: Messages sent through our platform, customer support inquiries</li>
                <li>Reviews and Ratings: Feedback you leave for other users</li>
              </ul>

              <p className="font-semibold mt-4 mb-2">2.2 Information Collected Automatically</p>
              <ul className="list-disc pl-6 space-y-1">
                <li>Device Information: Device type, operating system, browser type, unique device identifiers</li>
                <li>Usage Data: Pages visited, features used, time spent on the platform</li>
                <li>Location Data: General location based on IP address; precise location only if you grant permission</li>
                <li>Log Data: IP address, access times, referring URLs, error logs</li>
                <li>Cookies and Tracking: Session cookies, authentication tokens, analytics data</li>
              </ul>

              <p className="font-semibold mt-4 mb-2">2.3 Information from Third Parties</p>
              <ul className="list-disc pl-6 space-y-1">
                <li>Payment Processors: Transaction status and confirmation from Stripe</li>
                <li>Social Media: If you choose to link social accounts (e.g., Instagram for portfolio)</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">3. How We Use Your Information</h2>
              <p>We use the information we collect to:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Provide, maintain, and improve the Service</li>
                <li>Process bookings and payments</li>
                <li>Facilitate communication between Consumers and Barbers</li>
                <li>Send transactional notifications (booking confirmations, reminders, receipts)</li>
                <li>Send promotional communications (with your consent)</li>
                <li>Personalize your experience and recommend relevant barbers</li>
                <li>Analyze usage patterns to improve our platform</li>
                <li>Detect, prevent, and address fraud and security issues</li>
                <li>Comply with legal obligations</li>
                <li>Respond to customer support requests</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">4. How We Share Your Information</h2>
              <p>We may share your information in the following circumstances:</p>

              <p className="font-semibold mt-4 mb-2">4.1 With Other Users</p>
              <p>
                Consumers and Barbers can see each other's profile information, reviews, and booking details as necessary to facilitate appointments.
              </p>

              <p className="font-semibold mt-4 mb-2">4.2 With Service Providers</p>
              <ul className="list-disc pl-6 space-y-1">
                <li>Stripe: Payment processing</li>
                <li>Cloud Hosting: Data storage and server infrastructure</li>
                <li>Analytics Providers: Usage analysis and improvement</li>
                <li>Communication Services: Email delivery</li>
              </ul>

              <p className="font-semibold mt-4 mb-2">4.3 For Legal Reasons</p>
              <p>
                We may disclose your information if required by law, subpoena, or other legal process, or if we believe disclosure is necessary to protect our rights, your safety, or the safety of others.
              </p>

              <p className="font-semibold mt-4 mb-2">4.4 Business Transfers</p>
              <p>
                In the event of a merger, acquisition, or sale of assets, your information may be transferred as part of that transaction.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">5. Data Security</h2>
              <p>We implement industry-standard security measures to protect your information:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Encryption of data in transit (HTTPS/TLS)</li>
                <li>Encryption of sensitive data at rest</li>
                <li>Password hashing using bcrypt</li>
                <li>Secure payment processing via Stripe (PCI-DSS compliant)</li>
                <li>Regular security audits and monitoring</li>
                <li>Access controls limiting employee access to personal data</li>
              </ul>
              <p className="mt-3">
                While we strive to protect your information, no method of transmission over the Internet or electronic storage is 100% secure.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">6. Data Retention</h2>
              <p>
                We retain your personal information for as long as your account is active or as needed to provide you services. We may retain certain information for longer periods as required by law or for legitimate business purposes, such as:
              </p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Transaction records for tax and accounting purposes</li>
                <li>Communications related to disputes or legal matters</li>
                <li>Anonymized and aggregated data for analytics</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">7. Your Rights</h2>
              <p>Depending on your location, you may have the following rights:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Access: Request a copy of your personal data</li>
                <li>Correction: Request correction of inaccurate data</li>
                <li>Deletion: Request deletion of your data (subject to legal requirements)</li>
                <li>Portability: Request your data in a portable format</li>
                <li>Opt-Out: Unsubscribe from marketing communications</li>
                <li>Restrict Processing: Request limitations on how we use your data</li>
              </ul>
              <p className="mt-3">
                To exercise these rights, contact us at campuscuthelp@gmail.com.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">8. Cookies and Tracking</h2>
              <p>We use cookies and similar technologies to:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Keep you logged in</li>
                <li>Remember your preferences</li>
                <li>Analyze how our service is used</li>
                <li>Improve user experience</li>
              </ul>
              <p className="mt-3">
                You can control cookies through your browser settings. Note that disabling cookies may affect the functionality of the Service.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">9. Third-Party Links</h2>
              <p>
                Our Service may contain links to third-party websites or services (e.g., Instagram portfolios, Stripe). We are not responsible for the privacy practices of these third parties. We encourage you to review their privacy policies.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">10. Google API Services</h2>
              <p>
                CampusCut offers optional integration with Google Calendar to help barbers manage their availability. When you connect your Google Calendar:
              </p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>We access your Google Calendar to read busy/free times to prevent double-booking</li>
                <li>We may create calendar events for CampusCut appointments (with your permission)</li>
                <li>We store a secure OAuth refresh token to maintain the connection</li>
                <li>You can disconnect your Google Calendar at any time from your barber dashboard</li>
              </ul>
              <p className="mt-4 p-4 bg-gray-100 rounded-lg border border-gray-200">
                <strong>Limited Use Disclosure:</strong> CampusCut's use and transfer of information received from Google APIs to any other app will adhere to the{' '}
                <a 
                  href="https://developers.google.com/terms/api-services-user-data-policy" 
                  target="_blank" 
                  rel="noopener noreferrer"
                  className="text-primary-600 hover:text-primary-700 underline"
                >
                  Google API Services User Data Policy
                </a>
                , including the Limited Use requirements.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">11. Children's Privacy</h2>
              <p>
                The Service is not intended for users under 18 years of age. We do not knowingly collect personal information from children. If we become aware that we have collected data from a child, we will take steps to delete it.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">12. Changes to This Policy</h2>
              <p>
                We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new policy on this page and updating the "Last Updated" date. Material changes may be communicated via email or through the Service.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">13. Contact Us</h2>
              <p>If you have any questions about this Privacy Policy, please contact us at:</p>
              <p className="mt-2">Email: campuscuthelp@gmail.com</p>
            </section>
          </div>
        </div>

        {/* Related Links */}
        <div className="mt-8 flex flex-wrap gap-4 justify-center text-sm">
          <Link to="/terms" className="text-gray-600 hover:text-gray-900">
            Terms of Service
          </Link>
          <span className="text-gray-400">|</span>
          <Link to="/gdpr" className="text-gray-600 hover:text-gray-900">
            GDPR
          </Link>
        </div>
      </div>
    </div>
  );
}
