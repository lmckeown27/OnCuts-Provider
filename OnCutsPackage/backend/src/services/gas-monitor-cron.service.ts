/**
 * Gas Monitor Cron Service
 * 
 * Periodically checks gas wallet balance and creates top-up requests
 */

import cron from 'node-cron';
import gasEstimatorService from './gas-estimator.service';
import { logger } from '../utils/logger';

class GasMonitorCronService {
  private cronJob: cron.ScheduledTask | null = null;
  private isRunning: boolean = false;

  /**
   * Start the cron job
   * Default: every 30 minutes
   */
  start(schedule: string = '*/30 * * * *') {
    if (this.cronJob) {
      logger.warn('Gas monitor cron job already running');
      return;
    }

    // Validate cron expression
    if (!cron.validate(schedule)) {
      logger.error(`Invalid cron schedule: ${schedule}`);
      return;
    }

    this.cronJob = cron.schedule(schedule, async () => {
      if (this.isRunning) {
        logger.debug('Previous gas monitor job still running, skipping this cycle');
        return;
      }

      this.isRunning = true;

      try {
        logger.info('🔍 Running gas monitor check...');

        // Check gas estimate and auto-create top-up if needed
        const requestId = await gasEstimatorService.checkAndCreateTopUpIfNeeded();

        if (requestId) {
          logger.info(`✅ Gas monitor created top-up request: ${requestId}`);
        } else {
          logger.debug('✅ Gas monitor check complete - no action needed');
        }
      } catch (error) {
        logger.error('❌ Gas monitor cron job failed:', error);
      } finally {
        this.isRunning = false;
      }
    });

    logger.info(`⏰ Gas monitor cron job started (schedule: ${schedule})`);

    // Run immediately on start
    this.runNow();
  }

  /**
   * Stop the cron job
   */
  stop() {
    if (this.cronJob) {
      this.cronJob.stop();
      this.cronJob = null;
      logger.info('⏹️  Gas monitor cron job stopped');
    }
  }

  /**
   * Run the job immediately (manual trigger)
   */
  async runNow() {
    if (this.isRunning) {
      logger.warn('Gas monitor job already running');
      return;
    }

    this.isRunning = true;

    try {
      logger.info('🔍 Running gas monitor check (manual trigger)...');

      const requestId = await gasEstimatorService.checkAndCreateTopUpIfNeeded();

      if (requestId) {
        logger.info(`✅ Gas monitor created top-up request: ${requestId}`);
      } else {
        logger.debug('✅ Gas monitor check complete - no action needed');
      }
    } catch (error) {
      logger.error('❌ Gas monitor manual run failed:', error);
    } finally {
      this.isRunning = false;
    }
  }
}

// Singleton instance
const gasMonitorCronService = new GasMonitorCronService();

export default gasMonitorCronService;

