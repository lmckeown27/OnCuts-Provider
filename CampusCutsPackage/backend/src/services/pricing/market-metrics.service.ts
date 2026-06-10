/**
 * Market Metrics Service
 * 
 * Calculates campus-level market indicators:
 * - MSI (Market Size Index): Reflects campus population and barber supply
 * - MDI (Market Demand Index): Reflects booking volume relative to supply
 * 
 * Both indexes are normalized to 0-1 and smoothed with exponential moving average
 * to prevent daily volatility.
 */

import { logger } from '../../utils/logger';
import { pool } from '../../database/connection';
import Decimal from 'decimal.js';
import { startOfDay, endOfDay, subDays, format } from 'date-fns';

export interface MarketMetrics {
  campusId: string;
  msi: number; // Market Size Index (0-1)
  mdi: number; // Market Demand Index (0-1)
  activeBarbers: number;
  totalBookings30d: number;
  avgBookingsPerBarber: number;
}

interface PricingConfig {
  msiEmaAlpha: number;
  mdiEmaAlpha: number;
}

class MarketMetricsService {
  /**
   * Calculate Market Size Index (MSI) for a campus
   * 
   * MSI combines:
   * - Student population (larger = higher MSI)
   * - Barber supply (more barbers = higher MSI)
   * - Historical booking volume
   * 
   * Normalized to 0-1, smoothed with EMA
   */
  async calculateMSI(campusId: string): Promise<number> {
    // Get campus data
    const campusData = await this.getCampusData(campusId);

    if (!campusData) {
      logger.warn(`Campus ${campusId} not found`);
      return 0.5; // Default neutral MSI
    }

    // Calculate raw MSI components
    const studentPopulationScore = this.normalizeStudentCount(campusData.student_count);
    const barberSupplyScore = this.normalizeBarberCount(campusData.active_barbers);
    const bookingVolumeScore = this.normalizeBookingVolume(campusData.total_bookings_30d);

    // Weighted combination
    const rawMSI = new Decimal(studentPopulationScore)
      .times(0.4) // Population weight
      .plus(new Decimal(barberSupplyScore).times(0.3)) // Supply weight
      .plus(new Decimal(bookingVolumeScore).times(0.3)) // Volume weight
      .toNumber();

    // Get previous MSI for smoothing
    const previousMSI = await this.getPreviousMSI(campusId);

    // Apply exponential moving average smoothing
    const config = await this.loadConfig();
    const smoothedMSI = this.applyEMASmoothing(
      rawMSI,
      previousMSI,
      config.msiEmaAlpha
    );

    logger.info(`MSI for campus ${campusId}: raw=${rawMSI.toFixed(4)}, smoothed=${smoothedMSI.toFixed(4)}`);

    return smoothedMSI;
  }

  /**
   * Calculate Market Demand Index (MDI) for a campus
   * 
   * MDI = (total_bookings_30d / max(1, active_barbers))
   * Normalized to 0-1 using historical min/max bounds
   * Smoothed with EMA
   */
  async calculateMDI(campusId: string): Promise<number> {
    // Get campus metrics
    const campusData = await this.getCampusData(campusId);

    if (!campusData || campusData.active_barbers === 0) {
      return 0.5; // Default neutral MDI
    }

    // Calculate raw demand (bookings per barber)
    const rawDemand = new Decimal(campusData.total_bookings_30d)
      .dividedBy(Math.max(1, campusData.active_barbers))
      .toNumber();

    // Get historical bounds for normalization
    const bounds = await this.getHistoricalDemandBounds(campusId);

    // Normalize using historical min/max
    const normalizedMDI = this.normalizeToRange(
      rawDemand,
      bounds.min,
      bounds.max,
      0.05, // Lower bound (prevent 0)
      0.95  // Upper bound (prevent 1)
    );

    // Get previous MDI for smoothing
    const previousMDI = await this.getPreviousMDI(campusId);

    // Apply EMA smoothing
    const config = await this.loadConfig();
    const smoothedMDI = this.applyEMASmoothing(
      normalizedMDI,
      previousMDI,
      config.mdiEmaAlpha
    );

    logger.info(`MDI for campus ${campusId}: raw=${normalizedMDI.toFixed(4)}, smoothed=${smoothedMDI.toFixed(4)}`);

    return smoothedMDI;
  }

