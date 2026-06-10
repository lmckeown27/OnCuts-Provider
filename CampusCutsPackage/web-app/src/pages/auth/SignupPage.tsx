import { useState, useEffect, useRef } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { Eye, EyeOff, AlertCircle, Mail, CheckCircle, XCircle, X } from 'lucide-react';
import { useAuthStore } from '../../store/useAuthStore';
import { ROUTES } from '../../config/constants';
import TabChairLogo from '../../assets/logos/Tab_Chair.webp';

interface SignupForm {
  firstName: string;
  lastName: string;
  email: string;
  password: string;
  confirmPassword: string;
}

// Terms of Service content component
const TermsOfServiceContent = () => (
  <div className="prose prose-sm max-w-none space-y-6 text-gray-700">
    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">1. Introduction</h3>
      <p className="leading-relaxed">Welcome to CampusCut ("we," "our," or "us"). These Terms of Service ("Terms") govern your access to and use of the CampusCut platform, including our website, mobile applications, and all related services (collectively, the "Service").</p>
      <p className="leading-relaxed mt-2">By accessing or using the Service, you agree to be bound by these Terms. If you do not agree to these Terms, you may not access or use the Service.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">2. Description of Service</h3>
      <p className="leading-relaxed">CampusCut is a marketplace platform that connects consumers seeking grooming services ("Consumers") with independent barbers offering their services ("Barbers"). We facilitate:</p>
      <ul className="list-disc pl-5 mt-2 space-y-1">
        <li>Discovery and browsing of barber profiles and services</li>
        <li>Booking and scheduling of appointments</li>
        <li>Secure payment processing</li>
        <li>Reviews and ratings</li>
        <li>Communication between Consumers and Barbers</li>
      </ul>
      <p className="leading-relaxed mt-2"><strong>Important:</strong> CampusCut is a platform that connects users. We are not a grooming service provider. Barbers are independent contractors, not employees of CampusCut.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">3. Account Registration</h3>
      <p className="leading-relaxed">To use certain features of the Service, you must create an account. You agree to:</p>
      <ul className="list-disc pl-5 mt-2 space-y-1">
        <li>Provide accurate, current, and complete information</li>
        <li>Maintain and promptly update your account information</li>
        <li>Maintain the security of your password and account</li>
        <li>Accept responsibility for all activities under your account</li>
        <li>Notify us immediately of any unauthorized use</li>
      </ul>
      <p className="leading-relaxed mt-2">You must be at least 18 years old to create an account. By creating an account, you represent and warrant that you meet this age requirement.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">4. Consumer Terms</h3>
      <p className="leading-relaxed">As a Consumer using the Service, you agree to:</p>
      <ul className="list-disc pl-5 mt-2 space-y-1">
        <li>Provide accurate booking information including preferred date, time, and location</li>
        <li>Arrive on time for scheduled appointments</li>
        <li>Cancel or reschedule appointments with reasonable notice</li>
        <li>Treat Barbers with respect and professionalism</li>
        <li>Pay the agreed-upon price for services rendered</li>
        <li>Leave honest and fair reviews based on actual experiences</li>
      </ul>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">5. Barber Terms</h3>
      <p className="leading-relaxed">As a Barber using the Service, you agree to:</p>
      <ul className="list-disc pl-5 mt-2 space-y-1">
        <li>Maintain accurate and up-to-date profile information, including services and pricing</li>
        <li>Respond to booking requests in a timely manner</li>
        <li>Honor confirmed bookings and arrive on time</li>
        <li>Provide professional, quality services</li>
        <li>Comply with all applicable laws, regulations, and licensing requirements</li>
        <li>Maintain appropriate insurance coverage as required by law</li>
        <li>Treat Consumers with respect and professionalism</li>
      </ul>
      <p className="leading-relaxed mt-2">Barbers are independent contractors and are solely responsible for their services, business practices, tax obligations, and compliance with applicable laws.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">6. Payments and Fees</h3>
      <p className="leading-relaxed"><strong>Payment Processing:</strong> All payments are processed securely through Stripe, our third-party payment processor. By using the Service, you agree to Stripe's terms of service. We do not store your full credit card information on our servers.</p>
      <p className="leading-relaxed mt-2"><strong>Payouts to Barbers:</strong> Barbers receive payments for each completed booking. Payments are released after the service is marked as complete. Payout timing may vary based on payment processor policies.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">7. Cancellations and Refunds</h3>
      <p className="leading-relaxed">Cancellation policies are set by individual Barbers. We encourage both parties to communicate promptly regarding any changes to scheduled appointments. Refund eligibility depends on:</p>
      <ul className="list-disc pl-5 mt-2 space-y-1">
        <li>The timing of the cancellation</li>
        <li>The reason for cancellation</li>
        <li>The Barber's posted cancellation policy</li>
        <li>Whether the service was partially or fully rendered</li>
      </ul>
      <p className="leading-relaxed mt-2">Disputes between Consumers and Barbers should first be attempted to be resolved directly. CampusCut may assist in mediation but is not obligated to issue refunds.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">8. User Conduct</h3>
      <p className="leading-relaxed">You agree not to:</p>
      <ul className="list-disc pl-5 mt-2 space-y-1">
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
      <h3 className="text-lg font-bold text-gray-900 mb-2">9. Intellectual Property</h3>
      <p className="leading-relaxed">The Service and its original content, features, and functionality are owned by CampusCut and are protected by international copyright, trademark, patent, trade secret, and other intellectual property laws.</p>
      <p className="leading-relaxed mt-2">By posting content (including profile information, portfolio images, and reviews), you grant CampusCut a non-exclusive, worldwide, royalty-free license to use, display, and distribute such content in connection with the Service.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">10. Disclaimer of Warranties</h3>
      <p className="leading-relaxed uppercase text-xs">THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED. WE DO NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, SECURE, OR ERROR-FREE.</p>
      <p className="leading-relaxed uppercase text-xs mt-2">WE DO NOT ENDORSE, WARRANT, OR GUARANTEE ANY BARBER'S SERVICES, QUALIFICATIONS, OR WORK QUALITY. YOU USE THE SERVICE AND ENGAGE WITH BARBERS AT YOUR OWN RISK.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">11. Limitation of Liability</h3>
      <p className="leading-relaxed uppercase text-xs">TO THE MAXIMUM EXTENT PERMITTED BY LAW, CAMPUSCUT SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS OR REVENUES, WHETHER INCURRED DIRECTLY OR INDIRECTLY.</p>
      <p className="leading-relaxed uppercase text-xs mt-2">OUR TOTAL LIABILITY FOR ANY CLAIMS ARISING FROM OR RELATED TO THE SERVICE SHALL NOT EXCEED THE AMOUNT YOU PAID US IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">12. Indemnification</h3>
      <p className="leading-relaxed">You agree to indemnify, defend, and hold harmless CampusCut and its officers, directors, employees, and agents from any claims, damages, losses, liabilities, and expenses (including attorneys' fees) arising from your use of the Service or violation of these Terms.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">13. Termination</h3>
      <p className="leading-relaxed">We may terminate or suspend your account and access to the Service immediately, without prior notice or liability, for any reason, including if you breach these Terms.</p>
      <p className="leading-relaxed mt-2">Upon termination, your right to use the Service will immediately cease. All provisions of these Terms which should survive termination shall survive.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">14. Changes to Terms</h3>
      <p className="leading-relaxed">We reserve the right to modify these Terms at any time. We will notify users of any material changes by posting the new Terms on this page and updating the "Last Updated" date.</p>
      <p className="leading-relaxed mt-2">Your continued use of the Service after any changes constitutes your acceptance of the new Terms.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">15. Governing Law</h3>
      <p className="leading-relaxed">These Terms shall be governed by and construed in accordance with the laws of the State of California, United States, without regard to its conflict of law provisions.</p>
    </section>

    <section>
      <h3 className="text-lg font-bold text-gray-900 mb-2">16. Contact Us</h3>
      <p className="leading-relaxed">If you have any questions about these Terms, please contact us at:</p>
      <p className="leading-relaxed mt-2"><strong>Email:</strong> campuscuthelp@gmail.com</p>
    </section>

    <div className="mt-8 pt-6 border-t border-gray-200">
      <p className="text-center text-gray-500 text-sm">Last Updated: January 16, 2025</p>
    </div>
  </div>
);

export default function SignupPage() {
  const navigate = useNavigate();
  const { signup } = useAuthStore();
  const [isLoading, setIsLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [passwordStrength, setPasswordStrength] = useState(0);
  const [formData, setFormData] = useState<SignupForm>({
    firstName: '',
    lastName: '',
    email: '',
    password: '',
    confirmPassword: ''
  });
  const [validationErrors, setValidationErrors] = useState<{[key: string]: string}>({});
  
  // Terms of Service state
  const [showTermsModal, setShowTermsModal] = useState(false);
  const [hasScrolledToBottom, setHasScrolledToBottom] = useState(false);
  const [termsAccepted, setTermsAccepted] = useState(false);
  const termsScrollRef = useRef<HTMLDivElement>(null);
  
  // Handle terms scroll to detect when user reaches bottom
  const handleTermsScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const element = e.currentTarget;
    const scrolledToBottom = element.scrollHeight - element.scrollTop <= element.clientHeight + 50;
    if (scrolledToBottom && !hasScrolledToBottom) {
      setHasScrolledToBottom(true);
    }
  };
  
  // Accept terms and close modal
  const handleAcceptTerms = () => {
    setTermsAccepted(true);
    setShowTermsModal(false);
  };

  // Password strength checker
  const checkPasswordStrength = (password: string): number => {
    let strength = 0;
    if (password.length >= 8) strength++;
    if (/[a-z]/.test(password)) strength++;
    if (/[A-Z]/.test(password)) strength++;
    if (/[0-9]/.test(password)) strength++;
    if (/[^A-Za-z0-9]/.test(password)) strength++;
    return strength;
  };

  const getPasswordStrengthText = (strength: number): string => {
    if (strength <= 1) return 'Weak';
    if (strength <= 2) return 'Fair';
    if (strength <= 3) return 'Good';
    if (strength <= 4) return 'Strong';
    return 'Very Strong';
  };

  const getPasswordStrengthColor = (strength: number): string => {
    if (strength <= 1) return 'text-red-600';
    if (strength <= 2) return 'text-orange-500';
    if (strength <= 3) return 'text-yellow-600';
    if (strength <= 4) return 'text-blue-600';
    return 'text-green-600';
  };

  const getPasswordStrengthBarColor = (strength: number, level: number): string => {
    if (level > strength) return 'bg-gray-200';
    if (strength <= 1) return 'bg-red-500';
    if (strength <= 2) return 'bg-orange-500';
    if (strength <= 3) return 'bg-yellow-500';
    if (strength <= 4) return 'bg-blue-500';
    return 'bg-green-500';
  };

  useEffect(() => {
    setPasswordStrength(checkPasswordStrength(formData.password));
  }, [formData.password]);

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
    
    // Clear specific validation error when user starts typing
    if (validationErrors[name]) {
      setValidationErrors(prev => {
        const next = { ...prev };
        delete next[name];
        return next;
      });
    }
    if (error) setError(null);
  };

  const isValidEmail = (email: string): boolean => {
    // Basic format validation
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    if (!emailRegex.test(email)) return false;
    
    // Whitelist of valid TLDs
    const validTLDs = [
      // Generic TLDs
      'com', 'org', 'net', 'edu', 'gov', 'mil', 'int', 'info', 'biz', 'name', 'pro',
      // Popular new TLDs
      'io', 'co', 'app', 'dev', 'tech', 'ai', 'me', 'tv', 'cc', 'xyz', 'online', 'site', 'web', 'cloud', 'email',
      // Country code TLDs
      'us', 'uk', 'ca', 'au', 'de', 'fr', 'es', 'it', 'nl', 'be', 'ch', 'at', 'jp', 'cn', 'kr', 'in', 'br', 'mx', 
      'ar', 'cl', 'ru', 'pl', 'cz', 'se', 'no', 'dk', 'fi', 'ie', 'nz', 'sg', 'hk', 'tw', 'th', 'ph', 'my', 'id',
      'za', 'ng', 'ke', 'eg', 'il', 'ae', 'sa', 'pk', 'bd', 'vn', 'ua', 'gr', 'pt', 'hu', 'ro', 'bg', 'hr', 'sk',
      // Other common TLDs
      'mobi', 'asia', 'jobs', 'museum', 'travel', 'coop', 'aero', 'cat', 'post',
      // Company/brand TLDs
      'google', 'amazon', 'apple', 'microsoft', 'yahoo', 'gmail'
    ];
    
    const tld = email.split('.').pop()?.toLowerCase();
    if (!tld || !validTLDs.includes(tld)) return false;
    
    return true;
  };

  // Check if email has a valid domain (any email allowed for testing)
  const isUniversityEmail = (email: string): boolean => {
    // Allow any email domain for testing purposes
    return isValidEmail(email);
  };

  const validateForm = (): boolean => {
    const errors: {[key: string]: string} = {};

    if (!formData.firstName.trim()) {
      errors.firstName = 'First name is required';
    }

    if (!formData.lastName.trim()) {
      errors.lastName = 'Last name is required';
    }

    if (!formData.email.trim()) {
      errors.email = 'Email address is required';
    } else if (!isValidEmail(formData.email)) {
      errors.email = 'Please enter a valid email address';
    }

    if (!formData.password) {
      errors.password = 'Password is required';
    } else if (formData.password.length < 8) {
      errors.password = 'Password must be at least 8 characters';
    }

    if (formData.password !== formData.confirmPassword) {
      errors.confirmPassword = 'Passwords do not match';
    }

    setValidationErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const isFormValid = 
    formData.firstName.trim() !== '' &&
    formData.lastName.trim() !== '' &&
    formData.email.trim() !== '' &&
    isValidEmail(formData.email) &&
    isUniversityEmail(formData.email) &&
    formData.password.length >= 8 &&
    formData.password === formData.confirmPassword &&
    termsAccepted;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) {
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const result = await signup({
        first_name: formData.firstName,
        last_name: formData.lastName,
        email: formData.email,
        password: formData.password,
        user_type: 'student', // All users start as consumers; barber applications are separate
      });
      
      toast.success('Verification email sent! Please check your inbox.');
      
      // If in auto-verify mode (development), show the code
      if (result.verificationCode) {
        toast.success(`Dev Mode - Code: ${result.verificationCode}`, { duration: 10000 });
      }
      
      // Redirect to email verification page
      navigate('/web/verify-email');
    } catch (err: any) {
      const statusCode = err.response?.status;
      let errorMessage: string;
      
      if (statusCode === 429 || err.isRateLimitError) {
        errorMessage = 'Rate limit reached. Please wait a moment and reload the page.';
      } else {
        errorMessage = err.response?.data?.message || err.message || 'Signup failed. Please try again.';
      }
      setError(errorMessage);
      toast.error(errorMessage);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div 
      className="min-h-[100dvh] flex items-center justify-center py-12 px-4"
      style={{ backgroundColor: '#022b19' }}
    >
      <div className="max-w-md w-full">
        {/* Header - Logo & Title */}
        <div className="flex flex-col items-center justify-center mb-8">
          <Link to="/" className="hover:opacity-80 active:scale-95 transition-all duration-150">
            <img 
              src={TabChairLogo} 
              alt="CampusCut Logo" 
              className="h-16 w-auto mb-4"
            />
          </Link>
          <h1 className="text-3xl font-bold text-white mb-2">
            Create Account
          </h1>
          <p className="text-gray-300">Join CampusCut today</p>
        </div>

        {/* Form Card */}
        <div 
          className="bg-white rounded-2xl shadow-2xl p-8"
          style={{ maxWidth: '440px', margin: '0 auto' }}
        >
          <form onSubmit={handleSubmit} className="space-y-5">
            {/* Name Fields */}
            <div className="grid grid-cols-2 gap-4">
              {/* First Name */}
              <div className="relative">
                <label 
                  htmlFor="firstName" 
                  className="absolute -top-2.5 left-3 text-sm font-medium text-gray-700 bg-white px-1 z-10"
                >
                  First Name
                </label>
                <input
                  type="text"
                  id="firstName"
                  name="firstName"
                  value={formData.firstName}
                  onChange={handleInputChange}
                  className={`w-full pt-5 pb-3 px-4 border-2 rounded-lg focus:outline-none focus:ring-4 focus:ring-primary-400/20 transition-all duration-200 text-gray-900 placeholder-gray-400 ${
                    validationErrors.firstName ? 'border-red-400 focus:border-red-500' : 'border-primary-400 focus:border-primary-500'
                  }`}
                  placeholder="John"
                />
                {validationErrors.firstName && (
                  <p className="text-red-500 text-xs mt-1">{validationErrors.firstName}</p>
                )}
              </div>

              {/* Last Name */}
              <div className="relative">
                <label 
                  htmlFor="lastName" 
                  className="absolute -top-2.5 left-3 text-sm font-medium text-gray-700 bg-white px-1 z-10"
                >
                  Last Name
                </label>
                <input
                  type="text"
                  id="lastName"
                  name="lastName"
                  value={formData.lastName}
                  onChange={handleInputChange}
                  className={`w-full pt-5 pb-3 px-4 border-2 rounded-lg focus:outline-none focus:ring-4 focus:ring-primary-400/20 transition-all duration-200 text-gray-900 placeholder-gray-400 ${
                    validationErrors.lastName ? 'border-red-400 focus:border-red-500' : 'border-primary-400 focus:border-primary-500'
                  }`}
                  placeholder="Doe"
                />
                {validationErrors.lastName && (
                  <p className="text-red-500 text-xs mt-1">{validationErrors.lastName}</p>
                )}
              </div>
            </div>

            {/* Email Field */}
            <div className="relative">
              <label 
                htmlFor="email" 
                className="absolute -top-2.5 left-3 text-sm font-medium text-gray-700 bg-white px-1 z-10"
              >
                Email Address
              </label>
              <div className="relative">
                <input
                  type="email"
                  id="email"
                  name="email"
                  value={formData.email}
                  onChange={handleInputChange}
                  className={`w-full pt-5 pb-3 px-4 pr-12 border-2 rounded-lg focus:outline-none focus:ring-4 focus:ring-primary-400/20 transition-all duration-200 text-gray-900 placeholder-gray-400 ${
                    validationErrors.email ? 'border-red-400 focus:border-red-500' : 
                    (formData.email && isUniversityEmail(formData.email)) ? 'border-green-400 focus:border-green-500' :
                    'border-primary-400 focus:border-primary-500'
                  }`}
                  placeholder="you@example.com"
                  autoComplete="email"
                />
                {/* Email validation indicator */}
                {formData.email && (
                  <div className="absolute inset-y-0 right-4 flex items-center pointer-events-none">
                    {isValidEmail(formData.email) ? (
                      <CheckCircle className="w-5 h-5 text-green-500" />
                    ) : (
                      <XCircle className="w-5 h-5 text-red-500" />
                    )}
                  </div>
                )}
              </div>
              {validationErrors.email && (
                <p className="text-red-500 text-xs mt-1">{validationErrors.email}</p>
              )}
              <p className="text-gray-500 text-xs mt-1">We'll send a verification code to this email</p>
            </div>

            {/* Password Field */}
            <div className="relative">
              <label 
                htmlFor="password" 
                className="absolute -top-2.5 left-3 text-sm font-medium text-gray-700 bg-white px-1 z-10"
              >
                Password
              </label>
              <input
                type={showPassword ? "text" : "password"}
                id="password"
                name="password"
                value={formData.password}
                onChange={handleInputChange}
                className={`w-full pt-5 pb-3 px-4 pr-12 border-2 rounded-lg focus:outline-none focus:ring-4 focus:ring-primary-400/20 transition-all duration-200 text-gray-900 placeholder-gray-400 ${
                  validationErrors.password ? 'border-red-400 focus:border-red-500' : 'border-primary-400 focus:border-primary-500'
                }`}
                placeholder="••••••••"
                autoComplete="new-password"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-500 hover:text-gray-700 transition-colors p-1"
                tabIndex={-1}
              >
                {showPassword ? <EyeOff size={20} /> : <Eye size={20} />}
              </button>
              {validationErrors.password && (
                <p className="text-red-500 text-xs mt-1">{validationErrors.password}</p>
              )}
              
              {/* Password Strength Indicator */}
              {formData.password && (
                <div className="mt-2">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-gray-600">Password strength:</span>
                    <span className={getPasswordStrengthColor(passwordStrength)}>
                      {getPasswordStrengthText(passwordStrength)}
                    </span>
                  </div>
                  <div className="mt-1 flex space-x-1">
                    {[1, 2, 3, 4, 5].map((level) => (
                      <div
                        key={level}
                        className={`h-1.5 flex-1 rounded-full transition-colors duration-200 ${
                          getPasswordStrengthBarColor(passwordStrength, level)
                        }`}
                      />
                    ))}
                  </div>
                </div>
              )}
            </div>

            {/* Confirm Password Field */}
            <div className="relative">
              <label 
                htmlFor="confirmPassword" 
                className="absolute -top-2.5 left-3 text-sm font-medium text-gray-700 bg-white px-1 z-10"
              >
                Confirm Password
              </label>
              <input
                type={showConfirmPassword ? "text" : "password"}
                id="confirmPassword"
                name="confirmPassword"
                value={formData.confirmPassword}
                onChange={handleInputChange}
                className={`w-full pt-5 pb-3 px-4 pr-12 border-2 rounded-lg focus:outline-none focus:ring-4 focus:ring-primary-400/20 transition-all duration-200 text-gray-900 placeholder-gray-400 ${
                  validationErrors.confirmPassword || (formData.confirmPassword && formData.password !== formData.confirmPassword)
                    ? 'border-red-400 focus:border-red-500' 
                    : 'border-primary-400 focus:border-primary-500'
                }`}
                placeholder="••••••••"
                autoComplete="new-password"
              />
              <button
                type="button"
                onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-500 hover:text-gray-700 transition-colors p-1"
                tabIndex={-1}
              >
                {showConfirmPassword ? <EyeOff size={20} /> : <Eye size={20} />}
              </button>
              
              {/* Password Match Indicator */}
              {formData.confirmPassword && (
                <div className="flex items-center gap-1 mt-1">
                  {formData.password === formData.confirmPassword ? (
                    <>
                      <CheckCircle size={14} className="text-green-500" />
                      <span className="text-green-600 text-xs">Passwords match</span>
                    </>
                  ) : (
                    <>
                      <XCircle size={14} className="text-red-500" />
                      <span className="text-red-600 text-xs">Passwords do not match</span>
                    </>
                  )}
                </div>
              )}
            </div>

            {/* Terms of Service Agreement */}
            <div className="border-2 border-gray-200 rounded-lg p-4 bg-gray-50">
              <div className="flex items-start gap-3">
                <div className="flex-shrink-0 mt-0.5">
                  {termsAccepted ? (
                    <div className="w-5 h-5 bg-primary-500 rounded flex items-center justify-center">
                      <CheckCircle size={14} className="text-white" />
                    </div>
                  ) : (
                    <div className="w-5 h-5 border-2 border-gray-300 rounded bg-white"></div>
                  )}
                </div>
                <div className="flex-1">
                  <p className="text-sm text-gray-700">
                    I have read and agree to the{' '}
                    <button
                      type="button"
                      onClick={() => setShowTermsModal(true)}
                      className="text-primary-500 hover:text-primary-600 font-medium underline"
                    >
                      Terms of Service
                    </button>
                  </p>
                  {!termsAccepted && (
                    <p className="text-xs text-gray-500 mt-1">
                      You must read and accept the Terms of Service to continue
                    </p>
                  )}
                  {termsAccepted && (
                    <p className="text-xs text-primary-600 mt-1 flex items-center gap-1">
                      <CheckCircle size={12} />
                      Terms accepted
                    </p>
                  )}
                </div>
              </div>
            </div>

            {/* Error Message */}
            {error && (
              <div className="bg-red-50 border-2 border-red-200 rounded-lg p-4">
                <div className="flex items-start space-x-3">
                  <AlertCircle size={20} className="text-red-600 mt-0.5 flex-shrink-0" />
                  <div>
                    <p className="text-red-800 font-medium text-sm">Sign Up Failed</p>
                    <p className="text-red-700 text-sm mt-1">{error}</p>
                  </div>
                </div>
              </div>
            )}

            {/* Submit Button */}
            <button
              type="submit"
              disabled={!isFormValid || isLoading}
              className={`w-full py-4 px-6 rounded-lg font-semibold text-lg transition-all duration-200 ${
                isFormValid && !isLoading
                  ? 'bg-primary-400 hover:bg-primary-500 text-white shadow-lg hover:shadow-xl transform hover:-translate-y-0.5'
                  : 'bg-gray-300 text-gray-500 cursor-not-allowed'
              }`}
            >
              {isLoading ? (
                <div className="flex items-center justify-center space-x-2">
                  <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
                  <span>Creating account...</span>
                </div>
              ) : (
                'Create Account'
              )}
            </button>
          </form>

          {/* Divider */}
          <div className="my-6 flex items-center">
            <div className="flex-1 border-t border-gray-200"></div>
            <span className="px-4 text-gray-500 text-sm">or</span>
            <div className="flex-1 border-t border-gray-200"></div>
          </div>

          {/* Footer Links */}
          <div className="text-center space-y-4">
            <p className="text-gray-600">
              Already have an account?{' '}
              <Link 
                to={ROUTES.LOGIN} 
                className="text-primary-500 hover:text-primary-600 font-semibold transition-colors"
              >
                Sign in
              </Link>
            </p>

            {/* Support Link */}
            <p className="text-gray-500 text-sm">
              Need help?{' '}
              <a 
                href="mailto:campuscuthelp@gmail.com"
                className="text-primary-500 hover:text-primary-600 transition-colors inline-flex items-center gap-1"
              >
                <Mail size={14} />
                Contact Support
              </a>
            </p>

            {/* Terms */}
            <p className="text-gray-400 text-xs">
              By creating an account, you agree to our{' '}
              <Link to="/terms" className="text-emerald-600 hover:text-emerald-700 hover:underline">Terms of Service</Link>
              {' '}and{' '}
              <Link to="/privacy" className="text-emerald-600 hover:text-emerald-700 hover:underline">Privacy Policy</Link>
            </p>
          </div>
        </div>

        {/* Back to Landing */}
        <div className="text-center mt-6">
          <Link 
            to="/"
            className="text-gray-400 hover:text-white text-sm transition-colors"
          >
            ← Back to CampusCut
          </Link>
        </div>
      </div>

      {/* Terms of Service Modal */}
      {showTermsModal && (
        <div 
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60"
          onClick={() => setShowTermsModal(false)}
        >
          <div 
            className="bg-white rounded-2xl shadow-2xl max-w-2xl w-full max-h-[90vh] flex flex-col"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div className="relative px-6 py-4 border-b border-gray-200 flex-shrink-0">
              <h2 className="text-xl font-bold text-gray-900 text-center">Terms of Service</h2>
              <button
                onClick={() => setShowTermsModal(false)}
                className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 p-1 rounded-full hover:bg-gray-100 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>

            {/* Scroll instruction */}
            {!hasScrolledToBottom && (
              <div className="bg-primary-50 border-b border-primary-200 px-6 py-3 flex-shrink-0">
                <p className="text-primary-800 text-sm text-center">
                  Please scroll to the bottom to read the entire Terms of Service
                </p>
              </div>
            )}

            {/* Terms Content - Scrollable */}
            <div 
              ref={termsScrollRef}
              onScroll={handleTermsScroll}
              className="flex-1 overflow-y-auto overscroll-contain px-6 py-4 min-h-0"
            >
              <TermsOfServiceContent />
            </div>

            {/* Modal Footer */}
            <div className="border-t border-gray-200 px-6 py-4 flex-shrink-0 bg-gray-50 rounded-b-2xl">
              <div className="flex flex-col sm:flex-row gap-3">
                <button
                  onClick={() => setShowTermsModal(false)}
                  className="flex-1 py-3 px-4 rounded-lg font-medium text-gray-700 bg-white border border-gray-300 hover:bg-gray-50 transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleAcceptTerms}
                  disabled={!hasScrolledToBottom}
                  className={`flex-1 py-3 px-4 rounded-lg font-medium transition-all ${
                    hasScrolledToBottom
                      ? 'bg-primary-500 text-white hover:bg-primary-600'
                      : 'bg-gray-300 text-gray-500 cursor-not-allowed'
                  }`}
                >
                  {hasScrolledToBottom ? (
                    'I Accept the Terms'
                  ) : (
                    'Scroll to Accept'
                  )}
                </button>
              </div>
              {!hasScrolledToBottom && (
                <p className="text-xs text-gray-500 text-center mt-2">
                  You must scroll through the entire document to accept
                </p>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
