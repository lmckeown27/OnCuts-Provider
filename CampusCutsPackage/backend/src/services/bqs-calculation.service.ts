/**
 * Barber Quality Score (BQS) Calculation Service
 * 
 * Implements the exact formula:
 * BQS = 0.45*R + 0.25*D + 0.15*P + 0.15*L
 * 
 * Where:
 * R = ReviewScoreWeighted = avg_rating * log(1 + total_reviews)
 * D = DemandScore = (slots_booked / slots_available) * 100
 * P = PriceJustificationScore = 100 * (repeat_bookings_at_price / total_bookings_at_price)
 * L = LoyaltyScore = (repeat_customers / total_customers) * 100
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';

interface BQSComponents {
  reviewScoreWeighted: number;
  demandScore: number;
  priceJustificationScore: number;
  loyaltyScore: number;
}

interface BQSResult extends BQSComponents {
  bqs: number;
  barberId: string;
}

export class BQSCalculationService {
  /**
   * Calculate Review Score Weighted (R)
   * Formula: avg_rating * log(1 + total_reviews)
   */
  private calculateReviewScore(avgRating: number, totalReviews: number): number {
    if (totalReviews === 0) return 0;
    
    const logReviews = Math.log(1 + totalReviews);
    const reviewScore = avgRating * logReviews;
    
    // Normalize to 0-100 scale (assuming max is 5 * log(1000) ≈ 34.5)
    const normalized = (reviewScore / 34.5) * 100;
    
    return Math.min(Math.max(normalized, 0), 100);
  }

  /**
   * Calculate Demand Score (D)
   * Formula: (slots_booked / slots_available) * 100
   */
  private calculateDemandScore(slotsBooked: number, slotsAvailable: number): number {
    if (slotsAvailable === 0) return 0;
    
    const demandScore = (slotsBooked / slotsAvailable) * 100;
    
    return Math.min(Math.max(demandScore, 0), 100);
  }

  /**
   * Calculate Price Justification Score (P)
   * Formula: 100 * (repeat_bookings_at_price / total_bookings_at_price)
   */
  private async calculatePriceJustificationScore(barberId: string): Promise<number> {
    const result = await pool.query(`
      SELECT 
        COUNT(*) FILTER (WHERE is_repeat_customer = true) as repeat_bookings,
        COUNT(*) as total_bookings
      FROM bookings
      WHERE barber_id = $1 AND completed = true
    `, [barberId]);

    const { repeat_bookings, total_bookings } = result.rows[0];

    if (total_bookings === 0) return 0;

    const priceScore = (parseInt(repeat_bookings) / parseInt(total_bookings)) * 100;

    return Math.min(Math.max(priceScore, 0), 100);
  }

  /**
   * Calculate Loyalty Score (L)
   * Formula: (repeat_customers / total_customers) * 100
   */
  private calculateLoyaltyScore(repeatCustomers: number, totalCustomers: number): number {
    if (totalCustomers === 0) return 0;

    const loyaltyScore = (repeatCustomers / totalCustomers) * 100;

    return Math.min(Math.max(loyaltyScore, 0), 100);
  }

  /**
   * Calculate BQS for a single barber
   */
  async calculateBQSForBarber(barberId: string): Promise<BQSResult> {
    try {
      // Fetch barber data
      const barberResult = await pool.query(`
        SELECT 
          barber_id,
          avg_rating,
          review_count,
          slots_booked_weekly,
          slots_available_weekly,
          repeat_customers,
          total_customers
        FROM barbers
        WHERE barber_id = $1
      `, [barberId]);

      if (barberResult.rows.length === 0) {
        throw new Error(`Barber ${barberId} not found`);
      }

      const barber = barberResult.rows[0];

      // Calculate each component
      const reviewScoreWeighted = this.calculateReviewScore(
        parseFloat(barber.avg_rating) || 0,
        parseInt(barber.review_count) || 0
      );

      const demandScore = this.calculateDemandScore(
        parseInt(barber.slots_booked_weekly) || 0,
        parseInt(barber.slots_available_weekly) || 0
      );

      const priceJustificationScore = await this.calculatePriceJustificationScore(barberId);

      const loyaltyScore = this.calculateLoyaltyScore(
        parseInt(barber.repeat_customers) || 0,
        parseInt(barber.total_customers) || 0
      );

      // Calculate final BQS using exact formula
      const bqs = (
        0.45 * reviewScoreWeighted +
        0.25 * demandScore +
        0.15 * priceJustificationScore +
        0.15 * loyaltyScore
      );

      return {
        barberId,
        reviewScoreWeighted,
        demandScore,
        priceJustificationScore,
        loyaltyScore,
        bqs: Math.round(bqs * 100) / 100, // Round to 2 decimal places
      };
    } catch (error) {
      logger.error(`Error calculating BQS for barber ${barberId}:`, error);
      throw error;
    }
  }

  /**
   * Update barber's BQS in database
   */
  async updateBarberBQS(bqsResult: BQSResult): Promise<void> {
    await pool.query(`
      UPDATE barbers
      SET 
        bqs = $1,
        review_score_weighted = $2,
        demand_score = $3,
        price_justification_score = $4,
        loyalty_score = $5,
        bqs_last_updated = NOW(),
        updated_at = NOW()
      WHERE barber_id = $6
    `, [
      bqsResult.bqs,
      bqsResult.reviewScoreWeighted,
      bqsResult.demandScore,
      bqsResult.priceJustificationScore,
      bqsResult.loyaltyScore,
      bqsResult.barberId,
    ]);

    logger.info(`Updated BQS for barber ${bqsResult.barberId}: ${bqsResult.bqs}`);
  }

  /**
   * Recompute BQS for all active barbers
   * This is called by the nightly cron job
   */
  async recomputeAllBQS(): Promise<{ processed: number; failed: number }> {
    const startTime = Date.now();
    let processed = 0;
    let failed = 0;

    try {
      // Get all active barbers
      const result = await pool.query(`
        SELECT barber_id
        FROM barbers
        WHERE is_active = true
      `);

      const barbers = result.rows;

      logger.info(`Starting BQS recomputation for ${barbers.length} barbers`);

      // Process each barber
      for (const barber of barbers) {
        try {
          const bqsResult = await this.calculateBQSForBarber(barber.barber_id);
          await this.updateBarberBQS(bqsResult);
          processed++;
        } catch (error) {
          logger.error(`Failed to compute BQS for barber ${barber.barber_id}:`, error);
          failed++;
        }
      }

      const duration = Date.now() - startTime;

      logger.info(`BQS recomputation complete: ${processed} processed, ${failed} failed, ${duration}ms`);

      return { processed, failed };
    } catch (error) {
      logger.error('Error in recomputeAllBQS:', error);
      throw error;
    }
  }

  /**
   * Update barber statistics (called after new bookings/reviews)
   */
  async updateBarberStats(barberId: string): Promise<void> {
    try {
      // Update review stats
      await pool.query(`
        UPDATE barbers
        SET 
          review_count = (SELECT COUNT(*) FROM reviews WHERE barber_id = $1),
          avg_rating = (SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE barber_id = $1),
          updated_at = NOW()
        WHERE barber_id = $1
      `, [barberId]);

      // Update booking stats
      const bookingStats = await pool.query(`
        SELECT 
          COUNT(*) as total_bookings,
          COUNT(*) FILTER (WHERE completed = true) as completed_bookings,
          COUNT(DISTINCT user_id) as total_customers,
          COUNT(*) FILTER (WHERE is_repeat_customer = true) as repeat_bookings
        FROM bookings
        WHERE barber_id = $1
      `, [barberId]);

      const stats = bookingStats.rows[0];

      await pool.query(`
        UPDATE barbers
        SET 
          total_bookings = $1,
          completed_bookings = $2,
          total_customers = $3,
          updated_at = NOW()
        WHERE barber_id = $4
      `, [
        stats.total_bookings,
        stats.completed_bookings,
        stats.total_customers,
        barberId,
      ]);

      logger.info(`Updated stats for barber ${barberId}`);
    } catch (error) {
      logger.error(`Error updating barber stats for ${barberId}:`, error);
      throw error;
    }
  }
}

export const bqsService = new BQSCalculationService();

