/**
 * Scoring Engine Service
 * 
 * Computes barber performance scores (0-100) from raw metrics:
 * - Quality Score (ratings + repeat rate)
 * - Reliability Score (on-time % + low no-show %)
 * - Demand Score (bookings relative to campus peers)
 * - Performance Score (weighted combination)
 * - Effective Score (market-adjusted with MSI)
 */

import { logger } from '../../utils/logger';
import { pool } from '../../database/connection';
import Decimal from 'decimal.js';
import type { BarberMetric } from './metrics-aggregator.service';

export interface PricingConfig {
  qualityWeight: number;
  reliabilityWeight: number;
  demandWeight: number;
  ratingWeight: number;
  repeatRateWeight: number;
  onTimeWeight: number;
  noShowWeight: number;
  msiInfluence: number;
  newBarberBookingThreshold: number;
  newBarberQualityBoost: number;
}

export interface BarberScore {
  barberId: string;
  periodDate: Date;
  qualityScore: number;
  reliabilityScore: number;
  demandScore: number;
  performanceScore: number;
  effectiveScore: number;
  campusId: string;
  msi: number;
  mdi: number;
  isNewBarber: boolean;
  totalLifetimeBookings: number;
  breakdown: any;
}

class ScoringEngineService {
  /**
   * Calculate all scores for a barber
   */
  async calculateBarberScore(
    barberId: string,
    metric: BarberMetric,
    periodDate: Date
  ): Promise<BarberScore> {
    logger.info(`Calculating scores for barber ${barberId}`);

    // Load config
    const config = await this.loadConfig();

    // Get barber's campus and lifetime stats
    const barberInfo = await this.getBarberInfo(barberId);
    const campusId = barberInfo.campusId;
    const totalLifetimeBookings = barberInfo.totalBookings;

    // Check if new barber
    const isNewBarber = totalLifetimeBookings < config.newBarberBookingThreshold;

    // Calculate individual scores
    const qualityScore = this.calculateQualityScore(metric, config);
    const reliabilityScore = this.calculateReliabilityScore(metric, config);
    const demandScore = await this.calculateDemandScore(barberId, metric, campusId, periodDate);

    // Calculate weighted performance score
    const performanceScore = this.calculatePerformanceScore(
      qualityScore,
      reliabilityScore,
      demandScore,
      config,
      isNewBarber
    );

    // Get market metrics
    const marketMetrics = await this.getMarketMetrics(campusId, periodDate);
    const msi = marketMetrics.msi;
    const mdi = marketMetrics.mdi;

    // Calculate market-adjusted effective score
    const effectiveScore = this.calculateEffectiveScore(performanceScore, msi, config);

    const score: BarberScore = {
      barberId,
      periodDate,
      qualityScore,
      reliabilityScore,
      demandScore,
      performanceScore,
      effectiveScore,
      campusId,
      msi,
      mdi,
      isNewBarber,
      totalLifetimeBookings,
      breakdown: {
        qualityScore,
        reliabilityScore,
        demandScore,
        performanceScore,
        effectiveScore,
        weights: {
          quality: config.qualityWeight,
          reliability: config.reliabilityWeight,
          demand: config.demandWeight,
        },
        isNewBarber,
        msi,
        mdi,
      },
    };

    // Persist to database
    await this.saveScore(score);

    return score;
  }

  /**
   * Calculate Quality Score (0-100)
   * Based on: average rating (1-5) and repeat customer rate
   */
  calculateQualityScore(metric: BarberMetric, config: PricingConfig): number {
    // If no ratings yet, return neutral score
    if (!metric.avgRating || metric.totalRatings === 0) {
      return 50.0; // Neutral score for new barbers
    }

    // Normalize rating from 1-5 scale to 0-100 scale
    // 1 star = 0, 5 stars = 100
    const ratingNormalized = new Decimal(metric.avgRating - 1)
      .dividedBy(4)
      .times(100)
      .toDecimalPlaces(2)
      .toNumber();

    // Normalize repeat rate (0-1) to 0-100
    const repeatRateNormalized = new Decimal(metric.repeatRate)
      .times(100)
      .toDecimalPlaces(2)
      .toNumber();

    // Weighted combination
    const qualityScore = new Decimal(ratingNormalized)
      .times(config.ratingWeight)
      .plus(new Decimal(repeatRateNormalized).times(config.repeatRateWeight))
      .toDecimalPlaces(2)
      .toNumber();

    return Math.max(0, Math.min(100, qualityScore));
  }

