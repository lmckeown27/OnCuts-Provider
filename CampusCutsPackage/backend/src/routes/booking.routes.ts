import express, { Router } from 'express';
import { body, param, query } from 'express-validator';
import {
  createBooking,
  getBookings,
  getBookingById,
  confirmBooking,
  completeBooking,
  cancelBooking,
  getUserBookingHistory,
} from '../controllers/booking.controller';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validator';

const router: Router = express.Router();

/**
 * @route   POST /api/bookings
 * @desc    Create new booking
 * @access  Private (Students)
 */
router.post(
  '/',
  authenticate,
  [
    body('barberId').isUUID().withMessage('Valid barber ID required'),
    body('serviceType').notEmpty().withMessage('Service type required'),
    body('scheduledTime').isISO8601().withMessage('Valid scheduled time required'),
    body('durationMinutes').isInt({ min: 15, max: 240 }).withMessage('Duration must be 15-240 minutes'),
    body('locationDetails').optional().isString(),
    body('specialRequests').optional().isString(),
    validate,
  ],
  createBooking
);

/**
 * @route   GET /api/bookings
 * @desc    Get all bookings (filtered by user role)
 * @access  Private
 */
router.get(
  '/',
  authenticate,
  [
    query('status').optional().isIn(['pending', 'confirmed', 'completed', 'cancelled']),
    query('startDate').optional().isISO8601(),
    query('endDate').optional().isISO8601(),
    validate,
  ],
  getBookings
);

/**
 * @route   GET /api/bookings/:id
 * @desc    Get booking by ID
 * @access  Private (Only involved parties)
 */
router.get('/:id', authenticate, [param('id').isInt(), validate], getBookingById);

/**
 * @route   PUT /api/bookings/:id/confirm
 * @desc    Confirm a booking
 * @access  Private (Barber only)
 */
router.put(
  '/:id/confirm',
  authenticate,
  [param('id').isInt(), validate],
  confirmBooking
);

/**
 * @route   PUT /api/bookings/:id/complete
 * @desc    Mark booking as completed
 * @access  Private (Barber only)
 */
router.put(
  '/:id/complete',
  authenticate,
  [param('id').isInt(), validate],
  completeBooking
);

/**
 * @route   PUT /api/bookings/:id/cancel
 * @desc    Cancel a booking
 * @access  Private (Client or Barber)
 */
router.put(
  '/:id/cancel',
  authenticate,
  [
    param('id').isInt(),
    body('reason').optional().isString(),
    validate,
  ],
  cancelBooking
);

/**
 * @route   GET /api/bookings/history/user
 * @desc    Get booking history for authenticated user
 * @access  Private
 */
router.get('/history/user', authenticate, getUserBookingHistory);

export default router;

