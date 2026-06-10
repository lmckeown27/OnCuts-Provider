/**
 * App Status Component
 * 
 * Shows app connection status, notifications, and update availability
 */

import React, { useState, useEffect } from 'react';
import { Wifi, WifiOff, Bell, BellOff, Download, X } from 'lucide-react';
import { isOnline, checkForUpdates, activateUpdate } from '../utils/appUtils';
import Button from './Button';

export default function AppStatus() {
  const [online, setOnline] = useState(isOnline());
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const [showUpdatePrompt, setShowUpdatePrompt] = useState(false);
  const [notificationsEnabled, setNotificationsEnabled] = useState(
    'Notification' in window && Notification.permission === 'granted'
  );

  useEffect(() => {
    // Monitor online/offline status
    const handleOnline = () => setOnline(true);
    const handleOffline = () => setOnline(false);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    // Check for app updates
    const checkUpdates = async () => {
      const hasUpdate = await checkForUpdates();
      if (hasUpdate) {
        setUpdateAvailable(true);
        setShowUpdatePrompt(true);
      }
    };

    checkUpdates();
    const interval = setInterval(checkUpdates, 60 * 60 * 1000); // Check every hour

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
      clearInterval(interval);
    };
  }, []);

  const handleUpdate = async () => {
    await activateUpdate();
  };

  return (
    <>
      {/* Connection Status Banner */}
      {!online && (
        <div className="fixed top-0 left-0 right-0 z-50 bg-red-600 text-white px-4 py-2 text-center text-sm font-medium animate-slide-down">
          <div className="flex items-center justify-center gap-2">
            <WifiOff className="w-4 h-4" />
            <span>You're offline. Some features may be limited.</span>
          </div>
        </div>
      )}

      {/* Update Available Prompt */}
      {showUpdatePrompt && updateAvailable && (
        <div className="fixed bottom-4 left-4 right-4 z-50 max-w-md mx-auto animate-slide-up">
          <div className="bg-white rounded-lg shadow-2xl border-2 border-primary-500 p-4">
            <div className="flex items-start gap-4">
              <div className="bg-primary-100 rounded-full p-3 flex-shrink-0">
                <Download className="w-6 h-6 text-primary-600" />
              </div>
              
              <div className="flex-1">
                <h3 className="font-bold text-gray-900 mb-1">Update Available</h3>
                <p className="text-sm text-gray-600 mb-3">
                  A new version of CampusCut is ready. Update now for the latest features and improvements.
                </p>
                
                <div className="flex gap-2">
                  <Button
                    onClick={handleUpdate}
                    size="sm"
                    className="bg-primary-400 hover:bg-primary-500 flex-1"
                  >
                    Update Now
                  </Button>
                  <Button
                    onClick={() => setShowUpdatePrompt(false)}
                    size="sm"
                    variant="secondary"
                  >
                    Later
                  </Button>
                </div>
              </div>

              <button
                onClick={() => setShowUpdatePrompt(false)}
                className="text-gray-400 hover:text-gray-600 flex-shrink-0"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Status Indicators (Bottom Right) */}
      <div className="fixed bottom-4 right-4 z-40 flex flex-col gap-2">
        {/* Online Status */}
        <div
          className={`px-3 py-2 rounded-full shadow-lg flex items-center gap-2 text-sm font-medium transition-all ${
            online
              ? 'bg-green-100 text-green-800'
              : 'bg-red-100 text-red-800'
          }`}
          title={online ? 'Online' : 'Offline'}
        >
          {online ? (
            <>
              <Wifi className="w-4 h-4" />
              <span className="hidden sm:inline">Online</span>
            </>
          ) : (
            <>
              <WifiOff className="w-4 h-4" />
              <span className="hidden sm:inline">Offline</span>
            </>
          )}
        </div>

        {/* Notification Status */}
        {notificationsEnabled ? (
          <div
            className="px-3 py-2 rounded-full shadow-lg flex items-center gap-2 text-sm font-medium bg-blue-100 text-blue-800"
            title="Notifications enabled"
          >
            <Bell className="w-4 h-4" />
            <span className="hidden sm:inline">Notifications</span>
          </div>
        ) : (
          <div
            className="px-3 py-2 rounded-full shadow-lg flex items-center gap-2 text-sm font-medium bg-gray-100 text-gray-800"
            title="Notifications disabled"
          >
            <BellOff className="w-4 h-4" />
          </div>
        )}
      </div>
    </>
  );
}

