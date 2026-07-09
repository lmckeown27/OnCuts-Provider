/**
 * Stripe Payment Service
 * 
 * Handles customer payments for bookings with Stripe Connect
 * Platform takes 15%, barber receives 85%
 */

import Stripe from 'stripe';
import { getDefaultStripeClient } from '../config/stripe';
import { logger } from '../utils/logger';
import { pool } from '../database/connection';

function stripeClient(): Stripe {
  return getDefaultStripeClient();
}

const PLATFORM_FEE_PERCENTAGE = 0.15; // 15% platform fee (covers Stripe's ~4% processing fee, nets ~11%)

interface CreatePaymentIntentParams {
  amount: number; // Total amount in dollars (service + tip)
  serviceAmount?: number; // Service amount only in dollars (for fee calculation). If not provided, assumes amount has no tip.
  currency?: string;
  customerId?: string;
  barberId?: string; // User ID of the barber
  metadata?: Record<string, string>;
}

interface PaymentIntentResult {
  clientSecret: string;
  paymentIntentId: string;
  amount: number;
  platformFee: number;
  barberAmount: number;
}

class StripePaymentService {
  /**
   * Create or get customer
   */
  async createOrGetCustomer(email: string, userId: string, name?: string): Promise<string> {
    try {
      // Check if customer already exists
      const existingCustomers = await stripeClient().customers.list({
        email,
        limit: 1,
      });

      if (existingCustomers.data.length > 0) {
        return existingCustomers.data[0].id;
      }

      // Create new customer
      const customer = await stripeClient().customers.create({
        email,
        name,
        metadata: {
          userId,
        },
      });

      logger.info(`Created Stripe customer: ${customer.id} for user: ${userId}`);
      return customer.id;
    } catch (error: any) {
      logger.error('Error creating/getting Stripe customer:', error);
      throw new Error(`Failed to create customer: ${error.message}`);
    }
  }

  /**
   * Create payment intent for booking with Stripe Connect
   * Uses destination charges: payment goes to platform, then 85% transferred to barber
   */
  async createPaymentIntent(params: CreatePaymentIntentParams): Promise<PaymentIntentResult> {
    try {
      const { amount, serviceAmount, currency = 'usd', customerId, barberId, metadata = {} } = params;

      // Calculate fees
      // IMPORTANT: Platform fee is calculated ONLY on the service amount, NOT on tips
      // Barbers receive 100% of tips - tips should never have fees deducted
      const amountCents = Math.round(amount * 100); // Total amount in cents
      const serviceAmountCents = serviceAmount ? Math.round(serviceAmount * 100) : amountCents; // Service-only for fee calculation
      const platformFeeCents = Math.round(serviceAmountCents * PLATFORM_FEE_PERCENTAGE); // Fee on service only
      const barberAmountCents = amountCents - platformFeeCents; // Barber gets: service - fee + full tip

      // Get barber's Stripe Connect account ID
      let barberStripeAccountId: string | null = null;
      if (barberId) {
        const barberResult = await pool.query(
          'SELECT stripe_account_id FROM users WHERE id = $1',
          [barberId]
        );
        barberStripeAccountId = barberResult.rows[0]?.stripe_account_id;
      }

      // Build payment intent config
      const paymentIntentConfig: Stripe.PaymentIntentCreateParams = {
        amount: amountCents,
        currency,
        customer: customerId,
        metadata: {
          ...metadata,
          platformFee: platformFeeCents.toString(),
          barberAmount: barberAmountCents.toString(),
        },
        payment_method_types: ['card'], // Only card (includes Apple Pay, Google Pay) - excludes Klarna, Amazon Pay, Cash App
        excluded_payment_method_types: ['crypto'],
      };

      // If barber has a Stripe Connect account, use destination charges
      // This automatically splits the payment: 85% to barber, 15% to platform
      if (barberStripeAccountId) {
        paymentIntentConfig.application_fee_amount = platformFeeCents;
        paymentIntentConfig.transfer_data = {
          destination: barberStripeAccountId,
        };
        logger.info(`Payment will split: $${platformFeeCents / 100} to platform, $${barberAmountCents / 100} to barber (${barberStripeAccountId})`);
      } else {
        logger.warn(`Barber ${barberId} has no Stripe Connect account - payment goes to platform only. Manual payout required.`);
      }

      // Create payment intent
      const paymentIntent = await stripeClient().paymentIntents.create(paymentIntentConfig);

      logger.info(`Created payment intent: ${paymentIntent.id} for $${amount}${barberStripeAccountId ? ' (with Connect split)' : ' (no Connect - manual payout needed)'}`);

      return {
        clientSecret: paymentIntent.client_secret!,
        paymentIntentId: paymentIntent.id,
        amount: amountCents / 100,
        platformFee: platformFeeCents / 100,
        barberAmount: barberAmountCents / 100,
      };
    } catch (error: any) {
      logger.error('Error creating payment intent:', error);
      throw new Error(`Failed to create payment intent: ${error.message}`);
    }
  }