  /**
   * Calculate Reliability Score (0-100)
   * Based on: on-time percentage and inverse of no-show rate
   */
  calculateReliabilityScore(metric: BarberMetric, config: PricingConfig): number {
    // If no bookings, return neutral score
    if (metric.numBookings === 0) {
      return 50.0;
    }

    // On-time percentage (already 0-1, convert to 0-100)
    const onTimeScore = new Decimal(metric.onTimePct).times(100).toNumber();

    // Inverse of no-show rate (0 no-shows = 100, 100% no-shows = 0)
    const noShowScore = new Decimal(1)
      .minus(metric.noShowPct)
      .times(100)
      .toNumber();

    // Weighted combination
    const reliabilityScore = new Decimal(onTimeScore)
      .times(config.onTimeWeight)
      .plus(new Decimal(noShowScore).times(config.noShowWeight))
      .toDecimalPlaces(2)
      .toNumber();

    return Math.max(0, Math.min(100, reliabilityScore));
  }

  /**
   * Calculate Demand Score (0-100)
   * Based on: booking volume relative to campus peers (percentile ranking)
   */
  async calculateDemandScore(
    barberId: string,
    metric: BarberMetric,
    campusId: string,
    periodDate: Date
  ): Promise<number> {
    // Get all barbers' booking counts for this campus and period
    const result = await pool.query(
      `
      SELECT num_bookings
      FROM barber_metrics bm
      JOIN barbers b ON bm.barber_id = b.id
      WHERE b.campus_id = $1
        AND bm.period_date = $2
      ORDER BY num_bookings ASC
      `,
      [campusId, periodDate]
    );

    if (result.rows.length === 0) {
      return 50.0; // Neutral if no data
    }

    const allBookingCounts = result.rows.map(r => parseInt(r.num_bookings));
    const thisBarberBookings = metric.numBookings;

    // Calculate percentile rank
    const rank = allBookingCounts.filter(count => count < thisBarberBookings).length;
    const percentile = allBookingCounts.length > 1
      ? rank / (allBookingCounts.length - 1)
      : 0.5;

    // Convert percentile (0-1) to score (0-100)
    const demandScore = new Decimal(percentile)
      .times(100)
      .toDecimalPlaces(2)
      .toNumber();

    return Math.max(0, Math.min(100, demandScore));
  }

  /**
   * Calculate weighted Performance Score (0-100)
   */
  calculatePerformanceScore(
    qualityScore: number,
    reliabilityScore: number,
    demandScore: number,
    config: PricingConfig,
    isNewBarber: boolean
  ): number {
    let performanceScore = new Decimal(qualityScore)
      .times(config.qualityWeight)
      .plus(new Decimal(reliabilityScore).times(config.reliabilityWeight))
      .plus(new Decimal(demandScore).times(config.demandWeight))
      .toDecimalPlaces(2)
      .toNumber();

    // Apply new barber quality boost if applicable
    if (isNewBarber) {
      const boost = new Decimal(config.newBarberQualityBoost).times(100).toNumber();
      performanceScore = Math.min(100, performanceScore + boost);
      logger.info(`Applied new barber boost: +${boost} points`);
    }

    return Math.max(0, Math.min(100, performanceScore));
  }

  /**
   * Calculate Effective Score (market-adjusted)
   * EffectiveScore = PerformanceScore × (0.7 + 0.3 × MSI)
   */
  calculateEffectiveScore(
    performanceScore: number,
    msi: number,
    config: PricingConfig
  ): number {
    const msiMultiplier = new Decimal(0.7)
      .plus(new Decimal(config.msiInfluence).times(msi))
      .toNumber();

    const effectiveScore = new Decimal(performanceScore)
      .times(msiMultiplier)
      .toDecimalPlaces(2)
      .toNumber();

    return Math.max(0, Math.min(100, effectiveScore));
  }

  /**
   * Load pricing configuration
   */
  private async loadConfig(): Promise<PricingConfig> {
    const result = await pool.query(
      `SELECT * FROM pricing_config ORDER BY version DESC LIMIT 1`
    );

    if (result.rows.length === 0) {
      throw new Error('Pricing config not found');
    }

    const row = result.rows[0];
    return {
      qualityWeight: parseFloat(row.quality_weight),
      reliabilityWeight: parseFloat(row.reliability_weight),
      demandWeight: parseFloat(row.demand_weight),
      ratingWeight: parseFloat(row.rating_weight),
      repeatRateWeight: parseFloat(row.repeat_rate_weight),
      onTimeWeight: parseFloat(row.on_time_weight),
      noShowWeight: parseFloat(row.no_show_weight),
      msiInfluence: parseFloat(row.msi_influence),
      newBarberBookingThreshold: parseInt(row.new_barber_booking_threshold),
      newBarberQualityBoost: parseFloat(row.new_barber_quality_boost),
    };
  }

