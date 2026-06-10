/**
 * Gas Wallet Monitoring Routes
 */

import { Router } from 'express';
import {
  getGasWalletStatus,
  getGasWalletUsage,
  getGasWalletAlerts,
  checkGasWalletNow,
} from '../controllers/gas-wallet.controller';

const router = Router();

// GET /api/gas/monitor/status - Get current gas wallet status
router.get('/monitor/status', getGasWalletStatus);

// GET /api/gas/monitor/usage - Get usage history
router.get('/monitor/usage', getGasWalletUsage);

// GET /api/gas/monitor/alerts - Get recent alerts
router.get('/monitor/alerts', getGasWalletAlerts);

// POST /api/gas/monitor/check-now - Trigger immediate balance check
router.post('/monitor/check-now', checkGasWalletNow);

export default router;
