/**
 * Dynamic Pricing Controller
 * 
 * Handles API requests for pricing recommendations
 */

import { Request, Response, NextFunction } from 'express';
import dynamicPricingService, { PricingInput } from '../services/dynamic-pricing.service';
import { logger } from '../utils/logger';

/**
 * Calculate recommended price for a service
 * POST /api/dynamic-pricing/calculate
 */
export const calculatePrice = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const input: PricingInput = req.body;
    
    // Validate required fields
    if (!input.barber_rating || !input.service_category || !input.market_type) {
      return res.status(400).json({
        error: 'Missing required fields',
        required: ['barber_rating', 'service_category', 'market_type'],
      });
    }
    
    // Calculate pricing
    const result = dynamicPricingService.calculatePrice(input);
    
    logger.info('Pricing calculated', {
      service: input.service_category,
      market: input.market_type,
      recommended: result.recommended_price,
      confidence: result.confidence,
    });
    
    res.json({
      success: true,
      pricing: result,
    });
  } catch (error) {
    logger.error('Failed to calculate pricing:', error);
    next(error);
  }
};

/**
 * Calculate prices for multiple barbers (comparison)
 * POST /api/dynamic-pricing/batch
 */
export const calculateBatchPrices = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { inputs }: { inputs: PricingInput[] } = req.body;
    
    if (!Array.isArray(inputs) || inputs.length === 0) {
      return res.status(400).json({
        error: 'Invalid input: expected array of pricing inputs',
      });
    }
    
    if (inputs.length > 50) {
      return res.status(400).json({
        error: 'Too many inputs: maximum 50 barbers per batch',
      });
    }
    
    // Calculate price for each input
    const results = inputs.map((input: any) => dynamicPricingService.calculatePrice(input));
    
    res.json({
      success: true,
      count: results.length,
      pricing: results,
    });
  } catch (error) {
    logger.error('Failed to calculate batch pricing:', error);
    next(error);
  }
};

/**
 * Get suggested starting price for new barber
 * POST /api/dynamic-pricing/suggest-starting-price
 */
export const suggestStartingPrice = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { service_category, market_type, estimated_duration_minutes } = req.body;
    
    if (!service_category || !market_type) {
      return res.status(400).json({
        error: 'Missing required fields',
        required: ['service_category', 'market_type'],
      });
    }
    
    // Use calculatePrice with default values
    const result = dynamicPricingService.calculatePrice({
      service_category,
      market_type,
      barber_rating: 3.5, // Default for new barbers
      barber_completion_rate: 0.85, // Default completion rate
      barber_total_bookings: 0, // New barber
      barber_avg_price: 25, // Default starting price
      barbers_available_count: 5, // Conservative estimate
      bookings_last_24h: 10, // Conservative estimate
      time_of_day: dynamicPricingService.getCurrentTimeCategory(),
      estimated_duration_minutes: 45, // Default duration
    });
    
    res.json({
      success: true,
      suggested_pricing: result,
    });
  } catch (error) {
    logger.error('Failed to suggest starting price:', error);
    next(error);
  }
};

/**
 * Get current time-of-day multiplier
 * GET /api/dynamic-pricing/time-multiplier
 */
export const getCurrentTimeMultiplier = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const timeCategory = dynamicPricingService.getCurrentTimeCategory();
    
    const multipliers = {
      morning: 0.95,
      afternoon: 1.0,
      evening: 1.15,
      night: 0.9,
      weekend: 1.2,
    };
    
    res.json({
      success: true,
      current_time: new Date().toISOString(),
      time_category: timeCategory,
      multiplier: multipliers[timeCategory],
      all_multipliers: multipliers,
    });
  } catch (error) {
    logger.error('Failed to get time multiplier:', error);
    next(error);
  }
};

/**
 * Get pricing configuration (for transparency)
 * GET /api/dynamic-pricing/config
 */
export const getPricingConfig = async (req: Request, res: Response, next: NextFunction) => {
  try {
    res.json({
      success: true,
      config: {
        base_prices: {
          basic: 15,
          standard: 25,
          premium: 40,
        },
        market_multipliers: {
          small_campus: 0.85,
          medium_campus: 1.0,
          large_campus: 1.15,
          metro: 1.35,
        },
        time_multipliers: {
          morning: 0.95,
          afternoon: 1.0,
          evening: 1.15,
          night: 0.9,
          weekend: 1.2,
        },
        weights: {
          quality: 0.3,
          demand: 0.4,
          time: 0.2,
          market: 0.1,
        },
        bounds: {
          floor: '75% of base price',
          ceiling: '150% of base price',
        },
      },
    });
  } catch (error) {
    logger.error('Failed to get pricing config:', error);
    next(error);
  }
};

