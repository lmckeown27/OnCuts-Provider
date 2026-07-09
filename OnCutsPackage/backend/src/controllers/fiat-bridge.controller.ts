/**
 * Fiat Bridge Controller
 * 
 * Handles deposits (fiat → blockchain) and withdrawals (blockchain → fiat)
 * Users interact with familiar fiat UI, we handle blockchain behind the scenes
 */

import { Request, Response } from 'express';
import { constructStripeWebhookEvent, hasStripeWebhookSecretConfigured } from '../config/stripe';
import { logger } from '../utils/logger';
import fiatBlockchainBridge from '../services/fiat-blockchain-bridge.service';
import custodialSignerService from '../services/custodial-signer.service';

/**
 * Create deposit payment intent
 * 
 * USER FLOW:
 * 1. User clicks "Add Funds"
 * 2. Enters amount: $100
 * 3. Frontend gets payment intent from this endpoint
 * 4. Stripe Elements collects card details
 * 5. User confirms payment
 * 6. Webhook handler credits on-chain balance
 */
export async function createDeposit(req: Request, res: Response) {
  try {
    const { amount } = req.body;
    const email = (req as any).user?.email;

    if (!email) {
      return res.status(401).json({
        success: false,
        message: 'Not authenticated',
      });
    }

    if (!amount || amount <= 0) {
      return res.status(400).json({
        success: false,
        message: 'Invalid amount',
      });
    }

    // Minimum deposit: $5
    if (amount < 5) {
      return res.status(400).json({
        success: false,
        message: 'Minimum deposit is $5',
      });
    }

    // Maximum deposit: $1000 per transaction
    if (amount > 1000) {
      return res.status(400).json({
        success: false,
        message: 'Maximum deposit is $1000 per transaction',
      });
    }

    logger.info(`💰 Creating deposit intent: ${email} → $${amount}`);

    // Create Stripe PaymentIntent
    const paymentIntent = await fiatBlockchainBridge.createDepositIntent(email, amount);

    return res.status(200).json({
      success: true,
      data: {
        client_secret: paymentIntent.client_secret,
        payment_intent_id: paymentIntent.id,
        amount: amount,
      },
    });
  } catch (error) {
    logger.error('Failed to create deposit:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to create deposit',
      error: (error as Error).message,
    });
  }
}

/**
 * Get user balance (in USD)
 * 
 * Returns user's on-chain balance converted to USD
 */
export async function getBalance(req: Request, res: Response) {
  try {
    const email = (req as any).user?.email;

    if (!email) {
      return res.status(401).json({
        success: false,
        message: 'Not authenticated',
      });
    }

    const userAddress = custodialSignerService.getUserAddress(email);
    const balanceUSD = await fiatBlockchainBridge.getUserBalanceUSD(userAddress);

    if (!balanceUSD) {
      return res.status(404).json({
        success: false,
        message: 'Balance not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: {
        available: balanceUSD.available,
        locked: balanceUSD.locked,
        total: balanceUSD.total,
        currency: 'USD',
      },
    });
  } catch (error) {
    logger.error('Failed to get balance:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to load balance',
    });
  }
}

/**
 * Request withdrawal (barber cashes out)
 * 
 * USER FLOW:
 * 1. Barber clicks "Withdraw Earnings"
 * 2. Enters amount: $500
 * 3. Confirms bank account (Stripe Connect)
 * 4. We deduct from on-chain balance
 * 5. We send $500 to their bank via Stripe
 */
