/**
 * Market Calibration Module
 * 
 * Applies market-specific factors to BQS and ranking calculations
 * 
 * Large markets (LA): Higher competition, more dramatic pricing
 * Small markets (SLO): Lower variation, lower ceilings
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';

interface MarketFactors {
  marketId: string;
  marketName: string;
  demandNormalizationFactor: number;
  reviewWeightAdjustment: number;
  competitionIntensityScore: number;
}

interface CalibratedBQS {
  rawBQS: number;
  calibratedBQS: number;
  marketFactors: MarketFactors;
}

export class MarketCalibrationService {
  /**
   * Get market factors
   */
  async getMarketFactors(marketId: string): Promise<MarketFactors> {
    try {
      const result = await pool.query(`
        SELECT 
          mf.market_id,
          m.name as market_name,
          mf.demand_normalization_factor,
          mf.review_weight_adjustment,
          mf.competition_intensity_score
        FROM market_factors mf
        JOIN markets m ON mf.market_id = m.market_id
        WHERE mf.market_id = $1
      `, [marketId]);

      if (result.rows.length === 0) {
        // Return default factors if not configured
        logger.warn(`No market factors found for ${marketId}, using defaults`);
        return {
          marketId,
          marketName: 'Unknown',
          demandNormalizationFactor: 1.0,
          reviewWeightAdjustment: 1.0,
          competitionIntensityScore: 1.0,
        };
      }

      const row = result.rows[0];

      return {
        marketId: row.market_id,
        marketName: row.market_name,
        demandNormalizationFactor: parseFloat(row.demand_normalization_factor) || 1.0,
        reviewWeightAdjustment: parseFloat(row.review_weight_adjustment) || 1.0,
        competitionIntensityScore: parseFloat(row.competition_intensity_score) || 1.0,
      };
    } catch (error) {
      logger.error(`Error getting market factors for ${marketId}:`, error);
      throw error;
    }
  }

  /**
   * Apply market calibration to BQS
   * Adjusts BQS based on market factors
   */
  calibrateBQS(rawBQS: number, marketFactors: MarketFactors): CalibratedBQS {
    // Apply review weight adjustment (affects review component more in small markets)
    // Apply competition intensity (makes scores more spread out in competitive markets)
    
    let calibratedBQS = rawBQS;

    // In highly competitive markets, amplify differences
    if (marketFactors.competitionIntensityScore > 1.0) {
      // Amplify distance from median (50)
      const distanceFrom50 = rawBQS - 50;
      calibratedBQS = 50 + (distanceFrom50 * marketFactors.competitionIntensityScore);
    }

    // In small markets, compress differences
    if (marketFactors.competitionIntensityScore < 1.0) {
      const distanceFrom50 = rawBQS - 50;
      calibratedBQS = 50 + (distanceFrom50 * marketFactors.competitionIntensityScore);
    }

    // Clamp to 0-100
    calibratedBQS = Math.min(Math.max(calibratedBQS, 0), 100);

    return {
      rawBQS,
      calibratedBQS: Math.round(calibratedBQS * 100) / 100,
      marketFactors,
    };
  }

  /**
   * Update market factors (admin control)
   */
  async updateMarketFactors(
    marketId: string,
    factors: Partial<{
      demandNormalizationFactor: number;
      reviewWeightAdjustment: number;
      competitionIntensityScore: number;
    }>
  ): Promise<void> {
    try {
      const updates: string[] = [];
      const values: any[] = [];
      let paramIndex = 1;

      if (factors.demandNormalizationFactor !== undefined) {
        updates.push(`demand_normalization_factor = $${paramIndex++}`);
        values.push(factors.demandNormalizationFactor);
      }

      if (factors.reviewWeightAdjustment !== undefined) {
        updates.push(`review_weight_adjustment = $${paramIndex++}`);
        values.push(factors.reviewWeightAdjustment);
      }

      if (factors.competitionIntensityScore !== undefined) {
        updates.push(`competition_intensity_score = $${paramIndex++}`);
        values.push(factors.competitionIntensityScore);
      }

      if (updates.length === 0) {
        throw new Error('No factors to update');
      }

      updates.push(`updated_at = NOW()`);
      values.push(marketId);

      await pool.query(`
        UPDATE market_factors
        SET ${updates.join(', ')}
        WHERE market_id = $${paramIndex}
      `, values);

      logger.info(`Updated market factors for ${marketId}`);
    } catch (error) {
      logger.error(`Error updating market factors for ${marketId}:`, error);
      throw error;
    }
  }

  /**
   * Get all markets with their factors
   */
  async getAllMarketsWithFactors() {
    try {
      const result = await pool.query(`
        SELECT 
          m.market_id,
          m.name,
          m.city,
          m.state,
          m.base_price,
          m.average_price,
          m.premium_price_ceiling,
          mf.demand_normalization_factor,
          mf.review_weight_adjustment,
          mf.competition_intensity_score,
          (SELECT COUNT(*) FROM barbers WHERE market_id = m.market_id AND is_active = true) as active_barbers
        FROM markets m
        LEFT JOIN market_factors mf ON m.market_id = mf.market_id
        ORDER BY m.name
      `);

      return result.rows.map(row => ({
        marketId: row.market_id,
        name: row.name,
        city: row.city,
        state: row.state,
        basePrice: parseFloat(row.base_price),
        averagePrice: parseFloat(row.average_price),
        premiumPriceCeiling: parseFloat(row.premium_price_ceiling),
        demandNormalizationFactor: parseFloat(row.demand_normalization_factor) || 1.0,
        reviewWeightAdjustment: parseFloat(row.review_weight_adjustment) || 1.0,
        competitionIntensityScore: parseFloat(row.competition_intensity_score) || 1.0,
        activeBarbers: parseInt(row.active_barbers) || 0,
      }));
    } catch (error) {
      logger.error('Error getting markets with factors:', error);
      throw error;
    }
  }

  /**
   * Update market config (prices)
   */
  async updateMarketConfig(
    marketId: string,
    config: Partial<{
      basePrice: number;
      averagePrice: number;
      premiumPriceCeiling: number;
    }>
  ): Promise<void> {
    try {
      const updates: string[] = [];
      const values: any[] = [];
      let paramIndex = 1;

      if (config.basePrice !== undefined) {
        updates.push(`base_price = $${paramIndex++}`);
        values.push(config.basePrice);
      }

      if (config.averagePrice !== undefined) {
        updates.push(`average_price = $${paramIndex++}`);
        values.push(config.averagePrice);
      }

      if (config.premiumPriceCeiling !== undefined) {
        updates.push(`premium_price_ceiling = $${paramIndex++}`);
        values.push(config.premiumPriceCeiling);
      }

      if (updates.length === 0) {
        throw new Error('No config to update');
      }

      updates.push(`updated_at = NOW()`);
      values.push(marketId);

      await pool.query(`
        UPDATE markets
        SET ${updates.join(', ')}
        WHERE market_id = $${paramIndex}
      `, values);

      logger.info(`Updated market config for ${marketId}`);
    } catch (error) {
      logger.error(`Error updating market config for ${marketId}:`, error);
      throw error;
    }
  }
}

export const marketCalibrationService = new MarketCalibrationService();

