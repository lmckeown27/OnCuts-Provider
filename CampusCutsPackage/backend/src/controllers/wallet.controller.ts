/**
 * Wallet Controller
 * 
 * Handles all custodial wallet operations:
 * - Balance inquiries
 * - Deposits
 * - Withdrawals
 * - Transaction history
 * - Tips
 */

import { Response, NextFunction } from 'express';
import { AuthRequest } from '../middleware/auth';
import { ApiError } from '../middleware/errorHandler';
import ledgerService from '../services/ledger.service';
import paymentService from '../services/payment.service';
import payoutService from '../services/payout.service';
import { logger } from '../utils/logger';
import { dollarsToCents, centsToDollars } from '../types/wallet.types';

export const getBalance = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    
    const balance = await ledgerService.getUserBalance(userId);

    res.json({
      success: true,
      data: {
        available: centsToDollars(balance.balance_available),
        pending: centsToDollars(balance.balance_pending),
        locked: centsToDollars(balance.balance_locked),
        total: centsToDollars(balance.total_balance),
        available_cents: balance.balance_available,
        pending_cents: balance.balance_pending,
        locked_cents: balance.balance_locked,
        total_cents: balance.total_balance,
      },
    });
  } catch (error) {
    logger.error('Error getting balance:', error);
    next(error);
  }
};

export const createDepositIntent = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { amount } = req.body; // Amount in dollars

    if (!amount || amount <= 0) {
      throw new ApiError(400, 'Invalid amount');
    }

    const amountCents = dollarsToCents(amount);

    // Minimum deposit: $5
    if (amountCents < 500) {
      throw new ApiError(400, 'Minimum deposit is $5');
    }

    const result = await paymentService.createDepositIntent({
      userId,
      amountCents,
    });

    res.json({
      success: true,
      data: result,
    });
  } catch (error) {
    logger.error('Error creating deposit intent:', error);
    next(error);
  }
};

export const getTransactionHistory = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const limit = parseInt(req.query.limit as string) || 50;
    const offset = parseInt(req.query.offset as string) || 0;

    const result = await ledgerService.getLedgerHistory(userId, limit, offset);

    // Format amounts in dollars for readability
    const formattedEntries = result.entries.map((entry) => ({
      ...entry,
      amount_dollars: centsToDollars(entry.amount),
      balance_after_dollars: centsToDollars(entry.balance_after),
    }));

    res.json({
      success: true,
      data: {
        entries: formattedEntries,
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

export const requestWithdrawal = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { amount } = req.body; // Amount in dollars

    if (!amount || amount <= 0) {
      throw new ApiError(400, 'Invalid amount');
    }

    const amountCents = dollarsToCents(amount);

    // Minimum withdrawal: $10
    if (amountCents < 1000) {
      throw new ApiError(400, 'Minimum withdrawal is $10');
    }

    // Get user's Stripe account ID (should be set during onboarding)
    const balance = await ledgerService.getUserBalance(userId);
    
    if (balance.balance_available < amountCents) {
      throw new ApiError(400, 'Insufficient available balance');
    }

    // TODO: Get stripe_account_id from users table
    const stripeAccountId = 'acct_placeholder'; // Replace with actual lookup

    const withdrawalRequest = await payoutService.createWithdrawalRequest({
      user_id: userId,
      amount: amountCents,
      stripe_destination_id: stripeAccountId,
    });

    res.json({
      success: true,
      data: {
        withdrawal_id: withdrawalRequest.id,
        amount_dollars: centsToDollars(withdrawalRequest.amount),
        status: withdrawalRequest.status,
      },
    });
  } catch (error) {
    logger.error('Error requesting withdrawal:', error);
    next(error);
  }
};

export const getWithdrawalHistory = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const limit = parseInt(req.query.limit as string) || 20;
    const offset = parseInt(req.query.offset as string) || 0;

    const result = await payoutService.getWithdrawalHistory(userId, limit, offset);

    // Format amounts
    const formattedWithdrawals = result.withdrawals.map((w) => ({
      ...w,
      amount_dollars: centsToDollars(w.amount),
    }));

    res.json({
      success: true,
      data: {
        withdrawals: formattedWithdrawals,
        total: result.total,
        limit,
        offset,
      },
    });
  } catch (error) {
    logger.error('Error getting withdrawal history:', error);
    next(error);
  }
};

export const sendTip = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const fromUserId = req.user!.userId;
    const { toUserId, amount, bookingId } = req.body;

    if (!toUserId || !amount || amount <= 0) {
      throw new ApiError(400, 'Invalid tip parameters');
    }

    const amountCents = dollarsToCents(amount);

    // Minimum tip: $1
    if (amountCents < 100) {
      throw new ApiError(400, 'Minimum tip is $1');
    }

    await paymentService.processTip({
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

export const cancelWithdrawal = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { withdrawalId } = req.params;

    await payoutService.cancelWithdrawal(withdrawalId, userId);

    res.json({
      success: true,
      message: 'Withdrawal cancelled successfully',
    });
  } catch (error) {
    logger.error('Error cancelling withdrawal:', error);
    next(error);
  }
};

// Admin-only endpoints

export const issueCredit = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const adminId = req.user!.userId;
    const { userId, amount, description } = req.body;

    if (!userId || !amount || !description) {
      throw new ApiError(400, 'Missing required fields');
    }

    const amountCents = dollarsToCents(amount);

    await paymentService.issuePromotionalCredit({
      userId,
      amountCents,
      description,
      adminId,
    });

    res.json({
      success: true,
      message: 'Promotional credit issued',
      data: {
        user_id: userId,
        amount_dollars: amount,
      },
    });
  } catch (error) {
    logger.error('Error issuing credit:', error);
    next(error);
  }
};

export const getUserBalance = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { userId } = req.params;

    const balance = await ledgerService.getUserBalance(userId);

    res.json({
      success: true,
      data: {
        user_id: userId,
        available: centsToDollars(balance.balance_available),
        pending: centsToDollars(balance.balance_pending),
        locked: centsToDollars(balance.balance_locked),
        total: centsToDollars(balance.total_balance),
      },
    });
  } catch (error) {
    logger.error('Error getting user balance:', error);
    next(error);
  }
};

