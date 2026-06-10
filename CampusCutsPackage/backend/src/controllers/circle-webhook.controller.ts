/**
 * Circle Webhook Controller
 * 
 * Handles webhook events from Circle API for real-time updates on:
 * - Wallet creation
 * - Transaction status changes
 * - Transfer completions
 * 
 * Circle Webhook Documentation: https://developers.circle.com/w3s/docs/webhooks
 */

import { Request, Response } from 'express';
import { logger } from '../utils/logger';
import { pool } from '../database/connection';

/**
 * Circle Webhook Event Types
 */
type CircleWebhookEvent = 
  | 'wallets.wallet.created'
  | 'transactions.transaction.created'
  | 'transactions.transaction.confirmed'
  | 'transactions.transaction.failed'
  | 'transactions.transfer.created'
  | 'transactions.transfer.sent'
  | 'transactions.transfer.confirmed'
  | 'transactions.transfer.complete'
  | 'transactions.transfer.failed';

interface CircleWebhookPayload {
  id: string;
  type: CircleWebhookEvent;
  data: any;
  timestamp: string;
  subscriptionId: string;
}

/**
 * Handle Circle webhook events
 * 
 * POST /api/v1/circle/webhook
 * 
 * @param req - Express request with raw body
 * @param res - Express response
 */
export const handleCircleWebhook = async (req: Request, res: Response) => {
  try {
    const event: CircleWebhookPayload = req.body;

    logger.info('Circle webhook received', {
      type: event.type,
      id: event.id,
      timestamp: event.timestamp,
    });

    // Route to appropriate handler
    switch (event.type) {
      case 'wallets.wallet.created':
        await handleWalletCreated(event);
        break;

      case 'transactions.transaction.created':
      case 'transactions.transfer.created':
        await handleTransferCreated(event);
        break;

      case 'transactions.transaction.confirmed':
      case 'transactions.transfer.confirmed':
        await handleTransferConfirmed(event);
        break;

      case 'transactions.transfer.complete':
        await handleTransferCompleted(event);
        break;

      case 'transactions.transaction.failed':
      case 'transactions.transfer.failed':
        await handleTransferFailed(event);
        break;

      default:
        logger.warn(`Unhandled Circle webhook event: ${event.type}`);
    }

    // Always respond with 200 to acknowledge receipt
    res.json({ received: true });
  } catch (error: any) {
    logger.error('Circle webhook processing error:', {
      error: error.message,
      stack: error.stack,
    });

    // Still return 200 to prevent Circle from retrying
    // Log error for manual review
    res.json({ received: true, error: 'Processing failed' });
  }
};

/**
 * Handle wallet created event
 */
async function handleWalletCreated(event: CircleWebhookPayload): Promise<void> {
  try {
    const wallet = event.data.wallet;

    logger.info('✅ Wallet created webhook', {
      wallet_id: wallet.id,
      address: wallet.address,
      blockchain: wallet.blockchain,
      state: wallet.state,
    });

    // Update user record if wallet was created via registration
    // The wallet should already be in database from ensureUserWallet()
    // This webhook just confirms creation on Circle's side

  } catch (error: any) {
    logger.error('Error handling wallet created webhook:', error);
    throw error;
  }
}

/**
 * Handle transfer created event
 */
async function handleTransferCreated(event: CircleWebhookPayload): Promise<void> {
  try {
    const transfer = event.data.transaction || event.data.transfer;

    logger.info('💰 Transfer created webhook', {
      transfer_id: transfer.id,
      amount: transfer.amounts?.[0] || transfer.amount,
      status: transfer.state || transfer.status,
    });

    // Update transaction status in database
    await updateTransactionStatus(transfer.id, 'INITIATED');

  } catch (error: any) {
    logger.error('Error handling transfer created webhook:', error);
    throw error;
  }
}

/**
 * Handle transfer confirmed event
 */
async function handleTransferConfirmed(event: CircleWebhookPayload): Promise<void> {
  try {
    const transfer = event.data.transaction || event.data.transfer;

    logger.info('✅ Transfer confirmed webhook', {
      transfer_id: transfer.id,
      amount: transfer.amounts?.[0] || transfer.amount,
      status: transfer.state || transfer.status,
    });

    // Update transaction status
    await updateTransactionStatus(transfer.id, 'CONFIRMED');

  } catch (error: any) {
    logger.error('Error handling transfer confirmed webhook:', error);
    throw error;
  }
}

/**
 * Handle transfer completed event
 */
