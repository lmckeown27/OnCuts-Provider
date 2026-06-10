// API Configuration - Uses environment variables from .env
// Production uses relative URL (proxied through Nginx); for local dev, set VITE_API_URL=http://localhost:3001/api/v1
export const API_BASE_URL = import.meta.env.VITE_API_URL || import.meta.env.VITE_API_BASE_URL || '/api/v1';

/** Origin for non-versioned routes (e.g. /api/zklogin). */
export function getBackendOrigin(): string {
  if (import.meta.env.VITE_API_ORIGIN) {
    return import.meta.env.VITE_API_ORIGIN.replace(/\/$/, '');
  }
  const base = API_BASE_URL;
  if (base.startsWith('http')) {
    try {
      const url = new URL(base);
      return url.origin;
    } catch {
      return '';
    }
  }
  if (typeof window !== 'undefined') {
    return window.location.origin;
  }
  return '';
}
export const WS_URL = import.meta.env.VITE_WS_URL || `wss://${window.location.host}`;

/** Align with backend APP_NETWORK_MODE: testnet = Stripe test + Sui testnet; mainnet = live + Sui mainnet. */
export type AppNetworkMode = 'testnet' | 'mainnet';

function parseViteAppNetworkMode(): AppNetworkMode | null {
  const raw = (
    (import.meta.env.VITE_APP_NETWORK_MODE as string | undefined) ||
    (import.meta.env.VITE_SUI_NETWORK as string | undefined) ||
    ''
  )
    .trim()
    .toLowerCase();
  if (!raw || raw === 'auto') return null;
  if (raw === 'mainnet' || raw === 'live' || raw === 'production') return 'mainnet';
  if (raw === 'testnet' || raw === 'test' || raw === 'development') return 'testnet';
  return null;
}

export const APP_NETWORK_MODE: AppNetworkMode | null = parseViteAppNetworkMode();

const SUI_MAINNET_DEFAULT_USDC =
  '0xdba34672e30cb065b1f93e3ad5531876580039906648354972135f29979d9744::usdc::USDC';
const SUI_TESTNET_DEFAULT_USDC =
  '0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC';

/** Publishable key: set VITE_APP_NETWORK_MODE to pick test vs live pk when using split env names. */
export const STRIPE_PUBLIC_KEY =
  import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY ||
  import.meta.env.VITE_STRIPE_PUBLIC_KEY ||
  (APP_NETWORK_MODE === 'mainnet'
    ? import.meta.env.VITE_STRIPE_LIVE_PUBLISHABLE_KEY || import.meta.env.VITE_STRIPE_TEST_PUBLISHABLE_KEY
    : APP_NETWORK_MODE === 'testnet'
      ? import.meta.env.VITE_STRIPE_TEST_PUBLISHABLE_KEY || import.meta.env.VITE_STRIPE_LIVE_PUBLISHABLE_KEY
      : import.meta.env.PROD
        ? import.meta.env.VITE_STRIPE_LIVE_PUBLISHABLE_KEY || import.meta.env.VITE_STRIPE_TEST_PUBLISHABLE_KEY
        : import.meta.env.VITE_STRIPE_TEST_PUBLISHABLE_KEY || import.meta.env.VITE_STRIPE_LIVE_PUBLISHABLE_KEY) ||
  '';

// Sui — VITE_SUI_RPC_URL wins; else defaults from APP_NETWORK_MODE; else legacy testnet
export const SUI_RPC_URL =
  import.meta.env.VITE_SUI_RPC_URL ||
  (APP_NETWORK_MODE === 'mainnet'
    ? 'https://fullnode.mainnet.sui.io:443'
    : APP_NETWORK_MODE === 'testnet'
      ? 'https://fullnode.testnet.sui.io:443'
      : 'https://fullnode.testnet.sui.io:443');
export const SUI_PROVER_URL = import.meta.env.VITE_SUI_PROVER_URL || '';

