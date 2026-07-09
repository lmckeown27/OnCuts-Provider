/**
 * Transaction Service
 * 
 * Core of the production custodial wallet system.
 * Handles all balance changes with atomic database transactions.
 * Replaces the simplified ledger.service.ts with production-grade implementation.
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';

export enum TransactionType {
  CHARGE = 'charge',                      // Consumer charged via Stripe
  HOLD = 'hold',                          // Funds held in escrow (deprecated)
  RELEASE = 'release',                    // Escrow released to barber (deprecated)
  EARNING = 'earning',                    // Barber earning from direct payment
  PAYOUT = 'payout',                      // Barber withdrawal to bank
  REFUND = 'refund',                      // Refund to consumer
  FEE = 'fee',                            // Platform fee collected
  ONCHAIN_WITHDRAWAL = 'onchain_withdrawal', // Withdrawal to blockchain
  TIP = 'tip',                            // Tip payment
  ADJUSTMENT = 'adjustment',              // Admin adjustment
  REVERSAL = 'reversal'                   // Transaction reversal
}

export enum TransactionStatus {
  PENDING = 'pending',
  COMPLETED = 'completed',
  FAILED = 'failed',
  REVERSED = 'reversed'
}

export interface Transaction {
  id: number;
  tx_ref: string;
  user_id: string;
  type: TransactionType;
  amount: number;  // cents
  currency: string;
  status: TransactionStatus;
  related_booking_id?: string;
  related_tx_id?: number;
  stripe_payment_intent_id?: string;
  stripe_payout_id?: string;
  metadata?: Record<string, any>;
  created_at: Date;
  completed_at?: Date;
}

export interface CreateTransactionInput {
  user_id: string;
  type: TransactionType;
  amount: number;  // cents
  currency?: string;
  status?: TransactionStatus;
  related_booking_id?: string;
  related_tx_id?: number;
  stripe_payment_intent_id?: string;
  stripe_payout_id?: string;
  metadata?: Record<string, any>;
}

export interface UserBalance {
  user_id: string;
  available_amount: number;  // cents
  pending_amount: number;    // cents
  total_balance: number;     // cents
}

class TransactionService {
  /**
   * Get user's current balance
   */
  async getUserBalance(userId: string): Promise<UserBalance> {
    const result = await pool.query(
      `SELECT available_amount, pending_amount
       FROM balances
       WHERE user_id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      // Create balance record if doesn't exist
      await this.createBalanceRecord(userId);
      return {
        user_id: userId,
        available_amount: 0,
        pending_amount: 0,
        total_balance: 0,
      };
    }

    const balance = result.rows[0];
    return {
      user_id: userId,
      available_amount: balance.available_amount || 0,
      pending_amount: balance.pending_amount || 0,
      total_balance: (balance.available_amount || 0) + (balance.pending_amount || 0),
    };
  }

  /**
   * Create a balance record for a user
   */
  private async createBalanceRecord(userId: string): Promise<void> {
    await pool.query(
      `INSERT INTO balances (user_id, currency, available_amount, pending_amount)
       VALUES ($1, 'USD', 0, 0)
       ON CONFLICT (user_id) DO NOTHING`,
      [userId]
    );
  }

  /**
   * Create a transaction and update balance atomically
   * This is the core operation for all balance changes
   */
  async createTransaction(input: CreateTransactionInput): Promise<Transaction> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Ensure balance record exists
      await client.query(
        `INSERT INTO balances (user_id, currency, available_amount, pending_amount)
         VALUES ($1, $2, 0, 0)
         ON CONFLICT (user_id) DO NOTHING`,
        [input.user_id, input.currency || 'USD']
      );

      // 2. Lock the balance row
      const balanceResult = await client.query(
        `SELECT available_amount, pending_amount
         FROM balances
         WHERE user_id = $1
         FOR UPDATE`,
        [input.user_id]
      );

      const currentBalance = balanceResult.rows[0];

      // 3. Validate sufficient balance for debits
      if (input.amount < 0) {
        const requiredAmount = Math.abs(input.amount);
        if (currentBalance.available_amount < requiredAmount) {
          throw new ApiError(400, `Insufficient available balance. Required: $${requiredAmount / 100}, Available: $${currentBalance.available_amount / 100}`);
        }
      }

      // 4. Update balance based on transaction type
      const newAvailable = currentBalance.available_amount + input.amount;
      
      await client.query(
        `UPDATE balances
         SET available_amount = $1, updated_at = NOW()
         WHERE user_id = $2`,
        [newAvailable, input.user_id]
      );

      // 5. Create transaction record
      const txResult = await client.query(
        `INSERT INTO transactions (
          tx_ref, user_id, type, amount, currency, status,
          related_booking_id, related_tx_id,
          stripe_payment_intent_id, stripe_payout_id,
          metadata, completed_at
        )
        VALUES (
          generate_tx_ref(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
          CASE WHEN $5 = 'completed' THEN NOW() ELSE NULL END
        )
        RETURNING *`,
        [
          input.user_id,
          input.type,
          input.amount,
          input.currency || 'USD',
          input.status || TransactionStatus.COMPLETED,
          input.related_booking_id,
          input.related_tx_id,
          input.stripe_payment_intent_id,
          input.stripe_payout_id,
          JSON.stringify(input.metadata || {}),
        ]
      );

      await client.query('COMMIT');

      const transaction = txResult.rows[0];
      
      logger.info('Transaction created', {
        tx_ref: transaction.tx_ref,
        user_id: input.user_id,
        type: input.type,
        amount_dollars: input.amount / 100,
        new_balance_dollars: newAvailable / 100,
      });

      return transaction;
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to create transaction', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Update pending balance (for escrow operations)
   */
  async updatePendingBalance(userId: string, amountChange: number): Promise<void> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      const result = await client.query(
        `SELECT pending_amount FROM balances WHERE user_id = $1 FOR UPDATE`,
        [userId]
      );

      if (result.rows.length === 0) {
        throw new ApiError(404, 'Balance record not found');
      }

      const currentPending = result.rows[0].pending_amount;
      const newPending = currentPending + amountChange;

      if (newPending < 0) {
        throw new ApiError(400, 'Insufficient pending balance');
      }

      await client.query(
        `UPDATE balances
         SET pending_amount = $1, updated_at = NOW()
         WHERE user_id = $2`,
        [newPending, userId]
      );

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Transfer between two users (e.g., tips)
   * Creates two transactions atomically
   */
  async transfer(params: {
    from_user_id: string;
    to_user_id: string;
    amount: number;  // cents
    type: TransactionType;
    related_booking_id?: string;
    metadata?: Record<string, any>;
  }): Promise<{ debit: Transaction; credit: Transaction }> {
    if (params.amount <= 0) {
      throw new ApiError(400, 'Transfer amount must be positive');
    }

    if (params.from_user_id === params.to_user_id) {
      throw new ApiError(400, 'Cannot transfer to yourself');
    }

    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Debit from sender
      const debit = await this.createTransactionInTransaction(client, {
        user_id: params.from_user_id,
        type: params.type,
        amount: -params.amount,
        related_booking_id: params.related_booking_id,
        metadata: { ...params.metadata, transfer_to: params.to_user_id },
      });

      // Credit to receiver
      const credit = await this.createTransactionInTransaction(client, {
        user_id: params.to_user_id,
        type: params.type,
        amount: params.amount,
        related_booking_id: params.related_booking_id,
        related_tx_id: debit.id,
        metadata: { ...params.metadata, transfer_from: params.from_user_id },
      });

      await client.query('COMMIT');

      logger.info('Transfer completed', {
        from: params.from_user_id,
        to: params.to_user_id,
        amount_dollars: params.amount / 100,
        type: params.type,
      });

      return { debit, credit };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Transfer failed', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get transaction history for a user
   */
  async getTransactionHistory(
    userId: string,
    limit: number = 50,
    offset: number = 0
  ): Promise<{ transactions: Transaction[]; total: number }> {
    const [txResult, countResult] = await Promise.all([
      pool.query(
        `SELECT * FROM transactions
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT $2 OFFSET $3`,
        [userId, limit, offset]
      ),
      pool.query(
        `SELECT COUNT(*) as total FROM transactions WHERE user_id = $1`,
        [userId]
      ),
    ]);

    return {
      transactions: txResult.rows,
      total: parseInt(countResult.rows[0].total),
    };
  }

  /**
   * Get transaction by ID
   */
  async getTransaction(txId: number): Promise<Transaction | null> {
    const result = await pool.query(
      `SELECT * FROM transactions WHERE id = $1`,
      [txId]
    );

    return result.rows[0] || null;
  }

  /**
   * Get transaction by reference
   */
  async getTransactionByRef(txRef: string): Promise<Transaction | null> {
    const result = await pool.query(
      `SELECT * FROM transactions WHERE tx_ref = $1`,
      [txRef]
    );

    return result.rows[0] || null;
  }

  /**
   * Helper: Create transaction within existing database transaction
   */
  private async createTransactionInTransaction(
    client: any,
    input: CreateTransactionInput
  ): Promise<Transaction> {
    // Ensure balance exists
    await client.query(
      `INSERT INTO balances (user_id, currency, available_amount, pending_amount)
       VALUES ($1, 'USD', 0, 0)
       ON CONFLICT (user_id) DO NOTHING`,
      [input.user_id]
    );

    // Lock balance
    const balanceResult = await client.query(
      `SELECT available_amount FROM balances WHERE user_id = $1 FOR UPDATE`,
      [input.user_id]
    );

    const currentBalance = balanceResult.rows[0].available_amount;
    const newBalance = currentBalance + input.amount;

    if (newBalance < 0) {
      throw new ApiError(400, `Insufficient balance. Required: $${Math.abs(input.amount) / 100}, Available: $${currentBalance / 100}`);
    }

    // Update balance
    await client.query(
      `UPDATE balances SET available_amount = $1, updated_at = NOW() WHERE user_id = $2`,
      [newBalance, input.user_id]
    );

    // Create transaction
    const txResult = await client.query(
      `INSERT INTO transactions (
        tx_ref, user_id, type, amount, currency, status,
        related_booking_id, related_tx_id,
        stripe_payment_intent_id, stripe_payout_id,
        metadata, completed_at
      )
      VALUES (
        generate_tx_ref(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
        CASE WHEN $5 = 'completed' THEN NOW() ELSE NULL END
      )
      RETURNING *`,
      [
        input.user_id,
        input.type,
        input.amount,
        input.currency || 'USD',
        input.status || TransactionStatus.COMPLETED,
        input.related_booking_id,
        input.related_tx_id,
        input.stripe_payment_intent_id,
        input.stripe_payout_id,
        JSON.stringify(input.metadata || {}),
      ]
    );

    return txResult.rows[0];
  }
}

export default new TransactionService();

