/**
 * Wallet Routes V2
 * 
 * Production custodial wallet endpoints
 */

import express from 'express';
import { authenticate } from '../middleware/auth';
import * as walletController from '../controllers/wallet-v2.controller';

const router = express.Router();

// Balance & History
router.get('/balance', authenticate, walletController.getBalance);
router.get('/transactions', authenticate, walletController.getTransactionHistory);
router.get('/escrows', authenticate, walletController.getEscrows);

// Deposits
router.post('/deposit/intent', authenticate, walletController.createDepositIntent);

// Withdrawals
router.post('/withdraw/bank', authenticate, walletController.withdrawToBank);
router.post('/withdraw/onchain', authenticate, walletController.withdrawOnChain);
router.get('/withdrawals', authenticate, walletController.getWithdrawalHistory);

// Tips
router.post('/tip', authenticate, walletController.sendTip);

export default router;

