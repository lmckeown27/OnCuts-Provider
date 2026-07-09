import { useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import MainChairLogo from '../../assets/logos/Main_Chair.webp';

export default function GDPRPage() {
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
          <h1 className="text-3xl font-bold text-gray-900 mb-2">GDPR Compliance</h1>
          <p className="text-gray-500 mb-4">Last Updated: {lastUpdated}</p>
          <p className="text-gray-600 mb-8">
            For Users in the European Union (EU) and European Economic Area (EEA). This page outlines your rights under the General Data Protection Regulation (GDPR).
          </p>

          <div className="space-y-8 text-gray-700 leading-relaxed">
            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">1. Introduction</h2>
              <p>
                CampusCut is committed to complying with the General Data Protection Regulation (GDPR) for users located in the European Union (EU) and European Economic Area (EEA). This page explains how we process your personal data and your rights under GDPR.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">2. Data Controller</h2>
              <p>
                CampusCut is the data controller responsible for your personal data. For any data protection inquiries, please contact us at campuscuthelp@gmail.com.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">3. Legal Basis for Processing</h2>
              <p>Under GDPR, we must have a legal basis for processing your personal data. We rely on the following:</p>
              
              <p className="font-semibold mt-4 mb-1">3.1 Contract Performance</p>
              <p>Processing necessary to provide our services: account creation, booking management, payment processing, communications between users.</p>

              <p className="font-semibold mt-4 mb-1">3.2 Legitimate Interests</p>
              <p>Processing for platform improvement, fraud prevention, security, and analytics (where it does not override your rights).</p>

              <p className="font-semibold mt-4 mb-1">3.3 Consent</p>
              <p>Processing based on your explicit consent: marketing communications, optional features, cookies beyond essential functionality.</p>

              <p className="font-semibold mt-4 mb-1">3.4 Legal Obligation</p>
              <p>Processing required by law: tax records, fraud investigations, regulatory compliance.</p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">4. Your GDPR Rights</h2>
              <p>Under GDPR, you have the following rights:</p>
              <ul className="list-disc pl-6 mt-2 space-y-2">
                <li>Right to Access (Article 15): You can request a copy of all personal data we hold about you, including how it is processed and with whom it is shared.</li>
                <li>Right to Rectification (Article 16): You can request correction of inaccurate or incomplete personal data.</li>
                <li>Right to Erasure (Article 17): You can request deletion of your personal data when it is no longer necessary, you withdraw consent, or you object to processing.</li>
                <li>Right to Restrict Processing (Article 18): You can request limitations on how we process your data while we verify its accuracy or legitimacy of processing.</li>
                <li>Right to Data Portability (Article 20): You can request your data in a structured, machine-readable format and transfer it to another service provider.</li>
                <li>Right to Object (Article 21): You can object to processing based on legitimate interests or for direct marketing purposes.</li>
                <li>Right to Withdraw Consent (Article 7): Where we rely on your consent, you can withdraw it at any time without affecting prior processing.</li>
                <li>Right to Lodge a Complaint (Article 77): You have the right to file a complaint with a supervisory authority in your country of residence.</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">5. How to Exercise Your Rights</h2>
              <p>To exercise any of your GDPR rights, please contact us at:</p>
              <p className="mt-2">Email: campuscuthelp@gmail.com</p>
              <p className="mt-2">
                Please include "GDPR Request" in the subject line and provide sufficient information to verify your identity. We will respond within 30 days.
              </p>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">6. International Data Transfers</h2>
              <p>
                Our servers are located in the United States. If you are accessing the Service from the EU/EEA, your data will be transferred to the US. We ensure appropriate safeguards are in place:
              </p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Standard Contractual Clauses (SCCs) approved by the European Commission</li>
                <li>Adequacy decisions where applicable</li>
                <li>Data processing agreements with all sub-processors</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">7. Data Retention</h2>
              <p>We retain personal data only for as long as necessary:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Active accounts: Data retained while account is active</li>
                <li>After account deletion: Core data deleted within 30 days; some data retained for legal compliance (up to 7 years for financial records)</li>
                <li>Backups: Removed from backup systems within 90 days</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">8. Data Security Measures</h2>
              <p>We implement technical and organizational measures to protect your data:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Encryption in transit (TLS 1.3) and at rest (AES-256)</li>
                <li>Regular security assessments and penetration testing</li>
                <li>Access controls based on principle of least privilege</li>
                <li>Employee training on data protection</li>
                <li>Incident response procedures</li>
                <li>Secure development practices</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">9. Data Breach Notification</h2>
              <p>In the event of a personal data breach that poses a high risk to your rights and freedoms, we will:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Notify the relevant supervisory authority within 72 hours</li>
                <li>Notify affected individuals without undue delay</li>
                <li>Document the breach and remediation steps taken</li>
              </ul>
            </section>

            <section>
              <h2 className="text-xl font-bold text-gray-900 mb-3">10. Contact Information</h2>
              <p>For any GDPR-related questions or to exercise your rights:</p>
              <p className="mt-2">Email: campuscuthelp@gmail.com</p>
              <p className="mt-1">Subject line: GDPR Request - [Your Request Type]</p>
            </section>
          </div>
        </div>

        {/* Related Links */}
        <div className="mt-8 flex flex-wrap gap-4 justify-center text-sm">
          <Link to="/terms" className="text-gray-600 hover:text-gray-900">
            Terms of Service
          </Link>
          <span className="text-gray-400">|</span>
          <Link to="/privacy" className="text-gray-600 hover:text-gray-900">
            Privacy Policy
          </Link>
        </div>
      </div>
    </div>
  );
}
