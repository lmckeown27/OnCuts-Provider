import express, { Router } from 'express';
import { body, param, query } from 'express-validator';
import {
  submitReview,
  getBarberReviews,
  getReviewById,
  markReviewHelpful,
} from '../controllers/review.controller';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validator';

const router: Router = express.Router();

/**
 * @route   POST /api/reviews
 * @desc    Submit a review for a completed booking
 * @access  Private (Students only)
 */
router.post(
  '/',
  authenticate,
  [
    body('bookingId').isInt().withMessage('Valid booking ID required'),
    body('rating').isInt({ min: 1, max: 5 }).withMessage('Rating must be 1-5'),
    body('reviewText').notEmpty().withMessage('Review text required'),
    body('images').optional().isArray(),
    validate,
  ],
  submitReview
);

/**
 * @route   GET /api/reviews/barber/:barberId
 * @desc    Get all reviews for a barber
 * @access  Public
 */
router.get(
  '/barber/:barberId',
  [
    param('barberId').isUUID(),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 50 }),
    validate,
  ],
  getBarberReviews
);

/**
 * @route   GET /api/reviews/:id
 * @desc    Get review by ID
 * @access  Public
 */
router.get('/:id', [param('id').isUUID(), validate], getReviewById);

/**
 * @route   PUT /api/reviews/:id/helpful
 * @desc    Mark review as helpful
 * @access  Private
 */
router.put(
  '/:id/helpful',
  authenticate,
  [param('id').isUUID(), validate],
  markReviewHelpful
);

export default router;

