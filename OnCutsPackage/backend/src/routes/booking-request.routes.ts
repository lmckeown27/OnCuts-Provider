/**
 * Booking Request Routes (AirBnb-style)
 */

import { Router } from 'express';
import {
  createBookingRequest,
  getBarberPendingRequests,
  acceptBookingRequest,
  rejectBookingRequest,
  getCustomerProfile,
  getCustomerBookingStatus,
  sendMessage,
  getBookingMessages,
  getUserConversations,
  getUnreadCount,
} from '../controllers/booking-request.controller';

const router = Router();

// ============================================================
// BOOKING REQUEST ENDPOINTS
// ============================================================

// POST /api/booking-requests - Create new booking request
router.post('/', createBookingRequest);

// GET /api/booking-requests/barber/:barberId/pending - Get pending requests for barber
// Note: barberId here can be either the barber table ID or user ID - controller handles both
router.get('/barber/:barberId/pending', getBarberPendingRequests);

// POST /api/booking-requests/:bookingId/accept - Accept booking request
router.post('/:bookingId/accept', acceptBookingRequest);

// POST /api/booking-requests/:bookingId/reject - Reject booking request
router.post('/:bookingId/reject', rejectBookingRequest);

// GET /api/booking-requests/customer/:customerId/profile - Get customer profile (barber view)
router.get('/customer/:customerId/profile', getCustomerProfile);

// GET /api/booking-requests/customer/:customerId/status - Get customer booking status
router.get('/customer/:customerId/status', getCustomerBookingStatus);

// ============================================================
// MESSAGING ENDPOINTS
// ============================================================

// POST /api/booking-requests/:bookingId/messages - Send message
router.post('/:bookingId/messages', sendMessage);

// GET /api/booking-requests/:bookingId/messages - Get messages for booking
router.get('/:bookingId/messages', getBookingMessages);

// GET /api/booking-requests/user/:userId/conversations - Get all conversations
router.get('/user/:userId/conversations', getUserConversations);

// GET /api/booking-requests/user/:userId/unread-count - Get unread count
router.get('/user/:userId/unread-count', getUnreadCount);

export default router;