  /**
   * Update market metrics for all campuses
   */
  async updateAllCampusMetrics(periodDate: Date = new Date()): Promise<void> {
    logger.info('Updating market metrics for all campuses...');

    const campuses = await this.getAllActiveCampuses();

    for (const campus of campuses) {
      try {
        await this.updateCampusMetrics(campus.id, periodDate);
      } catch (error) {
        logger.error(`Failed to update metrics for campus ${campus.id}:`, error);
      }
    }

    logger.info('Campus market metrics update complete');
  }

  /**
   * Update metrics for a single campus
   */
  async updateCampusMetrics(campusId: string, periodDate: Date): Promise<void> {
    const campusData = await this.getCampusData(campusId);

    if (!campusData) {
      throw new Error(`Campus ${campusId} not found`);
    }

    const msi = await this.calculateMSI(campusId);
    const mdi = await this.calculateMDI(campusId);

    const periodStart = startOfDay(periodDate);
    const periodEnd = endOfDay(periodDate);

    // Save to database
    await pool.query(
      `
      INSERT INTO campus_market_metrics (
        campus_id,
        msi,
        mdi,
        active_barbers_count,
        total_bookings_30d,
        avg_bookings_per_barber,
        period_start,
        period_end
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      ON CONFLICT (campus_id, period_start)
      DO UPDATE SET
        msi = EXCLUDED.msi,
        mdi = EXCLUDED.mdi,
        active_barbers_count = EXCLUDED.active_barbers_count,
        total_bookings_30d = EXCLUDED.total_bookings_30d,
        avg_bookings_per_barber = EXCLUDED.avg_bookings_per_barber,
        updated_at = CURRENT_TIMESTAMP
      `,
      [
        campusId,
        msi,
        mdi,
        campusData.active_barbers,
        campusData.total_bookings_30d,
        campusData.active_barbers > 0
          ? campusData.total_bookings_30d / campusData.active_barbers
          : 0,
        periodStart,
        periodEnd,
      ]
    );
  }

  /**
   * Apply Exponential Moving Average smoothing
   */
  private applyEMASmoothing(
    current: number,
    previous: number | null,
    alpha: number
  ): number {
    if (previous === null) {
      return current; // First calculation, no smoothing
    }

    // EMA formula: smoothed = alpha * current + (1 - alpha) * previous
    const smoothed = new Decimal(alpha)
      .times(current)
      .plus(new Decimal(1 - alpha).times(previous))
      .toDecimalPlaces(4)
      .toNumber();

    return smoothed;
  }

  /**
   * Normalize student count to 0-1 scale
   */
  private normalizeStudentCount(studentCount: number): number {
    // Typical college range: 5,000 (small) to 50,000 (large)
    const min = 5000;
    const max = 50000;
    
    return this.normalizeToRange(studentCount, min, max, 0, 1);
  }

  /**
   * Normalize barber count to 0-1 scale
   */
  private normalizeBarberCount(barberCount: number): number {
    // Typical range: 1 (very small) to 50 (large campus)
    const min = 1;
    const max = 50;
    
    return this.normalizeToRange(barberCount, min, max, 0, 1);
  }

  /**
   * Normalize booking volume to 0-1 scale
   */
  private normalizeBookingVolume(bookings30d: number): number {
    // Typical range: 10 (very small) to 2000 (large active marketplace)
    const min = 10;
    const max = 2000;
    
    return this.normalizeToRange(bookings30d, min, max, 0, 1);
  }

  /**
   * Normalize value to target range with clamping
   */
  private normalizeToRange(
    value: number,
    inputMin: number,
    inputMax: number,
    outputMin: number,
    outputMax: number
  ): number {
    // Clamp input to valid range
    const clampedValue = Math.max(inputMin, Math.min(inputMax, value));

    // Normalize
    const normalized = new Decimal(clampedValue - inputMin)
      .dividedBy(inputMax - inputMin)
      .times(outputMax - outputMin)
      .plus(outputMin)
      .toDecimalPlaces(4)
      .toNumber();

    return normalized;
  }