async function handleTransferCompleted(event: CircleWebhookPayload): Promise<void> {
  try {
    const transfer = event.data.transaction || event.data.transfer;

    logger.info('✅ Transfer completed webhook', {
      transfer_id: transfer.id,
      amount: transfer.amounts?.[0] || transfer.amount,
      final_status: transfer.state || transfer.status,
    });

    // Update transaction status to complete
    await updateTransactionStatus(transfer.id, 'COMPLETE');

    // Get transaction details to trigger post-completion actions
    const txResult = await pool.query(
      'SELECT * FROM circle_transactions WHERE transfer_id = $1',
      [transfer.id]
    );

    if (txResult.rows.length > 0) {
      const transaction = txResult.rows[0];

      // If this was a booking payment, update booking status
      if (transaction.booking_id) {
        await handleBookingPaymentCompleted(transaction.booking_id);
      }
    }

  } catch (error: any) {
    logger.error('Error handling transfer completed webhook:', error);
    throw error;
  }
}

/**
 * Handle transfer failed event
 */
async function handleTransferFailed(event: CircleWebhookPayload): Promise<void> {
  try {
    const transfer = event.data.transaction || event.data.transfer;

    logger.error('❌ Transfer failed webhook', {
      transfer_id: transfer.id,
      amount: transfer.amounts?.[0] || transfer.amount,
      error: transfer.errorReason || transfer.error,
    });

    // Update transaction status and save error message
    await pool.query(
      `UPDATE circle_transactions 
       SET status = $1, 
           error_message = $2,
           updated_at = NOW(),
           completed_at = NOW()
       WHERE transfer_id = $3`,
      ['FAILED', transfer.errorReason || 'Transfer failed', transfer.id]
    );

    // Get transaction details to handle failure
    const txResult = await pool.query(
      'SELECT * FROM circle_transactions WHERE transfer_id = $1',
      [transfer.id]
    );

    if (txResult.rows.length > 0) {
      const transaction = txResult.rows[0];

      // If this was a booking payment, mark booking as payment failed
      if (transaction.booking_id) {
        await handleBookingPaymentFailed(transaction.booking_id, transfer.errorReason);
      }
    }

  } catch (error: any) {
    logger.error('Error handling transfer failed webhook:', error);
    throw error;
  }
}

/**
 * Update transaction status in database
 */
async function updateTransactionStatus(transferId: string, status: string): Promise<void> {
  try {
    const completedAt = (status === 'COMPLETE' || status === 'FAILED') ? 'NOW()' : 'NULL';

    await pool.query(
      `UPDATE circle_transactions 
       SET status = $1, 
           updated_at = NOW(),
           completed_at = ${completedAt}
       WHERE transfer_id = $2`,
      [status, transferId]
    );

    logger.info(`Updated transaction ${transferId} status to ${status}`);
  } catch (error: any) {
    logger.error(`Failed to update transaction status:`, {
      transfer_id: transferId,
      status,
      error: error.message,
    });
    throw error;
  }
}

/**
 * Handle booking payment completed
 */
async function handleBookingPaymentCompleted(bookingId: number): Promise<void> {
  try {
    // Update booking status to confirmed (payment received)
    await pool.query(
      `UPDATE bookings 
       SET payment_status = 'confirmed',
           status = 'confirmed',
           updated_at = NOW()
       WHERE id = $1`,
      [bookingId]
    );

    logger.info(`✅ Booking ${bookingId} payment confirmed`);

    // TODO: Trigger on-chain escrow creation
    // TODO: Send confirmation notifications to student and barber

  } catch (error: any) {
    logger.error(`Failed to update booking payment status:`, {
      booking_id: bookingId,
      error: error.message,
    });
    throw error;
  }
}

/**
 * Handle booking payment failed
 */
async function handleBookingPaymentFailed(bookingId: number, errorReason?: string): Promise<void> {
  try {
    // Update booking status to payment failed
    await pool.query(
      `UPDATE bookings 
       SET payment_status = 'failed',
           status = 'cancelled',
           updated_at = NOW()
       WHERE id = $1`,
      [bookingId]
    );

    logger.error(`❌ Booking ${bookingId} payment failed: ${errorReason}`);

    // TODO: Send failure notification to student
    // TODO: Refund if payment was partially processed

  } catch (error: any) {
    logger.error(`Failed to update booking payment failure:`, {
      booking_id: bookingId,
      error: error.message,
    });
    throw error;
  }
}

