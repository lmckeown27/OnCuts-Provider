/**
 * Booking Controller V2
 * 
 * Implements direct payment flow (no escrow):
 * 1. Create booking → Generate Stripe payment intent
 * 2. Consumer pays → Barber receives payment directly (minus fee)
 * 3. Cancel booking → Stripe refund if already paid
 * 
 * NOTE: Platform does NOT hold funds. All payments are direct consumer-to-barber.
 */

import { Response, NextFunction } from 'express';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest } from '../middleware/auth';
import paymentServiceV2 from '../services/payment-v2.service';
// ESCROW DISABLED - Platform uses direct payments
// import escrowService, { EscrowStatus } from '../services/escrow.service';
import auditService from '../services/audit.service';
import { logger } from '../utils/logger';

/**
 * Poll Stripe Checkout + DB settlement after redirect.
 * GET /api/v2/bookings/checkout-session/:sessionId/settlement
 */
export const getCheckoutSettlement = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const { sessionId } = req.params;
    const userId = req.user!.userId;

    const bookingResult = await pool.query(
      `SELECT id, status, stripe_checkout_session_id, bridge_payout_id, on_chain_settlement_status
       FROM bookings
       WHERE stripe_checkout_session_id = $1 AND consumer_id = $2`,
      [sessionId, userId]
    );

    if (bookingResult.rows.length === 0) {
      throw new ApiError(404, 'Booking not found for this session');
    }

    const booking = bookingResult.rows[0];
    const session = await paymentServiceV2.retrieveCheckoutSession(sessionId);

    res.json({
      success: true,
      data: {
        bookingId: booking.id,
        bookingStatus: booking.status,
        stripePaymentStatus: session.payment_status,
        bridgePayoutId: booking.bridge_payout_id,
        onChainSettlementStatus: booking.on_chain_settlement_status,
        paid: session.payment_status === 'paid',
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Create booking (no escrow - direct payment)
 * POST /api/bookings
 */
export const createBooking = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const {
      barberId,
      serviceId,
      priceCents,
      requestedSlot,
      locationDetails,
      specialRequests,
    } = req.body;

    const consumerId = req.user!.userId;

    // Validate required fields
    if (!barberId || !priceCents || !requestedSlot) {
      throw new ApiError(400, 'Missing required fields');
    }

    if (priceCents <= 0) {
      throw new ApiError(400, 'Invalid price');
    }

    // 1. Verify barber exists and is active
    const barberResult = await pool.query(
      `SELECT u.id, u.role
       FROM users u
       WHERE u.id = $1 AND u.role = 'barber' AND u.is_active = true`,
      [barberId]
    );

    if (barberResult.rows.length === 0) {
      throw new ApiError(404, 'Barber not found or inactive');
    }

    // Check if consumer is trying to book with themselves
    if (consumerId === barberId) {
      throw new ApiError(400, 'You cannot book a service with yourself');
    }

    // 2. Verify consumer exists (current user)
    const consumerResult = await pool.query(
      `SELECT id FROM users WHERE id = $1`,
      [consumerId]
    );

    if (consumerResult.rows.length === 0) {
      throw new ApiError(404, 'Consumer not found');
    }

    // 3. Create booking record (status: pending until payment)
    const bookingResult = await pool.query(
      `INSERT INTO bookings (
        consumer_id, barber_id, service_id, price_cents,
        requested_slot, status, location_details, special_requests
      )
      VALUES ($1, $2, $3, $4, $5, 'pending', $6, $7)
      RETURNING *`,
      [consumerId, barberId, serviceId, priceCents, requestedSlot, locationDetails, specialRequests]
    );

    const booking = bookingResult.rows[0];

    // 4. Stripe Checkout (card) → Bridge USDC on Sui
    const frontend =
      process.env.FRONTEND_URL || process.env.WEB_APP_URL || 'http://localhost:5173';
    const checkout = await paymentServiceV2.createBookingCheckoutSession({
      bookingId: booking.id,
      consumerId,
      barberId,
      amountCents: priceCents,
      serviceDescription: `Booking #${booking.id}`,
      successUrl: `${frontend}/web/student/payment/processing`,
      cancelUrl: `${frontend}/web/consumer/booking-status`,
    });

    // 5. Track Checkout Session on booking
    await pool.query(
      `UPDATE bookings SET stripe_checkout_session_id = $1 WHERE id = $2`,
      [checkout.sessionId, booking.id]
    );

    // 6. Audit log
    await auditService.log({
      actor_user_id: consumerId,
      action: 'booking_created',
      object_type: 'booking',
      object_id: booking.id,
      details: {
        barber_id: barberId,
        price_cents: priceCents,
        stripe_checkout_session_id: checkout.sessionId,
      },
    });

    logger.info('Booking created with payment intent (direct payment)', {
      booking_id: booking.id,
      consumer_id: consumerId,
      barber_id: barberId,
      amount_dollars: priceCents / 100,
      checkout_session_id: checkout.sessionId,
    });

    res.status(201).json({
      success: true,
      data: {
        booking,
        payment: {
          checkoutUrl: checkout.checkoutUrl,
          sessionId: checkout.sessionId,
          amountCents: checkout.amountCents,
        },
      },
      message: 'Booking created. Complete payment to confirm.',
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Confirm booking payment (called after Stripe payment succeeds)
 * POST /api/bookings/:id/confirm-payment
 */
export const confirmBookingPayment = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id: bookingId } = req.params;
    const { paymentIntentId } = req.body;
    const userId = req.user!.userId;

    // 1. Get booking
    const bookingResult = await pool.query(
      `SELECT * FROM bookings WHERE id = $1 AND consumer_id = $2`,
      [bookingId, userId]
    );

    if (bookingResult.rows.length === 0) {
      throw new ApiError(404, 'Booking not found');
    }

    const booking = bookingResult.rows[0];

    if (booking.status !== 'pending') {
      throw new ApiError(400, `Cannot confirm payment for booking with status: ${booking.status}`);
    }

    // 2. Process the payment confirmation
    await paymentServiceV2.processBookingPayment({
      bookingId,
      consumerId: booking.consumer_id,
      barberId: booking.barber_id,
      amountCents: booking.price_cents,
      stripePaymentIntentId: paymentIntentId,
    });

    // 3. Update booking status to paid/confirmed
    await pool.query(
      `UPDATE bookings SET status = 'confirmed', payment_status = 'completed', updated_at = NOW()
       WHERE id = $1`,
      [bookingId]
    );

    logger.info('Booking payment confirmed (direct payment)', {
      booking_id: bookingId,
      consumer_id: userId,
      barber_id: booking.barber_id,
    });

    res.json({
      success: true,
      data: { booking_id: bookingId, status: 'confirmed' },
      message: 'Payment confirmed. Barber has been notified.',
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Complete booking (barber marks as done)
 * POST /api/bookings/:id/complete
 */
export const completeBooking = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id: bookingId } = req.params;
    const { tipCents } = req.body;
    const userId = req.user!.userId;

    // 1. Get booking and verify barber ownership
    const bookingResult = await pool.query(
      `SELECT * FROM bookings
       WHERE id = $1 AND barber_id = $2`,
      [bookingId, userId]
    );

    if (bookingResult.rows.length === 0) {
      throw new ApiError(404, 'Booking not found or not authorized');
    }

    const booking = bookingResult.rows[0];

    if (booking.status !== 'confirmed' && booking.status !== 'paid') {
      throw new ApiError(400, `Cannot complete booking with status: ${booking.status}`);
    }

    // 2. Update booking status
    await pool.query(
      `UPDATE bookings
       SET status = 'completed', completed_at = NOW()
       WHERE id = $1`,
      [bookingId]
    );

    // 3. Process tip if provided
    if (tipCents && tipCents > 0) {
      await paymentServiceV2.processTip({
        fromUserId: booking.consumer_id,
        toUserId: booking.barber_id,
        amountCents: tipCents,
        bookingId,
      });
    }

    // 4. Audit log
    await auditService.log({
      actor_user_id: userId,
      action: 'booking_completed',
      object_type: 'booking',
      object_id: bookingId,
      details: {
        tip_cents: tipCents || 0,
      },
    });

    logger.info('Booking completed', {
      booking_id: bookingId,
      barber_id: userId,
      tip_dollars: (tipCents || 0) / 100,
    });

    res.json({
      success: true,
      data: {
        booking_id: bookingId,
        status: 'completed',
        tip_dollars: (tipCents || 0) / 100,
      },
      message: 'Booking marked as completed.',
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Cancel booking (refund if already paid)
 * POST /api/bookings/:id/cancel
 */
export const cancelBooking = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id: bookingId } = req.params;
    const { reason } = req.body;
    const userId = req.user!.userId;

    // 1. Get booking
    const bookingResult = await pool.query(
      `SELECT * FROM bookings
       WHERE id = $1 AND (consumer_id = $2 OR barber_id = $2)`,
      [bookingId, userId]
    );

    if (bookingResult.rows.length === 0) {
      throw new ApiError(404, 'Booking not found or not authorized');
    }

    const booking = bookingResult.rows[0];
    const isConsumer = booking.consumer_id === userId;
    const isBarber = booking.barber_id === userId;

    if (booking.status === 'completed') {
      throw new ApiError(400, 'Cannot cancel completed booking');
    }

    if (booking.status === 'cancelled') {
      throw new ApiError(400, 'Booking already cancelled');
    }

    // 2. If payment was made, process refund
    let refundResult = null;
    if (booking.payment_status === 'completed' && booking.stripe_payment_intent_id) {
      refundResult = await paymentServiceV2.processRefund({
        bookingId,
        consumerId: booking.consumer_id,
        barberId: booking.barber_id,
        amountCents: booking.price_cents,
        stripePaymentIntentId: booking.stripe_payment_intent_id,
        reason: reason || 'Booking cancelled',
      });
    }

    // 3. Update booking status
    await pool.query(
      `UPDATE bookings
       SET status = 'cancelled', cancelled_at = NOW(), cancellation_reason = $2
       WHERE id = $1`,
      [bookingId, reason]
    );

    // 3.5 Delete the conversation and its messages when booking is cancelled
    const convResult = await pool.query(
      `SELECT id FROM conversations WHERE booking_id = $1`,
      [bookingId]
    );
    
    if (convResult.rows.length > 0) {
      const conversationId = convResult.rows[0].id;
      
      // Delete all messages in the conversation first (foreign key constraint)
      await pool.query(
        `DELETE FROM messages WHERE conversation_id = $1`,
        [conversationId]
      );
      
      // Delete the conversation
      await pool.query(
        `DELETE FROM conversations WHERE id = $1`,
        [conversationId]
      );
      
      logger.info(`Deleted conversation ${conversationId} and messages for cancelled booking ${bookingId}`);
    }

    // 4. Audit log
    await auditService.log({
      actor_user_id: userId,
      action: 'booking_cancelled',
      object_type: 'booking',
      object_id: bookingId,
      details: {
        cancelled_by: isBarber ? 'barber' : 'consumer',
        reason,
        refund_issued: !!refundResult,
        refund_amount_cents: booking.price_cents,
      },
    });

    logger.info('Booking cancelled', {
      booking_id: bookingId,
      cancelled_by: isBarber ? 'barber' : 'consumer',
      refund_issued: !!refundResult,
      refund_dollars: booking.price_cents / 100,
      reason,
    });

    res.json({
      success: true,
      data: {
        booking_id: bookingId,
        status: 'cancelled',
        refund_issued: !!refundResult,
        refund_amount_dollars: booking.price_cents / 100,
      },
      message: refundResult 
        ? 'Booking cancelled. Refund has been processed.'
        : 'Booking cancelled.',
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Get bookings for user
 * GET /api/bookings
 */
export const getBookings = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const userRole = req.user!.role;
    const { status } = req.query;

    let query = `
      SELECT b.*,
        consumer."firstName" as consumer_first_name,
        consumer."lastName" as consumer_last_name,
        consumer.email as consumer_email,
        barber."firstName" as barber_first_name,
        barber."lastName" as barber_last_name,
        barber.email as barber_email
      FROM bookings b
      JOIN users consumer ON b.consumer_id = consumer.id
      JOIN users barber ON b.barber_id = barber.id
      WHERE ${userRole === 'barber' ? 'b.barber_id' : 'b.consumer_id'} = $1
    `;

    const params: any[] = [userId];

    if (status) {
      query += ` AND b.status = $2`;
      params.push(status);
    }

    query += ` ORDER BY b.created_at DESC`;

    const result = await pool.query(query, params);

    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Get booking by ID
 * GET /api/bookings/:id
 */
export const getBookingById = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const userId = req.user!.userId;

    const result = await pool.query(
      `SELECT b.*,
        consumer."firstName" as consumer_first_name,
        consumer."lastName" as consumer_last_name,
        barber."firstName" as barber_first_name,
        barber."lastName" as barber_last_name
      FROM bookings b
      JOIN users consumer ON b.consumer_id = consumer.id
      JOIN users barber ON b.barber_id = barber.id
      WHERE b.id = $1 AND (b.consumer_id = $2 OR b.barber_id = $2)`,
      [id, userId]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'Booking not found');
    }

    res.json({
      success: true,
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
};
