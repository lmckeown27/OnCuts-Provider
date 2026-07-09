/**
 * Circle Webhook Routes
 * 
 * Handles incoming webhooks from Circle API
 * 
 * Important: Must use express.raw() middleware to preserve raw body
 * for webhook signature verification (if implemented)
 */

import express from 'express';
import { handleCircleWebhook } from '../controllers/circle-webhook.controller';

const router = express.Router();

/**
 * POST /api/v1/circle/webhook
 * 
 * Receives webhook events from Circle API
 * 
 * Setup in Circle Dashboard:
 * 1. Go to: https://app-sandbox.circle.com/webhooks (or production URL)
 * 2. Click "Create Subscription"
 * 3. Enter endpoint: https://your-domain.com/api/v1/circle/webhook
 * 4. Select events to subscribe to:
 *    - wallets.wallet.created
 *    - transactions.transaction.created
 *    - transactions.transaction.confirmed
 *    - transactions.transaction.failed
 *    - transactions.transfer.created
 *    - transactions.transfer.confirmed
 *    - transactions.transfer.complete
 *    - transactions.transfer.failed
 * 5. Save subscription
 * 
 * Note: This endpoint does NOT require authentication
 * Circle webhooks are verified by checking the subscription ID
 */
router.post(
  '/webhook',
  express.json({ limit: '1mb' }), // Parse JSON body
  handleCircleWebhook
);

export default router;

