/**
 * Wallet Routes
 * 
 * All routes for custodial wallet operations
 */

import express from 'express';
import { authenticate } from '../middleware/auth';
import * as walletController from '../controllers/wallet.controller';

const router = express.Router();

/**
 * User Wallet Operations
 */

// GET /api/wallet/balance - Get current balance
router.get('/balance', authenticate, walletController.getBalance);

// POST /api/wallet/deposit/intent - Create deposit payment intent
router.post('/deposit/intent', authenticate, walletController.createDepositIntent);

// GET /api/wallet/transactions - Get transaction history
router.get('/transactions', authenticate, walletController.getTransactionHistory);

// POST /api/wallet/withdraw - Request withdrawal
router.post('/withdraw', authenticate, walletController.requestWithdrawal);

// GET /api/wallet/withdrawals - Get withdrawal history
router.get('/withdrawals', authenticate, walletController.getWithdrawalHistory);

// DELETE /api/wallet/withdrawals/:withdrawalId - Cancel pending withdrawal
router.delete('/withdrawals/:withdrawalId', authenticate, walletController.cancelWithdrawal);

// POST /api/wallet/tip - Send tip to another user
router.post('/tip', authenticate, walletController.sendTip);

/**
 * Admin Wallet Operations
 */

// POST /api/wallet/admin/credit - Issue promotional credit (admin only)
router.post('/admin/credit', authenticate, walletController.issueCredit);

// GET /api/wallet/admin/users/:userId/balance - Get any user's balance (admin only)
router.get('/admin/users/:userId/balance', authenticate, walletController.getUserBalance);

export default router;

