/**
 * Payout Service
 * 
 * Handles withdrawals from CampusCuts to user bank accounts
 * Integrates with Stripe Connect for instant payouts to barbers
 */

import Stripe from 'stripe';
import { getDefaultStripeClient } from '../config/stripe';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import ledgerService from './ledger.service';
import {
  TransactionType,
  BalanceType,
  WithdrawalStatus,
  WithdrawalRequest,
  CreateWithdrawalInput,
  centsToDollars,
} from '../types/wallet.types';
import { ApiError } from '../middleware/errorHandler';

function stripeSdk(): Stripe {
  return getDefaultStripeClient();
}

class PayoutService {
  /**
   * Request a withdrawal (barber cashing out)
   */
  async createWithdrawalRequest(input: CreateWithdrawalInput): Promise<WithdrawalRequest> {
    // 1. Check user has sufficient balance
    const balance = await ledgerService.getUserBalance(input.user_id);
    
    if (balance.balance_available < input.amount) {
      throw new ApiError(400, 'Insufficient available balance');
    }

    // 2. Create withdrawal request
    const result = await pool.query(
      `INSERT INTO withdrawal_requests (
        user_id, amount, status, stripe_destination_id
      ) VALUES ($1, $2, $3, $4)
      RETURNING *`,
      [input.user_id, input.amount, WithdrawalStatus.PENDING, input.stripe_destination_id]
    );

    const withdrawalRequest = result.rows[0];

    // 3. Process withdrawal immediately (or queue for async processing)
    try {
      await this.processWithdrawal(withdrawalRequest.id);
    } catch (error) {
      logger.error('Failed to process withdrawal immediately, will retry', {
        withdrawal_id: withdrawalRequest.id,
        error,
      });
    }

    return withdrawalRequest;
  }

  /**
   * Process a withdrawal request (Stripe Connect payout)
   */
  async processWithdrawal(withdrawalId: string): Promise<void> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Get withdrawal request
      const withdrawalResult = await client.query(
        `SELECT * FROM withdrawal_requests 
        WHERE id = $1 AND status = $2 
        FOR UPDATE`,
        [withdrawalId, WithdrawalStatus.PENDING]
      );

      if (withdrawalResult.rows.length === 0) {
        throw new ApiError(404, 'Withdrawal request not found or already processed');
      }

      const withdrawal: WithdrawalRequest = withdrawalResult.rows[0];

      // 2. Update status to processing
      await client.query(
        `UPDATE withdrawal_requests 
        SET status = $1, processed_at = NOW() 
        WHERE id = $2`,
        [WithdrawalStatus.PROCESSING, withdrawalId]
      );

      // 3. Debit user's available balance
      await ledgerService.createLedgerEntry({
        user_id: withdrawal.user_id,
        amount: -withdrawal.amount,
        type: TransactionType.WITHDRAWAL,
        balance_type: BalanceType.AVAILABLE,
        reference_type: 'withdrawal',
        reference_id: withdrawalId,
        description: `Withdrawal request ${withdrawalId}`,
        metadata: {
          stripe_destination_id: withdrawal.stripe_destination_id,
        },
      });

      // 4. Create Stripe payout
      if (!withdrawal.stripe_destination_id) {
        throw new Error('Stripe destination ID is required for bank withdrawals');
      }
      const payout = await this.createStripePayout(
        withdrawal.amount,
        withdrawal.stripe_destination_id
      );

      // 5. Update withdrawal with Stripe payout ID
      await client.query(
        `UPDATE withdrawal_requests 
        SET stripe_payout_id = $1, status = $2, completed_at = NOW() 
        WHERE id = $3`,
        [payout.id, WithdrawalStatus.COMPLETED, withdrawalId]
      );

      await client.query('COMMIT');

