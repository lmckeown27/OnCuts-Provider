import { SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { normalizeSuiAddress, isValidSuiAddress } from '@mysten/sui/utils';
import { v4 as uuidv4 } from 'uuid';
import { getEffectiveUsdcCoinType } from '../config/blockchain';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { fetchExternalSponsorSignature, isExternalGasSponsorConfigured } from './sui-external-sponsor.service';
import { getGasSponsorKeypair } from './sui-gas-sponsor.service';

const BARBER_SHARE_BP = 8000n; // 80.00%
const BP_DENOM = 10000n;
const MAX_ATTEMPTS = 3;
/** MIST. ~0.01 SUI — ample headroom for merge + split + transfers; paid from gas owner / treasury. */
const DEFAULT_GAS_BUDGET = 10_000_000n;
const GET_COINS_PAGE_LIMIT = 100;

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function loadKeypairFromEnv(secretName: string): Ed25519Keypair {
  const secret = process.env[secretName];
  if (!secret?.trim()) {
    throw new Error(`${secretName} is not configured`);
  }
  const trimmed = secret.trim();
  if (trimmed.startsWith('suiprivkey')) {
    return Ed25519Keypair.fromSecretKey(trimmed);
  }
  const hex = trimmed.replace(/^0x/, '');
  if (/^[0-9a-fA-F]{64}$/.test(hex)) {
    return Ed25519Keypair.fromSecretKey(Buffer.from(hex, 'hex'));
  }
  throw new Error(`${secretName} must be suiprivkey… or 64-char hex`);
}

/**
 * Total USDC across treasury coins is below the payout.
 * Use for dashboard alerts / Stripe webhook handling.
 */
export class InsufficientTreasuryFundsError extends Error {
  readonly name = 'InsufficientTreasuryFundsError';
  constructor(
    readonly totalAvailable: bigint,
    readonly required: bigint
  ) {
    super(
      `InsufficientTreasuryFundsError: treasury USDC total ${totalAvailable} < required ${required} (base units)`
    );
  }
}

/**
 * Signs USDC splits from treasury. Falls back to `SUI_TREASURY_SECRET`, then gas sponsor chain.
 */
function getTreasurySignerKeypair(): Ed25519Keypair {
  if (process.env.SUI_TREASURY_SIGNER_SECRET?.trim()) {
    return loadKeypairFromEnv('SUI_TREASURY_SIGNER_SECRET');
  }
  if (process.env.SUI_TREASURY_SECRET?.trim()) {
    return loadKeypairFromEnv('SUI_TREASURY_SECRET');
  }
  return getGasSponsorKeypair();
}

type SuiCoinItem = { coinObjectId: string; balance: string; coinType?: string };

/** Narrow shape from `getCoins` pagination (explicit type avoids TS circular inference on `page`). */
type PaginatedCoinsPage = {
  data?: SuiCoinItem[];
  hasNextPage: boolean;
  nextCursor?: string | null;
};

/**
 * DIY payout relayer: merge all treasury USDC coins into the largest, then atomic 80/20 split + transfers.
 *
 * `totalAmount` = amount to split in coin base units (e.g. USDC 6 decimals).
 */
export class SuiRelayerService {
  private client: SuiClient | null = null;

  private getClient(): SuiClient {
    if (!this.client) {
      const url = process.env.SUI_RPC_URL?.trim();
      if (!url) {
        throw new Error('SUI_RPC_URL is required for SuiRelayerService');
      }
      this.client = new SuiClient({ url });
    }
    return this.client;
  }

  /** Address whose Coin<USDC> objects we scan (must match treasury signer). */
  private getTreasuryAddress(): string {
    const raw = process.env.SUI_TREASURY_ADDRESS?.trim();
    if (!raw || !isValidSuiAddress(normalizeSuiAddress(raw))) {
      throw new Error('SUI_TREASURY_ADDRESS must be set to a valid Sui address for dynamic coin selection');
    }
    return normalizeSuiAddress(raw);
  }

  private getUsdcCoinType(): string {
    return getEffectiveUsdcCoinType();
  }

  private assertTreasurySignerOwnsTreasuryAddress(): void {
    const expected = this.getTreasuryAddress();
    const signer = normalizeSuiAddress(getTreasurySignerKeypair().toSuiAddress());
    if (signer !== expected) {
      throw new Error(
        `Treasury signer address ${signer} must equal SUI_TREASURY_ADDRESS ${expected} (signer must own the scanned coins)`
      );
    }
  }

  /**
   * Paginated suix_getCoins for treasury + USDC type.
   */
  private async fetchAllTreasuryUsdcCoins(): Promise<SuiCoinItem[]> {
    const client = this.getClient();
    const owner = this.getTreasuryAddress();
    const coinType = this.getUsdcCoinType();
    const out: SuiCoinItem[] = [];
    let cursor: string | null | undefined = null;

    do {
      const page: PaginatedCoinsPage = await client.getCoins({
        owner,
        coinType,
        cursor: cursor ?? undefined,
        limit: GET_COINS_PAGE_LIMIT,
      });
      const batch = (page.data ?? []) as SuiCoinItem[];
      out.push(...batch);
      cursor = page.hasNextPage ? page.nextCursor ?? null : null;
    } while (cursor);

    return out;
  }

  private getPlatformAddress(): string {
    const raw =
      process.env.SUI_PLATFORM_PAYOUT_ADDRESS?.trim() ||
      process.env.SUI_TREASURY_ADDRESS?.trim() ||
      '';
    if (!raw || !isValidSuiAddress(normalizeSuiAddress(raw))) {
      throw new Error('SUI_PLATFORM_PAYOUT_ADDRESS or SUI_TREASURY_ADDRESS must be a valid Sui address');
    }
    return normalizeSuiAddress(raw);
  }

  /**
   * PTB: merge all USDC coins into the largest balance, split 80/20, transfer to barber + platform.
   */
  private buildSplitPayoutTx(barberAddress: string, totalAmount: bigint, coins: SuiCoinItem[]): Transaction {
    const platform = this.getPlatformAddress();
    const barber = normalizeSuiAddress(barberAddress);
    if (!isValidSuiAddress(barber)) {
      throw new Error(`Invalid barberAddress: ${barberAddress}`);
    }
    if (totalAmount <= 0n) {
      throw new Error('totalAmount must be positive');
    }
    if (coins.length === 0) {
      throw new InsufficientTreasuryFundsError(0n, totalAmount);
    }

    const sorted = [...coins].sort((a, b) => {
      const db = BigInt(b.balance);
      const da = BigInt(a.balance);
      if (db > da) return 1;
      if (db < da) return -1;
      return 0;
    });

    const totalAvailable = sorted.reduce((sum, c) => sum + BigInt(c.balance), 0n);
    if (totalAvailable < totalAmount) {
      throw new InsufficientTreasuryFundsError(totalAvailable, totalAmount);
    }

    const barberAmount = (totalAmount * BARBER_SHARE_BP) / BP_DENOM;
    const platformAmount = totalAmount - barberAmount;
    if (barberAmount <= 0n || platformAmount <= 0n) {
      throw new Error('totalAmount too small for 80/20 split in base units');
    }

    const treasurySigner = getTreasurySignerKeypair();
    const sponsorSigner = getGasSponsorKeypair();
    const treasuryAddr = treasurySigner.toSuiAddress();
    const sponsorAddr = sponsorSigner.toSuiAddress();

    const tx = new Transaction();
    tx.setSender(treasuryAddr);

    if (normalizeSuiAddress(sponsorAddr) !== normalizeSuiAddress(treasuryAddr)) {
      tx.setGasOwner(sponsorAddr);
    }

    tx.setGasBudget(DEFAULT_GAS_BUDGET);

    const primaryId = normalizeSuiAddress(sorted[0].coinObjectId);
    const primary = tx.object(primaryId);

    if (sorted.length > 1) {
      const sources = sorted.slice(1).map((c) => tx.object(normalizeSuiAddress(c.coinObjectId)));
      tx.mergeCoins(primary, sources);
    }

    const [toBarber, toPlatform] = tx.splitCoins(primary, [barberAmount, platformAmount]);

    tx.transferObjects([toBarber], barber);
    tx.transferObjects([toPlatform], platform);

    logger.info('SuiRelayer: built merge+split PTB', {
      coinCount: sorted.length,
      totalAvailable: totalAvailable.toString(),
      payout: totalAmount.toString(),
    });

    return tx;
  }

  /**
   * PTB: merge treasury USDC, split `amount` to a single recipient (no platform leg).
   * Used for direct treasury payouts where the ledger already reflects the debit.
   */
  private buildDirectTreasuryUsdcTransferTx(
    recipientAddress: string,
    amount: bigint,
    coins: SuiCoinItem[]
  ): Transaction {
    const recipient = normalizeSuiAddress(recipientAddress);
    if (!isValidSuiAddress(recipient)) {
      throw new Error(`Invalid recipientAddress: ${recipientAddress}`);
    }
    if (amount <= 0n) {
      throw new Error('amount must be positive');
    }
    if (coins.length === 0) {
      throw new InsufficientTreasuryFundsError(0n, amount);
    }

    const sorted = [...coins].sort((a, b) => {
      const db = BigInt(b.balance);
      const da = BigInt(a.balance);
      if (db > da) return 1;
      if (db < da) return -1;
      return 0;
    });

    const totalAvailable = sorted.reduce((sum, c) => sum + BigInt(c.balance), 0n);
    if (totalAvailable < amount) {
      throw new InsufficientTreasuryFundsError(totalAvailable, amount);
    }

    const treasurySigner = getTreasurySignerKeypair();
    const sponsorSigner = getGasSponsorKeypair();
    const treasuryAddr = treasurySigner.toSuiAddress();
    const sponsorAddr = sponsorSigner.toSuiAddress();

    const tx = new Transaction();
    tx.setSender(treasuryAddr);

    if (normalizeSuiAddress(sponsorAddr) !== normalizeSuiAddress(treasuryAddr)) {
      tx.setGasOwner(sponsorAddr);
    }

    tx.setGasBudget(DEFAULT_GAS_BUDGET);

    const primaryId = normalizeSuiAddress(sorted[0].coinObjectId);
    const primary = tx.object(primaryId);

    if (sorted.length > 1) {
      const sources = sorted.slice(1).map((c) => tx.object(normalizeSuiAddress(c.coinObjectId)));
      tx.mergeCoins(primary, sources);
    }

    const [toRecipient] = tx.splitCoins(primary, [amount]);
    tx.transferObjects([toRecipient], recipient);

    logger.info('SuiRelayer: built direct USDC transfer PTB', {
      coinCount: sorted.length,
      totalAvailable: totalAvailable.toString(),
      transferAmount: amount.toString(),
    });

    return tx;
  }

  private async signAndExecute(tx: Transaction): Promise<{ digest: string; effects?: unknown }> {
    const client = this.getClient();
    const treasurySigner = getTreasurySignerKeypair();

    const sponsorSigner = getGasSponsorKeypair();
    const treasuryAddr = normalizeSuiAddress(treasurySigner.toSuiAddress());
    const sponsorAddr = normalizeSuiAddress(sponsorSigner.toSuiAddress());

    const bytes = await tx.build({ client });

    const treasurySig = await treasurySigner.signTransaction(bytes);

    let signatures: string[];
    if (isExternalGasSponsorConfigured()) {
      const sponsorSig = await fetchExternalSponsorSignature(bytes);
      signatures = [treasurySig.signature, sponsorSig];
    } else if (sponsorAddr === treasuryAddr) {
      signatures = [treasurySig.signature];
    } else {
      signatures = [treasurySig.signature, (await sponsorSigner.signTransaction(bytes)).signature];
    }

    const result = await client.executeTransactionBlock({
      transactionBlock: bytes,
      signature: signatures,
      options: {
        showEffects: true,
        showObjectChanges: true,
        showEvents: true,
      },
      requestType: 'WaitForLocalExecution',
    });

    const digest = result.digest;
    const status = result.effects?.status?.status;
    if (status !== 'success') {
      const err =
        result.effects?.status && 'error' in result.effects.status
          ? String((result.effects.status as { error?: unknown }).error)
          : 'execution failed';
      logger.error('SuiRelayer: transaction executed with non-success status', { digest, err, effects: result.effects });
      const e = new Error(`Sui transaction failed: ${err}`);
      (e as Error & { digest?: string }).digest = digest;
      throw e;
    }

    return { digest, effects: result.effects };
  }

  private async persistFailureAlert(params: {
    barberAddress: string;
    totalAmount: bigint;
    digest?: string;
    attempts: number;
    errorMessage: string;
  }): Promise<void> {
    try {
      await pool.query(
        `INSERT INTO ai_events_log (event_type, entity_type, entity_id, payload, processing_status, error, created_at)
         VALUES ($1, $2, $3, $4::jsonb, $5, $6, NOW())`,
        [
          'sui_relayer_payout_failed',
          'payout',
          uuidv4(),
          JSON.stringify({
            barberAddress: params.barberAddress,
            totalAmount: params.totalAmount.toString(),
            digest: params.digest ?? null,
            attempts: params.attempts,
          }),
          'failed',
          params.errorMessage,
        ]
      );
      logger.warn('SuiRelayer: failure recorded in ai_events_log', { digest: params.digest });
    } catch (dbErr) {
      logger.error('SuiRelayer: could not write ai_events_log', dbErr);
    }
  }

  private async persistTreasuryAlert(params: {
    barberAddress: string;
    totalAmount: bigint;
    error: Error;
  }): Promise<void> {
    try {
      await pool.query(
        `INSERT INTO ai_events_log (event_type, entity_type, entity_id, payload, processing_status, error, created_at)
         VALUES ($1, $2, $3, $4::jsonb, $5, $6, NOW())`,
        [
          'sui_relayer_insufficient_treasury',
          'payout',
          uuidv4(),
          JSON.stringify({
            barberAddress: params.barberAddress,
            totalAmount: params.totalAmount.toString(),
            treasuryAddress: this.getTreasuryAddress(),
          }),
          'failed',
          params.error.message,
        ]
      );
    } catch (dbErr) {
      logger.error('SuiRelayer: could not write treasury alert to ai_events_log', dbErr);
    }
  }

  /**
   * Execute merge + 80/20 USDC split; coins resolved dynamically each attempt.
   */
  async executeSplitPayout(barberAddress: string, totalAmount: number | bigint): Promise<{ digest: string }> {
    const total = typeof totalAmount === 'bigint' ? totalAmount : BigInt(Math.floor(Number(totalAmount)));
    this.assertTreasurySignerOwnsTreasuryAddress();

    let lastDigest: string | undefined;
    let lastError = '';

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const coins = await this.fetchAllTreasuryUsdcCoins();
      const totalAvailable = coins.reduce((sum, c) => sum + BigInt(c.balance), 0n);
      if (totalAvailable < total) {
        const e = new InsufficientTreasuryFundsError(totalAvailable, total);
        await this.persistTreasuryAlert({ barberAddress, totalAmount: total, error: e });
        throw e;
      }

      try {
        const tx = this.buildSplitPayoutTx(barberAddress, total, coins);
        const builtDigest = await tx.getDigest({ client: this.getClient() }).catch(() => undefined);
        logger.info('SuiRelayer: submitting merge+split payout', {
          attempt,
          barberAddress: normalizeSuiAddress(barberAddress),
          totalAmount: total.toString(),
          dryDigest: builtDigest,
        });

        const { digest } = await this.signAndExecute(tx);
        logger.info('SuiRelayer: split payout success', { digest, attempt });
        return { digest };
      } catch (err: unknown) {
        const e = err as Error & { digest?: string };
        lastError = e.message || String(err);
        lastDigest = e.digest ?? lastDigest;

        if (typeof (err as { digest?: string })?.digest === 'string') {
          lastDigest = (err as { digest: string }).digest;
        }

        logger.error('SuiRelayer: attempt failed', {
          attempt,
          digest: lastDigest,
          message: lastError,
        });

        if (attempt < MAX_ATTEMPTS) {
          await sleep(400 * 2 ** (attempt - 1));
        }
      }
    }

    await this.persistFailureAlert({
      barberAddress,
      totalAmount: total,
      digest: lastDigest,
      attempts: MAX_ATTEMPTS,
      errorMessage: lastError,
    });

    throw new Error(
      `SuiRelayer: executeSplitPayout failed after ${MAX_ATTEMPTS} attempts (last digest: ${lastDigest ?? 'none'}): ${lastError}`
    );
  }

  /**
   * Send `amount` USDC base units from treasury to `recipientAddress` (single-output transfer).
   */
  async executeDirectTreasuryUsdcTransfer(
    recipientAddress: string,
    amount: number | bigint
  ): Promise<{ digest: string }> {
    const total = typeof amount === 'bigint' ? amount : BigInt(Math.floor(Number(amount)));
    this.assertTreasurySignerOwnsTreasuryAddress();

    let lastDigest: string | undefined;
    let lastError = '';

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const coins = await this.fetchAllTreasuryUsdcCoins();
      const totalAvailable = coins.reduce((sum, c) => sum + BigInt(c.balance), 0n);
      if (totalAvailable < total) {
        const e = new InsufficientTreasuryFundsError(totalAvailable, total);
        await this.persistTreasuryAlert({ barberAddress: recipientAddress, totalAmount: total, error: e });
        throw e;
      }

      try {
        const tx = this.buildDirectTreasuryUsdcTransferTx(recipientAddress, total, coins);
        const builtDigest = await tx.getDigest({ client: this.getClient() }).catch(() => undefined);
        logger.info('SuiRelayer: submitting direct USDC transfer', {
          attempt,
          recipientAddress: normalizeSuiAddress(recipientAddress),
          amount: total.toString(),
          dryDigest: builtDigest,
        });

        const { digest } = await this.signAndExecute(tx);
        logger.info('SuiRelayer: direct USDC transfer success', { digest, attempt });
        return { digest };
      } catch (err: unknown) {
        const e = err as Error & { digest?: string };
        lastError = e.message || String(err);
        lastDigest = e.digest ?? lastDigest;

        if (typeof (err as { digest?: string })?.digest === 'string') {
          lastDigest = (err as { digest: string }).digest;
        }

        logger.error('SuiRelayer: direct transfer attempt failed', {
          attempt,
          digest: lastDigest,
          message: lastError,
        });

        if (attempt < MAX_ATTEMPTS) {
          await sleep(400 * 2 ** (attempt - 1));
        }
      }
    }

    await this.persistFailureAlert({
      barberAddress: recipientAddress,
      totalAmount: total,
      digest: lastDigest,
      attempts: MAX_ATTEMPTS,
      errorMessage: lastError,
    });

    throw new Error(
      `SuiRelayer: executeDirectTreasuryUsdcTransfer failed after ${MAX_ATTEMPTS} attempts (last digest: ${lastDigest ?? 'none'}): ${lastError}`
    );
  }
}

export default new SuiRelayerService();
