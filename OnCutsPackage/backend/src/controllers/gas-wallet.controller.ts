/**
 * Gas Wallet Monitoring Controller
 * 
 * Provides endpoints for monitoring gas wallet balance and usage
 */

import { Request, Response } from 'express';
import { logger } from '../utils/logger';

// Mock data for demonstration
// In production, this would query chain RPC and PostgreSQL
const mockGasWalletData = {
  address: process.env.GAS_WALLET_ADDRESS || '0x1234...5678',
  balance: 45.7823, // APT
  dailyUsage: 0.0234, // APT per day
  alerts: [
    {
      level: 'warning' as const,
      message: 'Gas wallet balance below 50 APT threshold',
      timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(), // 2 hours ago
    },
  ],
  usageHistory: [
    { date: new Date(Date.now() - 6 * 24 * 60 * 60 * 1000).toISOString(), usage: 0.0189, balance: 46.2 },
    { date: new Date(Date.now() - 5 * 24 * 60 * 60 * 1000).toISOString(), usage: 0.0212, balance: 46.1 },
    { date: new Date(Date.now() - 4 * 24 * 60 * 60 * 1000).toISOString(), usage: 0.0198, balance: 46.0 },
    { date: new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString(), usage: 0.0245, balance: 45.9 },
    { date: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(), usage: 0.0267, balance: 45.8 },
    { date: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000).toISOString(), usage: 0.0223, balance: 45.8 },
    { date: new Date().toISOString(), usage: 0.0234, balance: 45.7823 },
  ],
};

/**
 * Get current gas wallet status
 */
export async function getGasWalletStatus(req: Request, res: Response) {
  try {
    // Calculate days remaining based on current balance and daily usage
    const daysRemaining = Math.floor(mockGasWalletData.balance / mockGasWalletData.dailyUsage);
    
    // Determine status
    let status: 'healthy' | 'warning' | 'critical';
    if (mockGasWalletData.balance > 100) {
      status = 'healthy';
    } else if (mockGasWalletData.balance > 20) {
      status = 'warning';
    } else {
      status = 'critical';
    }

    res.json({
      address: mockGasWalletData.address,
      balance: mockGasWalletData.balance,
      balanceFormatted: `${mockGasWalletData.balance.toFixed(4)} APT`,
      status,
      dailyUsage: mockGasWalletData.dailyUsage,
      daysRemaining,
      lastChecked: new Date().toISOString(),
    });
  } catch (error) {
    logger.error('Failed to get gas wallet status:', error);
    res.status(500).json({ error: 'Failed to get gas wallet status' });
  }
}

/**
 * Get gas wallet usage history
 */
export async function getGasWalletUsage(req: Request, res: Response) {
  try {
    const days = parseInt(req.query.days as string) || 7;
    
    // Return last N days of history
    const history = mockGasWalletData.usageHistory.slice(-days);

    res.json({
      address: mockGasWalletData.address,
      history,
      totalUsage: history.reduce((sum, day) => sum + day.usage, 0),
      averageDaily: history.reduce((sum, day) => sum + day.usage, 0) / history.length,
    });
  } catch (error) {
    logger.error('Failed to get gas wallet usage:', error);
    res.status(500).json({ error: 'Failed to get gas wallet usage' });
  }
}

/**
 * Get gas wallet alerts
 */
export async function getGasWalletAlerts(req: Request, res: Response) {
  try {
    const limit = parseInt(req.query.limit as string) || 10;
    
    res.json({
      alerts: mockGasWalletData.alerts.slice(0, limit),
      count: mockGasWalletData.alerts.length,
    });
  } catch (error) {
    logger.error('Failed to get gas wallet alerts:', error);
    res.status(500).json({ error: 'Failed to get gas wallet alerts' });
  }
}

/**
 * Trigger immediate balance check
 */
export async function checkGasWalletNow(req: Request, res: Response) {
  try {
    logger.info('Manual gas wallet check triggered');
    
    // In production, this would:
    // 1. Query chain for current balance
    // 2. Update PostgreSQL cache
    // 3. Check thresholds and send alerts if needed
    
    res.json({
      success: true,
      message: 'Gas wallet check completed',
      balance: mockGasWalletData.balance,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error('Failed to check gas wallet:', error);
    res.status(500).json({ error: 'Failed to check gas wallet' });
  }
}
