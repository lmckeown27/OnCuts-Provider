/**
 * PWA Install Prompt Component
 * 
 * Detects if app can be installed and prompts user
 */

import React, { useEffect, useState } from 'react';
import { Download, X, Smartphone } from 'lucide-react';
import Button from './Button';
import Card from './Card';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

export default function PWAInstallPrompt() {
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [showPrompt, setShowPrompt] = useState(false);

  useEffect(() => {
    const handler = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e as BeforeInstallPromptEvent);
      setShowPrompt(true);
    };

    window.addEventListener('beforeinstallprompt', handler);

    return () => {
      window.removeEventListener('beforeinstallprompt', handler);
    };
  }, []);

  const handleInstall = async () => {
    if (!deferredPrompt) return;

    deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    
    if (outcome === 'accepted') {
      console.log('User accepted the install prompt');
    } else {
      console.log('User dismissed the install prompt');
    }

    setDeferredPrompt(null);
    setShowPrompt(false);
  };

  const handleDismiss = () => {
    setShowPrompt(false);
  };

  if (!showPrompt) return null;

  return (
    <div className="fixed bottom-4 left-4 right-4 z-50 max-w-md mx-auto animate-slide-up">
      <Card className="shadow-2xl border-2 border-primary-500">
        <div className="flex items-start gap-4">
          <div className="bg-primary-100 rounded-full p-3 flex-shrink-0">
            <Smartphone className="w-6 h-6 text-primary-400" />
          </div>
          
          <div className="flex-1">
            <h3 className="font-bold text-gray-900 mb-1">Install CampusCut</h3>
            <p className="text-sm text-gray-600 mb-3">
              Install the app for offline access, push notifications, and a native experience.
            </p>
            
            <div className="flex gap-2">
              <Button
                onClick={handleInstall}
                size="sm"
                className="bg-primary-400 hover:bg-primary-500 flex-1"
              >
                <Download className="w-4 h-4 mr-2" />
                Install
              </Button>
              <Button
                onClick={handleDismiss}
                size="sm"
                variant="secondary"
              >
                Later
              </Button>
            </div>
          </div>

          <button
            onClick={handleDismiss}
            className="text-gray-400 hover:text-gray-600 flex-shrink-0"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
      </Card>
    </div>
  );
}

