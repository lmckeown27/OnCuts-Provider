import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { logger } from '../utils/logger';

function keypairFromSecret(trimmed: string, envLabel: string): Ed25519Keypair {
  try {
    if (trimmed.startsWith('suiprivkey')) {
      return Ed25519Keypair.fromSecretKey(trimmed);
    }
    const hex = trimmed.replace(/^0x/, '');
    if (/^[0-9a-fA-F]{64}$/.test(hex)) {
      return Ed25519Keypair.fromSecretKey(Buffer.from(hex, 'hex'));
    }
  } catch (e) {
    logger.error(`Failed to parse ${envLabel}`, e);
  }
  throw new Error(`${envLabel} must be suiprivkey… or 64-char hex`);
}

/**
 * Gas sponsor keypair for Sui sponsored transactions (GasData pattern).
 * Barbers receive full USDC; platform pays SUI gas.
 *
 * Resolution order: `GAS_SPONSOR_SECRET` (dedicated gas wallet), then `SUI_TREASURY_SECRET`
 * (treasury pays gas), then `SUI_TREASURY_SIGNER_SECRET`.
 *
 * @see https://docs.sui.io/concepts/transactions/sponsored-transactions
 */
export function getGasSponsorKeypair(): Ed25519Keypair {
  const gas = process.env.GAS_SPONSOR_SECRET?.trim();
  if (gas) {
    return keypairFromSecret(gas, 'GAS_SPONSOR_SECRET');
  }
  const treasurySecret = process.env.SUI_TREASURY_SECRET?.trim();
  if (treasurySecret) {
    return keypairFromSecret(treasurySecret, 'SUI_TREASURY_SECRET');
  }
  const treasurySigner = process.env.SUI_TREASURY_SIGNER_SECRET?.trim();
  if (treasurySigner) {
    return keypairFromSecret(treasurySigner, 'SUI_TREASURY_SIGNER_SECRET');
  }
  throw new Error(
    'Configure GAS_SPONSOR_SECRET and/or SUI_TREASURY_SECRET and/or SUI_TREASURY_SIGNER_SECRET. ' +
      'The relayer needs at least one key for gas; use GAS_SPONSOR_SECRET if gas wallet differs from treasury.'
  );
}

/**
 * Placeholder: build sponsored transaction bytes with sponsor GasData.
 * Wire to your Move USDC package + Transaction builder when contracts are deployed.
 */
export async function sponsorTransactionStub(_txDescription: string): Promise<{ digest: string }> {
  logger.debug('sui-gas-sponsor: sponsorTransactionStub (implement with PTB + gasStation)');
  return { digest: '0x0' };
}
