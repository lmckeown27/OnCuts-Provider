/**
 * Stripe Webhook Routes
 * 
 * IMPORTANT: These routes MUST come BEFORE express.json() middleware
 * Stripe requires raw body to verify webhook signatures
 */

import express from 'express';
import { handleStripeWebhook } from '../controllers/stripe-webhook-enhanced.controller';

const router = express.Router();

/**
 * POST /api/webhooks/stripe
 * Handle Stripe webhook events
 * 
 * This route expects raw body (not JSON parsed)
 * 
 * Events handled:
 * - payment_intent.succeeded → Mark booking paid, trigger escrow
 * - payment_intent.payment_failed → Mark booking failed
 * - payment_intent.canceled → Cancel booking
 * - charge.refunded → Process refund
 * - account.updated → Update barber Stripe Connect status
 * - transfer.created → Log payout completion
 * - transfer.updated → Handle failed payouts
 */
router.post('/stripe', handleStripeWebhook);

export default router;

