/**
 * Pricing Routes
 * 
 * API endpoints for the dynamic pricing engine
 */

import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import * as pricingController from '../controllers/pricing.controller';

const router = Router();

// Public endpoints (require authentication but not admin)

/**
 * GET /api/pricing/estimate
 * Get price estimate for a barber/service
 */
router.get('/estimate', authenticate, pricingController.getPriceEstimate);

/**
 * GET /api/pricing/barber/:barberId/score
 * Get barber's performance score and history
 */
router.get('/barber/:barberId/score', authenticate, pricingController.getBarberScore);

/**
 * GET /api/pricing/barber/:barberId/history
 * Get barber's price history
 */
router.get('/barber/:barberId/history', authenticate, pricingController.getBarberPriceHistory);

/**
 * GET /api/pricing/services
 * Get all services with base prices
 */
router.get('/services', authenticate, pricingController.getServices);

/**
 * GET /api/pricing/config
 * Get current pricing configuration
 */
router.get('/config', authenticate, pricingController.getConfig);

// Admin-only endpoints

/**
 * GET /api/pricing/campus/:campusId/metrics
 * Get campus market metrics (admin only)
 */
router.get('/campus/:campusId/metrics', authenticate, pricingController.getCampusMetrics);

/**
 * POST /api/pricing/recompute
 * Trigger pricing recompute (admin only)
 */
router.post('/recompute', authenticate, pricingController.triggerRecompute);

/**
 * GET /api/pricing/anomalies
 * Get recent price anomalies (admin only)
 */
router.get('/anomalies', authenticate, pricingController.getAnomalies);

/**
 * PUT /api/pricing/config
 * Update pricing configuration (admin only)
 */
router.put('/config', authenticate, pricingController.updateConfig);

export default router;

