/**
 * Price Calculator Service
 * 
 * Calculates final prices for barbers based on:
 * - Effective Score (market-adjusted performance)
 * - Market Demand Index (MDI)
 * - Base prices and campus multipliers
 * 
 * Includes:
 * - Price formula application
 * - Shock protection (max daily change %)
 * - Min/max clamping
 * - Transparent breakdown generation
 */

import { logger } from '../../utils/logger';
import { pool } from '../../database/connection';
import Decimal from 'decimal.js';
import { format } from 'date-fns';

export interface PriceResult {
  barberId: string;
  serviceId: number;
  periodDate: Date;
  basePriceCents: number;
  minPriceCents: number;
  maxPriceCents: number;
  finalPriceCents: number;
  previousPriceCents: number | null;
  priceChangePct: number | null;
  isShockCapped: boolean;
  breakdown: PriceBreakdown;
}

export interface PriceBreakdown {
  performanceScore: number;
  effectiveScore: number;
  msi: number;
  mdi: number;
  basePrice: number;
  priceMultiplier: number;
  marketAdjustment: number;
  computedPrice: number;
  finalPrice: number;
  minPrice: number;
  maxPrice: number;
  cappedReason: string | null;
  priceChangePct: number | null;
}

interface PricingConfig {
  minPriceMultiplier: number;
  maxPriceMultiplier: number;
  mdiMinAdjustment: number;
  mdiMaxAdjustment: number;
  maxDailyPriceChangePct: number;
  minPriceChangeThresholdPct: number;
}

class PriceCalculatorService {
  /**
   * Calculate final price for a barber/service combination
   */
  async calculateFinalPrice(
    barberId: string,
    serviceId: number,
    effectiveScore: number,
    mdi: number,
    periodDate: Date
  ): Promise<PriceResult> {
    logger.info(`Calculating price for barber ${barberId}, service ${serviceId}`);

    // Get service base price and barber's campus multiplier
    const service = await this.getService(serviceId);
    const campus = await this.getBarberCampus(barberId);

    // Calculate base price for this campus
    const basePriceCents = this.calculateBasePrice(
      service.default_base_price_cents,
      campus.base_price_multiplier
    );

    // Calculate price bounds
    const minPriceCents = await this.calculateMinPrice(basePriceCents);
    const maxPriceCents = await this.calculateMaxPrice(basePriceCents);

    // Calculate price multiplier from effective score
    const priceMultiplier = await this.calculatePriceMultiplier(effectiveScore);

    // Calculate market demand adjustment
    const marketAdjustment = await this.calculateMarketAdjustment(mdi);

    // Compute raw price
    const computedPriceCents = new Decimal(basePriceCents)
      .times(priceMultiplier)
      .times(marketAdjustment)
      .toDecimalPlaces(0, Decimal.ROUND_HALF_UP)
      .toNumber();

    // Clamp to bounds
    let finalPriceCents = this.clampToMinMax(
      computedPriceCents,
      minPriceCents,
      maxPriceCents
    );

    let cappedReason: string | null = null;
    if (finalPriceCents === minPriceCents && computedPriceCents < minPriceCents) {
      cappedReason = 'min_price_floor';
    } else if (finalPriceCents === maxPriceCents && computedPriceCents > maxPriceCents) {
      cappedReason = 'max_price_ceiling';
    }

    // Get previous price for shock protection
    const previousPriceCents = await this.getPreviousPrice(barberId, serviceId);

    // Apply shock protection
    const shockProtected = await this.applyShockProtection(
      finalPriceCents,
      previousPriceCents
    );

    finalPriceCents = shockProtected.price;
    const isShockCapped = shockProtected.isCapped;
    if (isShockCapped) {
      cappedReason = shockProtected.reason || 'shock_protection';
    }

    // Calculate price change percentage
    const priceChangePct = previousPriceCents
      ? new Decimal(finalPriceCents - previousPriceCents)
          .dividedBy(previousPriceCents)
          .times(100)
          .toDecimalPlaces(2)
          .toNumber()
      : null;

    // Build transparent breakdown
    const breakdown: PriceBreakdown = {
      performanceScore: effectiveScore, // This is already the effective score
      effectiveScore,
      msi: campus.msi,
      mdi,
      basePrice: basePriceCents,
      priceMultiplier,
      marketAdjustment,
      computedPrice: computedPriceCents,
      finalPrice: finalPriceCents,
      minPrice: minPriceCents,
      maxPrice: maxPriceCents,
      cappedReason,
      priceChangePct,
    };

    const result: PriceResult = {
      barberId,
      serviceId,
      periodDate,
      basePriceCents,
      minPriceCents,
      maxPriceCents,
      finalPriceCents,
      previousPriceCents,
      priceChangePct,
      isShockCapped,
      breakdown,
    };

    // Save to database
    await this.savePrice(result);

    // Check for anomalies
    await this.checkForAnomalies(result);

    return result;
  }

