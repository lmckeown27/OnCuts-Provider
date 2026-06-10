/**
 * Barber Connect Routes
 * 
 * Handles Stripe Connect onboarding for barbers
 */

import express from 'express';
import { authenticate, requireRole } from '../middleware/auth';
import {
  createConnectAccount,
  getConnectStatus,
  refreshOnboardingLink,
  handleOnboardingReturn,
  getDashboardLink,
} from '../controllers/barber-connect.controller';
import { getBarberPayoutStatus, getBarberPayoutSummary } from '../controllers/barber-payout.controller';

const router = express.Router();

/** GET /api/barber/payout/status — Sui payout address on file */
router.get('/payout/status', authenticate, requireRole('barber', 'admin'), getBarberPayoutStatus);

/** GET /api/barber/payout/summary — ledger + booking earnings for Payout Settings */
router.get('/payout/summary', authenticate, requireRole('barber', 'admin'), getBarberPayoutSummary);

/**
 * Create Stripe Connect account
 * POST /api/barber/connect/create
 */
router.post('/connect/create', authenticate, requireRole('barber', 'admin'), createConnectAccount);

/**
 * Get Connect account status
 * GET /api/barber/connect/status
 */
router.get('/connect/status', authenticate, requireRole('barber', 'admin'), getConnectStatus);

/**
 * Refresh onboarding link
 * POST /api/barber/connect/refresh
 */
router.post('/connect/refresh', authenticate, requireRole('barber', 'admin'), refreshOnboardingLink);

/**
 * Handle onboarding return
 * GET /api/barber/connect/return
 */
router.get('/connect/return', authenticate, handleOnboardingReturn);

/**
 * Get Stripe Express dashboard login link
 * GET /api/barber/connect/dashboard
 */
router.get('/connect/dashboard', authenticate, requireRole('barber', 'admin'), getDashboardLink);

export default router;

