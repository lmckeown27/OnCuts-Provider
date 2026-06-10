/**
 * Pricing Cron Service
 * 
 * Scheduled jobs for the dynamic pricing engine:
 * - Daily pricing recompute (2 AM)
 * - Hourly metrics aggregation
 * - Weekly market metrics update
 */

import cron from 'node-cron';
import { logger } from '../../utils/logger';
import pricingOrchestrator from './pricing-orchestrator.service';
import metricsAggregator from './metrics-aggregator.service';
import marketMetrics from './market-metrics.service';
import { subDays } from 'date-fns';

class PricingCronService {
  private dailyRecomputeJob: cron.ScheduledTask | null = null;
  private hourlyMetricsJob: cron.ScheduledTask | null = null;
  private weeklyMarketJob: cron.ScheduledTask | null = null;

  /**
   * Start all pricing cron jobs
   */
  start() {
    // Daily pricing recompute at 2 AM
    this.dailyRecomputeJob = cron.schedule('0 2 * * *', async () => {
      logger.info('🔄 Starting daily pricing recompute (cron)...');
      try {
        const result = await pricingOrchestrator.recomputeAll({
          full: false,  // Incremental update
          periodDate: subDays(new Date(), 1), // Yesterday's data
        });

        logger.info(`✅ Daily pricing recompute complete:`, result);
      } catch (error) {
        logger.error('❌ Daily pricing recompute failed:', error);
      }
    });

    // Hourly metrics aggregation
    this.hourlyMetricsJob = cron.schedule('0 * * * *', async () => {
      logger.info('📊 Starting hourly metrics aggregation (cron)...');
      try {
        const yesterday = subDays(new Date(), 1);
        await metricsAggregator.aggregateDailyMetricsForAllBarbers(yesterday);
        logger.info('✅ Hourly metrics aggregation complete');
      } catch (error) {
        logger.error('❌ Hourly metrics aggregation failed:', error);
      }
    });

    // Weekly market metrics update (Sunday at 3 AM)
    this.weeklyMarketJob = cron.schedule('0 3 * * 0', async () => {
      logger.info('📈 Starting weekly market metrics update (cron)...');
      try {
        await marketMetrics.updateAllCampusMetrics();
        logger.info('✅ Weekly market metrics update complete');
      } catch (error) {
        logger.error('❌ Weekly market metrics update failed:', error);
      }
    });

    logger.info('⏰ Pricing cron jobs started:');
    logger.info('   - Daily recompute: 2 AM (every day)');
    logger.info('   - Hourly metrics: Top of every hour');
    logger.info('   - Weekly market update: 3 AM Sunday');
  }

  /**
   * Stop all cron jobs
   */
  stop() {
    if (this.dailyRecomputeJob) {
      this.dailyRecomputeJob.stop();
      logger.info('Stopped daily pricing recompute job');
    }

    if (this.hourlyMetricsJob) {
      this.hourlyMetricsJob.stop();
      logger.info('Stopped hourly metrics aggregation job');
    }

    if (this.weeklyMarketJob) {
      this.weeklyMarketJob.stop();
      logger.info('Stopped weekly market metrics job');
    }
  }

  /**
   * Manually trigger daily recompute (for testing)
   */
  async triggerDailyRecompute() {
    logger.info('🔄 Manually triggering daily pricing recompute...');
    const result = await pricingOrchestrator.recomputeAll({
      full: false,
      periodDate: subDays(new Date(), 1),
    });
    logger.info('✅ Manual daily recompute complete:', result);
    return result;
  }
}

export default new PricingCronService();

