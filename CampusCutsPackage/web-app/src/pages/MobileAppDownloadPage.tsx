/**
 * Mobile App Download Page
 * 
 * Native-style app install experience for CampusCut dApp
 * Features:
 * - iOS/Android native-style prompts
 * - Bottom sheet design
 * - Smooth animations
 * - App preview screenshots
 * - One-tap install
 */

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Download,
  Smartphone,
  Check,
  X,
  Zap,
  Shield,
  ArrowRight,
  Share2,
  Plus
} from 'lucide-react';
import { getPlatform, isAppInstalled } from '../utils/appUtils';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

export default function MobileAppDownloadPage() {
  const navigate = useNavigate();
  const [platform, setPlatform] = useState<'ios' | 'android' | 'desktop' | 'unknown'>('unknown');
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [isInstalled, setIsInstalled] = useState(false);
  const [showIOSInstructions, setShowIOSInstructions] = useState(false);
  const [showAndroidInstructions, setShowAndroidInstructions] = useState(false);

  useEffect(() => {
    setPlatform(getPlatform());
    setIsInstalled(isAppInstalled());

    const handler = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e as BeforeInstallPromptEvent);
    };

    const installHandler = () => {
      setIsInstalled(true);
      setDeferredPrompt(null);
    };

    window.addEventListener('beforeinstallprompt', handler);
    window.addEventListener('appinstalled', installHandler);

    return () => {
      window.removeEventListener('beforeinstallprompt', handler);
      window.removeEventListener('appinstalled', installHandler);
    };
  }, []);

  const handleIOSInstall = () => {
    setShowIOSInstructions(true);
  };

  const handleAndroidInstall = async () => {
    // Try native Android prompt first
    if (deferredPrompt && platform === 'android') {
      try {
        await deferredPrompt.prompt();
        const { outcome } = await deferredPrompt.userChoice;

        if (outcome === 'accepted') {
          setIsInstalled(true);
        }
        setDeferredPrompt(null);
      } catch (error) {
        console.error('Install error:', error);
        setShowAndroidInstructions(true);
      }
    } else {
      setShowAndroidInstructions(true);
    }
  };

  if (isInstalled) {
    return (
      <div className="fixed inset-0 bg-gradient-to-br from-green-50 via-white to-primary-50 flex items-center justify-center p-4">
        <div className="max-w-md w-full">
          <div className="bg-white rounded-3xl p-8 shadow-2xl text-center animate-slide-up">
            <div className="w-20 h-20 bg-green-500 rounded-full flex items-center justify-center mx-auto mb-6 animate-pulse">
              <Check className="w-10 h-10 text-white" />
            </div>
            
            <h1 className="text-3xl font-bold text-gray-900 mb-3">
              You're All Set!
            </h1>
            <p className="text-gray-600 mb-8">
              CampusCut is installed and ready to use. Access it from your home screen anytime!
            </p>

            <button
              onClick={() => navigate('/app')}
              className="w-full bg-primary-400 hover:bg-primary-500 text-white font-semibold py-4 rounded-xl transition-all active:scale-95 shadow-lg mb-3"
            >
              Open CampusCut
            </button>

            <button
              onClick={() => navigate('/')}
              className="w-full text-gray-600 font-medium py-3"
            >
              Back to Home
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 bg-gradient-to-br from-primary-50 via-white to-blue-50 flex flex-col">
      {/* Close Button */}
      <div className="absolute top-4 right-4 z-10" style={{ paddingTop: 'max(env(safe-area-inset-top), 16px)' }}>
        <button
          onClick={() => navigate('/')}
          className="w-10 h-10 bg-white/80 backdrop-blur-sm rounded-full flex items-center justify-center shadow-lg hover:bg-white transition-colors active:scale-95"
        >
          <X className="w-5 h-5 text-gray-600" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        <div className="max-w-md w-full mx-auto px-4" style={{ paddingTop: 'max(env(safe-area-inset-top, 0px) + 80px, 96px)', paddingBottom: 'max(env(safe-area-inset-bottom), 32px)' }}>
          {/* App Icon */}
          <div className="text-center mb-8 animate-fade-in">
            <div className="relative inline-block">
              <img
                src="/src/assets/logos/Logo1.png"
                alt="CampusCut"
                className="w-24 h-24 rounded-3xl shadow-2xl mx-auto mb-4"
              />
              <div className="absolute -bottom-2 -right-2 w-10 h-10 bg-primary-400 rounded-full flex items-center justify-center shadow-lg">
                <Download className="w-5 h-5 text-white" />
              </div>
            </div>
            
            <h1 className="text-3xl font-bold text-gray-900 mb-2 mt-6">
              Get CampusCut
            </h1>
            <p className="text-gray-600 text-lg">
              Install the app on your phone
            </p>
          </div>

          {/* Features */}
          <div className="space-y-3 mb-8">
            <div className="bg-white rounded-2xl p-4 shadow-lg border border-gray-100 flex items-center gap-4 animate-fade-in">
              <div className="w-12 h-12 bg-primary-100 rounded-xl flex items-center justify-center flex-shrink-0">
                <Zap className="w-6 h-6 text-primary-600" />
              </div>
              <div className="flex-1">
                <h3 className="font-bold text-gray-900">Lightning Fast</h3>
                <p className="text-sm text-gray-600">Instant loading, smooth animations</p>
              </div>
            </div>

            <div className="bg-white rounded-2xl p-4 shadow-lg border border-gray-100 flex items-center gap-4 animate-fade-in" style={{ animationDelay: '0.1s' }}>
              <div className="w-12 h-12 bg-blue-100 rounded-xl flex items-center justify-center flex-shrink-0">
                <Smartphone className="w-6 h-6 text-blue-600" />
              </div>
              <div className="flex-1">
                <h3 className="font-bold text-gray-900">Works Offline</h3>
                <p className="text-sm text-gray-600">Access bookings without internet</p>
              </div>
            </div>

            <div className="bg-white rounded-2xl p-4 shadow-lg border border-gray-100 flex items-center gap-4 animate-fade-in" style={{ animationDelay: '0.2s' }}>
              <div className="w-12 h-12 bg-green-100 rounded-xl flex items-center justify-center flex-shrink-0">
                <Shield className="w-6 h-6 text-green-600" />
              </div>
              <div className="flex-1">
                <h3 className="font-bold text-gray-900">Secure & Private</h3>
                <p className="text-sm text-gray-600">Blockchain-powered security</p>
              </div>
            </div>
          </div>

          {/* User Stats (Mock) */}
          <div className="bg-white rounded-2xl p-4 shadow-lg border border-gray-100 mb-8 animate-fade-in" style={{ animationDelay: '0.3s' }}>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600">Trusted by 2,847+ users</p>
              </div>
              <div className="text-right">
                <div className="text-2xl font-bold text-primary-600">2.8k+</div>
                <p className="text-xs text-gray-500">users</p>
              </div>
            </div>
          </div>

          {/* Install Buttons */}
          <div className="space-y-3 animate-fade-in" style={{ animationDelay: '0.4s' }}>
            {/* iOS Install Button */}
            <button
              onClick={handleIOSInstall}
              className="w-full bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 text-white font-bold py-5 rounded-2xl transition-all active:scale-98 shadow-2xl flex items-center justify-center gap-3 group"
            >
              <Smartphone className="w-6 h-6" />
              <span className="text-lg">Install on iOS</span>
              <ArrowRight className="w-5 h-5" />
            </button>

            {/* Android Install Button */}
            <button
              onClick={handleAndroidInstall}
              className="w-full bg-gradient-to-r from-green-500 to-green-600 hover:from-green-600 hover:to-green-700 text-white font-bold py-5 rounded-2xl transition-all active:scale-98 shadow-2xl flex items-center justify-center gap-3 group"
            >
              <Smartphone className="w-6 h-6" />
              <span className="text-lg">Install on Android</span>
              <ArrowRight className="w-5 h-5" />
            </button>

            <button
              onClick={() => navigate('/')}
              className="w-full text-gray-600 hover:text-gray-900 font-medium py-3 transition-colors"
            >
              Maybe Later
            </button>

            <p className="text-center text-xs text-gray-500 mt-4">
              Free • Less than 5MB • Install in seconds
            </p>
          </div>
        </div>
      </div>

      {/* iOS Instructions Bottom Sheet */}
      {showIOSInstructions && (
        <div
          className="fixed inset-0 min-h-[100dvh] bg-black/50 z-50 animate-fade-in"
          onClick={() => setShowIOSInstructions(false)}
        >
          <div
            className="absolute bottom-0 left-0 right-0 bg-white rounded-t-3xl p-6 max-h-[85dvh] overflow-y-auto animate-slide-up safe-area-inset-bottom"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="w-12 h-1 bg-gray-300 rounded-full mx-auto mb-6" />
            
            <div className="bg-blue-50 rounded-xl p-4 mb-6">
              <div className="flex items-center gap-2">
                <Smartphone className="w-5 h-5 text-blue-600" />
                <p className="text-blue-900 font-bold text-lg">
                  iOS / iPhone / iPad
                </p>
              </div>
            </div>
            
            <h2 className="text-2xl font-bold text-gray-900 mb-2">
              How to Install on iOS
            </h2>
            <p className="text-gray-600 mb-6">
              Follow these 3 simple steps
            </p>

            <div className="space-y-5">
              <div className="flex items-start gap-4">
                <div className="bg-primary-400 text-white rounded-full w-14 h-14 flex items-center justify-center flex-shrink-0 font-bold text-xl">1</div>
                <div className="flex-1 pt-3">
                  <p className="text-gray-800 text-lg leading-relaxed">
                    Tap the <Share2 className="w-5 h-5 inline mx-1 text-blue-500" /> <strong>Share</strong> icon
                  </p>
                </div>
              </div>

              <div className="flex items-start gap-4">
                <div className="bg-primary-400 text-white rounded-full w-14 h-14 flex items-center justify-center flex-shrink-0 font-bold text-xl">2</div>
                <div className="flex-1 pt-3">
                  <p className="text-gray-800 text-lg leading-relaxed">
                    Press <Plus className="w-5 h-5 inline mx-1 text-blue-500" /> <strong>"Add to Home Screen"</strong>
                  </p>
                </div>
              </div>

              <div className="flex items-start gap-4">
                <div className="bg-primary-400 text-white rounded-full w-14 h-14 flex items-center justify-center flex-shrink-0 font-bold text-xl">3</div>
                <div className="flex-1 pt-3">
                  <p className="text-gray-800 text-lg leading-relaxed">
                    Press <strong>"Add"</strong>
                  </p>
                </div>
              </div>
            </div>

            <button
              onClick={() => setShowIOSInstructions(false)}
              className="w-full bg-blue-500 hover:bg-blue-600 text-white font-semibold py-4 rounded-xl transition-colors active:scale-98 shadow-lg mt-8"
            >
              Got It
            </button>
          </div>
        </div>
      )}

      {/* Android Instructions Bottom Sheet */}
      {showAndroidInstructions && (
        <div
          className="fixed inset-0 min-h-[100dvh] bg-black/50 z-50 animate-fade-in"
          onClick={() => setShowAndroidInstructions(false)}
        >
          <div
            className="absolute bottom-0 left-0 right-0 bg-white rounded-t-3xl p-6 max-h-[85dvh] overflow-y-auto animate-slide-up safe-area-inset-bottom"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="w-12 h-1 bg-gray-300 rounded-full mx-auto mb-6" />
            
            <div className="bg-green-50 rounded-xl p-4 mb-6">
              <div className="flex items-center gap-2">
                <Smartphone className="w-5 h-5 text-green-600" />
                <p className="text-green-900 font-bold text-lg">
                  Android / Chrome
                </p>
              </div>
            </div>
            
            <h2 className="text-2xl font-bold text-gray-900 mb-2">
              How to Install on Android
            </h2>
            <p className="text-gray-600 mb-6">
              Follow these 3 simple steps
            </p>

            <div className="space-y-5">
              <div className="flex items-start gap-4">
                <div className="bg-primary-400 text-white rounded-full w-14 h-14 flex items-center justify-center flex-shrink-0 font-bold text-xl">1</div>
                <div className="flex-1 pt-3">
                  <p className="text-gray-800 text-lg leading-relaxed">
                    Tap the <strong>⋮ menu</strong> button in the top-right
                  </p>
                </div>
              </div>

              <div className="flex items-start gap-4">
                <div className="bg-primary-400 text-white rounded-full w-14 h-14 flex items-center justify-center flex-shrink-0 font-bold text-xl">2</div>
                <div className="flex-1 pt-3">
                  <p className="text-gray-800 text-lg leading-relaxed">
                    Press <strong>"Install app"</strong> or <strong>"Add to Home screen"</strong>
                  </p>
                </div>
              </div>

              <div className="flex items-start gap-4">
                <div className="bg-primary-400 text-white rounded-full w-14 h-14 flex items-center justify-center flex-shrink-0 font-bold text-xl">3</div>
                <div className="flex-1 pt-3">
                  <p className="text-gray-800 text-lg leading-relaxed">
                    Press <strong>"Install"</strong>
                  </p>
                </div>
              </div>
            </div>

            <button
              onClick={() => setShowAndroidInstructions(false)}
              className="w-full bg-green-500 hover:bg-green-600 text-white font-semibold py-4 rounded-xl transition-colors active:scale-98 shadow-lg mt-8"
            >
              Got It
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