      logger.info('Withdrawal processed successfully', {
        withdrawal_id: withdrawalId,
        user_id: withdrawal.user_id,
        amount: centsToDollars(withdrawal.amount),
        stripe_payout_id: payout.id,
      });
    } catch (error: any) {
      await client.query('ROLLBACK');

      // Mark withdrawal as failed
      await pool.query(
        `UPDATE withdrawal_requests 
        SET status = $1, failure_reason = $2 
        WHERE id = $3`,
        [WithdrawalStatus.FAILED, error.message, withdrawalId]
      );

      logger.error('Withdrawal processing failed', {
        withdrawal_id: withdrawalId,
        error: error.message,
      });

      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Create Stripe Connect payout
   */
  private async createStripePayout(
    amountCents: number,
    connectedAccountId: string
  ): Promise<Stripe.Payout> {
    try {
      const payout = await stripeSdk().payouts.create(
        {
          amount: amountCents,
          currency: 'usd',
          method: 'instant', // Use instant payouts (requires Stripe setup)
          statement_descriptor: 'CampusCuts Payout',
        },
        {
          stripeAccount: connectedAccountId, // Send to barber's connected account
        }
      );

      return payout;
    } catch (error: any) {
      logger.error('Stripe payout creation failed', {
        amount: centsToDollars(amountCents),
        connected_account: connectedAccountId,
        error: error.message,
      });
      throw new ApiError(500, `Payout failed: ${error.message}`);
    }
  }

  /**
   * Create Stripe Connect account for barber
   * (Call this during barber onboarding)
   */
  async createConnectedAccount(userId: string, email: string): Promise<string> {
    try {
      const account = await stripeSdk().accounts.create({
        type: 'express', // Express is easiest for barbers
        email,
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        business_type: 'individual',
      });

      // Store the connected account ID in your database
      await pool.query(
        `UPDATE users 
        SET stripe_account_id = $1 
        WHERE id = $2`,
        [account.id, userId]
      );

      logger.info('Stripe Connect account created', {
        user_id: userId,
        account_id: account.id,
      });

      return account.id;
    } catch (error: any) {
      logger.error('Failed to create Stripe Connect account', {
        user_id: userId,
        error: error.message,
      });
      throw new ApiError(500, 'Failed to create payout account');
    }
  }

  /**
   * Generate Stripe Connect onboarding link
   */
  async createAccountLink(accountId: string, returnUrl: string, refreshUrl: string): Promise<string> {
    try {
      const accountLink = await stripeSdk().accountLinks.create({
        account: accountId,
        refresh_url: refreshUrl,
        return_url: returnUrl,
        type: 'account_onboarding',
      });

      return accountLink.url;
    } catch (error: any) {
      logger.error('Failed to create account link', {
        account_id: accountId,
        error: error.message,
      });
      throw new ApiError(500, 'Failed to create onboarding link');
    }
  }

  /**
   * Get withdrawal history for user
   */
  async getWithdrawalHistory(
    userId: string,
    limit: number = 20,
    offset: number = 0
  ): Promise<{ withdrawals: WithdrawalRequest[]; total: number }> {
    const [withdrawalsResult, countResult] = await Promise.all([
      pool.query(
        `SELECT * FROM withdrawal_requests 
        WHERE user_id = $1 
        ORDER BY requested_at DESC 
        LIMIT $2 OFFSET $3`,
        [userId, limit, offset]
      ),
      pool.query(
        `SELECT COUNT(*) as total FROM withdrawal_requests WHERE user_id = $1`,
        [userId]
      ),
    ]);

    return {
      withdrawals: withdrawalsResult.rows,
      total: parseInt(countResult.rows[0].total),
    };
  }

  /**
   * Cancel a pending withdrawal
   */
  async cancelWithdrawal(withdrawalId: string, userId: string): Promise<void> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Get withdrawal
      const result = await client.query(
        `SELECT * FROM withdrawal_requests 
        WHERE id = $1 AND user_id = $2 AND status = $3 
        FOR UPDATE`,
        [withdrawalId, userId, WithdrawalStatus.PENDING]
      );

      if (result.rows.length === 0) {
        throw new ApiError(404, 'Withdrawal not found or cannot be cancelled');
      }

      const withdrawal: WithdrawalRequest = result.rows[0];

      // Refund the amount back to user's balance
      await ledgerService.createLedgerEntry({
        user_id: withdrawal.user_id,
        amount: withdrawal.amount,
        type: TransactionType.ADJUSTMENT,
        balance_type: BalanceType.AVAILABLE,
        reference_type: 'withdrawal',
        reference_id: withdrawalId,
        description: `Withdrawal ${withdrawalId} cancelled - refund`,
      });

      // Update withdrawal status
      await client.query(
        `UPDATE withdrawal_requests 
        SET status = $1 
        WHERE id = $2`,
        [WithdrawalStatus.CANCELLED, withdrawalId]
      );

      await client.query('COMMIT');

      logger.info('Withdrawal cancelled', {
        withdrawal_id: withdrawalId,
        user_id: userId,
      });
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to cancel withdrawal', error);
      throw error;
    } finally {
      client.release();
    }
  }
}

export default new PayoutService();

