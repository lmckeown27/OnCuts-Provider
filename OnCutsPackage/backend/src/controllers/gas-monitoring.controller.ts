/**
 * Gas Monitoring Controller
 * 
 * API endpoints for gas wallet monitoring and alerts
 */

import { Request, Response } from 'express';
import { gasWalletMonitor } from '../services/gas-wallet-monitor.service';
import { gasWalletCron } from '../services/gas-wallet-cron.service';
import { logger } from '../utils/logger';

/**
 * GET /api/gas/status
 * Get current gas wallet status
 */
export const getGasWalletStatus = async (req: Request, res: Response) => {
  try {
    const status = await gasWalletMonitor.getGasWalletBalance();
    
    res.json({
      success: true,
      status,
    });
  } catch (error: any) {
    logger.error('Error fetching gas wallet status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch gas wallet status',
      error: error.message,
    });
  }
};

/**
 * GET /api/gas/usage
 * Get gas usage statistics
 */
export const getUsageStatistics = async (req: Request, res: Response) => {
  try {
    const usage = await gasWalletMonitor.getUsageStatistics();
    
    // Calculate totals and averages
    const values = Object.values(usage) as number[];
    const total = values.reduce((a, b) => a + b, 0);
    const average = values.length > 0 ? total / values.length : 0;
    const max = values.length > 0 ? Math.max(...values) : 0;
    const min = values.length > 0 ? Math.min(...values) : 0;
    
    res.json({
      success: true,
      usage,
      statistics: {
        totalDays: values.length,
        totalUsage: total,
        averageDaily: average,
        maxDaily: max,
        minDaily: min,
      },
    });
  } catch (error: any) {
    logger.error('Error fetching usage statistics:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch usage statistics',
      error: error.message,
    });
  }
};

/**
 * GET /api/gas/alerts
 * Get alert history
 */
export const getAlertHistory = async (req: Request, res: Response) => {
  try {
    const limit = parseInt(req.query.limit as string) || 20;
    const history = await gasWalletMonitor.getAlertHistory(limit);
    
    res.json({
      success: true,
      alerts: history,
      count: history.length,
    });
  } catch (error: any) {
    logger.error('Error fetching alert history:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch alert history',
      error: error.message,
    });
  }
};

/**
 * POST /api/gas/check-now
 * Manually trigger gas wallet check
 */
export const checkNow = async (req: Request, res: Response) => {
  try {
    logger.info('Manual gas wallet check triggered');
    const status = await gasWalletMonitor.checkAndAlert();
    
    res.json({
      success: true,
      message: 'Gas wallet check completed',
      status,
    });
  } catch (error: any) {
    logger.error('Error in manual gas wallet check:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check gas wallet',
      error: error.message,
    });
  }
};

/**
 * POST /api/gas/record-usage
 * Record gas usage (called after transactions)
 */
export const recordUsage = async (req: Request, res: Response) => {
  try {
    const { amountAPT } = req.body;
    
    if (!amountAPT || amountAPT <= 0) {
      return res.status(400).json({
        success: false,
        message: 'Invalid amount',
      });
    }
    
    await gasWalletMonitor.recordGasUsage(amountAPT);
    
    res.json({
      success: true,
      message: 'Usage recorded',
    });
  } catch (error: any) {
    logger.error('Error recording gas usage:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to record usage',
      error: error.message,
    });
  }
};

/**
 * GET /api/gas/cron-status
 * Get cron job status
 */
export const getCronStatus = async (req: Request, res: Response) => {
  try {
    const status = gasWalletCron.getStatus();
    
    res.json({
      success: true,
      cronStatus: status,
    });
  } catch (error: any) {
    logger.error('Error fetching cron status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch cron status',
      error: error.message,
    });
  }
};

/**
 * GET /api/gas/dashboard
 * Get complete dashboard data
 */
export const getDashboardData = async (req: Request, res: Response) => {
  try {
    const [status, usage, alerts, cronStatus] = await Promise.all([
      gasWalletMonitor.getGasWalletBalance(),
      gasWalletMonitor.getUsageStatistics(),
      gasWalletMonitor.getAlertHistory(10),
      Promise.resolve(gasWalletCron.getStatus()),
    ]);
    
    // Calculate statistics
    const values = Object.values(usage) as number[];
    const totalUsage = values.reduce((a, b) => a + b, 0);
    const averageDaily = values.length > 0 ? totalUsage / values.length : 0;
    
    res.json({
      success: true,
      dashboard: {
        gasWallet: status,
        usage: {
          daily: usage,
          total: totalUsage,
          average: averageDaily,
          daysTracked: values.length,
        },
        alerts: {
          recent: alerts,
          count: alerts.length,
        },
        monitoring: cronStatus,
      },
    });
  } catch (error: any) {
    logger.error('Error fetching dashboard data:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch dashboard data',
      error: error.message,
    });
  }
};

