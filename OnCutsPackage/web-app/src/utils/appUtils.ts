// @ts-nocheck
/**
 * App Utilities for PWA Features
 * 
 * Handles push notifications, background sync, and app installation
 */

// ═══════════════════════════════════════════════════════════
//  TYPE DEFINITIONS
// ═══════════════════════════════════════════════════════════

export interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

// ═══════════════════════════════════════════════════════════
//  PUSH NOTIFICATIONS
// ═══════════════════════════════════════════════════════════

export async function requestNotificationPermission(): Promise<NotificationPermission> {
  if (!('Notification' in window)) {
    console.warn('This browser does not support notifications');
    return 'denied';
  }

  if (Notification.permission === 'granted') {
    return 'granted';
  }

  if (Notification.permission !== 'denied') {
    const permission = await Notification.requestPermission();
    return permission;
  }

  return Notification.permission;
}

export async function subscribeToPushNotifications(): Promise<PushSubscription | null> {
  try {
    const registration = await navigator.serviceWorker.ready;
    
    // Check if already subscribed
    const existingSubscription = await registration.pushManager.getSubscription();
    if (existingSubscription) {
      return existingSubscription;
    }

    // Subscribe to push notifications
    // Note: You'll need to add your VAPID public key here
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(
        // Replace with your VAPID public key
        'YOUR_VAPID_PUBLIC_KEY_HERE'
      ),
    });

    console.log('✅ Push notification subscription:', subscription);
    
    // Send subscription to your backend
    // await sendSubscriptionToBackend(subscription);
    
    return subscription;
  } catch (error) {
    console.error('❌ Failed to subscribe to push notifications:', error);
    return null;
  }
}

export async function unsubscribeFromPushNotifications(): Promise<boolean> {
  try {
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription();
    
    if (subscription) {
      await subscription.unsubscribe();
      console.log('✅ Unsubscribed from push notifications');
      return true;
    }
    
    return false;
  } catch (error) {
    console.error('❌ Failed to unsubscribe from push notifications:', error);
    return false;
  }
}

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  
  return outputArray;
}

export function showLocalNotification(title: string, options?: NotificationOptions): void {
  if ('Notification' in window && Notification.permission === 'granted') {
    new Notification(title, {
      icon: '/icon-192x192.png',
      badge: '/icon-96x96.png',
      ...options,
    });
  }
}

// ═══════════════════════════════════════════════════════════
//  BACKGROUND SYNC
// ═══════════════════════════════════════════════════════════

export async function registerBackgroundSync(tag: string): Promise<void> {
  try {
    const registration = await navigator.serviceWorker.ready;
    
    if ('sync' in registration) {
      await (registration as any).sync.register(tag);
      console.log(`✅ Background sync registered: ${tag}`);
    } else {
      console.warn('Background sync not supported');
    }
  } catch (error) {
    console.error('❌ Failed to register background sync:', error);
  }
}

// ═══════════════════════════════════════════════════════════
//  APP INSTALLATION
// ═══════════════════════════════════════════════════════════

export function isAppInstalled(): boolean {
  // Check if running as installed PWA
  return window.matchMedia('(display-mode: standalone)').matches ||
         (window.navigator as any).standalone === true ||
         document.referrer.includes('android-app://');
}

export function isIOSDevice(): boolean {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) && !(window as any).MSStream;
}

export function isAndroidDevice(): boolean {
  return /Android/.test(navigator.userAgent);
}

export function getPlatform(): 'ios' | 'android' | 'desktop' | 'unknown' {
  if (isIOSDevice()) return 'ios';
  if (isAndroidDevice()) return 'android';
  if (/Windows|Macintosh|Linux/.test(navigator.userAgent)) return 'desktop';
  return 'unknown';
}

// ═══════════════════════════════════════════════════════════
//  OFFLINE STORAGE
// ═══════════════════════════════════════════════════════════

export function saveOfflineAction(action: string, data: any): void {
  try {
    const offlineActions = getOfflineActions();
    offlineActions.push({
      id: Date.now().toString(),
      action,
      data,
      timestamp: new Date().toISOString(),
    });
    localStorage.setItem('campuscuts_offline_actions', JSON.stringify(offlineActions));
  } catch (error) {
    console.error('❌ Failed to save offline action:', error);
  }
}

export function getOfflineActions(): Array<{
  id: string;
  action: string;
  data: any;
  timestamp: string;
}> {
  try {
    const actions = localStorage.getItem('campuscuts_offline_actions');
    return actions ? JSON.parse(actions) : [];
  } catch (error) {
    console.error('❌ Failed to get offline actions:', error);
    return [];
  }
}

