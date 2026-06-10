/**
 * Withdrawal Batch Service
 * 
 * Queues and batches on-chain withdrawals for gas efficiency.
 * 
 * Cost comparison:
 * - Individual withdrawals: 1000 × $0.001 = $1.00
 * - Batched withdrawals: 1 batch = $0.002
 * - Savings: 99.8%!
 * 
 * Process:
 * 1. User requests withdrawal → queued
 * 2. Background job batches withdrawals every N minutes
 * 3. Single on-chain transaction sends to multiple recipients
 * 4. Mark all as completed
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';
import transactionService, { TransactionType, TransactionStatus } from './transaction.service';
import suiChainService from './sui-chain.service';
import auditService from './audit.service';
import gasCalculatorService from './gas-calculator.service';

export enum WithdrawalStatus {
  QUEUED = 'queued',
  BATCHED = 'batched',
  PROCESSING = 'processing',
  COMPLETED = 'completed',
  FAILED = 'failed'
}

export enum DestinationType {
  BANK = 'bank',
  ONCHAIN = 'onchain'
}

export interface WithdrawalQueueItem {
  id: number;
  user_id: string;
  transaction_id: number;
  amount: number;  // cents
  destination_type: DestinationType;
  destination_address?: string;
  chain?: string;
  status: WithdrawalStatus;
  batch_id?: string;
  queued_at: Date;
  processed_at?: Date;
  failure_reason?: string;
}

export interface WithdrawalBatch {
  id: string;
  chain: string;
  total_amount: number;
  withdrawal_count: number;
  tx_hash?: string;
  status: string;
  created_at: Date;
  submitted_at?: Date;
  confirmed_at?: Date;
  gas_used?: number;
  failure_reason?: string;
}

export interface QueueWithdrawalInput {
  user_id: string;
  amount: number;  // cents
  destination_type: DestinationType;
  destination_address?: string;
  chain?: string;
}

class WithdrawalBatchService {
  /**
   * Queue a withdrawal for batching
   */
  async queueWithdrawal(input: QueueWithdrawalInput): Promise<WithdrawalQueueItem> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Create withdrawal transaction (debit user's available balance)
      const transaction = await transactionService.createTransaction({
        user_id: input.user_id,
        type: input.destination_type === DestinationType.ONCHAIN 
          ? TransactionType.ONCHAIN_WITHDRAWAL 
          : TransactionType.PAYOUT,
        amount: -input.amount,  // Debit
        status: TransactionStatus.PENDING,
        metadata: {
          destination_type: input.destination_type,
          destination_address: input.destination_address,
          chain: input.chain,
        },
      });

      // 2. Add to withdrawal queue
      const queueResult = await client.query(
        `INSERT INTO withdrawal_queue (
          user_id, transaction_id, amount, destination_type,
          destination_address, chain, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING *`,
        [
          input.user_id,
          transaction.id,
          input.amount,
          input.destination_type,
          input.destination_address || null,
          input.chain || null,
          WithdrawalStatus.QUEUED,
        ]
      );

      // 3. Audit log
      await auditService.log({
        actor_user_id: input.user_id,
        action: 'withdrawal_queued',
        object_type: 'withdrawal_queue',
        object_id: queueResult.rows[0].id.toString(),
        details: {
          amount_cents: input.amount,
          destination_type: input.destination_type,
          chain: input.chain,
        },
      });

      await client.query('COMMIT');

      logger.info('Withdrawal queued', {
        user_id: input.user_id,
        amount_dollars: input.amount / 100,
        destination_type: input.destination_type,
        queue_id: queueResult.rows[0].id,
      });

      return queueResult.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to queue withdrawal', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Process batched withdrawals (background job)
   * Should be run every 5-15 minutes via cron
   */
  async processBatch(chain: string = 'sui', minBatchSize: number = 1): Promise<WithdrawalBatch | null> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Get queued on-chain withdrawals for this chain
      const queuedResult = await client.query(
        `SELECT * FROM withdrawal_queue
         WHERE status = $1
           AND destination_type = $2
           AND chain = $3
         ORDER BY queued_at ASC
         FOR UPDATE`,
        [WithdrawalStatus.QUEUED, DestinationType.ONCHAIN, chain]
      );

      const queued = queuedResult.rows;

      if (queued.length < minBatchSize) {
        await client.query('ROLLBACK');
        logger.info(`Not enough queued withdrawals for batch (${queued.length} < ${minBatchSize})`);
        return null;
      }

      // 2. Create batch record
      const batchId = this.generateBatchId();
      const totalAmount = queued.reduce((sum, w) => sum + parseInt(w.amount), 0);

      const batchResult = await client.query(
        `INSERT INTO withdrawal_batches (
          id, chain, total_amount, withdrawal_count, status
        )
        VALUES ($1, $2, $3, $4, $5)
        RETURNING *`,
        [
          batchId,
          chain,
          totalAmount,
          queued.length,
          'pending',
        ]
      );

      const batch: WithdrawalBatch = batchResult.rows[0];

      // 3. Mark withdrawals as batched
      const withdrawalIds = queued.map(w => w.id);
      await client.query(
        `UPDATE withdrawal_queue
         SET status = $1, batch_id = $2
         WHERE id = ANY($3::bigint[])`,
        [WithdrawalStatus.BATCHED, batchId, withdrawalIds]
      );

      await client.query('COMMIT');

      // 4. Submit batch to blockchain (outside transaction)
      try {
        const txHash = await this.submitBatchToChain(chain, queued);

        // 5. Update batch with tx hash
        await pool.query(
          `UPDATE withdrawal_batches
           SET status = 'submitted', tx_hash = $1, submitted_at = NOW()
           WHERE id = $2`,
          [txHash, batchId]
        );

        // 6. Wait for confirmation and mark complete
        await this.confirmBatch(batchId, txHash);

        logger.info('Batch processed successfully', {
          batch_id: batchId,
          chain,
          withdrawal_count: queued.length,
          total_dollars: totalAmount / 100,
          tx_hash: txHash,
        });

        return batch;
      } catch (error: any) {
        // Mark batch as failed
        await pool.query(
          `UPDATE withdrawal_batches
           SET status = 'failed', failure_reason = $1
           WHERE id = $2`,
          [error.message, batchId]
        );

        // Mark withdrawals as failed and refund
        await this.refundFailedBatch(batchId, error.message);

        throw error;
      }
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Batch processing failed', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Submit batch to blockchain
   */
  private async submitBatchToChain(chain: string, withdrawals: WithdrawalQueueItem[]): Promise<string> {
    if (chain !== 'sui') {
      throw new ApiError(400, `Unsupported chain: ${chain}`);
    }

    // Prepare recipients and amounts
    const recipients = withdrawals.map(w => w.destination_address);
    const amounts = withdrawals.map(w => w.amount);

    // Submit batch on-chain transaction (Sui when wired)
    // This requires a Move contract function like:
    // public entry fun batch_transfer(sender: &signer, recipients: vector<address>, amounts: vector<u64>)
    const txHash = await suiChainService.submitBatchWithdrawal(recipients, amounts);

    return txHash;
  }

  /**
   * Confirm batch and mark withdrawals as completed
   */
  private async confirmBatch(batchId: string, txHash: string): Promise<void> {
    try {
      // Wait for transaction confirmation (poll or webhook)
      // For now, assume immediate confirmation
      await new Promise(resolve => setTimeout(resolve, 3000));

      const client = await pool.connect();

      try {
        await client.query('BEGIN');

        // 1. Update batch status
        await client.query(
          `UPDATE withdrawal_batches
           SET status = 'confirmed', confirmed_at = NOW()
           WHERE id = $1`,
          [batchId]
        );

        // 2. Mark all withdrawals as completed
        await client.query(
          `UPDATE withdrawal_queue
           SET status = $1, processed_at = NOW()
           WHERE batch_id = $2`,
          [WithdrawalStatus.COMPLETED, batchId]
        );

        // 3. Mark related transactions as completed
        await client.query(
          `UPDATE transactions t
           SET status = 'completed', completed_at = NOW()
           FROM withdrawal_queue wq
           WHERE wq.batch_id = $1
             AND t.id = wq.transaction_id`,
          [batchId]
        );

        await client.query('COMMIT');

        logger.info('Batch confirmed', {
          batch_id: batchId,
          tx_hash: txHash,
        });
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error) {
      logger.error('Failed to confirm batch', { batch_id: batchId, error });
      throw error;
    }
  }

  /**
   * Refund failed batch (credit back to users)
   */
  private async refundFailedBatch(batchId: string, reason: string): Promise<void> {
    const withdrawals = await pool.query(
      `SELECT * FROM withdrawal_queue WHERE batch_id = $1`,
      [batchId]
    );

    for (const withdrawal of withdrawals.rows) {
      try {
        // Create refund transaction
        await transactionService.createTransaction({
          user_id: withdrawal.user_id,
          type: TransactionType.ADJUSTMENT,
          amount: withdrawal.amount,  // Credit back
          metadata: {
            reason: 'withdrawal_failed',
            original_queue_id: withdrawal.id,
            batch_id: batchId,
            failure_reason: reason,
          },
        });

        // Mark withdrawal as failed
        await pool.query(
          `UPDATE withdrawal_queue
           SET status = $1, failure_reason = $2, processed_at = NOW()
           WHERE id = $3`,
          [WithdrawalStatus.FAILED, reason, withdrawal.id]
        );

        logger.info('Withdrawal refunded due to batch failure', {
          user_id: withdrawal.user_id,
          amount_dollars: withdrawal.amount / 100,
          batch_id: batchId,
        });
      } catch (error) {
        logger.error('Failed to refund withdrawal', {
          withdrawal_id: withdrawal.id,
          error,
        });
      }
    }
  }

  /**
   * Get queued withdrawals for a user
   */
  async getUserWithdrawals(userId: string): Promise<WithdrawalQueueItem[]> {
    const result = await pool.query(
      `SELECT * FROM withdrawal_queue
       WHERE user_id = $1
       ORDER BY queued_at DESC`,
      [userId]
    );

    return result.rows;
  }

  /**
   * Get batch status
   */
  async getBatchStatus(batchId: string): Promise<WithdrawalBatch | null> {
    const result = await pool.query(
      `SELECT * FROM withdrawal_batches WHERE id = $1`,
      [batchId]
    );

    return result.rows[0] || null;
  }

  /**
   * Get stats
   */
  async getStats(): Promise<{
    queued_count: number;
    queued_total_cents: number;
    processing_count: number;
    completed_today: number;
  }> {
    const result = await pool.query(`
      SELECT
        COUNT(*) FILTER (WHERE status = 'queued') as queued_count,
        COALESCE(SUM(amount) FILTER (WHERE status = 'queued'), 0) as queued_total_cents,
        COUNT(*) FILTER (WHERE status IN ('batched', 'processing')) as processing_count,
        COUNT(*) FILTER (WHERE status = 'completed' AND processed_at > CURRENT_DATE) as completed_today
      FROM withdrawal_queue
    `);

    return result.rows[0];
  }

  /**
   * Generate unique batch ID
   */
  private generateBatchId(): string {
    const timestamp = Date.now();
    const random = Math.random().toString(36).substring(2, 8);
    return `BATCH-${timestamp}-${random}`;
  }
}

export default new WithdrawalBatchService();

