/**
 * Booking Payment Controller
 * 
 * Handles the complete payment flow for CampusCuts bookings:
 * 1. Student books appointment (no payment upfront)
 * 2. Barber completes service
 * 3. Create Payment Intent for student to pay
 * 4. Student pays via Stripe
 * 5. Webhook confirms payment
 * 6. Transfer funds to barber (minus 15% fee)
 * 7. Credit custodial wallet balances
 * 
 * Based on user instructions for Stripe integration
 */

import { Request, Response, NextFunction } from 'express';
import stripeService from '../services/stripe.service';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';
import type { AuthRequest } from '../middleware/auth';

/**
 * Step 1 & 3: Create Payment Intent for post-booking payment
 * POST /api/bookings/:id/payment/create
 * 
 * Called AFTER appointment is completed
 */
export const createBookingPaymentIntent = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user!.userId;
    const { id: bookingId } = req.params;

    logger.info('Creating post-booking payment intent', {
      user_id: userId,
      booking_id: bookingId,
    });

    // 1. Get booking details
    const bookingResult = await pool.query(
      `SELECT * FROM bookings WHERE id = $1 AND client_id = $2`,
      [bookingId, userId]
    );

    if (bookingResult.rows.length === 0) {
      throw new ApiError(404, 'Booking not found');
    }

    const booking = bookingResult.rows[0];

    // 2. Verify booking is completed but not paid
    if (booking.status !== 'completed') {
      throw new ApiError(400, 'Booking must be completed before payment');
    }

    if (booking.payment_status === 'paid') {
      throw new ApiError(400, 'Booking already paid');
    }

    // 3. Get or create Stripe customer for student
    let stripeCustomerId = null;
    const userResult = await pool.query(
      `SELECT stripe_customer_id, email, first_name, last_name FROM users WHERE id = $1`,
      [userId]
    );

    if (userResult.rows[0].stripe_customer_id) {
      stripeCustomerId = userResult.rows[0].stripe_customer_id;
    } else {
      // Create Stripe customer (Step 2 from instructions)
      const customer = await stripeService.createCustomer({
        userId,
        email: userResult.rows[0].email,
        name: `${userResult.rows[0].first_name} ${userResult.rows[0].last_name}`,
      });

      stripeCustomerId = customer.id;

      // Save customer ID
      await pool.query(
        `UPDATE users SET stripe_customer_id = $1 WHERE id = $2`,
        [stripeCustomerId, userId]
      );
    }

    // 4. Create Payment Intent (Step 3 from instructions)
    const paymentIntentResult = await stripeService.createPaymentIntent({
      amount: booking.price_cents,
      clientId: userId,
      barberId: booking.barber_id,
      bookingId: parseInt(bookingId),
      description: `Payment for ${booking.service_name} - CampusCuts`,
    });

    // 5. Update booking with payment intent ID
    await pool.query(
      `UPDATE bookings 
       SET stripe_payment_intent_id = $1,
           payment_status = 'pending'
       WHERE id = $2`,
      [paymentIntentResult.paymentIntentId, bookingId]
    );

    // 6. Audit log (using mock for development)
    logger.info('Payment intent created', {
      user_id: userId,
      action: 'PAYMENT_INTENT_CREATED',
      booking_id: bookingId,
      payment_intent_id: paymentIntentResult.paymentIntentId,
      amount_cents: booking.price_cents,
    });

    res.status(200).json({
      success: true,
      message: 'Payment intent created',
      data: {
        client_secret: paymentIntentResult.clientSecret,
        payment_intent_id: paymentIntentResult.paymentIntentId,
        amount_dollars: booking.price_cents / 100,
        barber_name: booking.barber_name,
        service_name: booking.service_name,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Step 4 & 5: Handle successful payment (called by webhook)
 * This is the core payment processing logic
 * 
 * Called when Stripe webhook sends 'payment_intent.succeeded'
 */
export const handlePaymentSuccess = async (
  paymentIntentId: string
): Promise<void> => {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // 1. Get Payment Intent from Stripe
    const paymentIntent = await stripeService.getPaymentIntent(paymentIntentId);

    if (paymentIntent.status !== 'succeeded') {
      logger.warn('Payment Intent not succeeded', {
        payment_intent_id: paymentIntentId,
        status: paymentIntent.status,
      });
      await client.query('ROLLBACK');
      return;
    }

    const bookingId = paymentIntent.metadata.booking_id;
    const barberId = paymentIntent.metadata.barber_id;
    const clientId = paymentIntent.metadata.client_id;
    const amountCents = paymentIntent.amount;

    logger.info('Processing successful booking payment', {
      payment_intent_id: paymentIntentId,
      booking_id: bookingId,
      amount_dollars: amountCents / 100,
    });

    // 2. Get booking details
    const bookingResult = await client.query(
      `SELECT * FROM bookings WHERE id = $1`,
      [bookingId]
    );

    if (bookingResult.rows.length === 0) {
      throw new Error(`Booking ${bookingId} not found`);
    }

    const booking = bookingResult.rows[0];

    // 3. Calculate fees (Step 6: Distribute payment minus 15%)
    const { platformFee, barberPayout } = stripeService.calculateFees(amountCents);

    logger.info('Payment distribution', {
      total: amountCents / 100,
      platform_fee: platformFee / 100,
      barber_payout: barberPayout / 100,
    });

    // 4. Get barber's Stripe Connect account
    const barberResult = await client.query(
      `SELECT stripe_account_id FROM users WHERE id = $1`,
      [barberId]
    );

    const barberStripeAccountId = barberResult.rows[0]?.stripe_account_id;

    if (!barberStripeAccountId) {
      logger.error('Barber does not have Stripe Connect account', {
        barber_id: barberId,
        booking_id: bookingId,
      });
      throw new Error('Barber payout account not configured');
    }

    // 5. Transfer to barber via Stripe Connect (Step 6 from instructions)
    const transferId = await stripeService.transferToBarber({
      amount: barberPayout,
      barberStripeAccountId,
      bookingId: parseInt(bookingId),
      description: `Payment for ${booking.service_name} - Booking #${bookingId}`,
      sourceTransaction: paymentIntent.latest_charge as string,
    });

    // 6. Update custodial wallet balances (simplified for development with mock database)
    // In production, this would use the V2 transaction service
    logger.info('Recording payment in custodial wallet', {
      platform_received: amountCents,
      barber_payout: barberPayout,
      platform_fee: platformFee,
      booking_id: bookingId,
    });

    // Update booking payment status
    await client.query(
      `UPDATE bookings 
       SET payment_status = 'paid',
           stripe_transfer_id = $1,
           paid_at = NOW()
       WHERE id = $2`,
      [transferId, bookingId]
    );

    // Audit logs
    logger.info('Booking payment successful', {
      user_id: clientId,
      action: 'BOOKING_PAYMENT_SUCCESS',
      booking_id: bookingId,
      payment_intent_id: paymentIntentId,
      amount_cents: amountCents,
      transfer_id: transferId,
    });

    logger.info('Barber payout received', {
      user_id: barberId,
      action: 'BARBER_PAYOUT_RECEIVED',
      booking_id: bookingId,
      payout_amount: barberPayout,
      platform_fee: platformFee,
      transfer_id: transferId,
    });

    await client.query('COMMIT');

    logger.info('✅ Booking payment processed successfully', {
      booking_id: bookingId,
      payment_intent_id: paymentIntentId,
      barber_payout_dollars: barberPayout / 100,
      platform_fee_dollars: platformFee / 100,
    });
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error('❌ Failed to process booking payment', {
      payment_intent_id: paymentIntentId,
      error,
    });
    throw error;
  } finally {
    client.release();
  }
};

/**
 * Handle failed payment
 */
export const handlePaymentFailed = async (
  paymentIntentId: string
): Promise<void> => {
  try {
    const paymentIntent = await stripeService.getPaymentIntent(paymentIntentId);
    const bookingId = paymentIntent.metadata.booking_id;
    const clientId = paymentIntent.metadata.client_id;

    logger.error('Payment failed for booking', {
      payment_intent_id: paymentIntentId,
      booking_id: bookingId,
      failure_message: paymentIntent.last_payment_error?.message,
    });

    // Update booking status
    await pool.query(
      `UPDATE bookings 
       SET payment_status = 'failed'
       WHERE id = $1`,
      [bookingId]
    );

    // Audit log
    logger.error('Booking payment failed', {
      user_id: clientId,
      action: 'BOOKING_PAYMENT_FAILED',
      booking_id: bookingId,
      payment_intent_id: paymentIntentId,
      failure_reason: paymentIntent.last_payment_error?.message,
    });

    // Could send notification to student here
  } catch (error) {
    logger.error('Failed to handle payment failure', {
      payment_intent_id: paymentIntentId,
      error,
    });
  }
};

/**
 * Get payment status for a booking
 * GET /api/bookings/:id/payment/status
 */
export const getBookingPaymentStatus = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user!.userId;
    const { id: bookingId } = req.params;

    const bookingResult = await pool.query(
      `SELECT 
         b.id,
         b.payment_status,
         b.price_cents,
         b.stripe_payment_intent_id,
         b.paid_at,
         b.service_name,
         u.first_name as barber_first_name,
         u.last_name as barber_last_name
       FROM bookings b
       JOIN users u ON b.barber_id = u.id
       WHERE b.id = $1 AND (b.client_id = $2 OR b.barber_id = $2)`,
      [bookingId, userId]
    );

    if (bookingResult.rows.length === 0) {
      throw new ApiError(404, 'Booking not found');
    }

    const booking = bookingResult.rows[0];

    res.status(200).json({
      success: true,
      data: {
        booking_id: booking.id,
        payment_status: booking.payment_status,
        amount_dollars: booking.price_cents / 100,
        service_name: booking.service_name,
        barber_name: `${booking.barber_first_name} ${booking.barber_last_name}`,
        paid_at: booking.paid_at,
        payment_intent_id: booking.stripe_payment_intent_id,
      },
    });
  } catch (error) {
    next(error);
  }
};

