/**
 * LocationPermissionPrompt Component
 * 
 * Prompts the user to share their location to find nearby barbers.
 */

import { useState, useEffect } from 'react';
import { MapPin, X, Loader2 } from 'lucide-react';

interface LocationPermissionPromptProps {
  isOpen: boolean;
  onClose: () => void;
  onAllow: () => void;
  onDeny?: () => void;
  loading?: boolean;
}

export default function LocationPermissionPrompt({
  isOpen,
  onClose,
  onAllow,
  onDeny,
  loading = false,
}: LocationPermissionPromptProps) {
  const [isVisible, setIsVisible] = useState(false);
  const [shouldRender, setShouldRender] = useState(false);

  useEffect(() => {
    if (isOpen) {
      setShouldRender(true);
      document.body.style.overflow = 'hidden';
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          setIsVisible(true);
        });
      });
    } else {
      setIsVisible(false);
      document.body.style.overflow = '';
      const timer = setTimeout(() => {
        setShouldRender(false);
      }, 150);
      return () => clearTimeout(timer);
    }

    return () => {
      document.body.style.overflow = '';
    };
  }, [isOpen]);

  const handleClose = () => {
    setIsVisible(false);
    setTimeout(onClose, 150);
  };

  if (!shouldRender) return null;

  return (
    <div
      className={`fixed inset-0 min-h-[100dvh] bg-black/50 flex items-center justify-center z-50 p-4 transition-all duration-150 ease-out ${
        isVisible ? 'opacity-100' : 'opacity-0'
      }`}
      onClick={handleClose}
    >
      <div
        className={`bg-white rounded-2xl shadow-2xl max-w-md w-full max-h-[85dvh] sm:max-h-[90vh] overflow-hidden transition-all duration-150 ease-out ${
          isVisible ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 translate-y-4'
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="bg-gradient-to-r from-primary-500 to-primary-600 px-6 py-5 relative">
          <div className="flex items-center justify-center gap-3">
            <div className="p-2 bg-white/20 rounded-lg">
              <MapPin className="w-6 h-6 text-white" />
            </div>
            <h2 className="text-xl font-bold text-white">Enable Location</h2>
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
          <p className="text-gray-700 text-center mb-4">
            CampusCuts needs your location to show you the <strong>closest barbers</strong> on your campus.
          </p>
          
          <div className="bg-gray-50 rounded-lg p-4 mb-6">
            <h3 className="font-semibold text-gray-900 mb-2">Why we need your location:</h3>
            <ul className="text-sm text-gray-600 space-y-2">
              <li className="flex items-start gap-2">
                <MapPin className="w-4 h-4 text-primary-500 mt-0.5 flex-shrink-0" />
                <span>Find barbers nearest to you</span>
              </li>
              <li className="flex items-start gap-2">
                <MapPin className="w-4 h-4 text-primary-500 mt-0.5 flex-shrink-0" />
                <span>Sort results by distance</span>
              </li>
              <li className="flex items-start gap-2">
                <MapPin className="w-4 h-4 text-primary-500 mt-0.5 flex-shrink-0" />
                <span>Show estimated travel time</span>
              </li>
            </ul>
          </div>

          <p className="text-xs text-gray-500 text-center mb-6">
            Your location is only used while using CampusCuts and is never shared with third parties.
          </p>

          {/* Buttons */}
          <div className="flex flex-col gap-3">
            <button
              onClick={onAllow}
              disabled={loading}
              className="w-full px-6 py-3 bg-primary-600 text-white rounded-lg font-semibold hover:bg-primary-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
            >
              {loading ? (
                <>
                  <Loader2 className="w-5 h-5 animate-spin" />
                  Getting Location...
                </>
              ) : (
                <>
                  <MapPin className="w-5 h-5" />
                  Allow Location Access
                </>
              )}
            </button>
            <button
              onClick={() => {
                if (onDeny) {
                  onDeny();
                } else {
                  handleClose();
                }
              }}
              disabled={loading}
              className="w-full px-6 py-3 text-gray-600 font-medium hover:text-gray-800 hover:bg-gray-100 rounded-lg transition-colors"
            >
              Not Now
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

