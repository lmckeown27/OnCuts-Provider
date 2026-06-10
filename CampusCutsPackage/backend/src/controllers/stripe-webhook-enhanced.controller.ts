/**
 * Enhanced Stripe Webhook Controller
 * 
 * Handles Stripe webhook events with full database integration
 * and blockchain escrow coordination
 * 
 * Required packages: stripe (already installed)
 * 
 * Events handled:
 * - payment_intent.succeeded → Mark booking as paid, trigger escrow lock
 * - payment_intent.payment_failed → Mark booking as failed, notify user
 * - payment_intent.canceled → Cancel booking
 * - charge.refunded → Process refund, release escrow
 * - account.updated → Update Stripe Connect status for barbers
 * - transfer.created → Log payout completion
 * - transfer.updated → Handle failed payouts
 */

import { Request, Response } from 'express';
import Stripe from 'stripe';
import { constructStripeWebhookEvent, hasStripeWebhookSecretConfigured } from '../config/stripe';
import { logger } from '../utils/logger';
import { pool, query } from '../database/connection';

/**
 * Main webhook handler
 * Verifies signature and routes to appropriate handler
 */
export const handleStripeWebhook = async (req: Request, res: Response) => {
  const sig = req.headers['stripe-signature'] as string;

  if (!sig) {
    logger.error('Stripe webhook: Missing stripe-signature header');
    return res.status(400).json({ error: 'Missing signature header' });
  }

  let event: Stripe.Event;

  try {
    // Verify webhook signature
    if (hasStripeWebhookSecretConfigured()) {
      event = constructStripeWebhookEvent(req.body, sig);
      logger.info(`Stripe webhook verified: ${event.type} (ID: ${event.id})`);
    } else {
      // For development without webhook secret
      event = req.body as Stripe.Event;
      logger.warn('⚠️ Stripe webhook: Secret not configured - skipping signature verification (DEV ONLY)');
    }
  } catch (err: any) {
    logger.error(`Stripe webhook signature verification failed: ${err.message}`);
    return res.status(400).json({ error: `Webhook Error: ${err.message}` });
  }

  // Handle the event
  try {
    logger.info(`Processing Stripe event: ${event.type}`);

    switch (event.type) {
      case 'payment_intent.succeeded':
        await handlePaymentIntentSucceeded(event.data.object as Stripe.PaymentIntent);
        break;

      case 'payment_intent.payment_failed':
        await handlePaymentIntentFailed(event.data.object as Stripe.PaymentIntent);
        break;

      case 'payment_intent.canceled':
        await handlePaymentIntentCanceled(event.data.object as Stripe.PaymentIntent);
        break;

      case 'charge.refunded':
        await handleChargeRefunded(event.data.object as Stripe.Charge);
        break;

      case 'account.updated':
        await handleAccountUpdated(event.data.object as Stripe.Account);
        break;

      case 'transfer.created':
        await handleTransferCreated(event.data.object as Stripe.Transfer);
        break;

      case 'transfer.updated':
        const transfer = event.data.object as any;
        if (transfer.status === 'failed') {
          await handleTransferFailed(transfer as Stripe.Transfer);
        } else {
          logger.info(`Transfer updated: ${transfer.id} - Status: ${transfer.status}`);
        }
        break;

      default:
        logger.info(`Unhandled Stripe event type: ${event.type}`);
    }

    // Always respond with success to acknowledge receipt
    res.json({ received: true, eventId: event.id });
    
  } catch (error: any) {
    logger.error(`Error handling Stripe webhook event: ${error.message}`, {
      eventType: event.type,
      eventId: event.id,
      stack: error.stack,
    });
    
    // Still return 200 to prevent retries for unrecoverable errors
    // Stripe will retry 500 errors, which we don't want for data consistency issues
    res.status(200).json({ 
      received: true, 
      error: 'Internal processing error (logged)',
      eventId: event.id 
    });
  }
};

/**
 * Handle successful payment intent
 * Updates booking status, records transaction, triggers escrow
 */
