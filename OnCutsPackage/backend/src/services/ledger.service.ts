/**
 * Ledger Service
 * 
 * Core of the custodial wallet system.
 * Handles all internal balance changes with atomic transactions.
 * Similar to Coinbase's internal ledger system.
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import {
  TransactionType,
  BalanceType,
  CreateLedgerEntryInput,
  InternalTransferInput,
  UserBalance,
  LedgerEntry,
  BookingPaymentInput,
  dollarsToCents,
  centsToDollars,
} from '../types/wallet.types';
import { ApiError } from '../middleware/errorHandler';

class LedgerService {
  /**
   * Get user's current balances
   */
  async getUserBalance(userId: string): Promise<UserBalance> {
    const result = await pool.query(
      `SELECT 
        balance_available, 
        balance_pending, 
        balance_locked
      FROM users 
      WHERE id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'User not found');
    }

    const balances = result.rows[0];
    return {
      user_id: userId,
      balance_available: balances.balance_available || 0,
      balance_pending: balances.balance_pending || 0,
      balance_locked: balances.balance_locked || 0,
      total_balance: (balances.balance_available || 0) + 
                    (balances.balance_pending || 0) + 
                    (balances.balance_locked || 0),
    };
  }

  /**
   * Create a ledger entry and update user balance
   * This is an ATOMIC operation - either both succeed or both fail
   */
  async createLedgerEntry(input: CreateLedgerEntryInput): Promise<LedgerEntry> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Get current balance
      const balanceResult = await client.query(
        `SELECT balance_available, balance_pending, balance_locked 
        FROM users 
        WHERE id = $1 
        FOR UPDATE`, // Lock the row to prevent race conditions
        [input.user_id]
      );

      if (balanceResult.rows.length === 0) {
        throw new ApiError(404, 'User not found');
      }

      const currentBalances = balanceResult.rows[0];
      const currentBalance = currentBalances[`balance_${input.balance_type}`] || 0;

      // 2. Calculate new balance
      const newBalance = currentBalance + input.amount;

      // 3. Validate balance won't go negative
      if (newBalance < 0) {
        throw new ApiError(400, `Insufficient ${input.balance_type} balance`);
      }

      // 4. Update user balance
      await client.query(
        `UPDATE users 
        SET balance_${input.balance_type} = $1, 
            updated_at = NOW() 
        WHERE id = $2`,
        [newBalance, input.user_id]
      );

      // 5. Create ledger entry
      const ledgerResult = await client.query(
        `INSERT INTO ledger_entries (
          user_id, amount, type, balance_type, balance_after,
          reference_type, reference_id, metadata, description, created_by
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING *`,
        [
          input.user_id,
          input.amount,
          input.type,
          input.balance_type,
          newBalance,
          input.reference_type,
          input.reference_id,
          JSON.stringify(input.metadata || {}),
          input.description,
          input.created_by,
        ]
      );

      await client.query('COMMIT');

      logger.info('Ledger entry created', {
        user_id: input.user_id,
        type: input.type,
        amount: centsToDollars(input.amount),
        balance_after: centsToDollars(newBalance),
      });

      return ledgerResult.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to create ledger entry', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Transfer funds between two users (e.g., booking payment, tip)
   * This is a DOUBLE-ENTRY transaction - atomic across both users
   */
  async internalTransfer(input: InternalTransferInput): Promise<{ debit: LedgerEntry; credit: LedgerEntry }> {
    if (input.amount <= 0) {
      throw new ApiError(400, 'Transfer amount must be positive');
    }

    if (input.from_user_id === input.to_user_id) {
      throw new ApiError(400, 'Cannot transfer to yourself');
    }

    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Debit from sender (negative amount)
      const debitEntry = await this.createLedgerEntryInTransaction(client, {
        user_id: input.from_user_id,
        amount: -input.amount,
        type: input.type,
        balance_type: BalanceType.AVAILABLE,
        reference_type: input.reference_type,
        reference_id: input.reference_id,
        description: input.description || `Transfer to user ${input.to_user_id}`,
      });

      // 2. Credit to receiver (positive amount)
      const creditEntry = await this.createLedgerEntryInTransaction(client, {
        user_id: input.to_user_id,
        amount: input.amount,
        type: input.type,
        balance_type: BalanceType.AVAILABLE,
        reference_type: input.reference_type,
        reference_id: input.reference_id,
        description: input.description || `Transfer from user ${input.from_user_id}`,
      });

      await client.query('COMMIT');

      logger.info('Internal transfer completed', {
        from: input.from_user_id,
        to: input.to_user_id,
        amount: centsToDollars(input.amount),
        type: input.type,
      });

      return { debit: debitEntry, credit: creditEntry };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to process internal transfer', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Handle booking payment flow
   * Customer pays → funds go to pending → released to barber on completion
   */
  async processBookingPayment(input: BookingPaymentInput): Promise<void> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Debit customer's available balance
      await this.createLedgerEntryInTransaction(client, {
        user_id: input.customer_id,
        amount: -input.total_amount,
        type: TransactionType.BOOKING_PAYMENT,
        balance_type: BalanceType.AVAILABLE,
        reference_type: 'booking',
        reference_id: input.booking_id,
        description: `Payment for booking ${input.booking_id}`,
      });

      // 2. Credit barber's pending balance (minus platform fee)
      const barberAmount = input.total_amount - input.platform_fee;
      await this.createLedgerEntryInTransaction(client, {
        user_id: input.barber_id,
        amount: barberAmount,
        type: TransactionType.BOOKING_PAYMENT,
        balance_type: BalanceType.PENDING,
        reference_type: 'booking',
        reference_id: input.booking_id,
        description: `Booking payment ${input.booking_id} (pending completion)`,
      });

      // 3. Record platform fee (could go to a platform account)
      if (input.platform_fee > 0) {
        await this.createLedgerEntryInTransaction(client, {
          user_id: input.barber_id,
          amount: -input.platform_fee,
          type: TransactionType.PLATFORM_FEE,
          balance_type: BalanceType.AVAILABLE,
          reference_type: 'booking',
          reference_id: input.booking_id,
          description: `Platform fee for booking ${input.booking_id}`,
          metadata: { platform_fee: input.platform_fee },
        });
      }

      // 4. Handle tip if provided
      if (input.tip_amount && input.tip_amount > 0) {
        await this.createLedgerEntryInTransaction(client, {
          user_id: input.barber_id,
          amount: input.tip_amount,
          type: TransactionType.TIP,
          balance_type: BalanceType.AVAILABLE,
          reference_type: 'booking',
          reference_id: input.booking_id,
          description: `Tip for booking ${input.booking_id}`,
        });
      }

      await client.query('COMMIT');

      logger.info('Booking payment processed', {
        booking_id: input.booking_id,
        customer_id: input.customer_id,
        barber_id: input.barber_id,
        total_amount: centsToDollars(input.total_amount),
        platform_fee: centsToDollars(input.platform_fee),
      });
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to process booking payment', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Release funds from pending to available (when service is completed)
   */
  async releaseBookingFunds(bookingId: string, barberId: string, amount: number): Promise<void> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Debit from pending
      await this.createLedgerEntryInTransaction(client, {
        user_id: barberId,
        amount: -amount,
        type: TransactionType.SERVICE_COMPLETION,
        balance_type: BalanceType.PENDING,
        reference_type: 'booking',
        reference_id: bookingId,
        description: `Service completed for booking ${bookingId}`,
      });

      // 2. Credit to available
      await this.createLedgerEntryInTransaction(client, {
        user_id: barberId,
        amount: amount,
        type: TransactionType.SERVICE_COMPLETION,
        balance_type: BalanceType.AVAILABLE,
        reference_type: 'booking',
        reference_id: bookingId,
        description: `Funds released for booking ${bookingId}`,
      });

      await client.query('COMMIT');

      logger.info('Booking funds released', {
        booking_id: bookingId,
        barber_id: barberId,
        amount: centsToDollars(amount),
      });
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to release booking funds', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get user's ledger history
   */
  async getLedgerHistory(
    userId: string,
    limit: number = 50,
    offset: number = 0
  ): Promise<{ entries: LedgerEntry[]; total: number }> {
    const [entriesResult, countResult] = await Promise.all([
      pool.query(
        `SELECT * FROM ledger_entries 
        WHERE user_id = $1 
        ORDER BY created_at DESC 
        LIMIT $2 OFFSET $3`,
        [userId, limit, offset]
      ),
      pool.query(
        `SELECT COUNT(*) as total FROM ledger_entries WHERE user_id = $1`,
        [userId]
      ),
    ]);

    return {
      entries: entriesResult.rows,
      total: parseInt(countResult.rows[0].total),
    };
  }

  /**
   * Helper: Create ledger entry within an existing transaction
   * Used for multi-entry atomic operations
   */
  private async createLedgerEntryInTransaction(
    client: any,
    input: CreateLedgerEntryInput
  ): Promise<LedgerEntry> {
    // Get current balance
    const balanceResult = await client.query(
      `SELECT balance_available, balance_pending, balance_locked 
      FROM users 
      WHERE id = $1 
      FOR UPDATE`,
      [input.user_id]
    );

    if (balanceResult.rows.length === 0) {
      throw new ApiError(404, 'User not found');
    }

    const currentBalances = balanceResult.rows[0];
    const currentBalance = currentBalances[`balance_${input.balance_type}`] || 0;
    const newBalance = currentBalance + input.amount;

    if (newBalance < 0) {
      throw new ApiError(400, `Insufficient ${input.balance_type} balance`);
    }

    // Update balance
    await client.query(
      `UPDATE users 
      SET balance_${input.balance_type} = $1, updated_at = NOW() 
      WHERE id = $2`,
      [newBalance, input.user_id]
    );

    // Create ledger entry
    const ledgerResult = await client.query(
      `INSERT INTO ledger_entries (
        user_id, amount, type, balance_type, balance_after,
        reference_type, reference_id, metadata, description, created_by
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *`,
      [
        input.user_id,
        input.amount,
        input.type,
        input.balance_type,
        newBalance,
        input.reference_type,
        input.reference_id,
        JSON.stringify(input.metadata || {}),
        input.description,
        input.created_by,
      ]
    );

    return ledgerResult.rows[0];
  }
}

export default new LedgerService();

