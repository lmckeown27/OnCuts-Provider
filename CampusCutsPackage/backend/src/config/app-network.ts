/**
 * Single switch for test stack vs live stack: Stripe test/live keys + Sui RPC + USDC type defaults.
 *
 * Set `APP_NETWORK_MODE=testnet` or `mainnet` (alias: `SUI_NETWORK` with the same values).
 * Omit or `APP_NETWORK_MODE=auto`: do not apply network defaults; use explicit env vars only.
 *
 * - Fills `SUI_RPC_URL` / `SUI_USDC_COIN_TYPE` only when unset (explicit env always wins).
 * - For Stripe API traffic only: when `STRIPE_MODE=auto`, maps testnet → test keys, mainnet → live keys.
 *   Explicit `STRIPE_MODE=test|live` always wins. Webhook key resolution is unchanged (uses event livemode).
 */

import { logger } from '../utils/logger';
import { SUI_MAINNET_NATIVE_USDC_COIN_TYPE } from './blockchain';

export const SUI_TESTNET_DEFAULT_RPC = 'https://fullnode.testnet.sui.io:443';
export const SUI_MAINNET_DEFAULT_RPC = 'https://fullnode.mainnet.sui.io:443';

/** Common Sui testnet USDC (Circle); override with SUI_USDC_COIN_TYPE if your deployment differs. */
export const SUI_TESTNET_DEFAULT_USDC_COIN_TYPE =
  '0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC';

export type AppNetworkMode = 'testnet' | 'mainnet';

/** null = switch not used (legacy: only explicit SUI_* / STRIPE_* env). */
export function resolveAppNetworkModeFromEnv(): AppNetworkMode | null {
  const raw = (process.env.APP_NETWORK_MODE || process.env.SUI_NETWORK || '').trim().toLowerCase();
  if (!raw || raw === 'auto') return null;
  if (raw === 'mainnet' || raw === 'live' || raw === 'production') return 'mainnet';
  if (raw === 'testnet' || raw === 'test' || raw === 'development') return 'testnet';
  logger.warn(`APP_NETWORK_MODE/SUI_NETWORK invalid value "${raw}" — ignoring`);
  return null;
}

/**
 * Apply default Sui RPC + USDC type when APP_NETWORK_MODE is set and vars are empty.
 * Call once at process startup after dotenv (see index.ts).
 */
export function applyAppNetworkModeDefaults(): void {
  const net = resolveAppNetworkModeFromEnv();
  if (!net) return;

  if (!process.env.SUI_RPC_URL?.trim()) {
    process.env.SUI_RPC_URL =
      net === 'mainnet' ? SUI_MAINNET_DEFAULT_RPC : SUI_TESTNET_DEFAULT_RPC;
    logger.info(`APP_NETWORK_MODE=${net}: defaulting SUI_RPC_URL=${process.env.SUI_RPC_URL}`);
  }

  if (!process.env.SUI_USDC_COIN_TYPE?.trim()) {
    process.env.SUI_USDC_COIN_TYPE =
      net === 'mainnet'
        ? SUI_MAINNET_NATIVE_USDC_COIN_TYPE
        : SUI_TESTNET_DEFAULT_USDC_COIN_TYPE;
    logger.info(`APP_NETWORK_MODE=${net}: defaulting SUI_USDC_COIN_TYPE for ${net}`);
  }
}

/**
 * When STRIPE_MODE=auto, prefer test vs live API keys from APP_NETWORK_MODE.
 * null = leave Stripe auto behavior to NODE_ENV (see getDefaultStripeSecretKey).
 */
export function stripeAutoModeFromAppNetwork(): 'test' | 'live' | null {
  const net = resolveAppNetworkModeFromEnv();
  if (net === 'testnet') return 'test';
  if (net === 'mainnet') return 'live';
  return null;
}
