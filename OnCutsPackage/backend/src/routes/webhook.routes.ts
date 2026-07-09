/**
 * Webhook Routes
 *
 * Stripe: POST /stripe (raw body).
 */

import express from 'express';
import { handleStripeWebhookSecure } from '../controllers/stripe-webhook-secure.controller';

const router = express.Router();

/**
 * Stripe webhook endpoint
 * POST /api/webhooks/stripe
 * 
 * IMPORTANT: This route must use raw body, not JSON parsed body
 * Configure in index.ts BEFORE express.json() middleware:
 * 
 * app.use('/api/webhooks', express.raw({ type: 'application/json' }), webhookRoutes);
 * 
 * Features:
 * - Signature verification
 * - Idempotency protection (prevents duplicate processing)
 * - Post-webhook verification with Stripe API
 * - Atomic database transactions
 */
router.post('/stripe', handleStripeWebhookSecure);

export default router;