  /**
   * Get barber info (campus, lifetime bookings)
   */
  private async getBarberInfo(barberId: string): Promise<{
    campusId: string;
    totalBookings: number;
  }> {
    const result = await pool.query(
      `
      SELECT
        b.campus_id,
        COUNT(bk.id) FILTER (WHERE bk.status = 'completed') as total_bookings
      FROM barbers b
      LEFT JOIN bookings bk ON b.id = bk.barber_id
      WHERE b.id = $1
      GROUP BY b.campus_id
      `,
      [barberId]
    );

    if (result.rows.length === 0) {
      throw new Error(`Barber ${barberId} not found`);
    }

    return {
      campusId: result.rows[0].campus_id,
      totalBookings: parseInt(result.rows[0].total_bookings) || 0,
    };
  }

  /**
   * Get market metrics for a campus
   */
  private async getMarketMetrics(
    campusId: string,
    periodDate: Date
  ): Promise<{ msi: number; mdi: number }> {
    const result = await pool.query(
      `
      SELECT msi, mdi
      FROM campus_market_metrics
      WHERE campus_id = $1
      ORDER BY period_start DESC
      LIMIT 1
      `,
      [campusId]
    );

    if (result.rows.length === 0) {
      logger.warn(`No market metrics found for campus ${campusId}, using defaults`);
      return { msi: 0.5, mdi: 0.5 };
    }

    return {
      msi: parseFloat(result.rows[0].msi),
      mdi: parseFloat(result.rows[0].mdi),
    };
  }

  /**
   * Save score to database
   */
  private async saveScore(score: BarberScore): Promise<void> {
    await pool.query(
      `
      INSERT INTO barber_scores (
        barber_id,
        period_date,
        quality_score,
        reliability_score,
        demand_score,
        performance_score,
        effective_score,
        campus_id,
        msi,
        mdi,
        is_new_barber,
        total_lifetime_bookings,
        breakdown
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
      ON CONFLICT (barber_id, period_date)
      DO UPDATE SET
        quality_score = EXCLUDED.quality_score,
        reliability_score = EXCLUDED.reliability_score,
        demand_score = EXCLUDED.demand_score,
        performance_score = EXCLUDED.performance_score,
        effective_score = EXCLUDED.effective_score,
        msi = EXCLUDED.msi,
        mdi = EXCLUDED.mdi,
        is_new_barber = EXCLUDED.is_new_barber,
        total_lifetime_bookings = EXCLUDED.total_lifetime_bookings,
        breakdown = EXCLUDED.breakdown,
        computed_at = CURRENT_TIMESTAMP
      `,
      [
        score.barberId,
        score.periodDate,
        score.qualityScore,
        score.reliabilityScore,
        score.demandScore,
        score.performanceScore,
        score.effectiveScore,
        score.campusId,
        score.msi,
        score.mdi,
        score.isNewBarber,
        score.totalLifetimeBookings,
        JSON.stringify(score.breakdown),
      ]
    );
  }

  /**
   * Get score history for a barber
   */
  async getBarberScoreHistory(
    barberId: string,
    days: number = 30
  ): Promise<BarberScore[]> {
    const result = await pool.query(
      `
      SELECT
        barber_id,
        period_date,
        quality_score,
        reliability_score,
        demand_score,
        performance_score,
        effective_score,
        campus_id,
        msi,
        mdi,
        is_new_barber,
        total_lifetime_bookings,
        breakdown
      FROM barber_scores
      WHERE barber_id = $1
        AND period_date >= CURRENT_DATE - $2
      ORDER BY period_date DESC
      `,
      [barberId, days]
    );

    return result.rows.map(row => ({
      barberId: row.barber_id,
      periodDate: new Date(row.period_date),
      qualityScore: parseFloat(row.quality_score),
      reliabilityScore: parseFloat(row.reliability_score),
      demandScore: parseFloat(row.demand_score),
      performanceScore: parseFloat(row.performance_score),
      effectiveScore: parseFloat(row.effective_score),
      campusId: row.campus_id,
      msi: parseFloat(row.msi),
      mdi: parseFloat(row.mdi),
      isNewBarber: row.is_new_barber,
      totalLifetimeBookings: row.total_lifetime_bookings,
      breakdown: row.breakdown,
    }));
  }
}

export default new ScoringEngineService();

