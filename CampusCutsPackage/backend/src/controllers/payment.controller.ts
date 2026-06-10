/**
 * Payment Controller
 * 
 * Handles payment operations for bookings
 */

import { Request, Response } from 'express';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import stripePaymentService from '../services/stripe-payment.service';
import stripeConnectService from '../services/stripe-connect.service';

/**
 * POST /api/payments/create-intent
 * Create payment intent for booking
 */
export const createPaymentIntent = async (req: Request, res: Response) => {
  try {
    const { amount, bookingId, barberId, studentId } = req.body;

    if (!amount || !bookingId) {
      return res.status(400).json({
        success: false,
        message: 'Amount and booking ID are required',
      });
    }

    // Get student details from PostgreSQL
    const studentResult = await pool.query(
      'SELECT id, email, first_name, last_name FROM users WHERE id = $1',
      [studentId]
    );
    
    if (studentResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Student not found',
      });
    }
    
    const student = studentResult.rows[0];

    // Create or get Stripe customer
    const customerId = await stripePaymentService.createOrGetCustomer(
      student.email,
      studentId,
      `${student.first_name} ${student.last_name}`
    );

    // Create payment intent with Stripe Connect split
    const paymentIntent = await stripePaymentService.createPaymentIntent({
      amount,
      customerId,
      barberId, // Pass barberId for Stripe Connect destination
      metadata: {
        bookingId,
        barberId,
        studentId,
      },
    });

    logger.info(`Payment intent created for booking: ${bookingId}`);

    res.json({
      success: true,
      data: {
        clientSecret: paymentIntent.clientSecret,
        paymentIntentId: paymentIntent.paymentIntentId,
        amount: paymentIntent.amount,
        platformFee: paymentIntent.platformFee,
        barberAmount: paymentIntent.barberAmount,
      },
    });
  } catch (error: any) {
    logger.error('Error creating payment intent:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to create payment intent',
    });
  }
};

/**
 * GET /api/payments/:paymentIntentId/status
 * Get payment status
 */
export const getPaymentStatus = async (req: Request, res: Response) => {
  try {
    const { paymentIntentId } = req.params;

    const paymentIntent = await stripePaymentService.getPaymentIntent(paymentIntentId);

    res.json({
      success: true,
      data: {
        id: paymentIntent.id,
        status: paymentIntent.status,
        amount: paymentIntent.amount / 100,
        currency: paymentIntent.currency,
        metadata: paymentIntent.metadata,
      },
    });
  } catch (error: any) {
    logger.error('Error getting payment status:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get payment status',
    });
  }
};

/**
 * POST /api/payments/:paymentIntentId/cancel
 * Cancel payment
 */
export const cancelPayment = async (req: Request, res: Response) => {
  try {
    const { paymentIntentId } = req.params;

    await stripePaymentService.cancelPaymentIntent(paymentIntentId);

    logger.info(`Payment cancelled: ${paymentIntentId}`);

    res.json({
      success: true,
      message: 'Payment cancelled successfully',
    });
  } catch (error: any) {
    logger.error('Error cancelling payment:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to cancel payment',
    });
  }
};

/**
 * POST /api/payments/:paymentIntentId/refund
 * Create refund
 */
export const createRefund = async (req: Request, res: Response) => {
  try {
    const { paymentIntentId } = req.params;
    const { amount, reason } = req.body;

    const refund = await stripePaymentService.createRefund(paymentIntentId, amount);

    logger.info(`Refund created: ${refund.id} for payment: ${paymentIntentId}`);

    res.json({
      success: true,
      message: 'Refund created successfully',
      data: {
        refundId: refund.id,
        amount: refund.amount / 100,
        status: refund.status,
      },
    });
  } catch (error: any) {
    logger.error('Error creating refund:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to create refund',
    });
  }
};

/**
 * GET /api/payments/customer/:customerId/payment-methods
 * Get customer payment methods
 */
export const getPaymentMethods = async (req: Request, res: Response) => {
  try {
    const { customerId } = req.params;

    const paymentMethods = await stripePaymentService.getCustomerPaymentMethods(customerId);

    res.json({
      success: true,
      data: paymentMethods.map(pm => ({
        id: pm.id,
        type: pm.type,
        card: pm.card ? {
          brand: pm.card.brand,
          last4: pm.card.last4,
          expMonth: pm.card.exp_month,
          expYear: pm.card.exp_year,
        } : null,
      })),
    });
  } catch (error: any) {
    logger.error('Error getting payment methods:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get payment methods',
    });
  }
};

