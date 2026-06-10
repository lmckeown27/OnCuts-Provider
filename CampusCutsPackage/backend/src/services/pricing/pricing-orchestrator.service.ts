/**
 * Pricing Orchestrator Service
 * 
 * Coordinates the full pricing recompute pipeline:
 * 1. Aggregate metrics from bookings
 * 2. Update market metrics (MSI/MDI) for campuses
 * 3. Compute barber scores
 * 4. Calculate final prices
 * 5. Detect anomalies
 * 6. Log results
 * 
 * Can run for all barbers, specific campuses, or individual barbers.
 */

import { logger } from '../../utils/logger';
import { pool } from '../../database/connection';
import metricsAggregator from './metrics-aggregator.service';
import scoringEngine from './scoring-engine.service';
import marketMetrics from './market-metrics.service';
import priceCalculator from './price-calculator.service';
import { format } from 'date-fns';

export interface RecomputeOptions {
  barberIds?: string[];
  campusIds?: string[];
  full?: boolean; // If true, recompute all barbers regardless of changes
  periodDate?: Date;
}

export interface RecomputeResult {
  jobId: number;
  status: string;
  barbersProcessed: number;
  pricesUpdated: number;
  errorsCount: number;
  durationMs: number;
  summary: any;
}

class PricingOrchestratorService {
  /**
   * Full recompute pipeline
   */
  async recomputeAll(options: RecomputeOptions = {}): Promise<RecomputeResult> {
    const startTime = Date.now();
    const periodDate = options.periodDate || new Date();

    logger.info('🔄 Starting pricing recompute pipeline...');
    logger.info(`Options: ${JSON.stringify(options)}`);

    // Create job log
    const jobId = await this.createJobLog(options);

    try {
      // Step 1: Get scope (which barbers to process)
      const barberIds = await this.getBarbersToProcess(options);
      logger.info(`Scope: ${barberIds.length} barbers to process`);

      // Step 2: Update market metrics for relevant campuses
      await this.step2_updateMarketMetrics(options.campusIds);

      // Step 3: Process each barber
      let barbersProcessed = 0;
      let pricesUpdated = 0;
      let errorsCount = 0;

      for (const barberId of barberIds) {
        try {
          // Step 3a: Aggregate metrics
          const metrics = await metricsAggregator.aggregateBarberMetrics(barberId, periodDate);

          // Step 3b: Compute scores
          const score = await scoringEngine.calculateBarberScore(barberId, metrics, periodDate);

          // Step 3c: Calculate prices for all services
          const services = await this.getAllServices();
          for (const service of services) {
            await priceCalculator.calculateFinalPrice(
              barberId,
              service.id,
              score.effectiveScore,
              score.mdi,
              periodDate
            );
            pricesUpdated++;
          }

          barbersProcessed++;
        } catch (error) {
          logger.error(`Failed to process barber ${barberId}:`, error);
          errorsCount++;
        }
      }

      const durationMs = Date.now() - startTime;

      // Update job log
      const result: RecomputeResult = {
        jobId,
        status: errorsCount === 0 ? 'completed' : 'partial',
        barbersProcessed,
        pricesUpdated,
        errorsCount,
        durationMs,
        summary: {
          totalBarbers: barberIds.length,
          periodDate: format(periodDate, 'yyyy-MM-dd'),
          options,
        },
      };

      await this.updateJobLog(jobId, result);

      logger.info(`✅ Pricing recompute complete: ${barbersProcessed} barbers, ${pricesUpdated} prices, ${errorsCount} errors in ${durationMs}ms`);

      return result;
    } catch (error) {
      logger.error('❌ Pricing recompute failed:', error);
      
      await this.updateJobLog(jobId, {
        status: 'failed',
        errorsCount: 1,
        error_details: error instanceof Error ? error.message : String(error),
      });

      throw error;
    }
  }

  /**
   * Recompute for a single barber (on-demand)
   */
  async recomputeBarber(barberId: string, periodDate: Date = new Date()): Promise<void> {
    logger.info(`Recomputing prices for barber ${barberId}`);

    // Aggregate metrics
    const metrics = await metricsAggregator.aggregateBarberMetrics(barberId, periodDate);

    // Compute scores
    const score = await scoringEngine.calculateBarberScore(barberId, metrics, periodDate);

    // Calculate prices for all services
    const services = await this.getAllServices();
    for (const service of services) {
      await priceCalculator.calculateFinalPrice(
        barberId,
        service.id,
        score.effectiveScore,
        score.mdi,
        periodDate
      );
    }

    logger.info(`✅ Barber ${barberId} recompute complete`);
  }

  /**
   * Recompute for all barbers on a campus
   */
  async recomputeCampus(campusId: string, periodDate: Date = new Date()): Promise<void> {
    logger.info(`Recomputing prices for campus ${campusId}`);

    await this.recomputeAll({
      campusIds: [campusId],
      periodDate,
    });
  }

  /**
   * Get barbers to process based on options
   */
  private async getBarbersToProcess(options: RecomputeOptions): Promise<string[]> {
    let query = 'SELECT id FROM barbers WHERE is_active = true';
    const params: any[] = [];

    if (options.barberIds && options.barberIds.length > 0) {
      params.push(options.barberIds);
      query += ` AND id = ANY($${params.length})`;
    }

    if (options.campusIds && options.campusIds.length > 0) {
      params.push(options.campusIds);
      query += ` AND campus_id = ANY($${params.length})`;
    }

    const result = await pool.query(query, params);
    return result.rows.map(r => r.id);
  }

  /**
   * Step 2: Update market metrics
   */
  private async step2_updateMarketMetrics(campusIds?: string[]): Promise<void> {
    logger.info('Step 2: Updating market metrics...');

    if (campusIds && campusIds.length > 0) {
      for (const campusId of campusIds) {
        await marketMetrics.updateCampusMetrics(campusId, new Date());
      }
    } else {
      await marketMetrics.updateAllCampusMetrics();
    }
  }

  /**
   * Get all services
   */
  private async getAllServices(): Promise<Array<{ id: number }>> {
    const result = await pool.query(
      `SELECT id FROM services WHERE is_active = true`
    );
    return result.rows;
  }

  /**
   * Create job log entry
   */
  private async createJobLog(options: RecomputeOptions): Promise<number> {
    const result = await pool.query(
      `
      INSERT INTO price_recompute_log (
        job_type,
        trigger_source,
        triggered_by,
        campus_ids,
        barber_ids,
        is_full_recompute,
        status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING id
      `,
      [
        'manual', // TODO: Detect if cron vs manual
        'api',
        'system', // TODO: Get from auth context
        options.campusIds || [],
        options.barberIds || [],
        options.full || false,
        'running',
      ]
    );

    return result.rows[0].id;
  }

  /**
   * Update job log with results
   */
  private async updateJobLog(jobId: number, result: Partial<RecomputeResult> & { error_details?: string }): Promise<void> {
    await pool.query(
      `
      UPDATE price_recompute_log
      SET
        status = $2,
        barbers_processed = $3,
        prices_updated = $4,
        errors_count = $5,
        duration_ms = $6,
        summary = $7,
        error_details = $8,
        completed_at = CURRENT_TIMESTAMP
      WHERE id = $1
      `,
      [
        jobId,
        result.status || 'completed',
        result.barbersProcessed || 0,
        result.pricesUpdated || 0,
        result.errorsCount || 0,
        result.durationMs || 0,
        JSON.stringify(result.summary || {}),
        result.error_details || null,
      ]
    );
  }
}

export default new PricingOrchestratorService();