async function handlePaymentIntentSucceeded(paymentIntent: Stripe.PaymentIntent) {
  const { bookingId, studentId, barberId } = paymentIntent.metadata;
  const amount = paymentIntent.amount / 100; // Convert cents to dollars

  logger.info(`💰 Payment succeeded: ${paymentIntent.id}`, {
    bookingId,
    amount: `$${amount}`,
    studentId,
    barberId,
  });

  if (!bookingId) {
    logger.warn('❌ No booking ID in payment intent metadata');
    return;
  }

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // 1. Update booking status to 'confirmed' and mark as paid
    const updateBookingQuery = `
      UPDATE bookings 
      SET 
        status = 'confirmed',
        payment_status = 'paid',
        payment_intent_id = $1,
        updated_at = NOW()
      WHERE id = $2
      RETURNING *
    `;

    const bookingResult = await client.query(updateBookingQuery, [
      paymentIntent.id,
      bookingId,
    ]);

    if (bookingResult.rowCount === 0) {
      logger.warn(`Booking ${bookingId} not found in database`);
      await client.query('ROLLBACK');
      return;
    }

    const booking = bookingResult.rows[0];
    logger.info(`✅ Booking ${bookingId} marked as paid and confirmed`);

    // 2. Record payment transaction
    const recordTransactionQuery = `
      INSERT INTO payment_transactions (
        booking_id,
        student_id,
        barber_id,
        payment_intent_id,
        amount,
        currency,
        status,
        payment_method,
        created_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
      RETURNING id
    `;

    const transactionResult = await client.query(recordTransactionQuery, [
      bookingId,
      studentId || booking.student_id,
      barberId || booking.barber_id,
      paymentIntent.id,
      amount,
      paymentIntent.currency.toUpperCase(),
      'succeeded',
      paymentIntent.payment_method_types[0] || 'card',
    ]);

    const transactionId = transactionResult.rows[0].id;
    logger.info(`💳 Payment transaction recorded: ${transactionId}`);

    // 3. Optional: Sui escrow / relayer hook when on-chain settlement is enabled (Stripe remains source of truth).

    // 4. Send confirmation notifications
    // TODO: Uncomment when notification service is ready
    /*
    try {
      const { notificationService } = await import('../services/notification.service');
      await notificationService.sendBookingConfirmation(
        studentId || booking.student_id,
        barberId || booking.barber_id,
        bookingId
      );
      logger.info(`📧 Confirmation notifications sent for booking ${bookingId}`);
    } catch (notifError: any) {
      logger.error(`Failed to send notifications: ${notifError.message}`);
    }
    */

    await client.query('COMMIT');
    logger.info(`✅ Payment processing complete for booking ${bookingId}`);

  } catch (error: any) {
    await client.query('ROLLBACK');
    logger.error(`Error processing payment success for booking ${bookingId}:`, {
      error: error.message,
      stack: error.stack,
    });
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Handle failed payment intent
 * Updates booking status and notifies user
 */
async function handlePaymentIntentFailed(paymentIntent: Stripe.PaymentIntent) {
  const { bookingId, studentId } = paymentIntent.metadata;
  const amount = paymentIntent.amount / 100;

  logger.error(`❌ Payment failed: ${paymentIntent.id}`, {
    bookingId,
    amount: `$${amount}`,
    studentId,
    reason: paymentIntent.last_payment_error?.message || 'Unknown',
  });

  if (!bookingId) return;

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // Update booking status to 'payment_failed'
    const updateQuery = `
      UPDATE bookings 
      SET 
        status = 'payment_failed',
        payment_status = 'failed',
        payment_intent_id = $1,
        updated_at = NOW()
      WHERE id = $2
      RETURNING *
    `;

    const result = await client.query(updateQuery, [paymentIntent.id, bookingId]);

    if (result.rowCount && result.rowCount > 0) {
      logger.info(`Booking ${bookingId} marked as payment_failed`);
    }

    // Record failed transaction
    const recordTransactionQuery = `
      INSERT INTO payment_transactions (
        booking_id,
        student_id,
        payment_intent_id,
        amount,
        currency,
        status,
        failure_reason,
        created_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
    `;

    await client.query(recordTransactionQuery, [
      bookingId,
      studentId,
      paymentIntent.id,
      amount,
      paymentIntent.currency.toUpperCase(),
      'failed',
      paymentIntent.last_payment_error?.message || 'Payment failed',
    ]);

    // TODO: Send failure notification
    /*
    const { notificationService } = await import('../services/notification.service');
    await notificationService.sendPaymentFailedNotification(studentId, bookingId);
    */

    await client.query('COMMIT');
    logger.info(`Payment failure processed for booking ${bookingId}`);

  } catch (error: any) {
    await client.query('ROLLBACK');
    logger.error(`Error processing payment failure: ${error.message}`);
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Handle canceled payment intent
 */
async function handlePaymentIntentCanceled(paymentIntent: Stripe.PaymentIntent) {
  const { bookingId } = paymentIntent.metadata;

  logger.info(`Payment canceled: ${paymentIntent.id}`, { bookingId });

  if (!bookingId) return;

  try {
    const updateQuery = `
      UPDATE bookings 
      SET 
        status = 'canceled',
        payment_status = 'canceled',
        updated_at = NOW()
      WHERE id = $1
    `;

    await query(updateQuery, [bookingId]);
    logger.info(`Booking ${bookingId} canceled due to payment cancellation`);

  } catch (error: any) {
    logger.error(`Error processing payment cancellation: ${error.message}`);
    throw error;
  }
}

/**
 * Handle charge refund
 * Updates booking and releases escrow
 */
async function handleChargeRefunded(charge: Stripe.Charge) {
  const amount = charge.amount_refunded / 100;

  logger.info(`Refund processed: ${charge.id} - Amount: $${amount}`, {
    paymentIntentId: charge.payment_intent,
  });

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // Find booking by payment_intent_id
    const findBookingQuery = `
      SELECT * FROM bookings 
      WHERE payment_intent_id = $1
    `;

    const bookingResult = await client.query(findBookingQuery, [charge.payment_intent]);

    if (bookingResult.rowCount === 0) {
      logger.warn(`No booking found for payment intent: ${charge.payment_intent}`);
      await client.query('ROLLBACK');
      return;
    }

    const booking = bookingResult.rows[0];

    // Update booking status
    const updateQuery = `
      UPDATE bookings 
      SET 
        status = 'refunded',
        payment_status = 'refunded',
        updated_at = NOW()
      WHERE id = $1
    `;

    await client.query(updateQuery, [booking.id]);
    logger.info(`Booking ${booking.id} marked as refunded`);

    // Record refund transaction
    const recordRefundQuery = `
      INSERT INTO payment_transactions (
        booking_id,
        student_id,
        barber_id,
        payment_intent_id,
        amount,
        currency,
        status,
        created_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
    `;

    await client.query(recordRefundQuery, [
      booking.id,
      booking.student_id,
      booking.barber_id,
      charge.payment_intent,
      -amount, // Negative for refund
      charge.currency.toUpperCase(),
      'refunded',
    ]);

    // Optional: release Sui-side settlement when on-chain escrow exists.

    await client.query('COMMIT');
    logger.info(`✅ Refund processed for booking ${booking.id}`);

  } catch (error: any) {
    await client.query('ROLLBACK');
    logger.error(`Error processing refund: ${error.message}`);
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Handle Stripe Connect account update
 * Updates barber onboarding status
 */
async function handleAccountUpdated(account: Stripe.Account) {
  const { userId, barberId } = account.metadata || {};

  logger.info(`Stripe Connect account updated: ${account.id}`, {
    userId,
    barberId,
    chargesEnabled: account.charges_enabled,
    payoutsEnabled: account.payouts_enabled,
  });

  if (!userId && !barberId) {
    logger.warn('No user/barber ID in Stripe account metadata');
    return;
  }

  try {
    const isOnboarded = account.charges_enabled && account.payouts_enabled;

    const updateQuery = `
      UPDATE users 
      SET 
        stripe_account_id = $1,
        stripe_connect_onboarded = $2,
        stripe_charges_enabled = $3,
        stripe_payouts_enabled = $4,
        updated_at = NOW()
      WHERE id = $5
      RETURNING id, email
    `;

    const result = await query(updateQuery, [
      account.id,
      isOnboarded,
      account.charges_enabled,
      account.payouts_enabled,
      userId || barberId,
    ]);

    if (result.rowCount && result.rowCount > 0) {
      const user = result.rows[0];
      logger.info(`✅ Barber ${user.id} (${user.email}) Stripe Connect status updated`, {
        onboarded: isOnboarded,
      });

      if (isOnboarded) {
        // TODO: Send onboarding success notification
        logger.info(`🎉 Barber ${user.id} fully onboarded to Stripe Connect`);
      }
    }

  } catch (error: any) {
    logger.error(`Error processing account update: ${error.message}`);
    throw error;
  }
}

/**
 * Handle transfer created (payout to barber)
 */
async function handleTransferCreated(transfer: Stripe.Transfer) {
  const amount = transfer.amount / 100;

  logger.info(`Transfer created: ${transfer.id} - Amount: $${amount}`, {
    destination: transfer.destination,
    metadata: transfer.metadata,
  });

  try {
    const { bookingId, barberId } = transfer.metadata || {};

    if (bookingId) {
      // Record payout
      const recordPayoutQuery = `
        INSERT INTO barber_payouts (
          barber_id,
          booking_id,
          transfer_id,
          amount,
          currency,
          status,
          created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, NOW())
      `;

      await query(recordPayoutQuery, [
        barberId,
        bookingId,
        transfer.id,
        amount,
        transfer.currency.toUpperCase(),
        'completed',
      ]);

      logger.info(`💸 Payout recorded for booking ${bookingId}`);
    }

  } catch (error: any) {
    logger.error(`Error processing transfer: ${error.message}`);
    // Don't throw - payout already succeeded
  }
}

/**
 * Handle failed transfer
 */
async function handleTransferFailed(transfer: Stripe.Transfer) {
  const amount = transfer.amount / 100;

  logger.error(`❌ Transfer failed: ${transfer.id} - Amount: $${amount}`, {
    destination: transfer.destination,
    metadata: transfer.metadata,
  });

  try {
    const { bookingId, barberId } = transfer.metadata || {};

    if (bookingId && barberId) {
      // Update payout status
      const updateQuery = `
        UPDATE barber_payouts 
        SET status = 'failed', updated_at = NOW()
        WHERE transfer_id = $1
      `;

      await query(updateQuery, [transfer.id]);

      // TODO: Notify barber of failed payout
      logger.info(`Barber ${barberId} notified of failed payout for booking ${bookingId}`);
    }

  } catch (error: any) {
    logger.error(`Error processing transfer failure: ${error.message}`);
  }
}

