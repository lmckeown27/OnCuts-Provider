/**
 * Feed Ranking Algorithm
 * 
 * RankScore = 0.5*BQS + 0.3*AvailabilityFit + 0.2*Proximity
 * 
 * Sorts barbers by RankScore (descending) for user feed
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';

interface RankingCriteria {
  marketId: string;
  desiredTime?: string;
  zipCode?: string;
  campusId?: string;
}

interface BarberRankResult {
  barberId: string;
  name: string;
  bqs: number;
  availabilityFit: number;
  proximity: number;
  rankScore: number;
  currentPrice: number;
  avgRating: number;
  reviewCount: number;
}

export class RankingAlgorithmService {
  /**
   * Calculate Availability Fit Score
   * How many available slots overlap with user's desired time
   * Simplified: Uses slots_available_weekly if no specific time given
   */
  private calculateAvailabilityFit(slotsAvailable: number, desiredTime?: string): number {
    // If specific time is provided, check actual availability
    // For now, simplified: more slots = higher availability
    if (slotsAvailable === 0) return 0;

    // Normalize to 0-100 scale (assuming max 40 slots per week)
    const fit = Math.min((slotsAvailable / 40) * 100, 100);

    return fit;
  }

  /**
   * Calculate Proximity Score
   * Uses zip code / campus cluster as non-GPS distance proxy
   * For same campus: 100, different campus: decreases based on distance
   */
  private calculateProximity(barberMarketId: string, userMarketId?: string): number {
    // Same market = highest proximity
    if (!userMarketId) return 50; // Default if no market specified

    if (barberMarketId === userMarketId) {
      return 100;
    }

    // Different market = lower proximity
    return 30;
  }

  /**
   * Get ranked barbers for user feed
   */
  async getRankedBarbers(criteria: RankingCriteria): Promise<BarberRankResult[]> {
    try {
      const { marketId, desiredTime, zipCode, campusId } = criteria;

      // Fetch all active barbers in market
      const result = await pool.query(`
        SELECT 
          b.barber_id,
          b.name,
          b.bqs,
          b.current_price,
          b.avg_rating,
          b.review_count,
          b.slots_available_weekly,
          b.market_id,
          m.name as market_name
        FROM barbers b
        JOIN markets m ON b.market_id = m.market_id
        WHERE b.is_active = true
          AND b.market_id = $1
          AND b.bqs IS NOT NULL
        ORDER BY b.bqs DESC
      `, [marketId]);

      const barbers = result.rows;

      // Calculate rank score for each barber
      const rankedBarbers: BarberRankResult[] = barbers.map(barber => {
        const bqs = parseFloat(barber.bqs) || 0;
        const availabilityFit = this.calculateAvailabilityFit(
          parseInt(barber.slots_available_weekly) || 0,
          desiredTime
        );
        const proximity = this.calculateProximity(barber.market_id, marketId);

        // Apply ranking formula: RankScore = 0.5*BQS + 0.3*AvailabilityFit + 0.2*Proximity
        const rankScore = (
          0.5 * bqs +
          0.3 * availabilityFit +
          0.2 * proximity
        );

        return {
          barberId: barber.barber_id,
          name: barber.name,
          bqs,
          availabilityFit,
          proximity,
          rankScore: Math.round(rankScore * 100) / 100,
          currentPrice: parseFloat(barber.current_price) || 0,
          avgRating: parseFloat(barber.avg_rating) || 0,
          reviewCount: parseInt(barber.review_count) || 0,
        };
      });

      // Sort by rank score (descending)
      rankedBarbers.sort((a, b) => b.rankScore - a.rankScore);

      logger.info(`Ranked ${rankedBarbers.length} barbers for market ${marketId}`);

      return rankedBarbers;
    } catch (error) {
      logger.error('Error in getRankedBarbers:', error);
      throw error;
    }
  }

  /**
   * Save ranking history for tracking
   */
  async saveRankingHistory(rankings: BarberRankResult[]): Promise<void> {
    try {
      for (let i = 0; i < rankings.length; i++) {
        const barber = rankings[i];
        await pool.query(`
          INSERT INTO barber_rank_history (barber_id, bqs, rank_score, market_rank)
          VALUES ($1, $2, $3, $4)
        `, [barber.barberId, barber.bqs, barber.rankScore, i + 1]);
      }

      logger.info(`Saved ranking history for ${rankings.length} barbers`);
    } catch (error) {
      logger.error('Error saving ranking history:', error);
      throw error;
    }
  }

  /**
   * Refresh rank scores for all barbers
   * Called by nightly cron after BQS and pricing updates
   */
  async refreshAllRankScores(): Promise<{ processed: number; failed: number }> {
    const startTime = Date.now();
    let processed = 0;
    let failed = 0;

    try {
      // Get all markets
      const marketsResult = await pool.query(`
        SELECT market_id
        FROM markets
      `);

      const markets = marketsResult.rows;

      logger.info(`Starting rank score refresh for ${markets.length} markets`);

      for (const market of markets) {
        try {
          const rankings = await this.getRankedBarbers({ marketId: market.market_id });
          await this.saveRankingHistory(rankings);
          processed += rankings.length;
        } catch (error) {
          logger.error(`Failed to refresh rankings for market ${market.market_id}:`, error);
          failed++;
        }
      }

      const duration = Date.now() - startTime;

      logger.info(`Rank score refresh complete: ${processed} processed, ${failed} failed, ${duration}ms`);

      return { processed, failed };
    } catch (error) {
      logger.error('Error in refreshAllRankScores:', error);
      throw error;
    }
  }

  /**
   * Get barber's current rank in their market
   */
  async getBarberMarketRank(barberId: string): Promise<{ rank: number; totalBarbers: number; percentile: number }> {
    try {
      const result = await pool.query(`
        WITH ranked_barbers AS (
          SELECT 
            barber_id,
            ROW_NUMBER() OVER (ORDER BY bqs DESC) as rank
          FROM barbers
          WHERE market_id = (SELECT market_id FROM barbers WHERE barber_id = $1)
            AND is_active = true
        )
        SELECT 
          rank,
          (SELECT COUNT(*) FROM ranked_barbers) as total_barbers
        FROM ranked_barbers
        WHERE barber_id = $1
      `, [barberId]);

      if (result.rows.length === 0) {
        throw new Error(`Barber ${barberId} not found`);
      }

      const { rank, total_barbers } = result.rows[0];
      const percentile = ((parseInt(total_barbers) - parseInt(rank) + 1) / parseInt(total_barbers)) * 100;

      return {
        rank: parseInt(rank),
        totalBarbers: parseInt(total_barbers),
        percentile: Math.round(percentile),
      };
    } catch (error) {
      logger.error(`Error getting market rank for barber ${barberId}:`, error);
      throw error;
    }
  }
}

export const rankingService = new RankingAlgorithmService();

