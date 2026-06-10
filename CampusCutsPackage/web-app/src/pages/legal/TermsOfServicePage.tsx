import { useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import MainChairLogo from '../../assets/logos/Main_Chair.webp';

export default function TermsOfServicePage() {
  const navigate = useNavigate();
  const lastUpdated = "January 21, 2026";

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
          <h1 className="text-3xl font-bold text-gray-900 mb-2">Terms of Service</h1>
          <p className="text-gray-500 mb-8">Last Updated: {lastUpdated}</p>

          <div className="space-y-8 text-gray-700 leading-relaxed">
            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">1. Introduction</h2>
              <p>
                Welcome to CampusCut ("we," "our," or "us"). These Terms of Service ("Terms") govern your access to and use of the CampusCut platform, including our website, mobile applications, and all related services (collectively, the "Service").
              </p>
              <p className="mt-3">
                By accessing or using the Service, you agree to be bound by these Terms. If you do not agree to these Terms, you may not access or use the Service.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">2. Description of Service</h2>
              <p>
                CampusCut is a marketplace platform that connects consumers seeking grooming services ("Consumers") with independent barbers offering their services ("Barbers") at college and university campuses. We facilitate:
              </p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Discovery and browsing of barber profiles and services</li>
                <li>Booking and scheduling of appointments</li>
                <li>Secure payment processing</li>
                <li>Reviews and ratings</li>
                <li>Communication between Consumers and Barbers</li>
                <li>Campus-based barber management</li>
              </ul>
              <p className="mt-3">
                Important: CampusCut is a platform that connects users. We are not a grooming service provider. Barbers are independent contractors, not employees of CampusCut.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">3. Account Registration</h2>
              <p>To use certain features of the Service, you must create an account. You agree to:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Provide accurate, current, and complete information</li>
                <li>Maintain and promptly update your account information</li>
                <li>Maintain the security of your password and account</li>
                <li>Accept responsibility for all activities under your account</li>
                <li>Notify us immediately of any unauthorized use</li>
              </ul>
              <p className="mt-3">
                You must be at least 18 years old to create an account. By creating an account, you represent and warrant that you meet this age requirement.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">4. Consumer Terms</h2>
              <p>As a Consumer using the Service, you agree to:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Provide accurate booking information including preferred date, time, and location</li>
                <li>Arrive on time for scheduled appointments</li>
                <li>Cancel or reschedule appointments with reasonable notice</li>
                <li>Treat Barbers with respect and professionalism</li>
                <li>Pay the agreed-upon price for services rendered</li>
                <li>Leave honest and fair reviews based on actual experiences</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">5. Barber Terms</h2>
              <p>As a Barber using the Service, you agree to:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Submit an application and receive approval before offering services</li>
                <li>Maintain accurate and up-to-date profile information, including services and pricing</li>
                <li>Respond to booking requests in a timely manner</li>
                <li>Honor confirmed bookings and arrive on time</li>
                <li>Provide professional, quality services</li>
                <li>Comply with all applicable laws, regulations, and licensing requirements</li>
                <li>Maintain appropriate insurance coverage as required by law</li>
                <li>Treat Consumers with respect and professionalism</li>
              </ul>
              <p className="mt-3">
                Barbers are independent contractors and are solely responsible for their services, business practices, tax obligations, and compliance with applicable laws.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">6. Campus Manager Terms</h2>
              <p>Campus Managers are users who oversee barber operations at specific campuses. As a Campus Manager, you agree to:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Review and manage barber applications for your assigned campus</li>
                <li>Maintain oversight of barber quality and conduct at your campus</li>
                <li>Act in good faith when approving or rejecting barber applications</li>
                <li>Report any issues or concerns to CampusCut support</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">7. Payments and Fees</h2>
              
              <p className="font-semibold mt-4 mb-2">7.1 Payment Processing</p>
              <p>
                All payments are processed securely through Stripe, our third-party payment processor. By using the Service, you agree to Stripe's terms of service. We do not store your full credit card information on our servers.
              </p>

              <p className="font-semibold mt-4 mb-2">7.2 Payouts to Barbers</p>
              <p>
                Barbers receive payments for each completed booking. Payments are released after the service is marked as complete. Payout timing may vary based on payment processor policies.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">8. Cancellations and Refunds</h2>
              <p>
                Cancellation policies are set by individual Barbers. We encourage both parties to communicate promptly regarding any changes to scheduled appointments. Refund eligibility depends on:
              </p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>The timing of the cancellation</li>
                <li>The reason for cancellation</li>
                <li>The Barber's posted cancellation policy</li>
                <li>Whether the service was partially or fully rendered</li>
              </ul>
              <p className="mt-3">
                Disputes between Consumers and Barbers should first be attempted to be resolved directly. CampusCut may assist in mediation but is not obligated to issue refunds.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">9. User Conduct</h2>
              <p>You agree not to:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Use the Service for any illegal purpose</li>
                <li>Harass, abuse, or harm another person</li>
                <li>Provide false or misleading information</li>
                <li>Interfere with or disrupt the Service</li>
                <li>Attempt to gain unauthorized access to any part of the Service</li>
                <li>Use automated systems to access the Service without permission</li>
                <li>Circumvent the platform to avoid fees</li>
                <li>Post fraudulent reviews or ratings</li>
                <li>Discriminate against any user based on protected characteristics</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">10. Intellectual Property</h2>
              <p>
                The Service and its original content, features, and functionality are owned by CampusCut and are protected by international copyright, trademark, patent, trade secret, and other intellectual property laws.
              </p>
              <p className="mt-3">
                By posting content (including profile information, portfolio images, and reviews), you grant CampusCut a non-exclusive, worldwide, royalty-free license to use, display, and distribute such content in connection with the Service.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">11. Disclaimer of Warranties</h2>
              <p>
                THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED. WE DO NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, SECURE, OR ERROR-FREE.
              </p>
              <p className="mt-3">
                WE DO NOT ENDORSE, WARRANT, OR GUARANTEE ANY BARBER'S SERVICES, QUALIFICATIONS, OR WORK QUALITY. YOU USE THE SERVICE AND ENGAGE WITH BARBERS AT YOUR OWN RISK.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">12. Limitation of Liability</h2>
              <p>
                TO THE MAXIMUM EXTENT PERMITTED BY LAW, CAMPUSCUT SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS OR REVENUES, WHETHER INCURRED DIRECTLY OR INDIRECTLY.
              </p>
              <p className="mt-3">
                OUR TOTAL LIABILITY FOR ANY CLAIMS ARISING FROM OR RELATED TO THE SERVICE SHALL NOT EXCEED THE AMOUNT YOU PAID US IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">13. Indemnification</h2>
              <p>
                You agree to indemnify, defend, and hold harmless CampusCut and its officers, directors, employees, and agents from any claims, damages, losses, liabilities, and expenses (including attorneys' fees) arising from your use of the Service or violation of these Terms.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">14. Termination</h2>
              <p>
                We may terminate or suspend your account and access to the Service immediately, without prior notice or liability, for any reason, including if you breach these Terms.
              </p>
              <p className="mt-3">
                Upon termination, your right to use the Service will immediately cease. All provisions of these Terms which should survive termination shall survive.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">15. Changes to Terms</h2>
              <p>
                We reserve the right to modify these Terms at any time. We will notify users of any material changes by posting the new Terms on this page and updating the "Last Updated" date.
              </p>
              <p className="mt-3">
                Your continued use of the Service after any changes constitutes your acceptance of the new Terms.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">16. Governing Law</h2>
              <p>
                These Terms shall be governed by and construed in accordance with the laws of the State of California, United States, without regard to its conflict of law provisions.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">17. Contact Us</h2>
              <p>If you have any questions about these Terms, please contact us at:</p>
              <p className="mt-2">Email: campuscuthelp@gmail.com</p>
            </section>
          </div>
        </div>

        {/* Related Links */}
        <div className="mt-8 flex flex-wrap gap-4 justify-center text-sm">
          <Link to="/privacy" className="text-gray-600 hover:text-gray-900">
            Privacy Policy
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