/**
 * POST /api/payments/barber/connect
 * Create Stripe Connect account for barber
 */
export const createBarberConnectAccount = async (req: Request, res: Response) => {
  try {
    const { userId, email, firstName, lastName } = req.body;

    if (!userId || !email) {
      return res.status(400).json({
        success: false,
        message: 'User ID and email are required',
      });
    }

    // Create Connect account
    const accountId = await stripeConnectService.createConnectAccount({
      userId,
      email,
      firstName,
      lastName,
    });

    // Create onboarding link
    const accountLink = await stripeConnectService.createAccountLink(accountId);

    logger.info(`Stripe Connect account created for barber: ${userId}`);

    res.json({
      success: true,
      message: 'Connect account created successfully',
      data: {
        accountId,
        onboardingUrl: accountLink.url,
      },
    });
  } catch (error: any) {
    logger.error('Error creating Connect account:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to create Connect account',
    });
  }
};

/**
 * GET /api/payments/barber/:accountId/status
 * Get barber Connect account status
 */
export const getBarberAccountStatus = async (req: Request, res: Response) => {
  try {
    const { accountId } = req.params;

    const account = await stripeConnectService.getAccount(accountId);
    const isOnboarded = await stripeConnectService.isAccountOnboarded(accountId);

    res.json({
      success: true,
      data: {
        accountId: account.id,
        isOnboarded,
        chargesEnabled: account.charges_enabled,
        payoutsEnabled: account.payouts_enabled,
        detailsSubmitted: account.details_submitted,
      },
    });
  } catch (error: any) {
    logger.error('Error getting account status:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get account status',
    });
  }
};

/**
 * POST /api/payments/barber/:accountId/payout
 * Create payout to barber
 */
export const createBarberPayout = async (req: Request, res: Response) => {
  try {
    const { accountId } = req.params;
    const { amount, bookingId } = req.body;

    if (!amount) {
      return res.status(400).json({
        success: false,
        message: 'Amount is required',
      });
    }

    // Check if account is onboarded
    const isOnboarded = await stripeConnectService.isAccountOnboarded(accountId);
    if (!isOnboarded) {
      return res.status(400).json({
        success: false,
        message: 'Barber account is not fully onboarded',
      });
    }

    // Create payout
    const transfer = await stripeConnectService.createPayout(accountId, amount, {
      bookingId: bookingId || '',
    });

    logger.info(`Payout created for barber account: ${accountId}`);

    res.json({
      success: true,
      message: 'Payout created successfully',
      data: {
        transferId: transfer.id,
        amount: transfer.amount / 100,
        status: 'succeeded',
      },
    });
  } catch (error: any) {
    logger.error('Error creating payout:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to create payout',
    });
  }
};

/**
 * GET /api/payments/barber/:accountId/balance
 * Get barber account balance
 */
export const getBarberBalance = async (req: Request, res: Response) => {
  try {
    const { accountId } = req.params;

    const balance = await stripeConnectService.getAccountBalance(accountId);

    res.json({
      success: true,
      data: balance,
    });
  } catch (error: any) {
    logger.error('Error getting barber balance:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get balance',
    });
  }
};

/**
 * GET /api/payments/barber/:accountId/payouts
 * Get barber payout history
 */
export const getBarberPayoutHistory = async (req: Request, res: Response) => {
  try {
    const { accountId } = req.params;
    const limit = parseInt(req.query.limit as string) || 10;

    const payouts = await stripeConnectService.getPayoutHistory(accountId, limit);

    res.json({
      success: true,
      data: payouts.map(payout => ({
        id: payout.id,
        amount: payout.amount / 100,
        created: new Date(payout.created * 1000).toISOString(),
        metadata: payout.metadata,
      })),
    });
  } catch (error: any) {
    logger.error('Error getting payout history:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to get payout history',
    });
  }
};

/**
 * GET /api/payments/barber/:accountId/dashboard-link
 * Get Stripe Express dashboard login link
 */
export const getBarberDashboardLink = async (req: Request, res: Response) => {
  try {
    const { accountId } = req.params;

    const loginUrl = await stripeConnectService.createLoginLink(accountId);

    res.json({
      success: true,
      data: {
        url: loginUrl,
      },
    });
  } catch (error: any) {
    logger.error('Error creating dashboard link:', error);
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to create dashboard link',
    });
  }
};
