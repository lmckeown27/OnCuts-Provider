import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.tsx';
import './index.css';

// Note: Wallet providers removed - platform uses Stripe for payments
// If blockchain integration is needed later, re-add:
// import { DirectWalletProvider } from './contexts/DirectWalletContext.tsx';
// import { SuiDappKitProviders } from './providers/SuiDappKitProviders.tsx';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE WORKER - COMPLETELY DISABLED
// ═══════════════════════════════════════════════════════════════════════════════
// 
// Service workers are DISABLED for testing to avoid caching issues and white screens.
// 
// TO RE-ENABLE (when ready for push notifications):
// 1. Uncomment the registration code below
// 2. Change ENABLE_SERVICE_WORKER to true
// 3. Test with: npm run build && npm run preview
// 
// ═══════════════════════════════════════════════════════════════════════════════

const ENABLE_SERVICE_WORKER = false;  // ← Change to true to enable

if (ENABLE_SERVICE_WORKER && 'serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/service-worker.js').then(
      (registration) => {
        console.log('✅ Service Worker registered successfully:', registration.scope);
        
        // Check for updates periodically
        setInterval(() => {
          registration.update();
        }, 60 * 60 * 1000); // Check every hour
        
        // Listen for updates
        registration.addEventListener('updatefound', () => {
          const newWorker = registration.installing;
          if (newWorker) {
            newWorker.addEventListener('statechange', () => {
              if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                console.log('🔄 New service worker available. Refresh to update.');
                if (confirm('A new version of CampusCut is available. Reload to update?')) {
                  window.location.reload();
                }
              }
            });
          }
        });
      },
      (error) => {
        console.log('❌ Service Worker registration failed:', error);
      }
    );
  });
}

// AUTO-CLEANUP: Unregister any lingering service workers
// This runs ALWAYS to clean up any previously registered service workers
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then((registrations) => {
    if (registrations.length > 0) {
      console.log('🧹 Cleaning up', registrations.length, 'service worker(s)...');
      registrations.forEach((registration) => {
        registration.unregister().then((success) => {
          if (success) {
            console.log('✅ Unregistered service worker:', registration.scope);
          }
        });
      });
      console.log('💡 Service workers disabled for testing. Will re-enable for notifications.');
    }
  });
}

// PWA Install Prompt (disabled - re-enable with service worker)
// Uncomment when ENABLE_SERVICE_WORKER is true
/*
let deferredPrompt: any;
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  deferredPrompt = e;
  console.log('📱 Install prompt ready');
});

window.addEventListener('appinstalled', () => {
  console.log('✅ PWA installed successfully!');
  deferredPrompt = null;
});
*/
