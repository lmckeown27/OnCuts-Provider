/**
 * Live Transaction Feed Controller
 * 
 * Provides API endpoints for admin dashboard live transaction monitoring
 * Fetches recent transactions from Sui (stub) and Stripe
 */

import { Request, Response, NextFunction } from 'express';
import suiMonitorService from '../services/sui-monitor.service';
import stripeMonitorService from '../services/stripe-monitor.service';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';

/**
 * Get combined transaction feed (Sui + Stripe)
 * GET /api/admin/live-feed
 */
export const getLiveFeed = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const limit = parseInt(req.query.limit as string) || 50;
    const platform = req.query.platform as string; // 'sui', 'stripe', or 'all'

    let query = `
      SELECT * FROM admin_transaction_feed
    `;

    const params: any[] = [];

    if (platform && platform !== 'all') {
      query += ` WHERE platform = $1`;
      params.push(platform);
    }

    query += ` ORDER BY timestamp DESC LIMIT $${params.length + 1}`;
    params.push(limit);

    const result = await pool.query(query, params);

    logger.info(`📊 Fetched ${result.rows.length} transactions for admin live feed`);

    res.json({
      success: true,
      data: result.rows,
      count: result.rows.length,
      platform: platform || 'all',
    });
  } catch (error) {
    logger.error('Failed to fetch live feed:', error);
    next(error);
  }
};

/**
 * Get recent Sui transactions (indexer/RPC integration pending)
 * GET /api/admin/live-feed/sui
 */
export const getSuiTransactions = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const limit = parseInt(req.query.limit as string) || 50;
    const transactions = await suiMonitorService.getRecentTransactions(limit);

    res.json({
      success: true,
      data: transactions,
      count: transactions.length,
      platform: 'sui',
    });
  } catch (error) {
    logger.error('Failed to fetch Sui transactions:', error);
    next(error);
  }
};

/**
 * Get recent Stripe events
 * GET /api/admin/live-feed/stripe
 */
export const getStripeEvents = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const limit = parseInt(req.query.limit as string) || 50;
    const events = await stripeMonitorService.getRecentEvents(limit);

    res.json({
      success: true,
      data: events,
      count: events.length,
      platform: 'stripe',
    });
  } catch (error) {
    logger.error('Failed to fetch Stripe events:', error);
    next(error);
  }
};

/**
 * Get platform statistics
 * GET /api/admin/live-feed/stats
 */
export const getPlatformStats = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    // Fetch real-time stats from view
    const statsResult = await pool.query(`
      SELECT * FROM realtime_platform_stats
    `);

    // Fetch Stripe payment stats
    const stripeStats = await stripeMonitorService.getPaymentStats();

    // Fetch daily stats for chart
    const dailyResult = await pool.query(`
      SELECT * FROM daily_transaction_stats
      ORDER BY date DESC
      LIMIT 30
    `);

    res.json({
      success: true,
      data: {
        realtime: statsResult.rows,
        stripe_payments: stripeStats,
        daily: dailyResult.rows,
      },
    });
  } catch (error) {
    logger.error('Failed to fetch platform stats:', error);
    next(error);
  }
};

/**
 * Search transactions
 * GET /api/admin/live-feed/search
 */
export const searchTransactions = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const {
      query: searchQuery,
      platform,
      from_date,
      to_date,
      min_amount,
      max_amount,
    } = req.query;

    let sql = `
      SELECT * FROM admin_transaction_feed
      WHERE 1=1
    `;
    const params: any[] = [];
    let paramIndex = 1;

    if (platform && platform !== 'all') {
      sql += ` AND platform = $${paramIndex}`;
      params.push(platform);
      paramIndex++;
    }

    if (searchQuery) {
      sql += ` AND (
        transaction_id ILIKE $${paramIndex} OR
        from_address ILIKE $${paramIndex} OR
        to_address ILIKE $${paramIndex} OR
        description ILIKE $${paramIndex}
      )`;
      params.push(`%${searchQuery}%`);
      paramIndex++;
    }

    if (from_date) {
      sql += ` AND timestamp >= $${paramIndex}`;
      params.push(from_date);
      paramIndex++;
    }

    if (to_date) {
      sql += ` AND timestamp <= $${paramIndex}`;
      params.push(to_date);
      paramIndex++;
    }

    if (min_amount) {
      sql += ` AND amount_usd >= $${paramIndex}`;
      params.push(parseFloat(min_amount as string));
      paramIndex++;
    }

    if (max_amount) {
      sql += ` AND amount_usd <= $${paramIndex}`;
      params.push(parseFloat(max_amount as string));
      paramIndex++;
    }

    sql += ` ORDER BY timestamp DESC LIMIT 100`;

    const result = await pool.query(sql, params);

    res.json({
      success: true,
      data: result.rows,
      count: result.rows.length,
    });
  } catch (error) {
    logger.error('Failed to search transactions:', error);
    next(error);
  }
};

