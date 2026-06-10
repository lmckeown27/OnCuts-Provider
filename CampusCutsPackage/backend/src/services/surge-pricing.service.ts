/**
 * Surge / Peak Pricing Module
 * 
 * Detects high demand and applies surge pricing
 * 
 * If (active_users_requesting / active_barbers_available) > 2.0:
 *   surge_multiplier = 1.20 to 1.40 (scaled based on ratio)
 * 
 * Applied to max_price only, not base_price
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';

interface SurgeStatus {
  marketId: string;
  timeBlock: Date;
  activeUsersRequesting: number;
  activeBarbersAvailable: number;
  demandSupplyRatio: number;
  surgeMultiplier: number;
  isActive: boolean;
}

export class SurgePricingService {
  /**
   * Calculate surge multiplier based on demand/supply ratio
   * 
   * ratio <= 2.0 → no surge (1.0)
   * ratio 2.0-3.0 → 1.20
   * ratio 3.0-4.0 → 1.30
   * ratio >= 4.0 → 1.40
   */
  private calculateSurgeMultiplier(demandSupplyRatio: number): number {
    if (demandSupplyRatio <= 2.0) return 1.0;
    if (demandSupplyRatio <= 3.0) return 1.20;
    if (demandSupplyRatio <= 4.0) return 1.30;
    return 1.40;
  }

  /**
   * Detect surge conditions for a market at a specific time block
   */
  async detectSurge(marketId: string, timeBlock?: Date): Promise<SurgeStatus> {
    try {
      const time = timeBlock || new Date();

      // For demo purposes, simulate demand/supply
      // In production, this would query actual real-time booking requests and barber availability

      // Get number of active barbers in market
      const barbersResult = await pool.query(`
        SELECT COUNT(*) as count
        FROM barbers
        WHERE market_id = $1 AND is_active = true
      `, [marketId]);

      const activeBarbersAvailable = parseInt(barbersResult.rows[0].count) || 0;

      // Simulate active users requesting (in production, query active booking sessions)
      // For now, estimate based on recent bookings in the time window
      const usersResult = await pool.query(`
        SELECT COUNT(DISTINCT user_id) as count
        FROM bookings
        WHERE barber_id IN (
          SELECT barber_id FROM barbers WHERE market_id = $1
        )
        AND created_at > NOW() - INTERVAL '1 hour'
      `, [marketId]);

      const activeUsersRequesting = parseInt(usersResult.rows[0].count) || 0;

      // Calculate demand/supply ratio
      const demandSupplyRatio = activeBarbersAvailable > 0 
        ? activeUsersRequesting / activeBarbersAvailable 
        : 0;

      const surgeMultiplier = this.calculateSurgeMultiplier(demandSupplyRatio);
      const isActive = surgeMultiplier > 1.0;

      return {
        marketId,
        timeBlock: time,
        activeUsersRequesting,
        activeBarbersAvailable,
        demandSupplyRatio: Math.round(demandSupplyRatio * 100) / 100,
        surgeMultiplier,
        isActive,
      };
    } catch (error) {
      logger.error(`Error detecting surge for market ${marketId}:`, error);
      throw error;
    }
  }

  /**
   * Save surge event to database
   */
  async saveSurgeEvent(surgeStatus: SurgeStatus): Promise<string> {
    try {
      const result = await pool.query(`
        INSERT INTO surge_events (
          market_id,
          time_block,
          active_users_requesting,
          active_barbers_available,
          demand_supply_ratio,
          surge_multiplier,
          is_active
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING event_id
      `, [
        surgeStatus.marketId,
        surgeStatus.timeBlock,
        surgeStatus.activeUsersRequesting,
        surgeStatus.activeBarbersAvailable,
        surgeStatus.demandSupplyRatio,
        surgeStatus.surgeMultiplier,
        surgeStatus.isActive,
      ]);

      return result.rows[0].event_id;
    } catch (error) {
      logger.error('Error saving surge event:', error);
      throw error;
    }
  }

  /**
   * Get current surge multiplier for a market
   */
  async getCurrentSurgeMultiplier(marketId: string): Promise<number> {
    try {
      // Check for active surge event in last 30 minutes
      const result = await pool.query(`
        SELECT surge_multiplier
        FROM surge_events
        WHERE market_id = $1
          AND is_active = true
          AND started_at > NOW() - INTERVAL '30 minutes'
        ORDER BY started_at DESC
        LIMIT 1
      `, [marketId]);

      if (result.rows.length === 0) {
        return 1.0; // No surge
      }

      return parseFloat(result.rows[0].surge_multiplier);
    } catch (error) {
      logger.error(`Error getting surge multiplier for market ${marketId}:`, error);
      return 1.0;
    }
  }

  /**
   * Apply surge pricing to barber's max price
   */
  async getBarberPriceWithSurge(barberId: string): Promise<{ baseMaxPrice: number; surgeMaxPrice: number; surgeMultiplier: number }> {
    try {
      const result = await pool.query(`
        SELECT 
          b.max_allowed_price,
          b.market_id
        FROM barbers b
        WHERE b.barber_id = $1
      `, [barberId]);

      if (result.rows.length === 0) {
        throw new Error(`Barber ${barberId} not found`);
      }

      const { max_allowed_price, market_id } = result.rows[0];
      const baseMaxPrice = parseFloat(max_allowed_price) || 0;

      const surgeMultiplier = await this.getCurrentSurgeMultiplier(market_id);
      const surgeMaxPrice = baseMaxPrice * surgeMultiplier;

      return {
        baseMaxPrice,
        surgeMaxPrice: Math.round(surgeMaxPrice * 100) / 100,
        surgeMultiplier,
      };
    } catch (error) {
      logger.error(`Error getting surge price for barber ${barberId}:`, error);
      throw error;
    }
  }

  /**
   * Check surge for all markets (called every 15 minutes)
   */
  async checkAllMarketsSurge(): Promise<{ processed: number; surgeActive: number }> {
    const startTime = Date.now();
    let processed = 0;
    let surgeActive = 0;

    try {
      const marketsResult = await pool.query(`
        SELECT market_id
        FROM markets
      `);

      const markets = marketsResult.rows;

      logger.info(`Starting surge detection for ${markets.length} markets`);

      for (const market of markets) {
        try {
          const surgeStatus = await this.detectSurge(market.market_id);
          
          if (surgeStatus.isActive) {
            await this.saveSurgeEvent(surgeStatus);
            surgeActive++;
            logger.info(`Surge active in market ${market.market_id}: ${surgeStatus.surgeMultiplier}x`);
          }

          processed++;
        } catch (error) {
          logger.error(`Failed surge detection for market ${market.market_id}:`, error);
        }
      }

      const duration = Date.now() - startTime;

      logger.info(`Surge detection complete: ${processed} markets checked, ${surgeActive} surge active, ${duration}ms`);

      return { processed, surgeActive };
    } catch (error) {
      logger.error('Error in checkAllMarketsSurge:', error);
      throw error;
    }
  }

  /**
   * End expired surge events
   */
  async endExpiredSurges(): Promise<number> {
    try {
      const result = await pool.query(`
        UPDATE surge_events
        SET 
          is_active = false,
          ended_at = NOW()
        WHERE is_active = true
          AND started_at < NOW() - INTERVAL '30 minutes'
        RETURNING event_id
      `);

      const count = result.rows.length;

      if (count > 0) {
        logger.info(`Ended ${count} expired surge events`);
      }

      return count;
    } catch (error) {
      logger.error('Error ending expired surges:', error);
      throw error;
    }
  }
}

export const surgePricingService = new SurgePricingService();

