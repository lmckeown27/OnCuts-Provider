/**
 * PWA Type Declarations
 * 
 * TypeScript definitions for PWA-specific browser APIs
 */

// BeforeInstallPrompt Event (Chrome/Edge)
interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

// Window interface extensions for PWA
interface WindowEventMap {
  beforeinstallprompt: BeforeInstallPromptEvent;
  appinstalled: Event;
}

// Navigator interface extensions
interface Navigator {
  standalone?: boolean;  // iOS Safari
  setAppBadge?: (count?: number) => Promise<void>;
  clearAppBadge?: () => Promise<void>;
}

// Service Worker registration with Background Sync
interface ServiceWorkerRegistration {
  sync?: {
    register(tag: string): Promise<void>;
    getTags(): Promise<string[]>;
  };
}

// Notification Options with additional properties
interface NotificationOptions {
  badge?: string;
  icon?: string;
  image?: string;
  vibrate?: number | number[];
  actions?: NotificationAction[];
  tag?: string;
  requireInteraction?: boolean;
}

// Share API
interface Navigator {
  share?: (data: { title?: string; text?: string; url?: string }) => Promise<void>;
}

// Storage Estimation
interface StorageEstimate {
  usage?: number;
  quota?: number;
}

interface NavigatorStorage {
  estimate(): Promise<StorageEstimate>;
}

interface Navigator {
  storage?: NavigatorStorage;
}