  /**
   * Confirm payment was successful
   */
  async getPaymentIntent(paymentIntentId: string): Promise<Stripe.PaymentIntent> {
    try {
      return await stripeClient().paymentIntents.retrieve(paymentIntentId);
    } catch (error: any) {
      logger.error('Error retrieving payment intent:', error);
      throw new Error(`Failed to retrieve payment intent: ${error.message}`);
    }
  }

  /**
   * Cancel payment intent
   */
  async cancelPaymentIntent(paymentIntentId: string): Promise<void> {
    try {
      await stripeClient().paymentIntents.cancel(paymentIntentId);
      logger.info(`Cancelled payment intent: ${paymentIntentId}`);
    } catch (error: any) {
      logger.error('Error cancelling payment intent:', error);
      throw new Error(`Failed to cancel payment intent: ${error.message}`);
    }
  }

  /**
   * Create refund
   */
  async createRefund(paymentIntentId: string, amount?: number): Promise<Stripe.Refund> {
    try {
      const refund = await stripeClient().refunds.create({
        payment_intent: paymentIntentId,
        amount: amount ? Math.round(amount * 100) : undefined, // Partial or full refund
      });

      logger.info(`Created refund: ${refund.id} for payment intent: ${paymentIntentId}`);
      return refund;
    } catch (error: any) {
      logger.error('Error creating refund:', error);
      throw new Error(`Failed to create refund: ${error.message}`);
    }
  }

  /**
   * Get customer payment methods
   */
  async getCustomerPaymentMethods(customerId: string): Promise<Stripe.PaymentMethod[]> {
    try {
      const paymentMethods = await stripeClient().paymentMethods.list({
        customer: customerId,
        type: 'card',
      });

      return paymentMethods.data;
    } catch (error: any) {
      logger.error('Error retrieving payment methods:', error);
      throw new Error(`Failed to retrieve payment methods: ${error.message}`);
    }
  }

  /**
   * Attach payment method to customer
   */
  async attachPaymentMethod(paymentMethodId: string, customerId: string): Promise<void> {
    try {
      await stripeClient().paymentMethods.attach(paymentMethodId, {
        customer: customerId,
      });

      // Set as default
      await stripeClient().customers.update(customerId, {
        invoice_settings: {
          default_payment_method: paymentMethodId,
        },
      });

      logger.info(`Attached payment method: ${paymentMethodId} to customer: ${customerId}`);
    } catch (error: any) {
      logger.error('Error attaching payment method:', error);
      throw new Error(`Failed to attach payment method: ${error.message}`);
    }
  }

  /**
   * Detach payment method from customer
   */
  async detachPaymentMethod(paymentMethodId: string): Promise<void> {
    try {
      await stripeClient().paymentMethods.detach(paymentMethodId);
      logger.info(`Detached payment method: ${paymentMethodId}`);
    } catch (error: any) {
      logger.error('Error detaching payment method:', error);
      throw new Error(`Failed to detach payment method: ${error.message}`);
    }
  }
}

export const stripePaymentService = new StripePaymentService();
export default stripePaymentService;

