/**
 * Temporary dev script: trigger the real Sui relayer (same executeSplitPayout as DIY payouts).
 * Isolates on-chain / treasury issues from Stripe webhooks.
 *
 * Run from repo root (CampusCuts/):
 *   npx ts-node backend/test-payout.ts
 *   bash scripts/test-payout-relayer.sh
 * Or from backend/:
 *   npx ts-node test-payout.ts
 *   npm run test:payout-relayer
 *
 * Args: [barberSuiAddress] [usdAmount] — or TEST_RELAYER_BARBER_ADDRESS / TEST_RELAYER_USD.
 * Env: loads repo-root `.env` if present, then `backend/.env` (overrides); else default dotenv (cwd).
 * You can also `export SUI_TREASURY_SECRET=...` or `GAS_SPONSOR_SECRET=...` before running.
 */

import fs from 'fs';
import dotenv from 'dotenv';
import path from 'path';

const backendEnvPath = path.join(__dirname, '.env');
const repoRootEnvPath = path.join(__dirname, '..', '.env');

if (fs.existsSync(repoRootEnvPath)) {
  dotenv.config({ path: repoRootEnvPath });
}
if (fs.existsSync(backendEnvPath)) {
  dotenv.config({ path: backendEnvPath, override: true });
}
if (!fs.existsSync(repoRootEnvPath) && !fs.existsSync(backendEnvPath)) {
  dotenv.config();
}

function hasRelayerSignerSecret(): boolean {
  return Boolean(
    process.env.GAS_SPONSOR_SECRET?.trim() ||
      process.env.SUI_TREASURY_SECRET?.trim() ||
      process.env.SUI_TREASURY_SIGNER_SECRET?.trim()
  );
}

if (!hasRelayerSignerSecret()) {
  const setOrUnset = (name: string): string =>
    process.env[name]?.trim() ? 'set' : 'unset';

  const wrongNames = ['GAS_SPONSOR_KEY', 'TREASURY_PRIVATE_KEY', 'SUI_PRIVATE_KEY'].filter(
    (k) => process.env[k]?.trim()
  );

  console.error(
    [
      'Missing Sui signer secret: set at least one of GAS_SPONSOR_SECRET, SUI_TREASURY_SECRET, SUI_TREASURY_SIGNER_SECRET.',
      `  backend/.env: ${backendEnvPath} — ${fs.existsSync(backendEnvPath) ? 'found' : 'not found'}`,
      `  repo root .env: ${repoRootEnvPath} — ${fs.existsSync(repoRootEnvPath) ? 'found' : 'not found'}`,
      '',
      'Add at least one line (same key + value as Railway / your live API). Examples:',
      '  SUI_TREASURY_SECRET=suiprivkey1q2w...   # treasury pays gas (common)',
      '  # or GAS_SPONSOR_SECRET=... / SUI_TREASURY_SIGNER_SECRET=...',
      '',
      `Sanity (names only): SUI_TREASURY_ADDRESS=${setOrUnset('SUI_TREASURY_ADDRESS')}, SUI_RPC_URL=${setOrUnset('SUI_RPC_URL')}`,
      ...(wrongNames.length
        ? [
            '',
            'These env vars are set but are NOT read by the relayer — copy the value into SUI_TREASURY_SECRET / GAS_SPONSOR_SECRET / SUI_TREASURY_SIGNER_SECRET:',
            ...wrongNames.map((k) => `  - ${k}`),
          ]
        : []),
      '',
      'Or: export SUI_TREASURY_SECRET=... in this shell, then run again.',
    ].join('\n')
  );
  process.exit(1);
}

import suiRelayerService from './src/services/sui-relayer.service';

const DEFAULT_BARBER =
  '0x3f493dc1c9e816873a735223735e7e8e39c400d0f3b4c8bc0d19103f494f7526';

async function main(): Promise<void> {
  const barber =
    process.env.TEST_RELAYER_BARBER_ADDRESS?.trim() ||
    process.argv[2]?.trim() ||
    DEFAULT_BARBER;

  const usdRaw = process.env.TEST_RELAYER_USD ?? process.argv[3] ?? '20';
  const usd = Number(usdRaw);
  if (!Number.isFinite(usd) || usd <= 0) {
    throw new Error(`Invalid USD amount: ${usdRaw}`);
  }
  const baseUnits = BigInt(Math.round(usd * 1e6));

  console.log('Manually triggering Sui relayer split payout...');
  console.log({ barber, usd, baseUnits: baseUnits.toString() });

  const { digest } = await suiRelayerService.executeSplitPayout(barber, baseUnits);
  console.log('Success', { digest });
}

void main().catch((e) => {
  console.error('Failed', e);
  process.exit(1);
});
