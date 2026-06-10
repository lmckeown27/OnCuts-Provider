/**
 * Fiat ↔ blockchain bridge (legacy; production = Stripe + Sui)
 *
 * Legacy fiat + custodial chain bridge (on-chain legs removed; Stripe-first).
 *
 * Stripe + Sui relayer + zkLogin. `handleDeposit` / `handleWithdrawal` throw;
 * `createDepositIntent` may remain for Stripe-only tests.
 */

import Stripe from 'stripe';
import { getDefaultStripeClient } from '../config/stripe';
import { logger } from '../utils/logger';
import blockchainQueryService from './blockchain-query.service';

function stripeSdk(): Stripe {
  return getDefaultStripeClient();
}

// USDC conversion rate (in production, fetch from real-time oracle)
const USDC_TO_USD_RATE = 1.0; // 1 USDC = $1 USD (stablecoin)
const APT_TO_USD_RATE = 10.0; // Legacy scalar name; fee helper math only (not chain RPC)

// Platform fee settings
const BOOKING_FEE_PERCENT = 15; // 15% platform fee on bookings
const WITHDRAWAL_FEE_USD = 1.00; // $1 flat withdrawal fee

// Legacy “octas” math kept for `calculatePlatformFee` return shape only (not on-chain)
const OCTAS_PER_APT = 100_000_000;

class FiatBlockchainBridgeService {
  /**
   * Removed: custodial on-chain credit path. Use Stripe + Sui settlement elsewhere.
   */
  async handleDeposit(paymentIntent: Stripe.PaymentIntent): Promise<void> {
    logger.warn(`fiat-blockchain-bridge.handleDeposit ignored for ${paymentIntent.id} (custodial on-chain deposit removed)`);
    throw new Error(
      'Legacy fiat→custodial-chain deposit removed. Use Stripe + Sui relayer / zkLogin, not balance_deposit webhooks.'
    );
  }

  /** Removed: custodial on-chain withdraw + Stripe leg. */
  async handleWithdrawal(
    _email: string,
    _password: string,
    _amountUSD: number,
    _stripeConnectAccountId: string
  ): Promise<{ success: boolean; txHash?: string; transferId?: string }> {
    throw new Error(
      'Legacy custodial-chain withdrawal + Stripe transfer removed. Use wallet-v2 / Connect flows where applicable.'
    );
  }

  /**
   * Calculate platform fee for a booking
   * 
   * Example: $30 haircut → $2.70 platform fee (9%)
   */
  calculatePlatformFee(bookingAmountUSD: number): {
    totalAmount: number;
    barberAmount: number;
    platformFee: number;
    amountOctas: number;
    barberOctas: number;
    feeOctas: number;
  } {
    const platformFee = bookingAmountUSD * (BOOKING_FEE_PERCENT / 100);
    const barberAmount = bookingAmountUSD - platformFee;

    // Convert to octas
    const amountOctas = Math.floor((bookingAmountUSD / APT_TO_USD_RATE) * OCTAS_PER_APT);
    const feeOctas = Math.floor((platformFee / APT_TO_USD_RATE) * OCTAS_PER_APT);
    const barberOctas = amountOctas - feeOctas;

    return {
      totalAmount: bookingAmountUSD,
      barberAmount,
      platformFee,
      amountOctas,
      barberOctas,
      feeOctas,
    };
  }

  /**
   * Get user's balance in USD (for display)
   */
  async getUserBalanceUSD(userAddress: string): Promise<{
    available: number;
    locked: number;
    total: number;
  } | null> {
    try {
      const balance = await blockchainQueryService.getUserBalance(userAddress);
      if (!balance) return null;

      const availableOctas = parseInt(balance.available);
      const lockedOctas = parseInt(balance.locked);

      const availableAPT = availableOctas / OCTAS_PER_APT;
      const lockedAPT = lockedOctas / OCTAS_PER_APT;

      const availableUSD = availableAPT * APT_TO_USD_RATE;
      const lockedUSD = lockedAPT * APT_TO_USD_RATE;
      const totalUSD = availableUSD + lockedUSD;

      return {
        available: parseFloat(availableUSD.toFixed(2)),
        locked: parseFloat(lockedUSD.toFixed(2)),
        total: parseFloat(totalUSD.toFixed(2)),
      };
    } catch (error) {
      logger.error(`Failed to get balance for ${userAddress}:`, error);
      return null;
    }
  }

  /**
   * Record deposit transaction (for audit trail)
   * In production, this would go to an accounting database or blockchain event log
   */
  private async recordDeposit(deposit: {
    user_email: string;
    user_address: string;
    amount_usd: number;
    amount_octas: number;
    stripe_payment_intent_id: string;
    blockchain_tx_hash: string;
    timestamp: Date;
  }): Promise<void> {
    // In production, store in accounting database or emit event
    logger.info(`📝 Deposit recorded:`, deposit);
    
    // TODO: Store in database or event log for compliance
    // await pool.query('INSERT INTO deposits (...) VALUES (...)');
  }

  /**
   * Record withdrawal transaction (for audit trail)
   */
  private async recordWithdrawal(withdrawal: {
    user_email: string;
    user_address: string;
    amount_usd: number;
    fee_usd: number;
    amount_octas: number;
    stripe_transfer_id: string;
    stripe_connect_account_id: string;
    blockchain_tx_hash: string;
    timestamp: Date;
  }): Promise<void> {
    // In production, store in accounting database or emit event
    logger.info(`📝 Withdrawal recorded:`, withdrawal);
    
    // TODO: Store in database or event log for compliance
    // await pool.query('INSERT INTO withdrawals (...) VALUES (...)');
  }

  /**
   * Get current conversion rates (for display)
   * In production, fetch from real-time oracle
   */
  getConversionRates(): {
    usdcToUsd: number;
    aptToUsd: number;
    bookingFeePercent: number;
    withdrawalFeeUsd: number;
  } {
    return {
      usdcToUsd: USDC_TO_USD_RATE,
      aptToUsd: APT_TO_USD_RATE,
      bookingFeePercent: BOOKING_FEE_PERCENT,
      withdrawalFeeUsd: WITHDRAWAL_FEE_USD,
    };
  }

  /**
   * Create Stripe PaymentIntent for deposit
   * 
   * Frontend calls this to initiate a deposit
   */
  async createDepositIntent(
    email: string,
    amountUSD: number
  ): Promise<Stripe.PaymentIntent> {
    try {
      const amountCents = Math.floor(amountUSD * 100);

      const paymentIntent = await stripeSdk().paymentIntents.create({
        amount: amountCents,
        currency: 'usd',
        metadata: {
          email,
          type: 'balance_deposit',
          amount_usd: amountUSD.toString(),
        },
        description: `CampusCuts balance deposit - $${amountUSD}`,
      });

      logger.info(`💳 Payment intent created: ${paymentIntent.id} for ${email} ($${amountUSD})`);

      return paymentIntent;
    } catch (error) {
      logger.error('Failed to create payment intent:', error);
      throw error;
    }
  }
}

// Export singleton instance
export default new FiatBlockchainBridgeService();