  /**
   * Calculate base price for a campus
   * BasePrice = service.default_base_price × campus.base_price_multiplier
   */
  private calculateBasePrice(
    defaultBasePriceCents: number,
    campusMultiplier: number
  ): number {
    return new Decimal(defaultBasePriceCents)
      .times(campusMultiplier)
      .toDecimalPlaces(0, Decimal.ROUND_HALF_UP)
      .toNumber();
  }

  /**
   * Calculate minimum price (80% of base)
   */
  private async calculateMinPrice(basePriceCents: number): Promise<number> {
    const config = await this.loadConfig();
    return new Decimal(basePriceCents)
      .times(config.minPriceMultiplier)
      .toDecimalPlaces(0, Decimal.ROUND_HALF_UP)
      .toNumber();
  }

  /**
   * Calculate maximum price (150% of base)
   */
  private async calculateMaxPrice(basePriceCents: number): Promise<number> {
    const config = await this.loadConfig();
    return new Decimal(basePriceCents)
      .times(config.maxPriceMultiplier)
      .toDecimalPlaces(0, Decimal.ROUND_HALF_UP)
      .toNumber();
  }

  /**
   * Calculate price multiplier from effective score
   * PriceMultiplier = 0.80 + (EffectiveScore / 100) × 0.70
   * Range: [0.80, 1.50]
   */
  private async calculatePriceMultiplier(effectiveScore: number): Promise<number> {
    const config = await this.loadConfig();
    
    const multiplier = new Decimal(config.minPriceMultiplier)
      .plus(
        new Decimal(effectiveScore)
          .dividedBy(100)
          .times(config.maxPriceMultiplier - config.minPriceMultiplier)
      )
      .toDecimalPlaces(4)
      .toNumber();

    return Math.max(config.minPriceMultiplier, Math.min(config.maxPriceMultiplier, multiplier));
  }

  /**
   * Calculate market demand adjustment
   * MarketAdjustment = 0.90 + (MDI × 0.20)
   * Range: [0.90, 1.10]
   */
  private async calculateMarketAdjustment(mdi: number): Promise<number> {
    const config = await this.loadConfig();
    
    const adjustment = new Decimal(config.mdiMinAdjustment)
      .plus(
        new Decimal(mdi).times(config.mdiMaxAdjustment - config.mdiMinAdjustment)
      )
      .toDecimalPlaces(4)
      .toNumber();

    return Math.max(config.mdiMinAdjustment, Math.min(config.mdiMaxAdjustment, adjustment));
  }

