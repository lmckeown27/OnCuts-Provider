/**
 * Marketplace Cron Jobs
 * 
 * Schedules:
 * - Nightly (2am): recompute_bqs, update_prices, refresh_rankings
 * - Every 15 minutes: surge_detector
 */

import cron from 'node-cron';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { bqsService } from './bqs-calculation.service';
import { marketplacePricingService } from './marketplace-pricing.service';
import { rankingService } from './ranking-algorithm.service';
import { surgePricingService } from './surge-pricing.service';

export class MarketplaceCronService {
  private jobs: Map<string, cron.ScheduledTask> = new Map();

  /**
   * Log cron job execution
   */
  private async logCronExecution(
    jobName: string,
    status: 'success' | 'failed' | 'running',
    durationMs?: number,
    recordsProcessed?: number,
    errorMessage?: string
  ): Promise<void> {
    try {
      await pool.query(`
        INSERT INTO cron_history (job_name, executed_at, status, duration_ms, records_processed, error_message)
        VALUES ($1, NOW(), $2, $3, $4, $5)
      `, [jobName, status, durationMs, recordsProcessed, errorMessage]);
    } catch (error) {
      // Silently fail if PostgreSQL is not available (blockchain fallback mode)
      if (process.env.NODE_ENV !== 'production') {
        logger.debug(`Cron logging skipped (PostgreSQL unavailable): ${jobName}`);
      }
    }
  }

  /**
   * Nightly BQS Recomputation (2am)
   */
  private async jobRecomputeBQS(): Promise<void> {
    const jobName = 'recompute_bqs';
    const startTime = Date.now();

    try {
      await this.logCronExecution(jobName, 'running');

      logger.info('🌙 Starting nightly BQS recomputation...');

      const result = await bqsService.recomputeAllBQS();
      const duration = Date.now() - startTime;

      await this.logCronExecution(jobName, 'success', duration, result.processed);

      logger.info(`✅ BQS recomputation complete: ${result.processed} processed, ${result.failed} failed`);
    } catch (error: any) {
      const duration = Date.now() - startTime;
      await this.logCronExecution(jobName, 'failed', duration, 0, error.message);
      logger.error('❌ BQS recomputation failed:', error);
    }
  }

  /**
   * Nightly Pricing Update (2am)
   */
  private async jobUpdatePrices(): Promise<void> {
    const jobName = 'update_prices';
    const startTime = Date.now();

    try {
      await this.logCronExecution(jobName, 'running');

      logger.info('💰 Starting nightly pricing update...');

      const result = await marketplacePricingService.updateAllPricingBounds();
      const duration = Date.now() - startTime;

      await this.logCronExecution(jobName, 'success', duration, result.processed);

      logger.info(`✅ Pricing update complete: ${result.processed} processed, ${result.failed} failed`);
    } catch (error: any) {
      const duration = Date.now() - startTime;
      await this.logCronExecution(jobName, 'failed', duration, 0, error.message);
      logger.error('❌ Pricing update failed:', error);
    }
  }

  /**
   * Nightly Rank Refresh (2am)
   */
  private async jobRefreshRankings(): Promise<void> {
    const jobName = 'refresh_rankings';
    const startTime = Date.now();

    try {
      await this.logCronExecution(jobName, 'running');

      logger.info('📊 Starting nightly ranking refresh...');

      const result = await rankingService.refreshAllRankScores();
      const duration = Date.now() - startTime;

      await this.logCronExecution(jobName, 'success', duration, result.processed);

      logger.info(`✅ Ranking refresh complete: ${result.processed} processed, ${result.failed} failed`);
    } catch (error: any) {
      const duration = Date.now() - startTime;
      await this.logCronExecution(jobName, 'failed', duration, 0, error.message);
      logger.error('❌ Ranking refresh failed:', error);
    }
  }

