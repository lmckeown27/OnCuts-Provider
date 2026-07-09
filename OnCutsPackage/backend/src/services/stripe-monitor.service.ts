/**
 * Stripe Payment Monitor Service
 * 
 * Captures and broadcasts real-time Stripe payment events
 * Stores payment events for audit trail
 * Broadcasts to admin dashboard via WebSocket
 */

import { logger } from '../utils/logger';
// import { pool } from '../database/connection'; // DEPRECATED - using blockchain
import { io } from '../index'; // Socket.IO instance
import Stripe from 'stripe';

// NOTE: This service is being refactored for blockchain-first architecture
// For now, events are broadcasted but not stored in PostgreSQL

interface ParsedStripeEvent {
  event_id: string;
  event_type: string;
  payment_intent_id?: string;
  customer_id?: string;
  amount_cents?: number;
  amount_usd?: number;
  status: string;
  timestamp: Date;
  description: string;
  metadata: any;
  student_email?: string;
  barber_email?: string;
  booking_id?: string;
}

class StripeMonitorService {
  /**
   * Process and broadcast a Stripe webhook event
   */
  async processEvent(event: Stripe.Event) {
    try {
      const parsed = await this.parseEvent(event);

      if (!parsed) {
        return; // Not a relevant event
      }

      // Store in database
      await this.storeEvent(parsed, event);

      // Broadcast to admin dashboard
      this.broadcastEvent(parsed);

      logger.info(`✅ Processed Stripe event: ${event.type} (${event.id})`);
    } catch (error) {
      logger.error(`Failed to process Stripe event ${event.id}:`, error);
    }
  }

  /**
   * Parse Stripe event to extract relevant data
   */
  private async parseEvent(event: Stripe.Event): Promise<ParsedStripeEvent | null> {
    const parsed: ParsedStripeEvent = {
      event_id: event.id,
      event_type: event.type,
      status: 'unknown',
      timestamp: new Date(event.created * 1000),
      description: '',
      metadata: {},
    };

    switch (event.type) {
      // Payment Intent Created
      case 'payment_intent.created': {
        const pi = event.data.object as Stripe.PaymentIntent;
        parsed.payment_intent_id = pi.id;
        parsed.customer_id = pi.customer as string;
        parsed.amount_cents = pi.amount;
        parsed.amount_usd = pi.amount / 100;
        parsed.status = pi.status;
        parsed.description = `Payment created: $${(pi.amount / 100).toFixed(2)}`;
        parsed.metadata = pi.metadata;
        parsed.booking_id = pi.metadata.bookingId;
        
        // Fetch student and barber emails from metadata
        if (pi.metadata.studentEmail) parsed.student_email = pi.metadata.studentEmail;
        if (pi.metadata.barberEmail) parsed.barber_email = pi.metadata.barberEmail;
        break;
      }

      // Payment Succeeded
      case 'payment_intent.succeeded': {
        const pi = event.data.object as Stripe.PaymentIntent;
        parsed.payment_intent_id = pi.id;
        parsed.customer_id = pi.customer as string;
        parsed.amount_cents = pi.amount;
        parsed.amount_usd = pi.amount / 100;
        parsed.status = 'succeeded';
        parsed.description = `Payment succeeded: $${(pi.amount / 100).toFixed(2)}`;
        parsed.metadata = pi.metadata;
        parsed.booking_id = pi.metadata.bookingId;
        
        if (pi.metadata.studentEmail) parsed.student_email = pi.metadata.studentEmail;
        if (pi.metadata.barberEmail) parsed.barber_email = pi.metadata.barberEmail;
        break;
      }

      // Payment Failed
      case 'payment_intent.payment_failed': {
        const pi = event.data.object as Stripe.PaymentIntent;
        parsed.payment_intent_id = pi.id;
        parsed.customer_id = pi.customer as string;
        parsed.amount_cents = pi.amount;
        parsed.amount_usd = pi.amount / 100;
        parsed.status = 'failed';
        parsed.description = `Payment failed: $${(pi.amount / 100).toFixed(2)}`;
        parsed.metadata = pi.metadata;
        parsed.booking_id = pi.metadata.bookingId;
        break;
      }

      // Charge Refunded
      case 'charge.refunded': {
        const charge = event.data.object as Stripe.Charge;
        parsed.payment_intent_id = charge.payment_intent as string;
        parsed.customer_id = charge.customer as string;
        parsed.amount_cents = charge.amount_refunded;
        parsed.amount_usd = charge.amount_refunded / 100;
        parsed.status = 'refunded';
        parsed.description = `Refund issued: $${(charge.amount_refunded / 100).toFixed(2)}`;
        parsed.metadata = charge.metadata;
        break;
      }

      // Transfer to Barber (Connect)
      case 'transfer.created': {
        const transfer = event.data.object as Stripe.Transfer;
        parsed.amount_cents = transfer.amount;
        parsed.amount_usd = transfer.amount / 100;
        parsed.status = 'created';
        parsed.description = `Transfer to barber: $${(transfer.amount / 100).toFixed(2)}`;
        parsed.metadata = transfer.metadata;
        parsed.booking_id = transfer.metadata.bookingId;
        parsed.barber_email = transfer.metadata.barberEmail;
        break;
      }

      // Transfer Paid (Note: 'transfer.paid' is not a valid Stripe event type)
      // Use 'transfer.created' instead for transfer events
      // case 'transfer.paid': {
      //   const transfer = event.data.object as Stripe.Transfer;
      //   parsed.amount_cents = transfer.amount;
      //   parsed.amount_usd = transfer.amount / 100;
      //   parsed.status = 'paid';
      //   parsed.description = `Transfer paid to barber: $${(transfer.amount / 100).toFixed(2)}`;
      //   parsed.metadata = transfer.metadata;
      //   parsed.booking_id = transfer.metadata.bookingId;
      //   parsed.barber_email = transfer.metadata.barberEmail;
      //   break;
      // }

      // Payout Created
      case 'payout.created': {
        const payout = event.data.object as Stripe.Payout;
        parsed.amount_cents = payout.amount;
        parsed.amount_usd = payout.amount / 100;
        parsed.status = payout.status;
        parsed.description = `Payout created: $${(payout.amount / 100).toFixed(2)}`;
        parsed.metadata = payout.metadata || {};
        break;
      }

      // Payout Paid
      case 'payout.paid': {
        const payout = event.data.object as Stripe.Payout;
        parsed.amount_cents = payout.amount;
        parsed.amount_usd = payout.amount / 100;
        parsed.status = 'paid';
        parsed.description = `Payout completed: $${(payout.amount / 100).toFixed(2)}`;
        parsed.metadata = payout.metadata || {};
        break;
      }

      // Payout Failed
      case 'payout.failed': {
        const payout = event.data.object as Stripe.Payout;
        parsed.amount_cents = payout.amount;
        parsed.amount_usd = payout.amount / 100;
        parsed.status = 'failed';
        parsed.description = `Payout failed: $${(payout.amount / 100).toFixed(2)}`;
        parsed.metadata = payout.metadata || {};
        break;
      }

      default:
        // Not a relevant event
        return null;
    }

    return parsed;
  }

