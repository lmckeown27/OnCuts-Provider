/**
 * Marketplace Pricing Engine (BQS-based)
 * 
 * Determines price bounds based on BQS:
 * 
 * If BQS < 60 → multiplier = 1.0
 * If 60–80 → multiplier = 1.10
 * If 80–90 → multiplier = 1.25
 * If 90–100 → multiplier = 1.50
 * 
 * min_price = market.base_price
 * max_price = market.premium_price_ceiling * multiplier
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';

interface PricingBounds {
  minPrice: number;
  maxPrice: number;
  multiplier: number;
  marketBasePrice: number;
  marketPremiumCeiling: number;
}

interface BarberPricingUpdate {
  barberId: string;
  currentPrice: number;
  minAllowedPrice: number;
  maxAllowedPrice: number;
  pricingMultiplier: number;
}

export class DynamicPricingService {
  /**
   * Calculate pricing multiplier based on BQS
   */
  private calculateMultiplier(bqs: number): number {
    if (bqs < 60) return 1.0;
    if (bqs >= 60 && bqs < 80) return 1.10;
    if (bqs >= 80 && bqs < 90) return 1.25;
    if (bqs >= 90) return 1.50;
    return 1.0;
  }

  /**
   * Get pricing bounds for a barber
   */
  async getPricingBounds(barberId: string): Promise<PricingBounds> {
    try {
      const result = await pool.query(`
        SELECT 
          b.bqs,
          m.base_price,
          m.premium_price_ceiling
        FROM barbers b
        JOIN markets m ON b.market_id = m.market_id
        WHERE b.barber_id = $1
      `, [barberId]);

      if (result.rows.length === 0) {
        throw new Error(`Barber ${barberId} not found or not assigned to a market`);
      }

      const { bqs, base_price, premium_price_ceiling } = result.rows[0];

      const multiplier = this.calculateMultiplier(parseFloat(bqs) || 0);
      const minPrice = parseFloat(base_price);
      const maxPrice = parseFloat(premium_price_ceiling) * multiplier;

      return {
        minPrice,
        maxPrice,
        multiplier,
        marketBasePrice: parseFloat(base_price),
        marketPremiumCeiling: parseFloat(premium_price_ceiling),
      };
    } catch (error) {
      logger.error(`Error getting pricing bounds for barber ${barberId}:`, error);
      throw error;
    }
  }

  /**
   * Validate if a price is within allowed bounds
   */
  async validatePrice(barberId: string, proposedPrice: number): Promise<{ valid: boolean; reason?: string; bounds?: PricingBounds }> {
    try {
      const bounds = await this.getPricingBounds(barberId);

      if (proposedPrice < bounds.minPrice) {
        return {
          valid: false,
          reason: `Price $${proposedPrice} is below minimum allowed price of $${bounds.minPrice}`,
          bounds,
        };
      }

      if (proposedPrice > bounds.maxPrice) {
        return {
          valid: false,
          reason: `Price $${proposedPrice} exceeds maximum allowed price of $${bounds.maxPrice.toFixed(2)} (BQS-based limit)`,
          bounds,
        };
      }

      return { valid: true, bounds };
    } catch (error) {
      logger.error(`Error validating price for barber ${barberId}:`, error);
      throw error;
    }
  }

  /**
   * Update barber's pricing bounds based on current BQS
   */
  async updateBarberPricingBounds(barberId: string): Promise<BarberPricingUpdate> {
    try {
      const bounds = await this.getPricingBounds(barberId);

      // Get barber's current price
      const result = await pool.query(`
        SELECT current_price
        FROM barbers
        WHERE barber_id = $1
      `, [barberId]);

      let currentPrice = result.rows[0]?.current_price ? parseFloat(result.rows[0].current_price) : bounds.minPrice;

      // Clamp current price to new bounds
      if (currentPrice < bounds.minPrice) {
        currentPrice = bounds.minPrice;
      } else if (currentPrice > bounds.maxPrice) {
        currentPrice = bounds.maxPrice;
      }

      // Update database
      await pool.query(`
        UPDATE barbers
        SET 
          min_allowed_price = $1,
          max_allowed_price = $2,
          pricing_multiplier = $3,
          current_price = $4,
          updated_at = NOW()
        WHERE barber_id = $5
      `, [
        bounds.minPrice,
        bounds.maxPrice,
        bounds.multiplier,
        currentPrice,
        barberId,
      ]);

      logger.info(`Updated pricing bounds for barber ${barberId}: $${bounds.minPrice}-$${bounds.maxPrice} (multiplier: ${bounds.multiplier})`);

      return {
        barberId,
        currentPrice,
        minAllowedPrice: bounds.minPrice,
        maxAllowedPrice: bounds.maxPrice,
        pricingMultiplier: bounds.multiplier,
      };
    } catch (error) {
      logger.error(`Error updating pricing bounds for barber ${barberId}:`, error);
      throw error;
    }
  }

  /**
   * Update all active barbers' pricing bounds
   * Called by nightly cron after BQS recomputation
   */
  async updateAllPricingBounds(): Promise<{ processed: number; failed: number }> {
    const startTime = Date.now();
    let processed = 0;
    let failed = 0;

    try {
      const result = await pool.query(`
        SELECT barber_id
        FROM barbers
        WHERE is_active = true AND market_id IS NOT NULL
      `);

      const barbers = result.rows;

      logger.info(`Starting pricing bounds update for ${barbers.length} barbers`);

      for (const barber of barbers) {
        try {
          await this.updateBarberPricingBounds(barber.barber_id);
          processed++;
        } catch (error) {
          logger.error(`Failed to update pricing for barber ${barber.barber_id}:`, error);
          failed++;
        }
      }

      const duration = Date.now() - startTime;

      logger.info(`Pricing bounds update complete: ${processed} processed, ${failed} failed, ${duration}ms`);

      return { processed, failed };
    } catch (error) {
      logger.error('Error in updateAllPricingBounds:', error);
      throw error;
    }
  }

  /**
   * Set barber price (with validation)
   */
  async setBarberPrice(barberId: string, newPrice: number): Promise<{ success: boolean; message: string; price?: number }> {
    try {
      const validation = await this.validatePrice(barberId, newPrice);

      if (!validation.valid) {
        return {
          success: false,
          message: validation.reason || 'Invalid price',
        };
      }

      await pool.query(`
        UPDATE barbers
        SET 
          current_price = $1,
          updated_at = NOW()
        WHERE barber_id = $2
      `, [newPrice, barberId]);

      logger.info(`Updated price for barber ${barberId}: $${newPrice}`);

      return {
        success: true,
        message: 'Price updated successfully',
        price: newPrice,
      };
    } catch (error) {
      logger.error(`Error setting price for barber ${barberId}:`, error);
      throw error;
    }
  }

  /**
   * Get barber pricing info (for display)
   */
  async getBarberPricingInfo(barberId: string) {
    try {
      const result = await pool.query(`
        SELECT 
          b.barber_id,
          b.name,
          b.current_price,
          b.min_allowed_price,
          b.max_allowed_price,
          b.pricing_multiplier,
          b.bqs,
          m.name as market_name,
          m.base_price as market_base_price,
          m.premium_price_ceiling as market_premium_ceiling
        FROM barbers b
        JOIN markets m ON b.market_id = m.market_id
        WHERE b.barber_id = $1
      `, [barberId]);

      if (result.rows.length === 0) {
        throw new Error(`Barber ${barberId} not found`);
      }

      return result.rows[0];
    } catch (error) {
      logger.error(`Error getting pricing info for barber ${barberId}:`, error);
      throw error;
    }
  }
}

export const marketplacePricingService = new DynamicPricingService();
