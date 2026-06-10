/**
 * Escrow Service
 * 
 * Handles booking payment holds and releases.
 * Core flow: Hold funds on booking → Release to barber on completion → Refund if cancelled
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';
import transactionService, { TransactionType, TransactionStatus } from './transaction.service';
import auditService from './audit.service';

export enum EscrowStatus {
  HELD = 'held',
  RELEASED = 'released',
  REFUNDED = 'refunded',
  EXPIRED = 'expired'
}

export interface EscrowHold {
  id: string;
  booking_id: string;
  consumer_id: string;
  barber_id: string;
  amount: number;  // cents
  currency: string;
  created_at: Date;
  expires_at: Date;
  onchain_tx_hash?: string;
  status: EscrowStatus;
  released_at?: Date;
  refunded_at?: Date;
}

export interface CreateEscrowInput {
  booking_id: string;
  consumer_id: string;
  barber_id: string;
  amount: number;  // cents
  expires_hours?: number;  // Default 48 hours
  stripe_payment_intent_id?: string;
}

export interface ReleaseEscrowInput {
  booking_id: string;
  tip_cents?: number;
  platform_fee_rate?: number;  // Default 0.15 (15%)
}

class EscrowService {
  /**
   * Create escrow hold for booking
   * Flow: Consumer's funds are already charged via Stripe (platform has the money)
   * This creates the escrow record and marks funds as held
   */
  async createHold(input: CreateEscrowInput): Promise<EscrowHold> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Validate consumer and barber exist
      const userCheck = await client.query(
        `SELECT id, role FROM users WHERE id = ANY($1::uuid[])`,
        [[input.consumer_id, input.barber_id]]
      );

      if (userCheck.rows.length !== 2) {
        throw new ApiError(404, 'Consumer or barber not found');
      }

      // 2. Calculate expiration (default 48 hours)
      const expiresAt = new Date();
      expiresAt.setHours(expiresAt.getHours() + (input.expires_hours || 48));

      // 3. Create escrow hold record
      const escrowResult = await client.query(
        `INSERT INTO escrow_holds (
          booking_id, consumer_id, barber_id, amount, currency, expires_at, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING *`,
        [
          input.booking_id,
          input.consumer_id,
          input.barber_id,
          input.amount,
          'USD',
          expiresAt,
          EscrowStatus.HELD
        ]
      );

      const escrow = escrowResult.rows[0];

      // 4. Create 'hold' transaction for consumer
      await transactionService.createTransaction({
        user_id: input.consumer_id,
        type: TransactionType.HOLD,
        amount: -input.amount,  // Debit from consumer
        related_booking_id: input.booking_id,
        stripe_payment_intent_id: input.stripe_payment_intent_id,
        metadata: {
          escrow_id: escrow.id,
          barber_id: input.barber_id,
        },
      });

      // 5. Update barber's pending balance
      await transactionService.updatePendingBalance(input.barber_id, input.amount);

      // 6. Audit log
      await auditService.log({
        actor_user_id: input.consumer_id,
        action: 'escrow_hold_created',
        object_type: 'escrow_hold',
        object_id: escrow.id,
        details: {
          booking_id: input.booking_id,
          amount_cents: input.amount,
          expires_at: expiresAt,
        },
      });

      await client.query('COMMIT');

      logger.info('Escrow hold created', {
        escrow_id: escrow.id,
        booking_id: input.booking_id,
        amount_dollars: input.amount / 100,
        consumer_id: input.consumer_id,
        barber_id: input.barber_id,
        expires_at: expiresAt,
      });

      return escrow;
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to create escrow hold', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Release escrow to barber (on booking completion)
   * Flow: Move from pending → available, deduct platform fee, handle tips
   */
  async releaseHold(input: ReleaseEscrowInput): Promise<{ escrow: EscrowHold; net_to_barber: number }> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Get and lock escrow
      const escrowResult = await client.query(
        `SELECT * FROM escrow_holds
         WHERE booking_id = $1 AND status = $2
         FOR UPDATE`,
        [input.booking_id, EscrowStatus.HELD]
      );

      if (escrowResult.rows.length === 0) {
        throw new ApiError(404, 'Escrow hold not found or already processed');
      }

      const escrow: EscrowHold = escrowResult.rows[0];

      // 2. Check if expired
      if (new Date() > new Date(escrow.expires_at)) {
        throw new ApiError(400, 'Escrow hold has expired');
      }

      // 3. Calculate amounts
      const platformFeeRate = input.platform_fee_rate || 0.15; // 15%
      const platformFeeCents = Math.floor(escrow.amount * platformFeeRate);
      const netToBarber = escrow.amount - platformFeeCents;

      // 4. Update escrow status
      await client.query(
        `UPDATE escrow_holds
         SET status = $1, released_at = NOW()
         WHERE id = $2`,
        [EscrowStatus.RELEASED, escrow.id]
      );

      // 5. Move barber's pending → available
      await client.query(
        `UPDATE balances
         SET pending_amount = pending_amount - $1,
             available_amount = available_amount + $2,
             updated_at = NOW()
         WHERE user_id = $3`,
        [escrow.amount, netToBarber, escrow.barber_id]
      );

      // 6. Create 'release' transaction for barber
      await transactionService.createTransaction({
        user_id: escrow.barber_id,
        type: TransactionType.RELEASE,
        amount: netToBarber,
        related_booking_id: input.booking_id,
        metadata: {
          escrow_id: escrow.id,
          gross_amount: escrow.amount,
          platform_fee: platformFeeCents,
        },
      });

      // 7. Create 'fee' transaction and record in platform_fees
      const feeResult = await transactionService.createTransaction({
        user_id: escrow.barber_id,
        type: TransactionType.FEE,
        amount: -platformFeeCents,
        related_booking_id: input.booking_id,
        metadata: {
          escrow_id: escrow.id,
          fee_rate: platformFeeRate,
        },
      });

      await client.query(
        `INSERT INTO platform_fees (amount, currency, source_tx_id)
         VALUES ($1, $2, $3)`,
        [platformFeeCents, 'USD', feeResult.id]
      );

      // 8. Handle tip if provided
      if (input.tip_cents && input.tip_cents > 0) {
        await transactionService.transfer({
          from_user_id: escrow.consumer_id,
          to_user_id: escrow.barber_id,
          amount: input.tip_cents,
          type: TransactionType.TIP,
          related_booking_id: input.booking_id,
        });
      }

      // 9. Audit log
      await auditService.log({
        actor_user_id: escrow.barber_id,
        action: 'escrow_released',
        object_type: 'escrow_hold',
        object_id: escrow.id,
        details: {
          booking_id: input.booking_id,
          gross_amount: escrow.amount,
          platform_fee: platformFeeCents,
          net_to_barber: netToBarber,
          tip_cents: input.tip_cents || 0,
        },
      });

      await client.query('COMMIT');

      logger.info('Escrow released', {
        escrow_id: escrow.id,
        booking_id: input.booking_id,
        gross_dollars: escrow.amount / 100,
        fee_dollars: platformFeeCents / 100,
        net_dollars: netToBarber / 100,
        tip_dollars: (input.tip_cents || 0) / 100,
      });

      return { escrow, net_to_barber: netToBarber };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to release escrow', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Refund escrow to consumer (on booking cancellation)
   */
  async refundHold(bookingId: string, reason: string): Promise<EscrowHold> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Get and lock escrow
      const escrowResult = await client.query(
        `SELECT * FROM escrow_holds
         WHERE booking_id = $1 AND status = $2
         FOR UPDATE`,
        [bookingId, EscrowStatus.HELD]
      );

      if (escrowResult.rows.length === 0) {
        throw new ApiError(404, 'Escrow hold not found or already processed');
      }

      const escrow: EscrowHold = escrowResult.rows[0];

      // 2. Update escrow status
      await client.query(
        `UPDATE escrow_holds
         SET status = $1, refunded_at = NOW()
         WHERE id = $2`,
        [EscrowStatus.REFUNDED, escrow.id]
      );

      // 3. Reduce barber's pending balance
      await client.query(
        `UPDATE balances
         SET pending_amount = pending_amount - $1,
             updated_at = NOW()
         WHERE user_id = $2`,
        [escrow.amount, escrow.barber_id]
      );

      // 4. Create refund transaction for consumer
      await transactionService.createTransaction({
        user_id: escrow.consumer_id,
        type: TransactionType.REFUND,
        amount: escrow.amount,  // Credit back to consumer
        related_booking_id: bookingId,
        metadata: {
          escrow_id: escrow.id,
          reason,
        },
      });

      // 5. Audit log
      await auditService.log({
        actor_user_id: escrow.consumer_id,
        action: 'escrow_refunded',
        object_type: 'escrow_hold',
        object_id: escrow.id,
        details: {
          booking_id: bookingId,
          amount_cents: escrow.amount,
          reason,
        },
      });

      await client.query('COMMIT');

      logger.info('Escrow refunded', {
        escrow_id: escrow.id,
        booking_id: bookingId,
        amount_dollars: escrow.amount / 100,
        consumer_id: escrow.consumer_id,
        reason,
      });

      return escrow;
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to refund escrow', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get escrow by booking ID
   */
  async getEscrowByBooking(bookingId: string): Promise<EscrowHold | null> {
    const result = await pool.query(
      `SELECT * FROM escrow_holds WHERE booking_id = $1`,
      [bookingId]
    );

    return result.rows[0] || null;
  }

  /**
   * Get all escrows for a user (as consumer or barber)
   */
  async getUserEscrows(userId: string, status?: EscrowStatus): Promise<EscrowHold[]> {
    let query = `
      SELECT * FROM escrow_holds
      WHERE (consumer_id = $1 OR barber_id = $1)
    `;
    const params: any[] = [userId];

    if (status) {
      query += ` AND status = $2`;
      params.push(status);
    }

    query += ` ORDER BY created_at DESC`;

    const result = await pool.query(query, params);
    return result.rows;
  }

  /**
   * Process expired escrows (background job)
   * Auto-refund holds that have passed expiration
   */
  async processExpiredEscrows(): Promise<number> {
    const result = await pool.query(
      `SELECT * FROM escrow_holds
       WHERE status = $1 AND expires_at < NOW()`,
      [EscrowStatus.HELD]
    );

    let processedCount = 0;

    for (const escrow of result.rows) {
      try {
        await this.refundHold(escrow.booking_id, 'Automatic refund - escrow expired');
        processedCount++;
      } catch (error) {
        logger.error('Failed to process expired escrow', {
          escrow_id: escrow.id,
          error,
        });
      }
    }

    if (processedCount > 0) {
      logger.info(`Processed ${processedCount} expired escrows`);
    }

    return processedCount;
  }
}

export default new EscrowService();

