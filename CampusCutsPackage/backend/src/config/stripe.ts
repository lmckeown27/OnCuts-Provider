import Stripe from 'stripe';
import { stripeAutoModeFromAppNetwork } from './app-network';

/** Keep in sync across all Stripe entrypoints (server SDK). */
export const STRIPE_API_VERSION = '2023-10-16' as const;

/**
 * Stripe iOS (`StripeCore` `STPAPIClient`) sends `Stripe-Version: 2020-08-27` for all requests.
 * Ephemeral keys **must** be created with that same `api_version` or PaymentSheet / Elements can fail
 * even when PaymentIntents are created successfully with `STRIPE_API_VERSION`.
 * @see https://docs.stripe.com/api/ephemeral_keys/create
 */
export const STRIPE_IOS_SDK_API_VERSION = '2020-08-27' as const;

function trimEnv(name: string): string | undefined {
  const v = process.env[name]?.trim();
  return v || undefined;
}

/** Standard + restricted Stripe API keys for live mode. */
function isLiveStripeApiKey(k: string | undefined): boolean {
  const s = k?.trim();
  return Boolean(s && (s.startsWith('sk_live_') || s.startsWith('rk_live_')));
}

/** Standard + restricted Stripe API keys for test mode. */
function isTestStripeApiKey(k: string | undefined): boolean {
  const s = k?.trim();
  return Boolean(s && (s.startsWith('sk_test_') || s.startsWith('rk_test_')));
}

/** Live secret: STRIPE_SECRET_KEY_LIVE or STRIPE_LIVE_SECRET_KEY */
function liveStripeSecretFromEnv(): string | undefined {
  return trimEnv('STRIPE_SECRET_KEY_LIVE') || trimEnv('STRIPE_LIVE_SECRET_KEY');
}

/** Test secret: STRIPE_SECRET_KEY_TEST or STRIPE_TEST_SECRET_KEY */
function testStripeSecretFromEnv(): string | undefined {
  return trimEnv('STRIPE_SECRET_KEY_TEST') || trimEnv('STRIPE_TEST_SECRET_KEY');
}

/** Live webhook signing secret */
function liveStripeWebhookFromEnv(): string | undefined {
  return trimEnv('STRIPE_WEBHOOK_SECRET_LIVE') || trimEnv('STRIPE_LIVE_WEBHOOK_SECRET');
}

/** Test webhook signing secret */
function testStripeWebhookFromEnv(): string | undefined {
  return trimEnv('STRIPE_WEBHOOK_SECRET_TEST') || trimEnv('STRIPE_TEST_WEBHOOK_SECRET');
}

/** True if any secret-key env var is set (generic or split live/test). */
export function isAnyStripeSecretKeyConfigured(): boolean {
  return Boolean(
    trimEnv('STRIPE_SECRET_KEY') || liveStripeSecretFromEnv() || testStripeSecretFromEnv()
  );
}

function dedupeStrings(values: (string | undefined)[]): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const s of values) {
    if (s && !seen.has(s)) {
      seen.add(s);
      out.push(s);
    }
  }
  return out;
}

/**
 * Webhook signing secrets to try in order (same HTTPS endpoint for test + live dashboards).
 * STRIPE_WEBHOOK_SECRET remains the primary / backward-compatible name.
 */
export function getStripeWebhookSecrets(): string[] {
  return dedupeStrings([
    trimEnv('STRIPE_WEBHOOK_SECRET'),
    trimEnv('STRIPE_WEBHOOK_SECRET_LIVE'),
    trimEnv('STRIPE_WEBHOOK_SECRET_TEST'),
  ]);
}

export function hasStripeWebhookSecretConfigured(): boolean {
  return getStripeWebhookSecrets().length > 0;
}

/**
 * Verify Stripe-Signature using any configured webhook secret.
 */
export function constructStripeWebhookEvent(
  payload: Buffer | string,
  signature: string
): Stripe.Event {
  const secrets = getStripeWebhookSecrets();
  if (secrets.length === 0) {
    throw new Error('No STRIPE_WEBHOOK_SECRET* configured');
  }
  const parser = new Stripe('sk_test_000000000000000000000000', { apiVersion: STRIPE_API_VERSION });
  let lastErr: Error | undefined;
  for (const secret of secrets) {
    try {
      return parser.webhooks.constructEvent(payload, signature, secret);
    } catch (e) {
      lastErr = e as Error;
    }
  }
  throw lastErr ?? new Error('Webhook signature verification failed');
}

const clientByKey = new Map<string, Stripe>();

export function getStripeClient(secretKey: string): Stripe {
  if (!secretKey) {
    throw new Error('Stripe secret key is empty');
  }
  let c = clientByKey.get(secretKey);
  if (!c) {
    c = new Stripe(secretKey, { apiVersion: STRIPE_API_VERSION });
    clientByKey.set(secretKey, c);
  }
  return c;
}

/**
 * Resolve restricted key for a given Stripe object livemode (from events or API objects).
 * STRIPE_MODE=live|test forces that key; auto picks sk_live_* / sk_test_* specific env vars first.
 */
