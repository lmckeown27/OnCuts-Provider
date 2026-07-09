/**
 * LoginPrompt Component
 * 
 * Prompts unauthenticated users to sign in or create an account
 * when they try to access protected features.
 * 
 * Supports redirect after login with barber context for scheduling flow.
 */

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { User, X, LogIn } from 'lucide-react';
import type { Barber } from '../types';

interface LoginPromptProps {
  isOpen: boolean;
  onClose: () => void;
  action?: 'schedule' | 'become_barber' | 'general';
  /** Barber to redirect to after login (for schedule flow) */
  redirectBarber?: Barber | null;
}

export default function LoginPrompt({
  isOpen,
  onClose,
  action = 'general',
  redirectBarber,
}: LoginPromptProps) {
  const navigate = useNavigate();
  const [isVisible, setIsVisible] = useState(false);
  const [shouldRender, setShouldRender] = useState(false);

  useEffect(() => {
    if (isOpen) {
      setShouldRender(true);
      // Lock body scroll with position fixed to prevent mobile viewport issues
      const scrollY = window.scrollY;
      document.body.style.overflow = 'hidden';
      document.body.style.position = 'fixed';
      document.body.style.width = '100%';
      document.body.style.top = `-${scrollY}px`;
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          setIsVisible(true);
        });
      });
    } else {
      setIsVisible(false);
      // Restore body scroll
      const scrollY = document.body.style.top;
      document.body.style.overflow = '';
      document.body.style.position = '';
      document.body.style.width = '';
      document.body.style.top = '';
      if (scrollY) {
        window.scrollTo(0, parseInt(scrollY || '0') * -1);
      }
      const timer = setTimeout(() => {
        setShouldRender(false);
      }, 150);
      return () => clearTimeout(timer);
    }

    return () => {
      document.body.style.overflow = '';
      document.body.style.position = '';
      document.body.style.width = '';
      document.body.style.top = '';
    };
  }, [isOpen]);

  const handleClose = () => {
    setIsVisible(false);
    setTimeout(onClose, 150);
  };

  const handleSignIn = () => {
    // If there's a barber to redirect to after login, store in localStorage
    if (redirectBarber && action === 'schedule') {
      localStorage.setItem('postLoginRedirect', JSON.stringify({
        type: 'schedule',
        barberId: redirectBarber.id,
        barber: redirectBarber,
      }));
    }
    handleClose();
    navigate('/web');
  };

  const getActionText = () => {
    switch (action) {
      case 'schedule':
        return 'schedule a service with this barber';
      case 'become_barber':
        return 'apply to become a barber';
      default:
        return 'access this feature';
    }
  };

  if (!shouldRender) return null;

  return (
    <div
      className={`fixed inset-0 min-h-[100dvh] bg-black/50 flex items-center justify-center z-50 p-6 transition-all duration-150 ease-out ${
        isVisible ? 'opacity-100' : 'opacity-0'
      }`}
      onClick={handleClose}
    >
      <div
        className={`bg-white rounded-2xl shadow-2xl max-w-md w-full max-h-[85dvh] sm:max-h-[80vh] overflow-y-auto transition-all duration-150 ease-out ${
          isVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 translate-y-4'
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="bg-gradient-to-r from-primary-500 to-primary-600 px-6 py-5 relative">
          <div className="flex items-center justify-center gap-3">
            <div className="p-2 bg-white/20 rounded-lg">
              <User className="w-6 h-6 text-white" />
            </div>
            <h2 className="text-xl font-bold text-white">Sign In Required</h2>
          </div>
          <button
            onClick={handleClose}
            className="absolute top-4 right-4 p-2 hover:bg-white/20 rounded-lg transition-colors"
          >
            <X className="w-5 h-5 text-white" />
          </button>
        </div>

        {/* Content */}
        <div className="p-6">
          <p className="text-gray-700 text-center mb-6">
            You need to sign in or create an account to <strong>{getActionText()}</strong>.
          </p>

          {/* Buttons */}
          <div className="flex flex-col gap-3">
            <button
              onClick={handleSignIn}
              className="w-full px-6 py-3 bg-primary-600 text-white rounded-lg font-semibold hover:bg-primary-700 transition-colors flex items-center justify-center gap-2"
            >
              <LogIn className="w-5 h-5" />
              Sign In / Create Account
            </button>
            <button
              onClick={handleClose}
              className="w-full px-6 py-3 text-gray-600 font-medium hover:text-gray-800 hover:bg-gray-100 rounded-lg transition-colors"
            >
              Continue Browsing
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

