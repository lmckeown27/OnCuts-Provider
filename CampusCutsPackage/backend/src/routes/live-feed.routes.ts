/**
 * Live Transaction Feed Routes
 * Admin-only routes for real-time transaction monitoring
 */

import express from 'express';
import { authenticate } from '../middleware/auth';
import {
  getLiveFeed,
  getSuiTransactions,
  getStripeEvents,
  getPlatformStats,
  searchTransactions,
} from '../controllers/live-feed.controller';

const router = express.Router();

// All routes require authentication and admin role
// In production, add role check middleware

/**
 * GET /api/admin/live-feed
 * Get combined transaction feed (Stripe + optional on-chain / Sui metadata)
 * Query params:
 *   - limit: number (default 50)
 *   - platform: 'sui' | 'stripe' | 'all' (default 'all')
 */
router.get('/', authenticate, getLiveFeed);

/**
 * GET /api/admin/live-feed/sui
 * Get recent Sui transactions (stub until indexer wired)
 */
router.get('/sui', authenticate, getSuiTransactions);

/**
 * GET /api/admin/live-feed/stripe
 * Get recent Stripe payment events
 */
router.get('/stripe', authenticate, getStripeEvents);

/**
 * GET /api/admin/live-feed/stats
 * Get platform statistics (real-time and daily)
 */
router.get('/stats', authenticate, getPlatformStats);

/**
 * GET /api/admin/live-feed/search
 * Search transactions with filters
 * Query params:
 *   - query: string (search in tx_id, addresses, description)
 *   - platform: 'sui' | 'stripe' | 'all'
 *   - from_date: ISO date
 *   - to_date: ISO date
 *   - min_amount: number
 *   - max_amount: number
 */
router.get('/search', authenticate, searchTransactions);

export default router;