  /**
   * Clamp price to min/max bounds
   */
  private clampToMinMax(price: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, price));
  }

  /**
   * Apply shock protection - prevent prices from changing too rapidly
   */
  private async applyShockProtection(
    newPriceCents: number,
    previousPriceCents: number | null
  ): Promise<{ price: number; isCapped: boolean; reason: string | null }> {
    if (!previousPriceCents) {
      return { price: newPriceCents, isCapped: false, reason: null };
    }

    const config = await this.loadConfig();

    // Calculate change percentage
    const changePct = new Decimal(newPriceCents - previousPriceCents)
      .dividedBy(previousPriceCents)
      .times(100)
      .toNumber();

    const absChangePct = Math.abs(changePct);

    // If change is below minimum threshold, don't update (stability)
    if (absChangePct < config.minPriceChangeThresholdPct) {
      logger.info(`Price change ${changePct.toFixed(2)}% below threshold, keeping previous price`);
      return {
        price: previousPriceCents,
        isCapped: true,
        reason: 'below_minimum_threshold',
      };
    }

    // If change exceeds max daily change, cap it
    if (absChangePct > config.maxDailyPriceChangePct) {
      const maxChangeAmount = new Decimal(previousPriceCents)
        .times(config.maxDailyPriceChangePct / 100)
        .toDecimalPlaces(0, Decimal.ROUND_HALF_UP)
        .toNumber();

      const cappedPrice = changePct > 0
        ? previousPriceCents + maxChangeAmount
        : previousPriceCents - maxChangeAmount;

      logger.warn(
        `Price shock detected: ${changePct.toFixed(2)}% > ${config.maxDailyPriceChangePct}%. ` +
        `Capping change to ±${config.maxDailyPriceChangePct}%`
      );

      return {
        price: cappedPrice,
        isCapped: true,
        reason: `shock_protection_${changePct > 0 ? 'increase' : 'decrease'}`,
      };
    }

    return { price: newPriceCents, isCapped: false, reason: null };
  }

  /**
   * Get service details
   */
  private async getService(serviceId: number): Promise<{
    id: number;
    default_base_price_cents: number;
  }> {
    const result = await pool.query(
      `SELECT id, default_base_price_cents FROM services WHERE id = $1`,
      [serviceId]
    );

    if (result.rows.length === 0) {
      throw new Error(`Service ${serviceId} not found`);
    }

    return result.rows[0];
  }

  /**
   * Get barber's campus and market metrics
   */
  private async getBarberCampus(barberId: string): Promise<{
    campus_id: string;
    base_price_multiplier: number;
    msi: number;
    mdi: number;
  }> {
    const result = await pool.query(
      `
      SELECT
        b.campus_id,
        COALESCE(cmm.msi, 0.5) as msi,
        COALESCE(cmm.mdi, 0.5) as mdi,
        COALESCE(c.base_price_multiplier, 1.0) as base_price_multiplier
      FROM barbers b
      JOIN campuses c ON b.campus_id = c.id
      LEFT JOIN LATERAL (
        SELECT msi, mdi
        FROM campus_market_metrics
        WHERE campus_id = b.campus_id
        ORDER BY period_start DESC
        LIMIT 1
      ) cmm ON true
      WHERE b.id = $1
      `,
      [barberId]
    );

    if (result.rows.length === 0) {
      throw new Error(`Barber ${barberId} not found`);
    }

    return {
      campus_id: result.rows[0].campus_id,
      base_price_multiplier: parseFloat(result.rows[0].base_price_multiplier),
      msi: parseFloat(result.rows[0].msi),
      mdi: parseFloat(result.rows[0].mdi),
    };
  }

  /**
   * Get previous price for shock protection
   */
  private async getPreviousPrice(
    barberId: string,
    serviceId: number
  ): Promise<number | null> {
    const result = await pool.query(
      `
      SELECT final_price_cents
      FROM barber_prices
      WHERE barber_id = $1 AND service_id = $2
      ORDER BY period_date DESC
      LIMIT 1
      `,
      [barberId, serviceId]
    );

    return result.rows.length > 0 ? parseInt(result.rows[0].final_price_cents) : null;
  }

  /**
   * Save price to database
   */
  private async savePrice(result: PriceResult): Promise<void> {
    await pool.query(
      `
      INSERT INTO barber_prices (
        barber_id,
        service_id,
        period_date,
        base_price_cents,
        min_price_cents,
        max_price_cents,
        final_price_cents,
        previous_price_cents,
        price_change_pct,
        is_shock_capped,
        breakdown
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      ON CONFLICT (barber_id, service_id, period_date)
      DO UPDATE SET
        base_price_cents = EXCLUDED.base_price_cents,
        min_price_cents = EXCLUDED.min_price_cents,
        max_price_cents = EXCLUDED.max_price_cents,
        final_price_cents = EXCLUDED.final_price_cents,
        previous_price_cents = EXCLUDED.previous_price_cents,
        price_change_pct = EXCLUDED.price_change_pct,
        is_shock_capped = EXCLUDED.is_shock_capped,
        breakdown = EXCLUDED.breakdown,
        computed_at = CURRENT_TIMESTAMP
      `,
      [
        result.barberId,
        result.serviceId,
        format(result.periodDate, 'yyyy-MM-dd'),
        result.basePriceCents,
        result.minPriceCents,
        result.maxPriceCents,
        result.finalPriceCents,
        result.previousPriceCents,
        result.priceChangePct,
        result.isShockCapped,
        JSON.stringify(result.breakdown),
      ]
    );
  }

  /**
   * Check for price anomalies and log them
   */
  private async checkForAnomalies(result: PriceResult): Promise<void> {
    const anomalies: Array<{
      type: string;
      severity: string;
      description: string;
    }> = [];

    // Large price increase
    if (result.priceChangePct && result.priceChangePct > 20) {
      anomalies.push({
        type: 'large_increase',
        severity: result.priceChangePct > 30 ? 'high' : 'medium',
        description: `Price increased by ${result.priceChangePct.toFixed(1)}%`,
      });
    }

    // Large price decrease
    if (result.priceChangePct && result.priceChangePct < -20) {
      anomalies.push({
        type: 'large_decrease',
        severity: result.priceChangePct < -30 ? 'high' : 'medium',
        description: `Price decreased by ${Math.abs(result.priceChangePct).toFixed(1)}%`,
      });
    }

    // Shock cap hit
    if (result.isShockCapped) {
      anomalies.push({
        type: 'shock_cap_hit',
        severity: 'medium',
        description: `Price change capped at ${result.breakdown.cappedReason}`,
      });
    }

    // Save anomalies
    for (const anomaly of anomalies) {
      await this.logAnomaly(result, anomaly);
    }
  }

  /**
   * Log price anomaly
   */
  private async logAnomaly(
    result: PriceResult,
    anomaly: { type: string; severity: string; description: string }
  ): Promise<void> {
    await pool.query(
      `
      INSERT INTO price_anomalies (
        barber_id,
        service_id,
        period_date,
        anomaly_type,
        severity,
        old_price_cents,
        new_price_cents,
        price_change_pct,
        description,
        context
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      `,
      [
        result.barberId,
        result.serviceId,
        format(result.periodDate, 'yyyy-MM-dd'),
        anomaly.type,
        anomaly.severity,
        result.previousPriceCents,
        result.finalPriceCents,
        result.priceChangePct,
        anomaly.description,
        JSON.stringify(result.breakdown),
      ]
    );

    logger.warn(
      `Price anomaly detected: ${anomaly.type} (${anomaly.severity}) - ${anomaly.description}`
    );
  }

  /**
   * Load pricing configuration
   */
  private async loadConfig(): Promise<PricingConfig> {
    const result = await pool.query(
      `
      SELECT
        min_price_multiplier,
        max_price_multiplier,
        mdi_min_adjustment,
        mdi_max_adjustment,
        max_daily_price_change_pct,
        min_price_change_threshold_pct
      FROM pricing_config
      ORDER BY version DESC
      LIMIT 1
      `
    );

    if (result.rows.length === 0) {
      throw new Error('Pricing config not found');
    }

    const row = result.rows[0];
    return {
      minPriceMultiplier: parseFloat(row.min_price_multiplier),
      maxPriceMultiplier: parseFloat(row.max_price_multiplier),
      mdiMinAdjustment: parseFloat(row.mdi_min_adjustment),
      mdiMaxAdjustment: parseFloat(row.mdi_max_adjustment),
      maxDailyPriceChangePct: parseFloat(row.max_daily_price_change_pct),
      minPriceChangeThresholdPct: parseFloat(row.min_price_change_threshold_pct),
    };
  }

  /**
   * Get barber's current price for a service
   */
  async getBarberPrice(barberId: string, serviceId: number): Promise<PriceResult | null> {
    const result = await pool.query(
      `
      SELECT
        barber_id,
        service_id,
        period_date,
        base_price_cents,
        min_price_cents,
        max_price_cents,
        final_price_cents,
        previous_price_cents,
        price_change_pct,
        is_shock_capped,
        breakdown
      FROM barber_prices
      WHERE barber_id = $1 AND service_id = $2
      ORDER BY period_date DESC
      LIMIT 1
      `,
      [barberId, serviceId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    const row = result.rows[0];
    return {
      barberId: row.barber_id,
      serviceId: row.service_id,
      periodDate: new Date(row.period_date),
      basePriceCents: row.base_price_cents,
      minPriceCents: row.min_price_cents,
      maxPriceCents: row.max_price_cents,
      finalPriceCents: row.final_price_cents,
      previousPriceCents: row.previous_price_cents,
      priceChangePct: row.price_change_pct ? parseFloat(row.price_change_pct) : null,
      isShockCapped: row.is_shock_capped,
      breakdown: row.breakdown,
    };
  }
}

export default new PriceCalculatorService();