  /**
   * Store Stripe event (REFACTORED for blockchain-first)
   * Events are now logged and broadcasted only - not stored in PostgreSQL
   * TODO: Consider storing event hashes on-chain for audit trail
   */
  private async storeEvent(parsed: ParsedStripeEvent, raw: Stripe.Event) {
    try {
      // Log event for audit trail
      logger.info('💳 Stripe event received:', {
        event_id: parsed.event_id,
        event_type: parsed.event_type,
        amount_usd: parsed.amount_usd,
        status: parsed.status,
      });
      
      // Events are broadcasted via WebSocket - no PostgreSQL storage needed
      // In blockchain-first architecture, critical payment data is on-chain
    } catch (error) {
      logger.error('Failed to process Stripe event:', error);
    }
  }

  /**
   * Broadcast event to admin dashboard via WebSocket
   */
  private broadcastEvent(parsed: ParsedStripeEvent) {
    try {
      io.to('admin-live-feed').emit('stripe-payment', {
        ...parsed,
        platform: 'stripe',
      });

      logger.debug(`📡 Broadcasted Stripe event to admin dashboard`);
    } catch (error) {
      logger.error('Failed to broadcast Stripe event:', error);
    }
  }

  /**
   * Get recent Stripe events (REFACTORED for blockchain-first)
   * Events are now retrieved from blockchain/IPFS, not PostgreSQL
   */
  async getRecentEvents(limit: number = 50) {
    try {
      // TODO: Query blockchain for on-chain payment events
      // For now, return empty array since events are not stored in PostgreSQL
      logger.info('Recent Stripe events requested - returning empty (blockchain-first)');
      return [];
    } catch (error) {
      logger.error('Failed to fetch recent Stripe events:', error);
      return [];
    }
  }

  /**
   * Get payment statistics (REFACTORED for blockchain-first)
   * Stats are now calculated from blockchain data
   */
  async getPaymentStats() {
    try {
      // TODO: Query blockchain for payment statistics
      // For now, return zero stats since we're not using PostgreSQL
      logger.info('Payment stats requested - returning zeros (blockchain-first)');
      return {
        successful_payments: 0,
        failed_payments: 0,
        refunds: 0,
        total_revenue: 0,
        total_refunded: 0,
      };
    } catch (error) {
      logger.error('Failed to fetch payment stats:', error);
      return null;
    }
  }
}

// Singleton instance
const stripeMonitorService = new StripeMonitorService();

export default stripeMonitorService;

