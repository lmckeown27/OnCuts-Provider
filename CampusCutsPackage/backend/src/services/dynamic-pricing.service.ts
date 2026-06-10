/**
 * Dynamic Pricing Service (Blockchain-First)
 * 
 * Calculates pricing based on:
 * - Barber quality/rating
 * - Market demand
 * - Time of day
 * - Service category
 */

import { logger } from '../utils/logger';

export interface PricingInput {
  barber_rating: number;
  barber_completion_rate: number;
  barber_total_bookings: number;
  barber_avg_price: number;
  barbers_available_count: number;
  bookings_last_24h: number;
  market_type: 'small_campus' | 'medium_campus' | 'large_campus' | 'metro';
  time_of_day: 'morning' | 'afternoon' | 'evening' | 'night' | 'weekend';
  service_category: 'basic' | 'standard' | 'premium';
  estimated_duration_minutes: number;
}

export interface PricingOutput {
  recommended_price: number;
  price_floor: number;
  price_ceiling: number;
  confidence: number;
  breakdown: {
    base_price: number;
    quality_adjustment: number;
    demand_adjustment: number;
    time_adjustment: number;
    market_adjustment: number;
  };
  reasoning: string;
}

class DynamicPricingService {
  private readonly BASE_PRICES = {
    basic: 15,
    standard: 25,
    premium: 40,
  };

  private readonly MARKET_MULTIPLIERS = {
    small_campus: 0.85,
    medium_campus: 1.0,
    large_campus: 1.15,
    metro: 1.35,
  };

  private readonly TIME_MULTIPLIERS = {
    morning: 0.95,
    afternoon: 1.0,
    evening: 1.15,
    night: 0.9,
    weekend: 1.2,
  };

  /**
   * Get current time category
   */
  getCurrentTimeCategory(): 'morning' | 'afternoon' | 'evening' | 'night' | 'weekend' {
    const now = new Date();
    const hour = now.getHours();
    const day = now.getDay();

    // Weekend
    if (day === 0 || day === 6) {
      return 'weekend';
    }

    // Weekday time slots
    if (hour >= 6 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 17) return 'afternoon';
    if (hour >= 17 && hour < 22) return 'evening';
    return 'night';
  }

  /**
   * Calculate dynamic price
   */
  calculatePrice(input: PricingInput): PricingOutput {
    try {
      // Get base price for service category
      const basePrice = this.BASE_PRICES[input.service_category];

      // Quality adjustment based on rating (0-5 scale)
      const qualityMultiplier = 0.8 + (input.barber_rating / 5) * 0.4; // 0.8 to 1.2
      const qualityAdjustment = basePrice * (qualityMultiplier - 1);

      // Demand adjustment based on availability
      const demandRatio = input.bookings_last_24h / Math.max(input.barbers_available_count, 1);
      const demandMultiplier = Math.min(1.3, 0.9 + demandRatio * 0.1); // 0.9 to 1.3
      const demandAdjustment = basePrice * (demandMultiplier - 1);

      // Time adjustment
      const timeMultiplier = this.TIME_MULTIPLIERS[input.time_of_day];
      const timeAdjustment = basePrice * (timeMultiplier - 1);

      // Market adjustment
      const marketMultiplier = this.MARKET_MULTIPLIERS[input.market_type];
      const marketAdjustment = basePrice * (marketMultiplier - 1);

      // Calculate final price
      const recommendedPrice = Math.round(
        (basePrice + qualityAdjustment + demandAdjustment + timeAdjustment + marketAdjustment) * 100
      ) / 100;

      // Calculate floor and ceiling (±20%)
      const priceFloor = Math.round(recommendedPrice * 0.8 * 100) / 100;
      const priceCeiling = Math.round(recommendedPrice * 1.2 * 100) / 100;

      // Confidence based on data quality
      const confidence = Math.min(
        100,
        50 + 
        (input.barber_total_bookings > 10 ? 20 : 0) +
        (input.barber_rating > 3 ? 20 : 0) +
        (input.barber_completion_rate > 0.8 ? 10 : 0)
      );

      const reasoning = this.generateReasoning(input, {
        qualityMultiplier,
        demandMultiplier,
        timeMultiplier,
        marketMultiplier,
      });

      return {
        recommended_price: recommendedPrice,
        price_floor: priceFloor,
        price_ceiling: priceCeiling,
        confidence,
        breakdown: {
          base_price: basePrice,
          quality_adjustment: Math.round(qualityAdjustment * 100) / 100,
          demand_adjustment: Math.round(demandAdjustment * 100) / 100,
          time_adjustment: Math.round(timeAdjustment * 100) / 100,
          market_adjustment: Math.round(marketAdjustment * 100) / 100,
        },
        reasoning,
      };
    } catch (error) {
      logger.error('Error calculating price:', error);
      throw error;
    }
  }

  /**
   * Generate human-readable pricing reasoning
   */
  private generateReasoning(
    input: PricingInput,
    multipliers: {
      qualityMultiplier: number;
      demandMultiplier: number;
      timeMultiplier: number;
      marketMultiplier: number;
    }
  ): string {
    const parts: string[] = [];

    // Quality
    if (multipliers.qualityMultiplier > 1.05) {
      parts.push(`High barber rating (${input.barber_rating.toFixed(1)}/5) increases price`);
    } else if (multipliers.qualityMultiplier < 0.95) {
      parts.push(`Lower barber rating (${input.barber_rating.toFixed(1)}/5) decreases price`);
    }

    // Demand
    if (multipliers.demandMultiplier > 1.1) {
      parts.push('High demand increases price');
    } else if (multipliers.demandMultiplier < 0.95) {
      parts.push('Low demand decreases price');
    }

    // Time
    if (input.time_of_day === 'weekend') {
      parts.push('Weekend premium applied');
    } else if (input.time_of_day === 'evening') {
      parts.push('Evening premium applied');
    } else if (input.time_of_day === 'night') {
      parts.push('Night discount applied');
    }

    // Market
    if (input.market_type === 'metro') {
      parts.push('Metro area premium');
    } else if (input.market_type === 'small_campus') {
      parts.push('Small campus discount');
    }

    return parts.length > 0 ? parts.join('. ') + '.' : 'Standard pricing applied.';
  }
}

const dynamicPricingService = new DynamicPricingService();
export default dynamicPricingService;

