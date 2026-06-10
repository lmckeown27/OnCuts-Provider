/**
 * Marketplace Controller
 * 
 * REST API endpoints for capitalistic marketplace engine
 */

import { Request, Response } from 'express';
import { logger } from '../utils/logger';
import { bqsService } from '../services/bqs-calculation.service';
import { marketplacePricingService } from '../services/marketplace-pricing.service';
import { rankingService } from '../services/ranking-algorithm.service';
import { surgePricingService } from '../services/surge-pricing.service';
import { marketCalibrationService } from '../services/market-calibration.service';
import { marketplaceCronService } from '../services/marketplace-cron.service';

/**
 * GET /barbers/ranked
 * Returns sorted list using RankScore
 */
export async function getRankedBarbers(req: Request, res: Response) {
  try {
    const { market_id, time, zip } = req.query;

    if (!market_id) {
      return res.status(400).json({ error: 'market_id is required' });
    }

    const rankings = await rankingService.getRankedBarbers({
      marketId: market_id as string,
      desiredTime: time as string,
      zipCode: zip as string,
    });

    res.json({
      marketId: market_id,
      count: rankings.length,
      barbers: rankings,
    });
  } catch (error: any) {
    logger.error('Error in getRankedBarbers:', error);
    res.status(500).json({ error: error.message || 'Failed to get ranked barbers' });
  }
}

/**
 * POST /barbers/:id/update_price
 * Server enforces allowed range
 */
export async function updateBarberPrice(req: Request, res: Response) {
  try {
    const { id } = req.params;
    const { price } = req.body;

    if (!price || isNaN(price)) {
      return res.status(400).json({ error: 'Valid price is required' });
    }

    const newPrice = parseFloat(price);

    // Validate price is within bounds
    const validation = await marketplacePricingService.validatePrice(id, newPrice);

    if (!validation.valid) {
      return res.status(400).json({
        error: validation.reason,
        bounds: validation.bounds,
      });
    }

    // Set the price
    const result = await marketplacePricingService.setBarberPrice(id, newPrice);

    res.json(result);
  } catch (error: any) {
    logger.error('Error in updateBarberPrice:', error);
    res.status(500).json({ error: error.message || 'Failed to update price' });
  }
}

/**
 * GET /barbers/:id/pricing-info
 * Get barber's pricing bounds and current price
 */
export async function getBarberPricingInfo(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const info = await marketplacePricingService.getBarberPricingInfo(id);
    const surgeInfo = await surgePricingService.getBarberPriceWithSurge(id);

    res.json({
      ...info,
      surge: surgeInfo,
    });
  } catch (error: any) {
    logger.error('Error in getBarberPricingInfo:', error);
    res.status(500).json({ error: error.message || 'Failed to get pricing info' });
  }
}

/**
 * GET /barbers/:id/bqs
 * Get barber's BQS breakdown
 */
export async function getBarberBQS(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const bqsResult = await bqsService.calculateBQSForBarber(id);

    res.json(bqsResult);
  } catch (error: any) {
    logger.error('Error in getBarberBQS:', error);
    res.status(500).json({ error: error.message || 'Failed to get BQS' });
  }
}

/**
 * GET /barbers/:id/market-rank
 * Get barber's rank in their market
 */
export async function getBarberMarketRank(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const rank = await rankingService.getBarberMarketRank(id);

    res.json(rank);
  } catch (error: any) {
    logger.error('Error in getBarberMarketRank:', error);
    res.status(500).json({ error: error.message || 'Failed to get market rank' });
  }
}

/**
 * GET /admin/markets
 * Get all markets with factors
 */
export async function getAllMarkets(req: Request, res: Response) {
  try {
    const markets = await marketCalibrationService.getAllMarketsWithFactors();

    res.json({
      count: markets.length,
      markets,
    });
  } catch (error: any) {
    logger.error('Error in getAllMarkets:', error);
    res.status(500).json({ error: error.message || 'Failed to get markets' });
  }
}

/**
 * POST /admin/markets/update
 * Update market config or factors
 */
export async function updateMarket(req: Request, res: Response) {
  try {
    const { market_id, config, factors } = req.body;

    if (!market_id) {
      return res.status(400).json({ error: 'market_id is required' });
    }

    if (config) {
      await marketCalibrationService.updateMarketConfig(market_id, config);
    }

    if (factors) {
      await marketCalibrationService.updateMarketFactors(market_id, factors);
    }

    res.json({
      success: true,
      message: 'Market updated successfully',
    });
  } catch (error: any) {
    logger.error('Error in updateMarket:', error);
    res.status(500).json({ error: error.message || 'Failed to update market' });
  }
}

/**
 * POST /cron/recompute_bqs
 * Manually trigger BQS recomputation
 */
export async function triggerBQSRecompute(req: Request, res: Response) {
  try {
    await marketplaceCronService.triggerBQSRecompute();

    res.json({
      success: true,
      message: 'BQS recomputation triggered',
    });
  } catch (error: any) {
    logger.error('Error in triggerBQSRecompute:', error);
    res.status(500).json({ error: error.message || 'Failed to trigger BQS recompute' });
  }
}

/**
 * POST /cron/update_prices
 * Manually trigger pricing update
 */
export async function triggerPricingUpdate(req: Request, res: Response) {
  try {
    await marketplaceCronService.triggerPricingUpdate();

    res.json({
      success: true,
      message: 'Pricing update triggered',
    });
  } catch (error: any) {
    logger.error('Error in triggerPricingUpdate:', error);
    res.status(500).json({ error: error.message || 'Failed to trigger pricing update' });
  }
}

/**
 * POST /cron/refresh_rankings
 * Manually trigger ranking refresh
 */
export async function triggerRankingRefresh(req: Request, res: Response) {
  try {
    await marketplaceCronService.triggerRankingRefresh();

    res.json({
      success: true,
      message: 'Ranking refresh triggered',
    });
  } catch (error: any) {
    logger.error('Error in triggerRankingRefresh:', error);
    res.status(500).json({ error: error.message || 'Failed to trigger ranking refresh' });
  }
}

/**
 * POST /cron/surge_detection
 * Manually trigger surge detection
 */
export async function triggerSurgeDetection(req: Request, res: Response) {
  try {
    await marketplaceCronService.triggerSurgeDetection();

    res.json({
      success: true,
      message: 'Surge detection triggered',
    });
  } catch (error: any) {
    logger.error('Error in triggerSurgeDetection:', error);
    res.status(500).json({ error: error.message || 'Failed to trigger surge detection' });
  }
}

/**
 * GET /admin/cron-history
 * Get cron job execution history
 */
export async function getCronHistory(req: Request, res: Response) {
  try {
    const limit = parseInt(req.query.limit as string) || 100;

    const history = await marketplaceCronService.getCronHistory(limit);

    res.json({
      count: history.length,
      history,
    });
  } catch (error: any) {
    logger.error('Error in getCronHistory:', error);
    res.status(500).json({ error: error.message || 'Failed to get cron history' });
  }
}

/**
 * GET /markets/:id/surge-status
 * Get current surge status for a market
 */
export async function getMarketSurgeStatus(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const surgeStatus = await surgePricingService.detectSurge(id);

    res.json(surgeStatus);
  } catch (error: any) {
    logger.error('Error in getMarketSurgeStatus:', error);
    res.status(500).json({ error: error.message || 'Failed to get surge status' });
  }
}

