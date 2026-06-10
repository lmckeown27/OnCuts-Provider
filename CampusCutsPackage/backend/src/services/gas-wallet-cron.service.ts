/**
 * Gas Wallet Cron Service
 * 
 * Scheduled jobs for gas wallet monitoring
 */

import cron from 'node-cron';
import { gasWalletMonitor } from './gas-wallet-monitor.service';
import { logger } from '../utils/logger';

class GasWalletCronService {
  private jobs: cron.ScheduledTask[] = [];

  /**
   * Start all cron jobs
   */
  start(): void {
    logger.info('Starting gas wallet monitoring cron jobs...');

    // Check every 15 minutes
    const frequentCheck = cron.schedule('*/15 * * * *', async () => {
      try {
        logger.info('Running frequent gas wallet check (every 15 min)...');
        await gasWalletMonitor.checkAndAlert();
      } catch (error) {
        logger.error('Error in frequent gas wallet check:', error);
      }
    });

    this.jobs.push(frequentCheck);
    logger.info('✅ Frequent check job scheduled (every 15 minutes)');

    // Detailed check every hour
    const hourlyCheck = cron.schedule('0 * * * *', async () => {
      try {
        logger.info('Running hourly gas wallet detailed check...');
        const status = await gasWalletMonitor.checkAndAlert();
        const usage = await gasWalletMonitor.getUsageStatistics();
        
        logger.info('Gas Wallet Status:', {
          balance: status.balance,
          status: status.status,
          daysRemaining: status.estimatedDaysRemaining,
        });
        
        logger.info('Recent usage:', usage);
      } catch (error) {
        logger.error('Error in hourly gas wallet check:', error);
      }
    });

    this.jobs.push(hourlyCheck);
    logger.info('✅ Hourly detailed check job scheduled');

    // Daily summary at 9 AM
    const dailySummary = cron.schedule('0 9 * * *', async () => {
      try {
        logger.info('Generating daily gas wallet summary...');
        const status = await gasWalletMonitor.checkAndAlert();
        const usage = await gasWalletMonitor.getUsageStatistics();
        const history = await gasWalletMonitor.getAlertHistory(5);
        
        logger.info('Daily Gas Wallet Summary:', {
          currentBalance: status.balance,
          status: status.status,
          daysRemaining: status.estimatedDaysRemaining,
          recentAlerts: history.length,
          usagePattern: usage,
        });
      } catch (error) {
        logger.error('Error generating daily summary:', error);
      }
    });

    this.jobs.push(dailySummary);
    logger.info('✅ Daily summary job scheduled (9 AM)');

    logger.info(`🚀 Gas wallet monitoring active with ${this.jobs.length} cron jobs`);
  }

  /**
   * Stop all cron jobs
   */
  stop(): void {
    logger.info('Stopping gas wallet monitoring cron jobs...');
    this.jobs.forEach(job => job.stop());
    this.jobs = [];
    logger.info('✅ All gas wallet monitoring jobs stopped');
  }

  /**
   * Get status of all jobs
   */
  getStatus(): { jobCount: number; running: boolean } {
    return {
      jobCount: this.jobs.length,
      running: this.jobs.length > 0,
    };
  }
}

export const gasWalletCron = new GasWalletCronService();