/** Native USDC type for the RPC network (must match backend). VITE_SUI_USDC_COIN_TYPE overrides. */
export const SUI_USDC_COIN_TYPE =
  (import.meta.env.VITE_SUI_USDC_COIN_TYPE as string | undefined)?.trim() ||
  (APP_NETWORK_MODE === 'mainnet'
    ? SUI_MAINNET_DEFAULT_USDC
    : APP_NETWORK_MODE === 'testnet'
      ? SUI_TESTNET_DEFAULT_USDC
      : '') ||
  '';

/**
 * Mysten public zkLogin proving service (free). Used when building ZK proofs for zkLogin-signed txs.
 * @see https://docs.sui.io/guides/developer/cryptography/zklogin-integration
 */
export const SUI_ZKLOGIN_PROVER_URL =
  (import.meta.env.VITE_SUI_ZKLOGIN_PROVER_URL as string | undefined)?.trim() ||
  'https://prover-v2.mystenlabs.com/v1';

/** Google OAuth Web client ID; authorized redirect URIs must include `.../web/zklogin/callback` and `/app/zklogin/callback`. */
export const GOOGLE_OAUTH_CLIENT_ID =
  (import.meta.env.VITE_GOOGLE_OAUTH_CLIENT_ID as string | undefined)?.trim() || '';

/**
 * Scheme + host for Google `redirect_uri` (no path, no trailing slash).
 * Defaults to `window.location.origin` so barbers on `/web/...` get `https://yoursite.com/web/zklogin/callback`.
 * Override if the public URL differs from what the browser reports (proxy/CDN).
 */
export function getGoogleOAuthRedirectOrigin(): string {
  const fromEnv = (import.meta.env.VITE_ZKLOGIN_REDIRECT_ORIGIN as string | undefined)?.trim().replace(/\/$/, '');
  if (fromEnv) {
    return fromEnv;
  }
  if (typeof window !== 'undefined') {
    return window.location.origin;
  }
  return '';
}

export function isZkLoginWalletlessEnabled(): boolean {
  return Boolean(GOOGLE_OAUTH_CLIENT_ID);
}

// App Metadata
export const APP_NAME = import.meta.env.VITE_APP_NAME || 'CampusCut';
export const APP_VERSION = import.meta.env.VITE_APP_VERSION || '1.0.0';

export const ROUTES = {
  HOME: '/',
  LOGIN: '/login',
  SIGNUP: '/signup',
  CAMPUS_SELECT: '/campus-select',
  CONSUMER: '/consumer',
  BARBER: '/barber',
  WALLET: '/wallet',

  // Student routes
  STUDENT_DISCOVERY: '/student/discovery',
  STUDENT_BARBER_DETAIL: '/student/barber/:id',
  STUDENT_BOOKING: '/student/booking/:barberId',
  STUDENT_BOOKINGS: '/student/bookings',
  STUDENT_PROFILE: '/student/profile',
  STUDENT_MESSAGES: '/student/messages',

  // Barber routes
  BARBER_DASHBOARD: '/barber/dashboard',
  BARBER_CALENDAR: '/barber/calendar',
  BARBER_EARNINGS: '/barber/earnings',
  BARBER_PROFILE: '/barber/profile',
  BARBER_MESSAGES: '/barber/messages',
} as const;

export const STORAGE_KEYS = {
  ACCESS_TOKEN: 'accessToken',
  REFRESH_TOKEN: 'refreshToken',
  USER: 'user',
  CAMPUS: 'campus',
} as const;

export const USER_ROLES = {
  STUDENT: 'student',
  BARBER: 'barber',
  ADMIN: 'admin',
} as const;

export const BOOKING_STATUS = {
  PENDING: 'pending',
  CONFIRMED: 'confirmed',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
} as const;

export const MESSAGE_TYPES = {
  TEXT: 'text',
  IMAGE: 'image',
  SYSTEM: 'system',
} as const;