  /**
   * Get campus data for calculations
   */
  private async getCampusData(campusId: string): Promise<{
    student_count: number;
    active_barbers: number;
    total_bookings_30d: number;
  } | null> {
    const thirtyDaysAgo = subDays(new Date(), 30);

    const result = await pool.query(
      `
      SELECT
        c.student_count,
        COUNT(DISTINCT b.id) FILTER (WHERE b.is_active = true) as active_barbers,
        COUNT(bk.id) FILTER (
          WHERE bk.status = 'completed' 
          AND bk.created_at >= $2
        ) as total_bookings_30d
      FROM campuses c
      LEFT JOIN barbers b ON c.id = b.campus_id
      LEFT JOIN bookings bk ON b.id = bk.barber_id
      WHERE c.id = $1
      GROUP BY c.id, c.student_count
      `,
      [campusId, thirtyDaysAgo]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return {
      student_count: parseInt(result.rows[0].student_count) || 10000,
      active_barbers: parseInt(result.rows[0].active_barbers) || 0,
      total_bookings_30d: parseInt(result.rows[0].total_bookings_30d) || 0,
    };
  }

  /**
   * Get historical demand bounds for normalization
   */
  private async getHistoricalDemandBounds(campusId: string): Promise<{
    min: number;
    max: number;
  }> {
    const result = await pool.query(
      `
      SELECT
        COALESCE(MIN(avg_bookings_per_barber), 0) as historical_min,
        COALESCE(MAX(avg_bookings_per_barber), 100) as historical_max
      FROM campus_market_metrics
      WHERE campus_id = $1
      `,
      [campusId]
    );

    if (result.rows.length === 0 || result.rows[0].historical_max === 0) {
      // No history, use reasonable defaults
      return { min: 0, max: 100 };
    }

    return {
      min: parseFloat(result.rows[0].historical_min),
      max: parseFloat(result.rows[0].historical_max),
    };
  }

  /**
   * Get previous MSI for smoothing
   */
  private async getPreviousMSI(campusId: string): Promise<number | null> {
    const result = await pool.query(
      `
      SELECT msi
      FROM campus_market_metrics
      WHERE campus_id = $1
      ORDER BY period_start DESC
      LIMIT 1
      `,
      [campusId]
    );

    return result.rows.length > 0 ? parseFloat(result.rows[0].msi) : null;
  }

  /**
   * Get previous MDI for smoothing
   */
  private async getPreviousMDI(campusId: string): Promise<number | null> {
    const result = await pool.query(
      `
      SELECT mdi
      FROM campus_market_metrics
      WHERE campus_id = $1
      ORDER BY period_start DESC
      LIMIT 1
      `,
      [campusId]
    );

    return result.rows.length > 0 ? parseFloat(result.rows[0].mdi) : null;
  }

  /**
   * Get all active campuses
   */
  private async getAllActiveCampuses(): Promise<Array<{ id: string }>> {
    const result = await pool.query(
      `SELECT id FROM campuses WHERE is_active = true`
    );

    return result.rows;
  }

  /**
   * Load pricing configuration
   */
  private async loadConfig(): Promise<PricingConfig> {
    const result = await pool.query(
      `SELECT msi_ema_alpha, mdi_ema_alpha FROM pricing_config ORDER BY version DESC LIMIT 1`
    );

    if (result.rows.length === 0) {
      return {
        msiEmaAlpha: 0.2,
        mdiEmaAlpha: 0.2,
      };
    }

    return {
      msiEmaAlpha: parseFloat(result.rows[0].msi_ema_alpha),
      mdiEmaAlpha: parseFloat(result.rows[0].mdi_ema_alpha),
    };
  }

  /**
   * Get current market metrics for a campus
   */
  async getCampusMarketMetrics(campusId: string): Promise<MarketMetrics | null> {
    const result = await pool.query(
      `
      SELECT
        campus_id,
        msi,
        mdi,
        active_barbers_count,
        total_bookings_30d,
        avg_bookings_per_barber
      FROM campus_market_metrics
      WHERE campus_id = $1
      ORDER BY period_start DESC
      LIMIT 1
      `,
      [campusId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    const row = result.rows[0];
    return {
      campusId: row.campus_id,
      msi: parseFloat(row.msi),
      mdi: parseFloat(row.mdi),
      activeBarbers: row.active_barbers_count,
      totalBookings30d: row.total_bookings_30d,
      avgBookingsPerBarber: parseFloat(row.avg_bookings_per_barber),
    };
  }
}

export default new MarketMetricsService();