export function resolveStripeSecretKeyForLivemode(livemode: boolean): string {
  const mode = (trimEnv('STRIPE_MODE') || 'auto').toLowerCase();
  const generic = trimEnv('STRIPE_SECRET_KEY');
  const liveKey = liveStripeSecretFromEnv();
  const testKey = testStripeSecretFromEnv();

  if (mode === 'live') {
    const k =
      liveKey ||
      (generic?.startsWith('sk_live') ? generic : undefined) ||
      generic;
    if (!k) {
      throw new Error(
        'STRIPE_MODE=live: set STRIPE_SECRET_KEY_LIVE / STRIPE_LIVE_SECRET_KEY or STRIPE_SECRET_KEY (sk_live_...)'
      );
    }
    return k;
  }

  if (mode === 'test') {
    const k =
      testKey ||
      (generic?.startsWith('sk_test') ? generic : undefined) ||
      generic;
    if (!k) {
      throw new Error(
        'STRIPE_MODE=test: set STRIPE_SECRET_KEY_TEST / STRIPE_TEST_SECRET_KEY or STRIPE_SECRET_KEY (sk_test_...)'
      );
    }
    return k;
  }

  if (livemode) {
    const k = liveKey || (generic?.startsWith('sk_live') ? generic : undefined);
    if (k) return k;
    if (generic?.startsWith('sk_test')) {
      throw new Error(
        'Live Stripe event but only sk_test STRIPE_SECRET_KEY is set; add STRIPE_SECRET_KEY_LIVE / STRIPE_LIVE_SECRET_KEY or use sk_live in STRIPE_SECRET_KEY'
      );
    }
    if (generic) return generic;
    throw new Error(
      'Live Stripe event: configure STRIPE_SECRET_KEY_LIVE / STRIPE_LIVE_SECRET_KEY or STRIPE_SECRET_KEY (sk_live_...)'
    );
  }

  const k = testKey || (generic?.startsWith('sk_test') ? generic : undefined);
  if (k) return k;
  if (generic?.startsWith('sk_live')) {
    throw new Error(
      'Test Stripe event but only sk_live STRIPE_SECRET_KEY is set; add STRIPE_SECRET_KEY_TEST or use sk_test in STRIPE_SECRET_KEY'
    );
  }
  if (generic) return generic;
  throw new Error(
    'Test Stripe event: configure STRIPE_SECRET_KEY_TEST / STRIPE_TEST_SECRET_KEY or STRIPE_SECRET_KEY (sk_test_...)'
  );
}

export function getStripeClientForLivemode(livemode: boolean): Stripe {
  return getStripeClient(resolveStripeSecretKeyForLivemode(livemode));
}

/**
 * Secret key for normal API traffic (checkout, Connect, etc.), not webhook-parsed livemode.
 * STRIPE_MODE live/test locks mode; auto prefers live in production, else test, with sensible fallbacks.
 */
export function getDefaultStripeSecretKey(): string {
  let mode = (trimEnv('STRIPE_MODE') || 'auto').toLowerCase();
  const stripeFromNet = stripeAutoModeFromAppNetwork();
  if (mode === 'auto' && stripeFromNet) {
    mode = stripeFromNet;
  }
  const generic = trimEnv('STRIPE_SECRET_KEY');
  const liveKey = liveStripeSecretFromEnv();
  const testKey = testStripeSecretFromEnv();

  if (mode === 'live') {
    const k = liveKey || (isLiveStripeApiKey(generic) ? generic : undefined) || '';
    if (!k) {
      throw new Error(
        'STRIPE_MODE=live: set STRIPE_SECRET_KEY_LIVE / STRIPE_LIVE_SECRET_KEY or STRIPE_SECRET_KEY to sk_live_… / rk_live_…. ' +
          'A sk_test_ value in STRIPE_SECRET_KEY alone is ignored (previously it incorrectly fell through and created test PaymentIntents).'
      );
    }
    return k;
  }
  if (mode === 'test') {
    const k = testKey || (isTestStripeApiKey(generic) ? generic : undefined) || '';
    if (!k) {
      throw new Error(
        'STRIPE_MODE=test: set STRIPE_SECRET_KEY_TEST / STRIPE_TEST_SECRET_KEY or STRIPE_SECRET_KEY to sk_test_… / rk_test_…. ' +
          'A sk_live_ value in STRIPE_SECRET_KEY alone is ignored.'
      );
    }
    return k;
  }

  if (process.env.NODE_ENV === 'production') {
    return (
      liveKey ||
      (isLiveStripeApiKey(generic) ? generic : undefined) ||
      testKey ||
      (isTestStripeApiKey(generic) ? generic : undefined) ||
      ''
    );
  }

  return (
    testKey ||
    (isTestStripeApiKey(generic) ? generic : undefined) ||
    (isLiveStripeApiKey(generic) ? generic : undefined) ||
    liveKey ||
    ''
  );
}

let defaultClient: Stripe | null = null;

/**
 * Default Stripe SDK client for API calls (checkout, Connect, etc.).
 * Do not call at module load time if the process should boot without Stripe keys;
 * call from route handlers or lazy helpers so missing env fails on first use only.
 */
export function getDefaultStripeClient(): Stripe {
  const k = getDefaultStripeSecretKey();
  if (!k) {
    throw new Error(
      'Stripe not configured: set STRIPE_SECRET_KEY and/or split keys, or APP_NETWORK_MODE=testnet|mainnet with STRIPE_TEST_SECRET_KEY / STRIPE_LIVE_SECRET_KEY (see src/config/app-network.ts)'
    );
  }
  if (!defaultClient) {
    defaultClient = getStripeClient(k);
  }
  return defaultClient;
}

/**
 * Clear cached default client (e.g. tests).
 */
export function resetDefaultStripeClientCache(): void {
  defaultClient = null;
}
