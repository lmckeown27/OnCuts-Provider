/**
 * Wallet Controller V2
 * 
 * User-facing wallet operations with direct payment system (no escrow)
 */

import { Response, NextFunction } from 'express';
import { AuthRequest } from '../middleware/auth';
import { ApiError } from '../middleware/errorHandler';
import transactionService from '../services/transaction.service';
import paymentServiceV2 from '../services/payment-v2.service';
import payoutServiceV2 from '../services/payout-v2.service';
// ESCROW DISABLED - Direct payments only
// import escrowService from '../services/escrow.service';
import { logger } from '../utils/logger';
import { pool } from '../database/connection';

/**
 * Get wallet balance
 * GET /api/wallet/balance
 */
export const getBalance = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    
    const balance = await transactionService.getUserBalance(userId);

    res.json({
      success: true,
      data: {
        available_dollars: balance.available_amount / 100,
        pending_dollars: balance.pending_amount / 100,
        total_dollars: balance.total_balance / 100,
        available_cents: balance.available_amount,
        pending_cents: balance.pending_amount,
        total_cents: balance.total_balance,
      },
    });
  } catch (error) {
    logger.error('Error getting balance:', error);
    next(error);
  }
};

/**
 * Create deposit intent
 * POST /api/wallet/deposit/intent
 */
export const createDepositIntent = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { amount } = req.body;

    if (!amount || amount <= 0) {
      throw new ApiError(400, 'Invalid amount');
    }

    const amountCents = Math.round(amount * 100);

    // Minimum deposit: $5
    if (amountCents < 500) {
      throw new ApiError(400, 'Minimum deposit is $5');
    }

    const result = await paymentServiceV2.createDepositIntent(userId, amountCents);

    res.json({
      success: true,
      data: result,
    });
  } catch (error) {
    logger.error('Error creating deposit intent:', error);
    next(error);
  }
};

/**
 * Get transaction history
 * GET /api/wallet/transactions
 */
export const getTransactionHistory = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const limit = parseInt(req.query.limit as string) || 50;
    const offset = parseInt(req.query.offset as string) || 0;

    const result = await transactionService.getTransactionHistory(userId, limit, offset);

    // Format amounts in dollars
    const formattedTransactions = result.transactions.map(tx => ({
      ...tx,
      amount_dollars: tx.amount / 100,
    }));

    res.json({
      success: true,
      data: {
        transactions: formattedTransactions,
        total: result.total,
        limit,
        offset,
      },
    });
  } catch (error) {
    logger.error('Error getting transaction history:', error);
    next(error);
  }
};

/**
 * Request withdrawal to bank
 * POST /api/wallet/withdraw/bank
 */
export const withdrawToBank = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { amount } = req.body;

    if (!amount || amount <= 0) {
      throw new ApiError(400, 'Invalid amount');
    }

    const amountCents = Math.round(amount * 100);

    // Minimum withdrawal: $10
    if (amountCents < 1000) {
      throw new ApiError(400, 'Minimum withdrawal is $10');
    }

    // Get user's Stripe account ID
    const userResult = await pool.query(
      `SELECT stripe_account_id FROM users WHERE id = $1`,
      [userId]
    );

    if (!userResult.rows[0]?.stripe_account_id) {
      throw new ApiError(400, 'Stripe account not connected. Please complete payout onboarding first.');
    }

    const stripeAccountId = userResult.rows[0].stripe_account_id;

    const result = await payoutServiceV2.withdrawToBank({
      userId,
      amountCents,
      stripeAccountId,
    });

    res.json({
      success: true,
      data: {
        payout_id: result.payoutId,
        amount_dollars: amount,
      },
      message: 'Withdrawal processed successfully',
    });
  } catch (error) {
    logger.error('Error processing withdrawal:', error);
    next(error);
  }
};

/**
 * Request on-chain withdrawal
 * POST /api/wallet/withdraw/onchain
 */
export const withdrawOnChain = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { amount, destinationAddress, chain } = req.body;

    if (!amount || amount <= 0) {
      throw new ApiError(400, 'Invalid amount');
    }

    if (!destinationAddress) {
      throw new ApiError(400, 'Destination address required');
    }

    const amountCents = Math.round(amount * 100);

    // Minimum withdrawal: $10
    if (amountCents < 1000) {
      throw new ApiError(400, 'Minimum withdrawal is $10');
    }

    const result = await payoutServiceV2.withdrawOnChain({
      userId,
      amountCents,
      destinationAddress,
      chain: chain || 'sui',
    });

    res.json({
      success: true,
      data: {
        queue_id: result.queueId,
        status: result.status,
        amount_dollars: amount,
      },
      message: 'Withdrawal queued for batching. Will be processed within 15 minutes.',
    });
  } catch (error) {
    logger.error('Error queuing on-chain withdrawal:', error);
    next(error);
  }
};

/**
 * Get withdrawal history
 * GET /api/wallet/withdrawals
 */
export const getWithdrawalHistory = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;

    const withdrawals = await payoutServiceV2.getWithdrawalHistory(userId);

    // Format amounts
    const formatted = withdrawals.map(w => ({
      ...w,
      amount_dollars: w.amount / 100,
    }));

    res.json({
      success: true,
      data: formatted,
    });
  } catch (error) {
    logger.error('Error getting withdrawal history:', error);
    next(error);
  }
};

/**
 * Send tip
 * POST /api/wallet/tip
 */
export const sendTip = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const fromUserId = req.user!.userId;
    const { toUserId, amount, bookingId } = req.body;

    if (!toUserId || !amount || amount <= 0) {
      throw new ApiError(400, 'Invalid tip parameters');
    }

    const amountCents = Math.round(amount * 100);

    // Minimum tip: $1
    if (amountCents < 100) {
      throw new ApiError(400, 'Minimum tip is $1');
    }

    await paymentServiceV2.processTip({
      fromUserId,
      toUserId,
      amountCents,
      bookingId,
    });

    res.json({
      success: true,
      message: 'Tip sent successfully',
      data: {
        amount_dollars: amount,
        to_user_id: toUserId,
      },
    });
  } catch (error) {
    logger.error('Error sending tip:', error);
    next(error);
  }
};

/**
 * Get escrows for user (DEPRECATED - No escrow in direct payment flow)
 * GET /api/wallet/escrows
 */
export const getEscrows = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    // Escrow is disabled - return empty array
    res.json({
      success: true,
      data: [],
      message: 'Escrow is disabled. Platform uses direct payments.',
    });
  } catch (error) {
    logger.error('Error getting escrows:', error);
    next(error);
  }
};
