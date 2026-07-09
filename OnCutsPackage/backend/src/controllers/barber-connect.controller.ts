/**
 * Barber Connect Controller
 * 
 * Step 5: Use Stripe Connect for barbers to receive payouts
 * Handles barber onboarding to Stripe Connect Express accounts
 */

import { Response, NextFunction } from 'express';
import stripeService from '../services/stripe.service';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';
import type { AuthRequest } from '../middleware/auth';

/**
 * Create Stripe Connect account for barber
 * POST /api/barber/connect/create
 * 
 * Step 5 from instructions: Onboard each barber with Stripe connected account
 */
export const createConnectAccount = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user!.userId;
    // Role check is handled by requireRole middleware in routes

    logger.info('Creating Stripe Connect account for barber', {
      user_id: userId,
    });

    // 1. Check if barber already has Connect account
    const userResult = await pool.query(
      `SELECT stripe_account_id, email, first_name, last_name FROM users WHERE id = $1`,
      [userId]
    );

    if (userResult.rows.length === 0) {
      throw new ApiError(404, 'User not found');
    }

    const user = userResult.rows[0];

    if (user.stripe_account_id) {
      // Already has account, just return onboarding link
      const accountLink = await stripeService.createAccountLink(
        user.stripe_account_id,
        `${process.env.FRONTEND_URL}/web/barber/connect/refresh`,
        `${process.env.FRONTEND_URL}/web/barber/connect/return`
      );

      return res.status(200).json({
        success: true,
        message: 'Connect account already exists',
        data: {
          account_id: user.stripe_account_id,
          onboarding_url: accountLink,
        },
      });
    }

    // 2. Create new Stripe Connect account
    const accountId = await stripeService.createConnectedAccount({
      email: user.email,
      firstName: user.first_name,
      lastName: user.last_name,
    });

    // 3. Save account ID to database
    await pool.query(
      `UPDATE users SET stripe_account_id = $1 WHERE id = $2`,
      [accountId, userId]
    );

    // 4. Create account link for onboarding
    const accountLink = await stripeService.createAccountLink(
      accountId,
      `${process.env.FRONTEND_URL}/web/barber/connect/refresh`,
      `${process.env.FRONTEND_URL}/web/barber/connect/return`
    );

    // 5. Audit log
    logger.info('Stripe Connect account created', {
      user_id: userId,
      action: 'STRIPE_CONNECT_ACCOUNT_CREATED',
      account_id: accountId,
    });

    logger.info('✅ Stripe Connect account created', {
      user_id: userId,
      account_id: accountId,
    });

    res.status(201).json({
      success: true,
      message: 'Connect account created successfully',
      data: {
        account_id: accountId,
        onboarding_url: accountLink,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Get Connect account status
 * GET /api/barber/connect/status
 */
export const getConnectStatus = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user!.userId;
    // Role check is handled by requireRole middleware in routes

    const userResult = await pool.query(
      `SELECT stripe_account_id FROM users WHERE id = $1`,
      [userId]
    );

    if (userResult.rows.length === 0) {
      throw new ApiError(404, 'User not found');
    }

    const stripeAccountId = userResult.rows[0].stripe_account_id;

    if (!stripeAccountId) {
      return res.status(200).json({
        success: true,
        data: {
          has_account: false,
          details_submitted: false,
          charges_enabled: false,
          payouts_enabled: false,
        },
      });
    }

    // Get account status from Stripe
    const status = await stripeService.getAccountStatus(stripeAccountId);

    // Sync database with current Stripe status
    await pool.query(
      `UPDATE users 
       SET stripe_payouts_enabled = $1, stripe_charges_enabled = $2 
       WHERE id = $3`,
      [status.payoutsEnabled, status.chargesEnabled, userId]
    );

    res.status(200).json({
      success: true,
      data: {
        has_account: true,
        account_id: stripeAccountId,
        ...status,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Refresh onboarding link
 * POST /api/barber/connect/refresh
 */
export const refreshOnboardingLink = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user!.userId;
    // Role check is handled by requireRole middleware in routes

    const userResult = await pool.query(
      `SELECT stripe_account_id FROM users WHERE id = $1`,
      [userId]
    );

    const stripeAccountId = userResult.rows[0]?.stripe_account_id;

    if (!stripeAccountId) {
      throw new ApiError(400, 'No Connect account found. Create one first.');
    }

    // Create new account link
    const accountLink = await stripeService.createAccountLink(
      stripeAccountId,
      `${process.env.FRONTEND_URL}/web/barber/connect/refresh`,
      `${process.env.FRONTEND_URL}/web/barber/connect/return`
    );

    res.status(200).json({
      success: true,
      message: 'Onboarding link refreshed',
      data: {
        onboarding_url: accountLink,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Handle successful onboarding return
 * GET /api/barber/connect/return
 */
export const handleOnboardingReturn = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user!.userId;

    logger.info('Barber returned from Stripe onboarding', {
      user_id: userId,
    });

    // Get updated account status
    const userResult = await pool.query(
      `SELECT stripe_account_id FROM users WHERE id = $1`,
      [userId]
    );

    const stripeAccountId = userResult.rows[0]?.stripe_account_id;

    if (!stripeAccountId) {
      throw new ApiError(400, 'No Connect account found');
    }

    const status = await stripeService.getAccountStatus(stripeAccountId);

    // Update the database with current Stripe status
    await pool.query(
      `UPDATE users 
       SET stripe_payouts_enabled = $1, stripe_charges_enabled = $2 
       WHERE id = $3`,
      [status.payoutsEnabled, status.chargesEnabled, userId]
    );

    // Audit log
    logger.info('Stripe Connect onboarding completed', {
      user_id: userId,
      action: 'STRIPE_CONNECT_ONBOARDING_COMPLETED',
      account_id: stripeAccountId,
      status,
    });

    res.status(200).json({
      success: true,
      message: 'Onboarding status retrieved',
      data: status,
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Get Stripe Express dashboard login link
 * GET /api/barber/connect/dashboard
 */
export const getDashboardLink = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user!.userId;
    // Role check is handled by requireRole middleware in routes

    const userResult = await pool.query(
      `SELECT stripe_account_id FROM users WHERE id = $1`,
      [userId]
    );

    const stripeAccountId = userResult.rows[0]?.stripe_account_id;

    if (!stripeAccountId) {
      throw new ApiError(400, 'No Connect account found. Complete onboarding first.');
    }

    // Create login link for Stripe Express dashboard
    const loginLink = await stripeService.createExpressLoginLink(stripeAccountId);

    res.status(200).json({
      success: true,
      data: {
        dashboard_url: loginLink,
      },
    });
  } catch (error) {
    next(error);
  }
};

