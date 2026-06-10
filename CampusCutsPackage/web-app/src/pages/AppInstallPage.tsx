/**
 * App Installation Instructions Page (Mobile-Optimized)
 * 
 * Touch-friendly guide for installing CampusCut as a PWA
 * Features:
 * - Platform-specific instructions (iOS/Android/Desktop)
 * - Large touch targets
 * - Single-column mobile layout
 * - Visual step-by-step guide
 */

import { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { 
  Smartphone, 
  Monitor, 
  Download, 
  Share2, 
  Plus, 
  ArrowLeft,
  Check,
  Zap,
  Bell,
  WifiOff
} from 'lucide-react';
import { 
  isAppInstalled, 
  getPlatform
} from '../utils/appUtils';

// PWA Install types
interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

export default function AppInstallPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [isInstalled, setIsInstalled] = useState(false);
  const [platform, setPlatform] = useState<'ios' | 'android' | 'desktop' | 'unknown'>('unknown');
  
  // Check if we're on /app/* route (mobile) or /web/* route (desktop)
  const isMobileRoute = location.pathname.startsWith('/app');

  useEffect(() => {
    setIsInstalled(isAppInstalled());
    setPlatform(getPlatform());

    // Listen for install prompt
    const handler = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e as BeforeInstallPromptEvent);
    };

    window.addEventListener('beforeinstallprompt', handler);

    // Listen for successful install
    const installHandler = () => {
      setIsInstalled(true);
      setDeferredPrompt(null);
    };

    window.addEventListener('appinstalled', installHandler);

    return () => {
      window.removeEventListener('beforeinstallprompt', handler);
      window.removeEventListener('appinstalled', installHandler);
    };
  }, []);

  const handleInstallClick = async () => {
    if (!deferredPrompt) return;

    deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;

    if (outcome === 'accepted') {
      setIsInstalled(true);
    }

    setDeferredPrompt(null);
  };

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      {/* Header */}
      <header className="bg-white border-b border-gray-200 px-4 py-4 safe-area-inset-top">
        <div className="flex items-center gap-3">
          <button
            onClick={() => navigate('/')}
            className="p-2 hover:bg-gray-100 rounded-full transition-colors active:scale-95"
          >
            <ArrowLeft className="w-6 h-6 text-gray-600" />
          </button>
          <div>
            <h1 className="text-lg font-bold text-gray-900">Install CampusCut</h1>
            <p className="text-xs text-gray-500">Get the app experience</p>
          </div>
        </div>
      </header>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-4 py-6">
        {/* Logo */}
        <div className="text-center mb-8">
          <img 
            src="/src/assets/logos/Logo1.png" 
            alt="CampusCut" 
            className="h-16 w-auto mx-auto mb-4" 
          />
          <h2 className="text-2xl font-bold text-gray-900 mb-2">
            {isInstalled ? 'App Installed!' : 'Install CampusCut'}
          </h2>
          <p className="text-gray-600">
            {isInstalled 
              ? 'You can now use CampusCut offline!' 
              : 'Get instant access from your home screen'}
          </p>
        </div>

        {/* Installation Status or Instructions */}
        {isInstalled ? (
          <div className="bg-green-50 border-2 border-green-300 rounded-2xl p-6 mb-6">
            <div className="flex items-center gap-4 mb-4">
              <div className="bg-green-500 rounded-full p-3">
                <Check className="w-8 h-8 text-white" />
              </div>
              <div>
                <h3 className="text-xl font-bold text-green-900">All Set!</h3>
                <p className="text-green-700 text-sm">Ready to use offline</p>
              </div>
            </div>
            <p className="text-green-800 text-sm">
              CampusCut is installed on your device. You can now access it from your home screen and use it offline.
            </p>
          </div>
        ) : (
          <>
            {/* Quick Install Button (if available) */}
            {deferredPrompt && (platform === 'android' || platform === 'desktop') && (
              <button
                onClick={handleInstallClick}
                className="w-full bg-primary-400 text-white rounded-2xl p-6 mb-6 active:scale-98 transition-transform shadow-lg"
              >
                <div className="flex items-center justify-center gap-3 mb-2">
                  <Download className="w-8 h-8" />
                  <span className="text-2xl font-bold">Install Now</span>
                </div>
                <p className="text-sm opacity-90">One-tap instant install</p>
              </button>
            )}

            {/* iOS Instructions */}
            {platform === 'ios' && (
              <div className="bg-white rounded-2xl p-6 mb-6 border border-gray-200">
                <div className="flex items-center gap-3 mb-6">
                  <div className="bg-blue-100 rounded-full p-3">
                    <Smartphone className="w-6 h-6 text-blue-600" />
                  </div>
                  <h3 className="text-lg font-bold text-gray-900">iOS Installation</h3>
                </div>

                <div className="space-y-5">
                  <div className="flex gap-4">
                    <div className="bg-primary-400 text-white rounded-full w-10 h-10 flex items-center justify-center flex-shrink-0 font-bold text-lg">1</div>
                    <div className="flex-1">
                      <p className="text-gray-700 text-base leading-relaxed">
                        Tap the <strong>Share</strong> button <Share2 className="w-5 h-5 inline text-blue-600" /> at the bottom
                      </p>
                    </div>
                  </div>

                  <div className="flex gap-4">
                    <div className="bg-primary-400 text-white rounded-full w-10 h-10 flex items-center justify-center flex-shrink-0 font-bold text-lg">2</div>
                    <div className="flex-1">
                      <p className="text-gray-700 text-base leading-relaxed">
                        Scroll and tap <strong>"Add to Home Screen"</strong> <Plus className="w-5 h-5 inline text-blue-600" />
                      </p>
                    </div>
                  </div>

                  <div className="flex gap-4">
                    <div className="bg-primary-400 text-white rounded-full w-10 h-10 flex items-center justify-center flex-shrink-0 font-bold text-lg">3</div>
                    <div className="flex-1">
                      <p className="text-gray-700 text-base leading-relaxed">
                        Tap <strong>"Add"</strong> to complete installation
                      </p>
                    </div>
                  </div>
                </div>

                <div className="mt-6 p-4 bg-blue-50 rounded-xl">
                  <p className="text-sm text-blue-800">
                    <strong>Note:</strong> Safari browser required for iOS installation
                  </p>
                </div>
              </div>
            )}

            {/* Android Instructions */}
            {platform === 'android' && !deferredPrompt && (
              <div className="bg-white rounded-2xl p-6 mb-6 border border-gray-200">
                <div className="flex items-center gap-3 mb-6">
                  <div className="bg-green-100 rounded-full p-3">
                    <Smartphone className="w-6 h-6 text-green-600" />
                  </div>
                  <h3 className="text-lg font-bold text-gray-900">Android Installation</h3>
                </div>

                <div className="space-y-5">
                  <div className="flex gap-4">
                    <div className="bg-primary-400 text-white rounded-full w-10 h-10 flex items-center justify-center flex-shrink-0 font-bold text-lg">1</div>
                    <div className="flex-1">
                      <p className="text-gray-700 text-base leading-relaxed">
                        Tap the <strong>menu</strong> (⋮) in the top-right
                      </p>
                    </div>
                  </div>

                  <div className="flex gap-4">
                    <div className="bg-primary-400 text-white rounded-full w-10 h-10 flex items-center justify-center flex-shrink-0 font-bold text-lg">2</div>
                    <div className="flex-1">
                      <p className="text-gray-700 text-base leading-relaxed">
                        Tap <strong>"Install app"</strong> or <strong>"Add to Home screen"</strong>
                      </p>
                    </div>
                  </div>

                  <div className="flex gap-4">
                    <div className="bg-primary-400 text-white rounded-full w-10 h-10 flex items-center justify-center flex-shrink-0 font-bold text-lg">3</div>
                    <div className="flex-1">
                      <p className="text-gray-700 text-base leading-relaxed">
                        Tap <strong>"Install"</strong> to complete
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* Desktop Instructions */}
            {platform === 'desktop' && !deferredPrompt && (
              <div className="bg-white rounded-2xl p-6 mb-6 border border-gray-200">
                <div className="flex items-center gap-3 mb-6">
                  <div className="bg-primary-100 rounded-full p-3">
                    <Monitor className="w-6 h-6 text-primary-600" />
                  </div>
                  <h3 className="text-lg font-bold text-gray-900">Desktop Installation</h3>
                </div>

                <div className="space-y-5">
                  <div className="flex gap-4">
                    <div className="bg-primary-400 text-white rounded-full w-10 h-10 flex items-center justify-center flex-shrink-0 font-bold text-lg">1</div>
                    <div className="flex-1">
                      <p className="text-gray-700 text-base leading-relaxed">
                        Look for the <strong>install icon</strong> <Download className="w-5 h-5 inline text-primary-600" /> in address bar
                      </p>
                    </div>
                  </div>

                  <div className="flex gap-4">
                    <div className="bg-primary-400 text-white rounded-full w-10 h-10 flex items-center justify-center flex-shrink-0 font-bold text-lg">2</div>
                    <div className="flex-1">
                      <p className="text-gray-700 text-base leading-relaxed">
                        Click the icon and then <strong>"Install"</strong>
                      </p>
                    </div>
                  </div>

                  <div className="flex gap-4">
                    <div className="bg-primary-400 text-white rounded-full w-10 h-10 flex items-center justify-center flex-shrink-0 font-bold text-lg">3</div>
                    <div className="flex-1">
                      <p className="text-gray-700 text-base leading-relaxed">
                        CampusCut opens in its own window!
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </>
        )}

        {/* Benefits */}
        <div className="space-y-3 mb-6">
          <h3 className="text-lg font-bold text-gray-900 mb-4">App Benefits</h3>
          
          <div className="bg-white rounded-xl p-4 border border-gray-200">
            <div className="flex items-center gap-3">
              <div className="bg-primary-100 rounded-full p-2">
                <WifiOff className="w-5 h-5 text-primary-600" />
              </div>
              <div>
                <h4 className="font-semibold text-gray-900">Works Offline</h4>
                <p className="text-sm text-gray-600">Access bookings without internet</p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-xl p-4 border border-gray-200">
            <div className="flex items-center gap-3">
              <div className="bg-blue-100 rounded-full p-2">
                <Bell className="w-5 h-5 text-blue-600" />
              </div>
              <div>
                <h4 className="font-semibold text-gray-900">Push Notifications</h4>
                <p className="text-sm text-gray-600">Instant booking alerts</p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-xl p-4 border border-gray-200">
            <div className="flex items-center gap-3">
              <div className="bg-green-100 rounded-full p-2">
                <Zap className="w-5 h-5 text-green-600" />
              </div>
              <div>
                <h4 className="font-semibold text-gray-900">Lightning Fast</h4>
                <p className="text-sm text-gray-600">Native app performance</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Bottom CTA */}
      <div className="border-t border-gray-200 p-4 bg-white safe-area-inset-bottom">
        <button
          onClick={() => navigate(isInstalled ? '/app' : '/')}
          className="w-full bg-primary-400 hover:bg-primary-500 text-white font-semibold py-4 rounded-xl transition-colors active:scale-98 shadow-lg"
        >
          {isInstalled ? 'Open CampusCut' : 'Continue to Website'}
        </button>
        {!isInstalled && (
          <p className="text-center text-xs text-gray-500 mt-3">
            You can install the app later from your browser menu
          </p>
        )}
      </div>
    </div>
  );
}

