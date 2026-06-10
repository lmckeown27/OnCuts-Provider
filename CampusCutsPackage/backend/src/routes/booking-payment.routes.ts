/**
 * Booking Payment Routes
 * 
 * Handles post-booking payment flows via Stripe
 */

import express from 'express';
import { authenticate } from '../middleware/auth';
import {
  createBookingPaymentIntent,
  getBookingPaymentStatus,
} from '../controllers/booking-payment.controller';

const router = express.Router();

/**
 * Create payment intent for completed booking
 * POST /api/bookings/:id/payment/create
 */
router.post('/:id/payment/create', authenticate, createBookingPaymentIntent);

/**
 * Get payment status for booking
 * GET /api/bookings/:id/payment/status
 */
router.get('/:id/payment/status', authenticate, getBookingPaymentStatus);

export default router;

