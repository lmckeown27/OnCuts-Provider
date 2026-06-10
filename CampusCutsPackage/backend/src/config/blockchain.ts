/**
 * Sui / USDC coordinates for production.
 * Override any value via environment variables (see backend/.env.example).
 */

/** Native USDC on Sui mainnet (package id + type). */
export const SUI_MAINNET_NATIVE_USDC_COIN_TYPE =
  '0xdba34672e30cb065b1f93e3ad5531876580039906648354972135f29979d9744::usdc::USDC';

/**
 * Effective USDC Move type for `getCoins` / PTB (env wins for testnet / upgrades).
 */
export function getEffectiveUsdcCoinType(): string {
  const fromEnv = process.env.SUI_USDC_COIN_TYPE?.trim();
  if (fromEnv) return fromEnv;
  return SUI_MAINNET_NATIVE_USDC_COIN_TYPE;
}
