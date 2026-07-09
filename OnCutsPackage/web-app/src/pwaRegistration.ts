/**
 * PWA Registration
 * 
 * Registers the service worker and handles updates
 */

export function registerServiceWorker() {
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker
        .register('/service-worker.js')
        .then((registration) => {
          console.log('Service Worker registered:', registration.scope);
          
          // Check for updates every hour
          setInterval(() => {
            registration.update();
          }, 60 * 60 * 1000);
          
          // Handle updates
          registration.addEventListener('updatefound', () => {
            const newWorker = registration.installing;
            
            if (newWorker) {
              newWorker.addEventListener('statechange', () => {
                if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                  // New service worker available
                  console.log('New version available! Please refresh.');
                  
                  // Show update notification
                  showUpdateNotification(registration);
                }
              });
            }
          });
        })
        .catch((error) => {
          console.error('❌ Service Worker registration failed:', error);
        });
    });
  } else {
    console.log('Service Worker not supported in this browser');
  }
}

/**
 * Show update notification with refresh button
 */
function showUpdateNotification(registration: ServiceWorkerRegistration) {
  // Create notification UI
  const notification = document.createElement('div');
  notification.style.cssText = `
    position: fixed;
    bottom: 20px;
    left: 50%;
    transform: translateX(-50%);
    background: #4F46E5;
    color: white;
    padding: 16px 24px;
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
    z-index: 10000;
    display: flex;
    gap: 16px;
    align-items: center;
    animation: slideUp 0.3s ease-out;
  `;
  
  notification.innerHTML = `
    <span>New version available!</span>
    <button id="pwa-refresh-btn" style="
      background: white;
      color: #4F46E5;
      border: none;
      padding: 8px 16px;
      border-radius: 4px;
      font-weight: 600;
      cursor: pointer;
    ">
      Refresh
    </button>
  `;
  
  document.body.appendChild(notification);
  
  // Handle refresh button
  document.getElementById('pwa-refresh-btn')?.addEventListener('click', () => {
    if (registration.waiting) {
      registration.waiting.postMessage({ type: 'SKIP_WAITING' });
    }
    window.location.reload();
  });
  
  // Auto-dismiss after 30 seconds
  setTimeout(() => {
    notification.remove();
  }, 30000);
}

/**
 * Request notification permission
 */
export async function requestNotificationPermission(): Promise<boolean> {
  if (!('Notification' in window)) {
    console.log('Notifications not supported');
    return false;
  }
  
  if (Notification.permission === 'granted') {
    return true;
  }
  
  if (Notification.permission !== 'denied') {
    const permission = await Notification.requestPermission();
    return permission === 'granted';
  }
  
  return false;
}

/**
 * Show install prompt
 */
export function setupInstallPrompt() {
  let deferredPrompt: any = null;
  
  window.addEventListener('beforeinstallprompt', (e) => {
    // Prevent the mini-infobar from appearing
    e.preventDefault();
    
    // Save the event
    deferredPrompt = e;
    
    // Show custom install button
    showInstallPrompt(deferredPrompt);
  });
  
  // Handle successful installation
  window.addEventListener('appinstalled', () => {
    console.log('CampusCut installed as PWA');
    deferredPrompt = null;
  });
}

/**
 * Show install prompt UI
 */
function showInstallPrompt(deferredPrompt: any) {
  const prompt = document.createElement('div');
  prompt.style.cssText = `
    position: fixed;
    bottom: 20px;
    left: 50%;
    transform: translateX(-50%);
    background: white;
    color: #1F2937;
    padding: 16px 24px;
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
    z-index: 10000;
    display: flex;
    gap: 16px;
    align-items: center;
    border: 2px solid #4F46E5;
  `;
  
  prompt.innerHTML = `
    <span>Install CampusCut for quick access!</span>
    <button id="pwa-install-btn" style="
      background: #4F46E5;
      color: white;
      border: none;
      padding: 8px 16px;
      border-radius: 4px;
      font-weight: 600;
      cursor: pointer;
    ">
      Install
    </button>
    <button id="pwa-dismiss-btn" style="
      background: transparent;
      color: #6B7280;
      border: none;
      padding: 8px;
      cursor: pointer;
      font-size: 18px;
    ">
      ✕
    </button>
  `;
  
  document.body.appendChild(prompt);
  
  // Handle install button
  document.getElementById('pwa-install-btn')?.addEventListener('click', async () => {
    if (deferredPrompt) {
      deferredPrompt.prompt();
      const { outcome } = await deferredPrompt.userChoice;
      console.log(`User response: ${outcome}`);
      deferredPrompt = null;
      prompt.remove();
    }
  });
  
  // Handle dismiss button
  document.getElementById('pwa-dismiss-btn')?.addEventListener('click', () => {
    prompt.remove();
    // Don't show again for 7 days
    localStorage.setItem('pwa-install-dismissed', Date.now().toString());
  });
  
  // Check if dismissed recently
  const dismissed = localStorage.getItem('pwa-install-dismissed');
  if (dismissed) {
    const daysSince = (Date.now() - parseInt(dismissed)) / (1000 * 60 * 60 * 24);
    if (daysSince < 7) {
      prompt.remove();
      return;
    }
  }
}

/**
 * Check if app is installed as PWA
 */
export function isAppInstalled(): boolean {
  return window.matchMedia('(display-mode: standalone)').matches ||
         (window.navigator as any).standalone ||
         document.referrer.includes('android-app://');
}

/**
 * Get PWA display mode
 */
export function getDisplayMode(): 'browser' | 'standalone' | 'minimal-ui' | 'fullscreen' {
  if (window.matchMedia('(display-mode: fullscreen)').matches) {
    return 'fullscreen';
  }
  if (window.matchMedia('(display-mode: standalone)').matches) {
    return 'standalone';
  }
  if (window.matchMedia('(display-mode: minimal-ui)').matches) {
    return 'minimal-ui';
  }
  return 'browser';
}

// Auto-initialize
if (typeof window !== 'undefined') {
  registerServiceWorker();
  setupInstallPrompt();
  
  // Log display mode
  console.log(`Display mode: ${getDisplayMode()}`);
  console.log(`Installed: ${isAppInstalled()}`);
}

