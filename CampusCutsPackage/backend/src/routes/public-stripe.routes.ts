/**
 * Unauthenticated Stripe **publishable** key for native clients (safe to expose; matches server secret mode).
 */
import { Router } from 'express';
import { sendStripeClientConfig } from '../controllers/stripe-client-config.controller';

const router = Router();

/**
 * GET /api/v1/stripe/client-config
 * Body: { success: true, publishableKey: "pk_live_…" | "pk_test_…" }
 */
router.get('/client-config', sendStripeClientConfig);

export default router;
