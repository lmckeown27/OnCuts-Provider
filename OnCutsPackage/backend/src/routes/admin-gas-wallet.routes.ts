/**
 * Admin Gas Wallet Routes
 * 
 * Monitor and manage the platform's APT gas wallet
 * Admin can:
 * - Check gas wallet balance
 * - View gas usage statistics
 * - Get refill instructions
 * - Fund from faucet (devnet only)
 */

import { Router } from 'express';
import gasWalletService from '../services/gas-wallet.service';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';

const router = Router();

/**
 * GET /admin/gas-wallet/status
 * Get current gas wallet status
 */
router.get('/status', async (req, res, next) => {
  try {
    const status = await gasWalletService.getGasWalletStatus();
    
    res.json({
      success: true,
      data: status,
    });
  } catch (error) {
    next(error);
  }
});

/**
 * GET /admin/gas-wallet/check
 * Check if gas wallet needs refill (alert levels)
 */
router.get('/check', async (req, res, next) => {
  try {
    const check = await gasWalletService.checkBalanceStatus();
    
    res.json({
      success: true,
      data: check,
    });
  } catch (error) {
    next(error);
  }
});

/**
 * GET /admin/gas-wallet/refill-instructions
 * Get instructions on how to refill gas wallet
 */
router.get('/refill-instructions', async (req, res, next) => {
  try {
    const instructions = gasWalletService.getRefillInstructions();
    
    res.json({
      success: true,
      data: instructions,
    });
  } catch (error) {
    next(error);
  }
});

/**
 * POST /admin/gas-wallet/fund-faucet
 * Deprecated: use Sui testnet faucet or fund the gas sponsor key.
 */
router.post('/fund-faucet', async (req, res, next) => {
  try {
    await gasWalletService.fundFromFaucet();
  } catch (error) {
    next(error);
  }
});

/**
 * GET /admin/gas-wallet/estimate
 * Estimate gas cost for different transaction types
 */
router.get('/estimate', async (req, res, next) => {
  try {
    const estimates = {
      create_escrow: gasWalletService.estimateGasCost('create_escrow'),
      release_payment: gasWalletService.estimateGasCost('release_payment'),
      refund: gasWalletService.estimateGasCost('refund'),
    };

    const aptPrice = await gasWalletService.getAptPrice();
    
    res.json({
      success: true,
      data: {
        gas_costs_apt: estimates,
        gas_costs_usd: {
          create_escrow: estimates.create_escrow * aptPrice,
          release_payment: estimates.release_payment * aptPrice,
          refund: estimates.refund * aptPrice,
        },
        apt_price_usd: aptPrice,
      },
    });
  } catch (error) {
    next(error);
  }
});

export default router;



