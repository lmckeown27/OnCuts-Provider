/**
 * Pricing API Controller (Blockchain-First Version)
 * 
 * Handles all pricing-related API endpoints:
 * - Price estimates for barbers/services
 * - Barber performance scores
 * - Campus market metrics
 * - Pricing configuration
 * - Recompute triggers (admin only)
 * - Anomaly monitoring (admin only)
 * 
 * Dynamic pricing: PostgreSQL + Redis; chain signals via `blockchain-query` (Sui / stubs).
 */

import { Request, Response } from 'express';
import { logger } from '../utils/logger';
import dynamicPricingService, { PricingInput } from '../services/dynamic-pricing.service';
import blockchainQueryService from '../services/blockchain-query.service';

/**
 * GET /api/pricing/estimate
 * Get current price estimate for a barber/service
 * Query params: barberAddress, serviceCategory, marketType
 */
export async function getPriceEstimate(req: Request, res: Response) {
  try {
    const { barberAddress, serviceCategory, marketType } = req.query;

    if (!barberAddress || !serviceCategory) {
      return res.status(400).json({
        success: false,
        message: 'barberAddress and serviceCategory are required',
      });
    }

    // Get barber data from blockchain
    const barberData = await blockchainQueryService.getUserAccount(barberAddress as string);
    
    if (!barberData || barberData.role !== 1) { // role 1 = barber
      return res.status(404).json({
        success: false,
        message: 'Barber not found',
      });
    }

    // Get barber ratings to calculate avg
    const barberRating = await blockchainQueryService.getBarberRating(barberAddress as string);

    // Build pricing input
    const pricingInput: PricingInput = {
      barber_rating: barberRating ? parseFloat(barberRating.weighted_average_rating) : 3.5,
      barber_completion_rate: 0.9, // TODO: Calculate from booking history
      barber_total_bookings: parseInt(barberData.total_bookings) || 0,
      barber_avg_price: 25, // TODO: Calculate from booking history
      barbers_available_count: 5, // TODO: Query from blockchain
      bookings_last_24h: 10, // TODO: Query from blockchain
      market_type: (marketType as any) || 'medium_campus',
      time_of_day: dynamicPricingService.getCurrentTimeCategory(),
      service_category: serviceCategory as any,
      estimated_duration_minutes: 30,
    };

    // Calculate pricing
    const pricing = dynamicPricingService.calculatePrice(pricingInput);

    return res.json({
      success: true,
      data: {
        barberAddress,
        serviceCategory,
        finalPriceUsd: pricing.recommended_price,
        finalPriceCents: Math.round(pricing.recommended_price * 100),
        priceFloor: pricing.price_floor,
        priceCeiling: pricing.price_ceiling,
        confidence: pricing.confidence,
        breakdown: pricing.breakdown,
        reasoning: pricing.reasoning,
      },
    });
  } catch (error: any) {
    logger.error('Error getting price estimate:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get price estimate',
      error: error.message,
    });
  }
}

/**
 * GET /api/pricing/barber/:barberId/score
 * Get barber's performance score (from blockchain)
 */
export async function getBarberScore(req: Request, res: Response) {
  try {
    const { barberId } = req.params;

    // Get barber data from blockchain
    const barberData = await blockchainQueryService.getUserAccount(barberId);
    
    if (!barberData || barberData.role !== 1) { // role 1 = barber
      return res.status(404).json({
        success: false,
        message: 'Barber not found',
      });
    }

    // Get barber ratings
    const barberRating = await blockchainQueryService.getBarberRating(barberId);
    const avgRating = barberRating ? parseFloat(barberRating.weighted_average_rating) : 0;

    return res.json({
      success: true,
      data: {
        barberId,
        performanceScore: Math.round((avgRating / 5) * 100),
        rating: avgRating,
        completionRate: 0.9, // TODO: Calculate from booking history
        totalBookings: parseInt(barberData.total_bookings),
        avgPrice: 25, // TODO: Calculate from booking history
      },
    });
  } catch (error: any) {
    logger.error('Error getting barber score:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get barber score',
      error: error.message,
    });
  }
}

/**
 * GET /api/pricing/barber/:barberId/history
 * Get barber's price history (from blockchain bookings)
 */
