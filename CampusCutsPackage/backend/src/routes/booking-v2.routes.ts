/**
 * Booking Routes V2
 * 
 * Direct payment booking flow (no escrow)
 * Consumer pays barber directly via Stripe
 */

import express from 'express';
import { authenticate } from '../middleware/auth';
import * as bookingController from '../controllers/booking-v2.controller';

const router = express.Router();

router.get(
  '/checkout-session/:sessionId/settlement',
  authenticate,
  bookingController.getCheckoutSettlement
);

// Create booking (Stripe Checkout Session, Sui settlement)
router.post('/', authenticate, bookingController.createBooking);

// Confirm payment (after Stripe payment succeeds)
router.post('/:id/confirm-payment', authenticate, bookingController.confirmBookingPayment);

// Get bookings for user
router.get('/', authenticate, bookingController.getBookings);

// Get booking by ID
router.get('/:id', authenticate, bookingController.getBookingById);

// Complete booking (barber marks as done)
router.post('/:id/complete', authenticate, bookingController.completeBooking);

// Cancel booking (refund if paid)
router.post('/:id/cancel', authenticate, bookingController.cancelBooking);

export default router;