export async function requestWithdrawal(req: Request, res: Response) {
  try {
    const { amount, password } = req.body;
    const email = (req as any).user?.email;
    const stripeConnectAccountId = (req as any).user?.stripe_connect_account_id;

    if (!email) {
      return res.status(401).json({
        success: false,
        message: 'Not authenticated',
      });
    }

    if (!password) {
      return res.status(400).json({
        success: false,
        message: 'Password required',
      });
    }

    if (!stripeConnectAccountId) {
      return res.status(400).json({
        success: false,
        message: 'Bank account not connected. Please set up Stripe Connect first.',
      });
    }

    if (!amount || amount <= 0) {
      return res.status(400).json({
        success: false,
        message: 'Invalid amount',
      });
    }

    // Minimum withdrawal: $10
    if (amount < 10) {
      return res.status(400).json({
        success: false,
        message: 'Minimum withdrawal is $10',
      });
    }

    logger.info(`💸 Processing withdrawal: ${email} → $${amount}`);

    // Process withdrawal
    const result = await fiatBlockchainBridge.handleWithdrawal(
      email,
      password,
      amount,
      stripeConnectAccountId
    );

    if (!result.success) {
      throw new Error('Withdrawal failed');
    }

    return res.status(200).json({
      success: true,
      message: `$${amount} sent to your bank account!`,
      data: {
        amount,
        fee: 1.00, // $1 withdrawal fee
        net_amount: amount - 1.00,
        tx_hash: result.txHash,
        transfer_id: result.transferId,
        estimated_arrival: '1-2 business days',
      },
    });
  } catch (error) {
    logger.error('Failed to process withdrawal:', error);
    return res.status(500).json({
      success: false,
      message: (error as Error).message || 'Failed to process withdrawal',
    });
  }
}

/**
 * Get conversion rates and fees (for display)
 */
export async function getRates(req: Request, res: Response) {
  try {
    const rates = fiatBlockchainBridge.getConversionRates();

    return res.status(200).json({
      success: true,
      data: {
        apt_to_usd: rates.aptToUsd,
        usdc_to_usd: rates.usdcToUsd,
        booking_fee_percent: rates.bookingFeePercent,
        withdrawal_fee_usd: rates.withdrawalFeeUsd,
      },
    });
  } catch (error) {
    logger.error('Failed to get rates:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to load rates',
    });
  }
}

/**
 * Calculate platform fee for booking (preview)
 */
export async function calculateFee(req: Request, res: Response) {
  try {
    const { amount } = req.query;

    if (!amount || isNaN(Number(amount))) {
      return res.status(400).json({
        success: false,
        message: 'Invalid amount',
      });
    }

    const amountUSD = Number(amount);
    const breakdown = fiatBlockchainBridge.calculatePlatformFee(amountUSD);

    return res.status(200).json({
      success: true,
      data: {
        total_amount: breakdown.totalAmount,
        barber_receives: breakdown.barberAmount,
        platform_fee: breakdown.platformFee,
        fee_percentage: `${fiatBlockchainBridge.getConversionRates().bookingFeePercent}%`,
      },
    });
  } catch (error) {
    logger.error('Failed to calculate fee:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to calculate fee',
    });
  }
}

/**
 * Webhook handler for Stripe events
 * 
 * THIS IS CRITICAL: Called by Stripe when payment succeeds
 * Automatically credits user's on-chain balance
 */
export async function handleStripeWebhook(req: Request, res: Response) {
  try {
    const rawSig = req.headers['stripe-signature'];
    const sig = Array.isArray(rawSig) ? rawSig[0] : rawSig;

    if (!sig || typeof sig !== 'string') {
      return res.status(400).json({ error: 'Missing signature' });
    }

    // Verify webhook signature (tries test + live webhook secrets)
    if (!hasStripeWebhookSecretConfigured()) {
      logger.error('No STRIPE_WEBHOOK_SECRET* configured');
      return res.status(500).json({ error: 'Webhook not configured' });
    }

    const event = constructStripeWebhookEvent(req.body, sig);

    logger.info(`📨 Stripe webhook received: ${event.type}`);

    // Handle payment success → Credit on-chain balance
    if (event.type === 'payment_intent.succeeded') {
      const paymentIntent = event.data.object;
      
      // Only process balance deposits (not booking payments)
      if (paymentIntent.metadata.type === 'balance_deposit') {
        await fiatBlockchainBridge.handleDeposit(paymentIntent);
      }
    }

    return res.status(200).json({ received: true });
  } catch (error) {
    logger.error('Webhook error:', error);
    return res.status(400).json({
      error: 'Webhook error',
      message: (error as Error).message,
    });
  }
}

