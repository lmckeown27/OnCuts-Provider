/**
 * Payout Service V2
 * 
 * Handles withdrawals with batching support for gas efficiency.
 * 
 * Flow:
 * 1. Bank withdrawal: Stripe Connect instant payout
 * 2. On-chain withdrawal: Queue → Batch → Process
 */

import Stripe from 'stripe';
import { getDefaultStripeClient } from '../config/stripe';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';
import withdrawalBatchService, { DestinationType } from './withdrawal-batch.service';
import auditService from './audit.service';
import { pool } from '../database/connection';
import suiRelayerService from './sui-relayer.service';

function stripeSdk(): Stripe {
  return getDefaultStripeClient();
}

export interface WithdrawToBankInput {
  userId: string;
  amountCents: number;
  stripeAccountId: string;
}

export interface WithdrawOnChainInput {
  userId: string;
  amountCents: number;
  destinationAddress: string;
  chain: string;
}

class PayoutServiceV2 {
  /**
   * Withdraw to bank via Stripe Connect (instant payout)
   */
  async withdrawToBank(input: WithdrawToBankInput): Promise<{
    success: boolean;
    payoutId: string;
  }> {
    try {
      // 1. Queue withdrawal
      const queueItem = await withdrawalBatchService.queueWithdrawal({
        user_id: input.userId,
        amount: input.amountCents,
        destination_type: DestinationType.BANK,
        destination_address: input.stripeAccountId,
      });

      // 2. Process immediately (not batched for bank withdrawals)
      const payout = await this.processStripePayout(
        input.amountCents,
        input.stripeAccountId
      );

      // 3. Mark as completed
      await pool.query(
        `UPDATE withdrawal_queue
         SET status = 'completed', processed_at = NOW()
         WHERE id = $1`,
        [queueItem.id]
      );

      // 4. Audit log
      await auditService.log({
        actor_user_id: input.userId,
        action: 'bank_withdrawal_completed',
        object_type: 'withdrawal',
        object_id: queueItem.id.toString(),
        details: {
          amount_cents: input.amountCents,
          payout_id: payout.id,
        },
      });

      logger.info('Bank withdrawal completed', {
        user_id: input.userId,
        amount_dollars: input.amountCents / 100,
        payout_id: payout.id,
      });

      return {
        success: true,
        payoutId: payout.id,
      };
    } catch (error: any) {
      logger.error('Bank withdrawal failed', {
        user_id: input.userId,
        error: error.message,
      });
      throw error;
    }
  }

  /**
   * Withdraw to on-chain address (queued for batching)
   */
  async withdrawOnChain(input: WithdrawOnChainInput): Promise<{
    success: boolean;
    queueId: number;
    status: string;
  }> {
    try {
      // Queue for batching
      const queueItem = await withdrawalBatchService.queueWithdrawal({
        user_id: input.userId,
        amount: input.amountCents,
        destination_type: DestinationType.ONCHAIN,
        destination_address: input.destinationAddress,
        chain: input.chain,
      });

      // Audit log
      await auditService.log({
        actor_user_id: input.userId,
        action: 'onchain_withdrawal_queued',
        object_type: 'withdrawal',
        object_id: queueItem.id.toString(),
        details: {
          amount_cents: input.amountCents,
          destination: input.destinationAddress,
          chain: input.chain,
        },
      });

      logger.info('On-chain withdrawal queued', {
        user_id: input.userId,
        amount_dollars: input.amountCents / 100,
        destination: input.destinationAddress,
        chain: input.chain,
        queue_id: queueItem.id,
      });

      return {
        success: true,
        queueId: queueItem.id,
        status: 'queued',
      };
    } catch (error: any) {
      logger.error('On-chain withdrawal queueing failed', {
        user_id: input.userId,
        error: error.message,
      });
      throw error;
    }
  }

  /**
   * Process Stripe Connect payout
   */
  private async processStripePayout(
    amountCents: number,
    connectedAccountId: string
  ): Promise<Stripe.Payout> {
    try {
      const payout = await stripeSdk().payouts.create(
        {
          amount: amountCents,
          currency: 'usd',
          method: 'instant',
          statement_descriptor: 'CampusCuts',
        },
        {
          stripeAccount: connectedAccountId,
        }
      );

      return payout;
    } catch (error: any) {
      logger.error('Stripe payout failed', {
        amount_dollars: amountCents / 100,
        account: connectedAccountId,
        error: error.message,
      });
      throw new ApiError(500, `Payout failed: ${error.message}`);
    }
  }

  /**
   * Create Stripe Connect account for barber
   */
  async createConnectedAccount(
    userId: string,
    email: string
  ): Promise<string> {
    try {
      const account = await stripeSdk().accounts.create({
        type: 'express',
        email,
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        business_type: 'individual',
      });

      // Store in database
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
  async createAccountLink(
    accountId: string,
    returnUrl: string,
    refreshUrl: string
  ): Promise<string> {
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
  async getWithdrawalHistory(userId: string): Promise<any[]> {
    return withdrawalBatchService.getUserWithdrawals(userId);
  }

  /**
   * Get withdrawal stats (admin)
   */
  async getWithdrawalStats(): Promise<any> {
    return withdrawalBatchService.getStats();
  }

  /**
   * Stripe-settled USDC split on Sui (treasury → barber + platform).
   * Gas is paid by the treasury / `GAS_SPONSOR_SECRET` path (see `sui-relayer.service`); no Enoki.
   * Persists `payments.path_b_sui_tx_digest` for explorer links / idempotency.
   */
  async executeSuiOnChainUsdcPayout(input: {
    barberSuiAddress: string;
    amountBaseUnits: string;
    bookingId: string;
    paymentIntentId: string;
  }): Promise<{ digest: string }> {
    const total = BigInt(input.amountBaseUnits);
    const { digest } = await suiRelayerService.executeSplitPayout(input.barberSuiAddress, total);

    if (input.paymentIntentId?.trim()) {
      await pool.query(
        `UPDATE payments SET path_b_sui_tx_digest = $1 WHERE payment_intent_id = $2`,
        [digest, input.paymentIntentId.trim()]
      );
    }

    logger.info('Sui on-chain USDC payout executed', {
      bookingId: input.bookingId,
      digest,
      paymentIntentId: input.paymentIntentId,
    });

    return { digest };
  }
}

export default new PayoutServiceV2();

