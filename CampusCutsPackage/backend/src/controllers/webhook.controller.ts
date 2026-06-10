/**
 * Stripe Webhook Controller
 * 
 * Step 7: Webhook Event Notifications
 * Handles Stripe events like payment_intent.succeeded
 * 
 * Security: Verifies webhook signatures to prevent fraud
 */

import { Request, Response, NextFunction } from 'express';
import stripeMonitorService from '../services/stripe-monitor.service';
import { handlePaymentSuccess, handlePaymentFailed } from './booking-payment.controller';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';
import { constructStripeWebhookEvent } from '../config/stripe';

/**
 * Stripe Webhook Handler (legacy)
 * POST /api/webhooks/stripe
 *
 * Production uses `stripe-webhook-secure.controller` via `webhook.routes.ts`.
 *
 * IMPORTANT: This route MUST use raw body, not JSON parsed
 * See index.ts for proper configuration
 */
export const handleStripeWebhook = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const signature = req.headers['stripe-signature'] as string;

    if (!signature) {
      logger.warn('Webhook received without signature');
      throw new ApiError(400, 'No signature provided');
    }

    // Tries STRIPE_WEBHOOK_SECRET*, STRIPE_*_WEBHOOK_SECRET (see config/stripe.ts)
    const event = constructStripeWebhookEvent(req.body, signature);

    logger.info('Stripe webhook received', {
      event_type: event.type,
      event_id: event.id,
    });

    // Step 7.1.5: Process event for live monitoring (store + broadcast to admin)
    await stripeMonitorService.processEvent(event);

    // Step 7.2: Handle different event types
    switch (event.type) {
      case 'payment_intent.succeeded':
        await handlePaymentIntentSucceeded(event);
        break;

      case 'payment_intent.payment_failed':
        await handlePaymentIntentFailedEvent(event);
        break;

      case 'charge.refunded':
        await handleChargeRefunded(event);
        break;

      case 'account.updated':
        await handleAccountUpdated(event);
        break;

      case 'payout.paid':
        await handlePayoutPaid(event);
        break;

      case 'payout.failed':
        await handlePayoutFailedEvent(event);
        break;

      default:
        logger.info('Unhandled webhook event type', {
          event_type: event.type,
        });
    }

    // Always return 200 to acknowledge receipt
    // Stripe will retry if we return an error
    res.status(200).json({ received: true });
  } catch (error) {
    logger.error('Webhook handling failed', error);
    // Return 400 for signature errors (don't retry)
    // Return 500 for processing errors (Stripe will retry)
    next(error);
  }
};

/**
 * Handle payment_intent.succeeded event
 * This is the core payment confirmation (Step 7 from instructions)
 */
async function handlePaymentIntentSucceeded(event: any) {
  const paymentIntent = event.data.object;

  logger.info('Processing payment_intent.succeeded', {
    payment_intent_id: paymentIntent.id,
    amount: paymentIntent.amount,
    status: paymentIntent.status,
  });

  try {
    // Call the main payment processing logic
    await handlePaymentSuccess(paymentIntent.id);

    logger.info('✅ Payment processed successfully via webhook', {
      payment_intent_id: paymentIntent.id,
    });
  } catch (error) {
    logger.error('❌ Failed to process payment webhook', {
      payment_intent_id: paymentIntent.id,
      error,
    });
    // Don't throw - we don't want Stripe to retry
    // Log the error for manual investigation
  }
}

/**
 * Handle payment_intent.payment_failed event
 */
async function handlePaymentIntentFailedEvent(event: any) {
  const paymentIntent = event.data.object;

  logger.error('Payment failed', {
    payment_intent_id: paymentIntent.id,
    amount: paymentIntent.amount,
    failure_message: paymentIntent.last_payment_error?.message,
    failure_code: paymentIntent.last_payment_error?.code,
  });

  try {
    await handlePaymentFailed(paymentIntent.id);

    // Could send notification to student here
    logger.info('Payment failure handled', {
      payment_intent_id: paymentIntent.id,
    });
  } catch (error) {
    logger.error('Failed to handle payment failure webhook', {
      payment_intent_id: paymentIntent.id,
      error,
    });
  }
}

/**
 * Handle charge.refunded event
 */
async function handleChargeRefunded(event: any) {
  const charge = event.data.object;

  logger.info('Refund processed', {
    charge_id: charge.id,
    refund_amount: charge.amount_refunded,
    payment_intent: charge.payment_intent,
  });

  // The refund was initiated by our backend
  // Transaction already handled in refundPayment method
  // This is just for logging/notification
}

/**
 * Handle account.updated event (Stripe Connect)
 */
async function handleAccountUpdated(event: any) {
  const account = event.data.object;

  logger.info('Stripe Connect account updated', {
    account_id: account.id,
    details_submitted: account.details_submitted,
    charges_enabled: account.charges_enabled,
    payouts_enabled: account.payouts_enabled,
  });

  // Could update barber's verification status in database
  // Or send notification if account is now fully onboarded
}

/**
 * Handle payout.paid event
 */
async function handlePayoutPaid(event: any) {
  const payout = event.data.object;

  logger.info('Payout completed', {
    payout_id: payout.id,
    amount: payout.amount,
    arrival_date: payout.arrival_date,
    destination: payout.destination,
  });

  // Payout to barber's bank completed successfully
  // Could update withdrawal status in database
  // Or send confirmation notification to barber
}

/**
 * Handle payout.failed event
 */
async function handlePayoutFailedEvent(event: any) {
  const payout = event.data.object;

  logger.error('Payout failed', {
    payout_id: payout.id,
    amount: payout.amount,
    failure_message: payout.failure_message,
    failure_code: payout.failure_code,
  });

  // Payout to barber failed
  // Could refund barber's wallet balance
  // Send notification to barber and admin
}

