import { Queue, Worker, type Job } from 'bullmq';
import { normalizeSuiAddress, isValidSuiAddress } from '@mysten/sui/utils';
import { query } from '../database/connection';
import { logger } from '../utils/logger';

export const PAYOUT_QUEUE_NAME = 'process-payout';

export interface ProcessPayoutJobData {
  barberSuiAddress: string;
  /** USDC base units (6 decimals), decimal string to avoid JSON bigint issues */
  amountBaseUnits: string;
  bookingId: string;
  stripeCheckoutSessionId: string;
  /** Stripe PaymentIntent id — idempotency + `payments.path_b_sui_tx_digest` */
  paymentIntentId: string;
}

function connectionOptions() {
  return { url: process.env.REDIS_URL || 'redis://127.0.0.1:6379' };
}

export const payoutQueue = new Queue(PAYOUT_QUEUE_NAME, {
  connection: connectionOptions(),
  defaultJobOptions: {
    removeOnComplete: 500,
    removeOnFail: 5000,
    attempts: 3,
    backoff: { type: 'exponential', delay: 2000 },
  },
});

let payoutWorker: Worker<ProcessPayoutJobData> | null = null;

/**
 * Enqueue DIY Sui relayer payout. Concurrency 1 on the worker avoids treasury object version clashes.
 */
export async function enqueueProcessPayout(data: ProcessPayoutJobData): Promise<void> {
  const barber = normalizeSuiAddress(data.barberSuiAddress);
  if (!isValidSuiAddress(barber)) {
    throw new Error(`Invalid barber Sui address: ${data.barberSuiAddress}`);
  }
  await payoutQueue.add(
    'split',
    { ...data, barberSuiAddress: barber },
    { jobId: `checkout-${data.stripeCheckoutSessionId}` }
  );
  logger.info('process-payout: job enqueued', {
    bookingId: data.bookingId,
    sessionId: data.stripeCheckoutSessionId,
  });
}

async function runPayoutJob(job: Job<ProcessPayoutJobData>): Promise<{ digest: string }> {
  const { barberSuiAddress, amountBaseUnits, bookingId, stripeCheckoutSessionId, paymentIntentId } =
    job.data;

  if (paymentIntentId) {
    const dup = await query(
      `SELECT path_b_sui_tx_digest FROM payments WHERE payment_intent_id = $1 AND path_b_sui_tx_digest IS NOT NULL`,
      [paymentIntentId]
    );
    if (dup.rows[0]?.path_b_sui_tx_digest) {
      logger.info('process-payout: idempotent skip (payment already has Sui digest)', {
        paymentIntentId,
        digest: dup.rows[0].path_b_sui_tx_digest,
      });
      return { digest: dup.rows[0].path_b_sui_tx_digest };
    }
  }

  const payoutV2 = (await import('../services/payout-v2.service')).default;
  const { digest } = await payoutV2.executeSuiOnChainUsdcPayout({
    barberSuiAddress,
    amountBaseUnits,
    bookingId,
    paymentIntentId: paymentIntentId || '',
  });

  await query(
    `UPDATE bookings SET bridge_payout_id = $1, on_chain_settlement_status = $2, "updatedAt" = NOW() WHERE id = $3`,
    [`diy-${digest}`, 'completed', bookingId]
  );
  logger.info('process-payout: relayer success', {
    digest,
    bookingId,
    sessionId: stripeCheckoutSessionId,
  });
  return { digest };
}

export function startPayoutWorker(): Worker<ProcessPayoutJobData> {
  if (payoutWorker) {
    return payoutWorker;
  }
  payoutWorker = new Worker<ProcessPayoutJobData>(
    PAYOUT_QUEUE_NAME,
    async (job) => runPayoutJob(job),
    { connection: connectionOptions(), concurrency: 1 }
  );
  payoutWorker.on('failed', (job, err) => {
    logger.error('process-payout: job failed', {
      jobId: job?.id,
      bookingId: job?.data?.bookingId,
      err: err?.message,
    });
    const maxAttempts = job?.opts?.attempts ?? 1;
    if (job && job.attemptsMade >= maxAttempts && job.data?.bookingId) {
      query(
        `UPDATE bookings SET on_chain_settlement_status = $1, "updatedAt" = NOW() WHERE id = $2`,
        ['relayer_failed', job.data.bookingId]
      ).catch((e) => logger.error('process-payout: could not mark booking relayer_failed', e));
    }
  });
  payoutWorker.on('completed', (job) => {
    logger.info('process-payout: job completed', { jobId: job.id, bookingId: job.data.bookingId });
  });
  logger.info('process-payout: worker started (concurrency: 1)');
  return payoutWorker;
}

export async function closePayoutInfrastructure(): Promise<void> {
  if (payoutWorker) {
    await payoutWorker.close();
    payoutWorker = null;
  }
  await payoutQueue.close();
}