export async function getBarberPriceHistory(req: Request, res: Response) {
  try {
    const { barberId } = req.params;

    // Get barber's bookings from blockchain
    const bookings = await blockchainQueryService.getUserBookings(barberId);

    // Extract pricing history
    const priceHistory = bookings.map((booking: any) => ({
      date: booking.created_at,
      price: booking.amount_total / 100_000_000, // Convert octas to APT
      serviceType: booking.service_name,
    }));

    return res.json({
      success: true,
      data: {
        barberId,
        history: priceHistory,
        avgPrice: priceHistory.length > 0
          ? priceHistory.reduce((sum: number, b: any) => sum + b.price, 0) / priceHistory.length
          : 0,
      },
    });
  } catch (error: any) {
    logger.error('Error getting barber price history:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get price history',
      error: error.message,
    });
  }
}

/**
 * GET /api/pricing/services
 * Get all services with base prices
 */
export async function getServices(req: Request, res: Response) {
  try {
    return res.json({
      success: true,
      data: {
        services: [
          {
            id: 1,
            category: 'basic',
            name: 'Basic Cut',
            basePrice: 15,
            duration: 20,
            description: 'Simple haircut, quick and efficient',
          },
          {
            id: 2,
            category: 'standard',
            name: 'Regular Haircut',
            basePrice: 25,
            duration: 35,
            description: 'Standard haircut with styling',
          },
          {
            id: 3,
            category: 'premium',
            name: 'Premium Service',
            basePrice: 40,
            duration: 60,
            description: 'Detailed cut with wash and styling',
          },
        ],
      },
    });
  } catch (error: any) {
    logger.error('Error getting services:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get services',
      error: error.message,
    });
  }
}

/**
 * GET /api/pricing/config
 * Get current pricing configuration
 */
export async function getConfig(req: Request, res: Response) {
  try {
    return res.json({
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
      },
    });
  } catch (error: any) {
    logger.error('Error getting pricing config:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get pricing config',
      error: error.message,
    });
  }
}

/**
 * GET /api/pricing/campus/:campusId/metrics
 * Get campus market metrics (simplified - no DB needed)
 */
export async function getCampusMetrics(req: Request, res: Response) {
  try {
    const { campusId } = req.params;

    // Get platform stats from blockchain
    const stats = await blockchainQueryService.getPlatformStats();

    return res.json({
      success: true,
      data: {
        campusId,
        totalBarbers: stats.totalBarbers,
        totalBookings: stats.totalBookings,
        avgPrice: 25, // TODO: Calculate from blockchain bookings
        bookingsLast24h: 10, // TODO: Calculate from blockchain
      },
    });
  } catch (error: any) {
    logger.error('Error getting campus metrics:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get campus metrics',
      error: error.message,
    });
  }
}

/**
 * POST /api/pricing/recompute
 * Trigger pricing recompute (no-op in blockchain-first - prices are dynamic)
 */
export async function triggerRecompute(req: Request, res: Response) {
  try {
    logger.info('Pricing recompute triggered (no-op in blockchain-first architecture)');
    
    return res.json({
      success: true,
      message: 'Pricing is calculated dynamically - no recompute needed',
    });
  } catch (error: any) {
    logger.error('Error in recompute trigger:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to trigger recompute',
      error: error.message,
    });
  }
}

/**
 * GET /api/pricing/anomalies
 * Get recent price anomalies (TODO: implement blockchain-based detection)
 */
export async function getAnomalies(req: Request, res: Response) {
  try {
    // TODO: Implement anomaly detection based on blockchain data
    return res.json({
      success: true,
      data: {
        anomalies: [],
        message: 'Anomaly detection not yet implemented for blockchain-first architecture',
      },
    });
  } catch (error: any) {
    logger.error('Error getting anomalies:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get anomalies',
      error: error.message,
    });
  }
}

/**
 * PUT /api/pricing/config
 * Update pricing configuration (TODO: store in Redis or smart contract)
 */
export async function updateConfig(req: Request, res: Response) {
  try {
    // TODO: Implement config updates in Redis or smart contract
    return res.json({
      success: false,
      message: 'Config updates not yet implemented for blockchain-first architecture',
    });
  } catch (error: any) {
    logger.error('Error updating config:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to update config',
      error: error.message,
    });
  }
}
