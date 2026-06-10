import { useState, useEffect, useRef } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { Mail, AlertCircle, CheckCircle, RefreshCw, ArrowLeft } from 'lucide-react';
import { useAuthStore } from '../../store/useAuthStore';
import TabChairLogo from '../../assets/logos/Tab_Chair.webp';
import { useViewport } from '../../hooks/useViewport';

export default function VerifyEmailPage() {
  const navigate = useNavigate();
  const { verifyEmail, resendVerificationCode, isLoading, error, clearError, isAuthenticated, pendingVerificationEmail } = useAuthStore();
  const { isMobile } = useViewport();
  
  const [code, setCode] = useState(['', '', '', '', '', '']);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isResending, setIsResending] = useState(false);
  const [resendCooldown, setResendCooldown] = useState(0);
  const [email, setEmail] = useState<string | null>(null);
  const [hasCheckedRedirect, setHasCheckedRedirect] = useState(false);
  const [sessionExpired, setSessionExpired] = useState(false);
  const inputRefs = useRef<(HTMLInputElement | null)[]>([]);

  // Get email from store or localStorage on mount (not during render)
  useEffect(() => {
    const storedEmail = pendingVerificationEmail || localStorage.getItem('pendingVerificationEmail');
    setEmail(storedEmail);
  }, [pendingVerificationEmail]);

  // Handle post-login redirect after authentication
  useEffect(() => {
    if (!isAuthenticated || hasCheckedRedirect) return;
    
    setHasCheckedRedirect(true);
    
    // Check for post-login redirect
    const postLoginRedirect = localStorage.getItem('postLoginRedirect');
    if (postLoginRedirect) {
      try {
        const redirect = JSON.parse(postLoginRedirect);
        localStorage.removeItem('postLoginRedirect');
        
        if (redirect.type === 'schedule' && redirect.barber) {
          navigate(`/web/consumer/book/${redirect.barberId}`, {
            state: { barber: redirect.barber }
          });
          return;
        }
      } catch (e) {
        localStorage.removeItem('postLoginRedirect');
      }
    }
    
    // Default redirect to consumer page
    navigate('/web/consumer');
  }, [isAuthenticated, hasCheckedRedirect, navigate]);

  // Redirect if no pending email (after email state is initialized)
  useEffect(() => {
    if (email === null) return; // Still loading
    if (!email && !isAuthenticated) {
      navigate('/web');
    }
  }, [email, isAuthenticated, navigate]);

  // Scroll to top on mount
  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);

  // Resend cooldown timer
  useEffect(() => {
    if (resendCooldown > 0) {
      const timer = setTimeout(() => setResendCooldown(resendCooldown - 1), 1000);
      return () => clearTimeout(timer);
    }
  }, [resendCooldown]);

  // Focus first input on mount
  useEffect(() => {
    inputRefs.current[0]?.focus();
  }, []);

  const handleInputChange = (index: number, value: string) => {
    // Only allow digits
    if (!/^\d*$/.test(value)) return;
    
    const newCode = [...code];
    newCode[index] = value.slice(-1); // Take only last character
    setCode(newCode);
    
    // Auto-focus next input
    if (value && index < 5) {
      inputRefs.current[index + 1]?.focus();
    }
    
    // Clear error when typing
    if (error) clearError();
  };

  const handleKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    // Handle backspace
    if (e.key === 'Backspace' && !code[index] && index > 0) {
      inputRefs.current[index - 1]?.focus();
    }
    
    // Handle paste
    if (e.key === 'v' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      navigator.clipboard.readText().then((text) => {
        const digits = text.replace(/\D/g, '').slice(0, 6).split('');
        const newCode = [...code];
        digits.forEach((digit, i) => {
          if (i < 6) newCode[i] = digit;
        });
        setCode(newCode);
        
        // Focus last filled input or last input
        const lastFilledIndex = Math.min(digits.length, 5);
        inputRefs.current[lastFilledIndex]?.focus();
      });
    }
  };

  const handlePaste = (e: React.ClipboardEvent) => {
    e.preventDefault();
    const text = e.clipboardData.getData('text');
    const digits = text.replace(/\D/g, '').slice(0, 6).split('');
    const newCode = [...code];
    digits.forEach((digit, i) => {
      if (i < 6) newCode[i] = digit;
    });
    setCode(newCode);
    
    // Focus last filled input or last input
    const lastFilledIndex = Math.min(digits.length, 5);
    inputRefs.current[lastFilledIndex]?.focus();
  };

  const verificationCode = code.join('');
  const isCodeComplete = verificationCode.length === 6;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!isCodeComplete || !email) return;
    
    setIsSubmitting(true);
    clearError();

    try {
      await verifyEmail(email, verificationCode);
      toast.success('Email verified successfully! Welcome to CampusCut!');
      // Redirect is handled by the useEffect that watches isAuthenticated
    } catch (err: any) {
      const statusCode = err.response?.status;
      if (statusCode === 429 || err.isRateLimitError) {
        toast.error('Rate limit reached. Please wait a moment and reload the page.');
      } else {
        toast.error(err.message || 'Verification failed. Please try again.');
      }
      // Clear the code inputs on error so user can try again
      setCode(['', '', '', '', '', '']);
      inputRefs.current[0]?.focus();
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleResend = async () => {
    if (!email || isResending || resendCooldown > 0) return;
    
    setIsResending(true);
    clearError();

    try {
      await resendVerificationCode(email);
      toast.success('Verification code resent! Check your email.');
      setResendCooldown(60); // 60 second cooldown
      // Clear the code inputs
      setCode(['', '', '', '', '', '']);
      inputRefs.current[0]?.focus();
    } catch (err: any) {
      const statusCode = err.response?.status;
      const errorMessage = err.response?.data?.error?.message || 
                           err.response?.data?.message || 
                           err.message || '';
      
      if (statusCode === 429 || err.isRateLimitError) {
        toast.error('Rate limit reached. Please wait a moment and reload the page.');
      } else if (errorMessage.toLowerCase().includes('no pending registration') || 
                 errorMessage.toLowerCase().includes('register first')) {
        // Session expired - show inline message with signup button
        setSessionExpired(true);
        localStorage.removeItem('pendingVerificationEmail');
      } else {
        toast.error(errorMessage || 'Failed to resend code. Please try again.');
      }
    } finally {
      setIsResending(false);
    }
  };

  if (!email) {
    return null; // Will redirect in useEffect
  }

  return (
    <div 
      className="min-h-[100dvh] flex items-center justify-center py-6 sm:py-12 px-3 sm:px-4"
      style={{ backgroundColor: '#022b19' }}
    >
      <div className="max-w-md w-full">
        {/* Header - Logo */}
        <div className="flex flex-col items-center justify-center mb-4 sm:mb-8">
          <Link to="/" className="hover:opacity-80 active:scale-95 transition-all duration-150">
            <img 
              src={TabChairLogo} 
              alt="CampusCut Logo" 
              className="h-12 sm:h-16 w-auto mb-2 sm:mb-4"
            />
          </Link>
          
          <h1 className="text-2xl sm:text-3xl font-bold text-white mb-1 sm:mb-2">
            Check Your Email
          </h1>
          <p className="text-sm sm:text-base text-gray-300 text-center">
            We sent a 6-digit code to
          </p>
          <p className="text-sm sm:text-base text-primary-400 font-semibold mt-1 break-all text-center px-4">
            {email}
          </p>
        </div>

        {/* Verification Card */}
        <div 
          className="bg-white rounded-xl sm:rounded-2xl shadow-2xl p-4 sm:p-8"
          style={{ maxWidth: '400px', margin: '0 auto' }}
        >
          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Code Input */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-3 text-center">
                Enter Verification Code
              </label>
              
              <div className="flex justify-center gap-2">
                {code.map((digit, index) => (
                  <input
                    key={index}
                    ref={(el) => { inputRefs.current[index] = el; }}
                    type="text"
                    inputMode="numeric"
                    maxLength={1}
                    value={digit}
                    onChange={(e) => handleInputChange(index, e.target.value)}
                    onKeyDown={(e) => handleKeyDown(index, e)}
                    onPaste={handlePaste}
                    className={`w-12 h-14 text-center text-2xl font-bold border-2 rounded-lg focus:outline-none focus:ring-4 focus:ring-primary-400/20 transition-all duration-200 ${
                      digit 
                        ? 'border-primary-400 bg-primary-50 text-primary-700' 
                        : 'border-gray-300 text-gray-900'
                    }`}
                  />
                ))}
              </div>
              
              <p className="text-gray-500 text-xs text-center mt-3">
                This code expires in 10 minutes
              </p>
            </div>

            {/* Session Expired Message */}
            {sessionExpired && (
              <div className="bg-amber-50 border-2 border-amber-200 rounded-lg p-4">
                <div className="text-center">
                  <AlertCircle size={32} className="text-amber-600 mx-auto mb-2" />
                  <p className="text-amber-800 font-medium">Session Expired</p>
                  <p className="text-amber-700 text-sm mt-1 mb-4">
                    Your registration session has expired. Please sign up again.
                  </p>
                  <button
                    type="button"
                    onClick={() => navigate('/web/signup')}
                    className="w-full bg-primary-500 text-white font-semibold py-2 px-4 rounded-lg hover:bg-primary-600 transition-colors"
                  >
                    Sign Up Again
                  </button>
                </div>
              </div>
            )}

            {/* Error Message */}
            {error && !sessionExpired && (
              <div className="bg-red-50 border-2 border-red-200 rounded-lg p-4">
                <div className="flex items-start space-x-3">
                  <AlertCircle size={20} className="text-red-600 mt-0.5 flex-shrink-0" />
                  <div>
                    <p className="text-red-800 font-medium text-sm">Verification Failed</p>
                    <p className="text-red-700 text-sm mt-1">{error}</p>
                  </div>
                </div>
              </div>
            )}

            {/* Submit Button */}
            <button
              type="submit"
              disabled={!isCodeComplete || isSubmitting || isLoading}
              className={`w-full py-4 px-6 rounded-lg font-semibold text-lg transition-all duration-200 flex items-center justify-center gap-2 ${
                isCodeComplete && !isSubmitting
                  ? 'bg-primary-400 hover:bg-primary-500 text-white shadow-lg hover:shadow-xl transform hover:-translate-y-0.5'
                  : 'bg-gray-300 text-gray-500 cursor-not-allowed'
              }`}
            >
              {isSubmitting ? (
                <>
                  <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
                  <span>Verifying...</span>
                </>
              ) : (
                'Verify Email'
              )}
            </button>
          </form>

          {/* Divider */}
          <div className="my-6 flex items-center">
            <div className="flex-1 border-t border-gray-200"></div>
            <span className="px-4 text-gray-500 text-sm">didn't receive it?</span>
            <div className="flex-1 border-t border-gray-200"></div>
          </div>

          {/* Resend Code */}
          <div className="text-center">
            <button
              onClick={handleResend}
              disabled={isResending || resendCooldown > 0}
              className={`inline-flex items-center gap-2 text-primary-500 hover:text-primary-600 font-medium transition-colors ${
                (isResending || resendCooldown > 0) ? 'opacity-50 cursor-not-allowed' : ''
              }`}
            >
              <RefreshCw size={16} className={isResending ? 'animate-spin' : ''} />
              {resendCooldown > 0 
                ? `Resend in ${resendCooldown}s` 
                : isResending 
                  ? 'Sending...' 
                  : 'Resend Code'}
            </button>
          </div>

          {/* Spam Notice */}
          <div className="mt-6 p-4 bg-primary-50 border border-primary-200 rounded-lg">
            <p className="text-sm text-primary-800 text-center">
              <strong>Check your spam/junk folder</strong> if you don't see the email.
              Sometimes verification emails end up there.
            </p>
          </div>

          {/* Support Link */}
          <div className="mt-4 text-center">
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
          </div>
        </div>

        {/* Back to Sign Up */}
        <div className="text-center mt-6">
          <Link 
            to="/web"
            className="text-gray-400 hover:text-white text-sm transition-colors inline-flex items-center gap-2"
          >
            <ArrowLeft size={16} />
            Back to Sign Up
          </Link>
        </div>
      </div>
    </div>
  );
}