export function clearOfflineActions(): void {
  try {
    localStorage.removeItem('campuscuts_offline_actions');
  } catch (error) {
    console.error('❌ Failed to clear offline actions:', error);
  }
}

export async function syncOfflineActions(): Promise<void> {
  const actions = getOfflineActions();
  
  if (actions.length === 0) {
    return;
  }
  
  console.log(`📤 Syncing ${actions.length} offline actions...`);
  
  for (const action of actions) {
    try {
      // Process each offline action
      // This would call your API to sync the data
      console.log('Processing offline action:', action);
      // await processOfflineAction(action);
    } catch (error) {
      console.error('❌ Failed to sync action:', action, error);
    }
  }
  
  clearOfflineActions();
  console.log('✅ Offline actions synced successfully');
}

// ═══════════════════════════════════════════════════════════
//  NETWORK STATUS
// ═══════════════════════════════════════════════════════════

export function isOnline(): boolean {
  return navigator.onLine;
}

export function onOnline(callback: () => void): () => void {
  window.addEventListener('online', callback);
  return () => window.removeEventListener('online', callback);
}

export function onOffline(callback: () => void): () => void {
  window.addEventListener('offline', callback);
  return () => window.removeEventListener('offline', callback);
}

// ═══════════════════════════════════════════════════════════
//  CACHE MANAGEMENT
// ═══════════════════════════════════════════════════════════

export async function clearAppCache(): Promise<void> {
  try {
    const cacheNames = await caches.keys();
    await Promise.all(
      cacheNames.map(cacheName => caches.delete(cacheName))
    );
    console.log('✅ App cache cleared');
  } catch (error) {
    console.error('❌ Failed to clear app cache:', error);
  }
}

export async function getCacheSize(): Promise<number> {
  if ('storage' in navigator && 'estimate' in navigator.storage) {
    const estimate = await navigator.storage.estimate();
    return estimate.usage || 0;
  }
  return 0;
}

// ═══════════════════════════════════════════════════════════
//  APP UPDATES
// ═══════════════════════════════════════════════════════════

export async function checkForUpdates(): Promise<boolean> {
  try {
    const registration = await navigator.serviceWorker.ready;
    await registration.update();
    return registration.waiting !== null;
  } catch (error) {
    console.error('❌ Failed to check for updates:', error);
    return false;
  }
}

export async function activateUpdate(): Promise<void> {
  const registration = await navigator.serviceWorker.ready;
  
  if (registration.waiting) {
    registration.waiting.postMessage({ type: 'SKIP_WAITING' });
    
    // Reload page after activation
    let refreshing = false;
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (!refreshing) {
        refreshing = true;
        window.location.reload();
      }
    });
  }
}

// ═══════════════════════════════════════════════════════════
//  APP SHARING
// ═══════════════════════════════════════════════════════════

export async function shareApp(
  title: string = 'CampusCut',
  text: string = 'Check out CampusCut - Fair prices for students, great earnings for barbers!',
  url: string = window.location.origin
): Promise<boolean> {
  if ('share' in navigator) {
    try {
      await navigator.share({ title, text, url });
      return true;
    } catch (error) {
      if ((error as Error).name !== 'AbortError') {
        console.error('❌ Failed to share:', error);
      }
      return false;
    }
  }
  
  // Fallback: Copy to clipboard
  try {
    await navigator.clipboard.writeText(url);
    console.log('✅ URL copied to clipboard');
    return true;
  } catch (error) {
    console.error('❌ Failed to copy to clipboard:', error);
    return false;
  }
}

// ═══════════════════════════════════════════════════════════
//  APP BADGES (For notification counts)
// ═══════════════════════════════════════════════════════════

export function setAppBadge(count: number): void {
  if ('setAppBadge' in navigator) {
    (navigator as any).setAppBadge(count);
  }
}

export function clearAppBadge(): void {
  if ('clearAppBadge' in navigator) {
    (navigator as any).clearAppBadge();
  }
}

// ═══════════════════════════════════════════════════════════
//  HAPTIC FEEDBACK (Mobile)
// ═══════════════════════════════════════════════════════════

export function vibrateDevice(pattern: number | number[] = 200): void {
  if ('vibrate' in navigator) {
    navigator.vibrate(pattern);
  }
}

export function hapticFeedback(type: 'light' | 'medium' | 'heavy' = 'medium'): void {
  const patterns = {
    light: 10,
    medium: 20,
    heavy: 30,
  };
  
  vibrateDevice(patterns[type]);
}

