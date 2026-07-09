/**
 * Fiat Bridge Routes
 * 
 * Legacy Stripe deposit intents; on-chain settlement is Sui when enabled.
 * Users never know they're using crypto!
 */

import express from 'express';
import { authenticate } from '../middleware/auth';
import * as fiatBridgeController from '../controllers/fiat-bridge.controller';

const router = express.Router();

// ═══════════════════════════════════════════════════════════
//  DEPOSIT ROUTES (Fiat → Blockchain)
// ═══════════════════════════════════════════════════════════

/**
 * POST /api/fiat-bridge/deposit
 * Create payment intent for depositing funds
 * 
 * Body: { amount: number }
 * Returns: { client_secret, payment_intent_id, amount }
 */
router.post('/deposit', authenticate, fiatBridgeController.createDeposit);

/**
 * GET /api/fiat-bridge/balance
 * Get user's balance in USD (from blockchain)
 * 
 * Returns: { available, locked, total, currency }
 */
router.get('/balance', authenticate, fiatBridgeController.getBalance);

// ═══════════════════════════════════════════════════════════
//  WITHDRAWAL ROUTES (Blockchain → Fiat)
// ═══════════════════════════════════════════════════════════

/**
 * POST /api/fiat-bridge/withdrawal
 * Request withdrawal to bank account
 * 
 * Body: { amount: number, password: string }
 * Returns: { amount, fee, net_amount, tx_hash, transfer_id }
 */
router.post('/withdrawal', authenticate, fiatBridgeController.requestWithdrawal);

// ═══════════════════════════════════════════════════════════
//  UTILITY ROUTES
// ═══════════════════════════════════════════════════════════

/**
 * GET /api/fiat-bridge/rates
 * Get current conversion rates and fees
 * 
 * Returns: { apt_to_usd, usdc_to_usd, booking_fee_percent, withdrawal_fee_usd }
 */
router.get('/rates', fiatBridgeController.getRates);

/**
 * GET /api/fiat-bridge/calculate-fee
 * Calculate platform fee for a given amount
 * 
 * Query: ?amount=30
 * Returns: { total_amount, barber_receives, platform_fee, fee_percentage }
 */
router.get('/calculate-fee', fiatBridgeController.calculateFee);

// ═══════════════════════════════════════════════════════════
//  WEBHOOK (Stripe → Backend)
// ═══════════════════════════════════════════════════════════

/**
 * POST /api/fiat-bridge/webhook
 * Stripe webhook endpoint
 * 
 * Called by Stripe when payment succeeds
 * Automatically credits user's on-chain balance
 * 
 * NOTE: This endpoint receives raw body (not JSON)
 */
router.post('/webhook', express.raw({ type: 'application/json' }), fiatBridgeController.handleStripeWebhook);

export default router;