  /**
   * Surge Detection (every 15 minutes)
   */
  private async jobSurgeDetection(): Promise<void> {
    const jobName = 'surge_detection';
    const startTime = Date.now();

    try {
      await this.logCronExecution(jobName, 'running');

      logger.info('🔥 Running surge detection...');

      // End expired surges first
      await surgePricingService.endExpiredSurges();

      // Check current surge status
      const result = await surgePricingService.checkAllMarketsSurge();
      const duration = Date.now() - startTime;

      await this.logCronExecution(jobName, 'success', duration, result.processed);

      if (result.surgeActive > 0) {
        logger.info(`🔥 Surge active in ${result.surgeActive} markets`);
      }
    } catch (error: any) {
      const duration = Date.now() - startTime;
      await this.logCronExecution(jobName, 'failed', duration, 0, error.message);
      logger.error('❌ Surge detection failed:', error);
    }
  }

  /**
   * Check if PostgreSQL is available
   */
  private async isPostgresAvailable(): Promise<boolean> {
    try {
      await pool.query('SELECT 1');
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Start all cron jobs
   */
  async startAllJobs(): Promise<void> {
    // Check if PostgreSQL is available
    const postgresAvailable = await this.isPostgresAvailable();
    
    if (!postgresAvailable) {
      logger.warn('⚠️  Marketplace cron jobs disabled: PostgreSQL not available');
      logger.warn('   The system will operate in blockchain-only mode');
      return;
    }

    logger.info('🚀 Starting marketplace cron jobs...');

    // Nightly jobs at 2am: BQS → Pricing → Rankings
    const nightlyJob = cron.schedule('0 2 * * *', async () => {
      logger.info('🌙 Starting nightly marketplace update (2am)...');
      
      // Run in sequence
      await this.jobRecomputeBQS();
      await this.jobUpdatePrices();
      await this.jobRefreshRankings();
      
      logger.info('✅ Nightly marketplace update complete');
    });

    this.jobs.set('nightly', nightlyJob);

    // Surge detection disabled - requires surge_events table
    // TODO: Re-enable when surge pricing feature is implemented
    // const surgeJob = cron.schedule('*/15 * * * *', async () => {
    //   await this.jobSurgeDetection();
    // });
    // this.jobs.set('surge', surgeJob);

    logger.info('✅ Marketplace cron jobs started:');
    logger.info('   - Nightly update: 2am (BQS → Pricing → Rankings)');
    logger.info('   - Surge detection: Disabled');
  }

  /**
   * Stop all cron jobs
   */
  stopAllJobs(): void {
    this.jobs.forEach((job, name) => {
      job.stop();
      logger.info(`Stopped cron job: ${name}`);
    });
    this.jobs.clear();
  }

  /**
   * Manually trigger BQS recomputation (for admin/testing)
   */
  async triggerBQSRecompute(): Promise<any> {
    logger.info('🔧 Manual BQS recomputation triggered');
    await this.jobRecomputeBQS();
  }

  /**
   * Manually trigger pricing update (for admin/testing)
   */
  async triggerPricingUpdate(): Promise<any> {
    logger.info('🔧 Manual pricing update triggered');
    await this.jobUpdatePrices();
  }

  /**
   * Manually trigger ranking refresh (for admin/testing)
   */
  async triggerRankingRefresh(): Promise<any> {
    logger.info('🔧 Manual ranking refresh triggered');
    await this.jobRefreshRankings();
  }

  /**
   * Manually trigger surge detection (for admin/testing)
   */
  async triggerSurgeDetection(): Promise<any> {
    logger.info('🔧 Manual surge detection triggered');
    await this.jobSurgeDetection();
  }

  /**
   * Get cron job history
   */
  async getCronHistory(limit: number = 100) {
    try {
      const result = await pool.query(`
        SELECT *
        FROM cron_history
        ORDER BY executed_at DESC
        LIMIT $1
      `, [limit]);

      return result.rows;
    } catch (error) {
      logger.error('Error getting cron history:', error);
      throw error;
    }
  }
}

export const marketplaceCronService = new MarketplaceCronService();

