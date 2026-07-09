/**
 * Dynamic Pricing Routes
 */

import { Router } from 'express';
import * as dynamicPricingController from '../controllers/dynamic-pricing.controller';

const router = Router();

/**
 * @route   POST /api/dynamic-pricing/calculate
 * @desc    Calculate recommended price for a service
 * @access  Public (can be called by frontend)
 */
router.post('/calculate', dynamicPricingController.calculatePrice);

/**
 * @route   POST /api/dynamic-pricing/batch
 * @desc    Calculate prices for multiple barbers (comparison view)
 * @access  Public
 */
router.post('/batch', dynamicPricingController.calculateBatchPrices);

/**
 * @route   POST /api/dynamic-pricing/suggest-starting-price
 * @desc    Get suggested starting price for new barber
 * @access  Public
 */
router.post('/suggest-starting-price', dynamicPricingController.suggestStartingPrice);

/**
 * @route   GET /api/dynamic-pricing/time-multiplier
 * @desc    Get current time-of-day multiplier
 * @access  Public
 */
router.get('/time-multiplier', dynamicPricingController.getCurrentTimeMultiplier);

/**
 * @route   GET /api/dynamic-pricing/config
 * @desc    Get pricing configuration (transparency)
 * @access  Public
 */
router.get('/config', dynamicPricingController.getPricingConfig);

export default router;

