/**
 * Marketplace Routes
 * 
 * API endpoints for capitalistic marketplace engine
 */

import { Router } from 'express';
import {
  getRankedBarbers,
  updateBarberPrice,
  getBarberPricingInfo,
  getBarberBQS,
  getBarberMarketRank,
  getAllMarkets,
  updateMarket,
  triggerBQSRecompute,
  triggerPricingUpdate,
  triggerRankingRefresh,
  triggerSurgeDetection,
  getCronHistory,
  getMarketSurgeStatus,
} from '../controllers/marketplace.controller';

const router = Router();

// ============================================================
// BARBER ENDPOINTS
// ============================================================

// GET /api/marketplace/barbers/ranked - Get ranked barbers for user feed
router.get('/barbers/ranked', getRankedBarbers);

// POST /api/marketplace/barbers/:id/update_price - Update barber price (enforced bounds)
router.post('/barbers/:id/update_price', updateBarberPrice);

// GET /api/marketplace/barbers/:id/pricing-info - Get barber pricing info
router.get('/barbers/:id/pricing-info', getBarberPricingInfo);

// GET /api/marketplace/barbers/:id/bqs - Get barber BQS breakdown
router.get('/barbers/:id/bqs', getBarberBQS);

// GET /api/marketplace/barbers/:id/market-rank - Get barber's market rank
router.get('/barbers/:id/market-rank', getBarberMarketRank);

// ============================================================
// MARKET ENDPOINTS
// ============================================================

// GET /api/marketplace/markets/:id/surge-status - Get surge status for market
router.get('/markets/:id/surge-status', getMarketSurgeStatus);

// ============================================================
// ADMIN ENDPOINTS
// ============================================================

// GET /api/marketplace/admin/markets - Get all markets with factors
router.get('/admin/markets', getAllMarkets);

// POST /api/marketplace/admin/markets/update - Update market config/factors
router.post('/admin/markets/update', updateMarket);

// GET /api/marketplace/admin/cron-history - Get cron job history
router.get('/admin/cron-history', getCronHistory);

// ============================================================
// CRON TRIGGER ENDPOINTS (Admin/Testing)
// ============================================================

// POST /api/marketplace/cron/recompute_bqs - Trigger BQS recomputation
router.post('/cron/recompute_bqs', triggerBQSRecompute);

// POST /api/marketplace/cron/update_prices - Trigger pricing update
router.post('/cron/update_prices', triggerPricingUpdate);

// POST /api/marketplace/cron/refresh_rankings - Trigger ranking refresh
router.post('/cron/refresh_rankings', triggerRankingRefresh);

// POST /api/marketplace/cron/surge_detection - Trigger surge detection
router.post('/cron/surge_detection', triggerSurgeDetection);

export default router;

