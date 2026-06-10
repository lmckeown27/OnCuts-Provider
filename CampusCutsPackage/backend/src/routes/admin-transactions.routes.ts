/**
 * Admin Transactions Routes
 * 
 * NOTE: These routes are public for demo purposes.
 * In production, add authentication middleware.
 */

import { Router } from 'express';
// import { authenticate } from '../middleware/auth'; // Commented out for demo
import * as adminTransactionsController from '../controllers/admin-transactions.controller';

const router = Router();

/**
 * @route   GET /api/admin/transactions
 * @desc    Get recent transactions (with optional campus filter)
 * @access  Public (for demo dashboard)
 */
router.get(
  '/',
  // authenticate, // Removed for demo - add back in production
  adminTransactionsController.getRecentTransactions
);

/**
 * @route   GET /api/admin/transactions/stats
 * @desc    Get transaction statistics
 * @access  Public (for demo dashboard)
 */
router.get(
  '/stats',
  // authenticate, // Removed for demo - add back in production
  adminTransactionsController.getTransactionStats
);

export default router;

