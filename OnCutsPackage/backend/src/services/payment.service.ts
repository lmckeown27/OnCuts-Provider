/**
 * Payment Service - Unified Payment Interface
 * 
 * Supports both off-chain (Stripe) and on-chain (Circle + Blockchain) payments
 * Current mode: OFF-CHAIN (Stripe only)
 * 
 * Architecture allows seamless migration to on-chain when needed.
 */

import Stripe from 'stripe';
import { getDefaultStripeClient } from '../config/stripe';
import { logger } from '../utils/logger';
import { pool } from '../database/connection';

// ==========================================
// Types & Interfaces
// ==========================================

export interface Escrow {
  id: string;
  bookingId: number;
  amount: number;
  status: 'pending' | 'held' | 'released' | 'refunded' | 'failed';
  type: 'offchain' | 'onchain';
  
  // Off-chain fields (Stripe)
  stripePaymentIntentId?: string;
  stripeTransferId?: string;
  
  // On-chain fields (future)
  blockchainTxHash?: string;
  blockchainEscrowId?: string;
  usdcAmount?: number;
  
  createdAt: Date;
  updatedAt: Date;
}

export interface PaymentResult {
  success: boolean;
  escrow?: Escrow;
  error?: string;
  clientSecret?: string; // For Stripe payment confirmation
}

export interface ReleaseResult {
  success: boolean;
  transferId?: string;
  error?: string;
}

// ==========================================
// Payment Service Class
// ==========================================

class PaymentService {
  private paymentMode: 'offchain' | 'onchain';

  private getStripe(): Stripe {
    return getDefaultStripeClient();
  }

  constructor() {
    // Determine payment mode
    this.paymentMode = (process.env.PAYMENT_MODE as 'offchain' | 'onchain') || 'offchain';
    
    logger.info(`Payment Service initialized in ${this.paymentMode.toUpperCase()} mode`);
  }
  
  // ==========================================
  // Public API - Works for Both Modes
  // ==========================================
  
  /**
   * Create payment escrow
   * Off-chain: Creates Stripe PaymentIntent with manual capture
   * On-chain: Converts to USDC and creates blockchain escrow
   */
  async createEscrow(
    bookingId: number,
    amount: number,
    studentId: number,
    barberId: number,
    metadata?: Record<string, string>
  ): Promise<PaymentResult> {
    try {
      logger.info(`Creating ${this.paymentMode} escrow for booking ${bookingId}`);
      
      if (this.paymentMode === 'offchain') {
        return await this.createOffChainEscrow(bookingId, amount, studentId, barberId, metadata);
      } else {
        return await this.createOnChainEscrow(bookingId, amount, studentId, barberId, metadata);
      }
    } catch (error: any) {
      logger.error('Failed to create escrow:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  /**
   * Release escrow to barber
   * Off-chain: Captures Stripe payment and transfers to barber
   * On-chain: Releases blockchain escrow
   */
  async releaseEscrow(escrowId: string): Promise<ReleaseResult> {
    try {
      const escrow = await this.getEscrow(escrowId);
      
      if (!escrow) {
        throw new Error('Escrow not found');
      }
      
      if (escrow.status !== 'held') {
        throw new Error(`Cannot release escrow in status: ${escrow.status}`);
      }
      
      logger.info(`Releasing ${escrow.type} escrow ${escrowId}`);
      
      if (escrow.type === 'offchain') {
        return await this.releaseOffChainEscrow(escrow);
      } else {
        return await this.releaseOnChainEscrow(escrow);
      }
    } catch (error: any) {
      logger.error('Failed to release escrow:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  /**
   * Refund escrow to student
   */
  async refundEscrow(escrowId: string, reason?: string): Promise<ReleaseResult> {
    try {
      const escrow = await this.getEscrow(escrowId);
      
      if (!escrow) {
        throw new Error('Escrow not found');
      }
      
      if (escrow.status !== 'held') {
        throw new Error(`Cannot refund escrow in status: ${escrow.status}`);
      }
      
      logger.info(`Refunding ${escrow.type} escrow ${escrowId}`);
      
      if (escrow.type === 'offchain') {
        return await this.refundOffChainEscrow(escrow, reason);
      } else {
        return await this.refundOnChainEscrow(escrow, reason);
      }
    } catch (error: any) {
      logger.error('Failed to refund escrow:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  /**
   * Get escrow status
   */
  async getEscrow(escrowId: string): Promise<Escrow | null> {
    const result = await pool.query(
      'SELECT * FROM escrows WHERE id = $1',
      [escrowId]
    );
    
    if (result.rows.length === 0) {
      return null;
    }
    
    return this.mapDbRowToEscrow(result.rows[0]);
  }
  
  /**
   * Get all escrows for a booking
   */
  async getEscrowsForBooking(bookingId: number): Promise<Escrow[]> {
    const result = await pool.query(
      'SELECT * FROM escrows WHERE booking_id = $1 ORDER BY created_at DESC',
      [bookingId]
    );
    
    return result.rows.map(row => this.mapDbRowToEscrow(row));
  }
  
  // ==========================================
  // Off-Chain Implementation (Stripe)
  // ==========================================
  
  private async createOffChainEscrow(
    bookingId: number,
    amount: number,
    studentId: number,
    barberId: number,
    metadata?: Record<string, string>
  ): Promise<PaymentResult> {
    // Create Stripe PaymentIntent with manual capture
    // This holds the funds but doesn't charge until we capture
    const paymentIntent = await this.getStripe().paymentIntents.create({
      amount: Math.round(amount * 100), // Stripe uses cents
      currency: 'usd',
      capture_method: 'manual', // Hold funds, don't charge yet
      metadata: {
        bookingId: bookingId.toString(),
        studentId: studentId.toString(),
        barberId: barberId.toString(),
        ...metadata
      },
      description: `CampusCuts Booking #${bookingId}`,
    });
    
    // Store escrow in database
    const result = await pool.query(
      `INSERT INTO escrows (
        booking_id, amount, status, type,
        stripe_payment_intent_id,
        created_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
      RETURNING *`,
      [bookingId, amount, 'pending', 'offchain', paymentIntent.id]
    );
    
    const escrow = this.mapDbRowToEscrow(result.rows[0]);
    
    logger.info(`Created off-chain escrow ${escrow.id} for booking ${bookingId}`);
    
    return {
      success: true,
      escrow,
      clientSecret: paymentIntent.client_secret || undefined
    };
  }
  
  private async releaseOffChainEscrow(escrow: Escrow): Promise<ReleaseResult> {
    if (!escrow.stripePaymentIntentId) {
      throw new Error('Missing Stripe PaymentIntent ID');
    }
    
    // 1. Capture the payment (charge the student)
    const paymentIntent = await this.getStripe().paymentIntents.capture(
      escrow.stripePaymentIntentId
    );
    
    logger.info(`Captured payment ${escrow.stripePaymentIntentId}`);
    
    // 2. Calculate platform fee
    const platformFeePercent = parseFloat(process.env.STRIPE_PLATFORM_FEE_PERCENT || '5.0');
    const platformFee = Math.round(escrow.amount * (platformFeePercent / 100) * 100);
    const barberAmount = (escrow.amount * 100) - platformFee;
    
    // 3. Get barber's Stripe Connect account ID
    const barberResult = await pool.query(
      `SELECT u.stripe_account_id, b.user_id
       FROM bookings b
       JOIN users u ON u.id = b.barber_id
       WHERE b.id = $1`,
      [escrow.bookingId]
    );
    
    if (barberResult.rows.length === 0) {
      throw new Error('Barber not found for booking');
    }
    
    const stripeAccountId = barberResult.rows[0].stripe_account_id;
    
    if (!stripeAccountId) {
      throw new Error('Barber has not connected Stripe account');
    }
    
    // 4. Transfer to barber via Stripe Connect
    const transfer = await this.getStripe().transfers.create({
      amount: barberAmount,
      currency: 'usd',
      destination: stripeAccountId,
      metadata: {
        bookingId: escrow.bookingId.toString(),
        escrowId: escrow.id
      },
      description: `Payout for Booking #${escrow.bookingId}`
    });
    
    // 5. Update escrow status
    await pool.query(
      `UPDATE escrows 
       SET status = $1, stripe_transfer_id = $2, updated_at = NOW()
       WHERE id = $3`,
      ['released', transfer.id, escrow.id]
    );
    
    // 6. Update booking status
    await pool.query(
      `UPDATE bookings 
       SET payment_status = $1, updated_at = NOW()
       WHERE id = $2`,
      ['completed', escrow.bookingId]
    );
    
    logger.info(`Released escrow ${escrow.id}, transferred ${barberAmount / 100} to barber`);
    
    return {
      success: true,
      transferId: transfer.id
    };
  }
  
  private async refundOffChainEscrow(escrow: Escrow, reason?: string): Promise<ReleaseResult> {
    if (!escrow.stripePaymentIntentId) {
      throw new Error('Missing Stripe PaymentIntent ID');
    }
    
    // Cancel the payment intent (refund to student)
    const paymentIntent = await this.getStripe().paymentIntents.cancel(
      escrow.stripePaymentIntentId
    );
    
    // Update escrow status
    await pool.query(
      `UPDATE escrows 
       SET status = $1, updated_at = NOW()
       WHERE id = $2`,
      ['refunded', escrow.id]
    );
    
    // Update booking status
    await pool.query(
      `UPDATE bookings 
       SET payment_status = $1, updated_at = NOW()
       WHERE id = $2`,
      ['refunded', escrow.bookingId]
    );
    
    logger.info(`Refunded escrow ${escrow.id}. Reason: ${reason || 'Not provided'}`);
    
    return {
      success: true,
      transferId: paymentIntent.id
    };
  }
  
  // ==========================================
  // On-Chain Implementation (Future)
  // ==========================================
  
  private async createOnChainEscrow(
    bookingId: number,
    amount: number,
    studentId: number,
    barberId: number,
    metadata?: Record<string, string>
  ): Promise<PaymentResult> {
    // TODO: Implement when Circle + Blockchain are ready
    // 1. Charge via Stripe
    // 2. Convert USD to USDC via Circle
    // 3. On-chain escrow via Sui when enabled
    // 4. Store in database
    
    throw new Error('On-chain escrow not yet implemented. Set PAYMENT_MODE=offchain');
  }
  
  private async releaseOnChainEscrow(escrow: Escrow): Promise<ReleaseResult> {
    // TODO: Implement when Circle + Blockchain are ready
    // 1. Release blockchain escrow
    // 2. Convert USDC to USD via Circle
    // 3. Transfer to barber
    
    throw new Error('On-chain release not yet implemented. Set PAYMENT_MODE=offchain');
  }
  
  private async refundOnChainEscrow(escrow: Escrow, reason?: string): Promise<ReleaseResult> {
    // TODO: Implement when Circle + Blockchain are ready
    
    throw new Error('On-chain refund not yet implemented. Set PAYMENT_MODE=offchain');
  }
  
  // ==========================================
  // Backward Compatibility Methods
  // ==========================================
  
  /**
   * Process booking payment (legacy method)
   * Wrapper for createEscrow
   */
  async processBookingPayment(params: {
    bookingId: number;
    amount?: number;
    studentId?: number;
    barberId: number | string;
    customerId?: number | string;
    totalAmountCents?: number;
    stripePaymentIntentId?: string;
    metadata?: Record<string, string>;
  }): Promise<PaymentResult> {
    // Convert cents to dollars if totalAmountCents is provided
    const amount = params.amount || (params.totalAmountCents ? params.totalAmountCents / 100 : 0);
    
    // Convert IDs to numbers
    const studentId = params.studentId || 
      (typeof params.customerId === 'string' ? parseInt(params.customerId) : params.customerId) || 0;
    const barberId = typeof params.barberId === 'string' ? parseInt(params.barberId) : params.barberId;
    
    return this.createEscrow(
      params.bookingId,
      amount,
      studentId,
      barberId,
      params.metadata
    );
  }
  
  /**
   * Release booking funds (legacy method)
   * Wrapper for releaseEscrow
   */
  async releaseBookingFunds(params: {
    bookingId: number;
    barberId?: number | string;
    barberAddress?: string;
    amountCents?: number;
  }): Promise<ReleaseResult> {
    const escrows = await this.getEscrowsForBooking(params.bookingId);
    const activeEscrow = escrows.find(e => e.status === 'held');
    
    if (!activeEscrow) {
      return {
        success: false,
        error: 'No active escrow found for booking'
      };
    }
    
    return this.releaseEscrow(activeEscrow.id);
  }
  
  /**
   * Refund booking payment (legacy method)
   * Wrapper for refundEscrow
   */
  async refundBookingPayment(params: {
    bookingId: number;
    customerId?: number | string;
    barberId?: number | string;
    totalAmountCents?: number;
    reason?: string;
  }): Promise<ReleaseResult> {
    const escrows = await this.getEscrowsForBooking(params.bookingId);
    const activeEscrow = escrows.find(e => e.status === 'held');
    
    if (!activeEscrow) {
      return {
        success: false,
        error: 'No active escrow found for booking'
      };
    }
    
    return this.refundEscrow(activeEscrow.id, params.reason);
  }
  
  /**
   * Create deposit intent (legacy method)
   * For wallet deposits - simplified implementation
   */
  async createDepositIntent(params: {
    userId: number | string;
    amount?: number;
    amountCents?: number;
    metadata?: Record<string, string>;
  }): Promise<PaymentResult> {
    try {
      // Convert userId to number if string
      const userId = typeof params.userId === 'string' ? parseInt(params.userId) : params.userId;
      
      // Use amountCents if provided, otherwise convert amount to cents
      const amountCents = params.amountCents || (params.amount ? Math.round(params.amount * 100) : 0);
      
      // Create a simple payment intent for wallet deposit
      const paymentIntent = await this.getStripe().paymentIntents.create({
        amount: amountCents,
        currency: 'usd',
        metadata: {
          userId: userId.toString(),
          type: 'wallet_deposit',
          ...params.metadata
        },
        description: `Wallet deposit for user ${userId}`
      });
      
      return {
        success: true,
        clientSecret: paymentIntent.client_secret || undefined
      };
    } catch (error: any) {
      logger.error('Failed to create deposit intent:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  /**
   * Process tip (legacy method)
   * Creates a direct charge for tips
   */
  async processTip(params: {
    studentId?: number;
    barberId?: number;
    fromUserId?: number | string;
    toUserId?: number | string;
    amount?: number;
    amountCents?: number;
    bookingId?: number | string;
  }): Promise<PaymentResult> {
    try {
      // Map fromUserId/toUserId to studentId/barberId and convert to numbers
      const fromUserId = typeof params.fromUserId === 'string' ? parseInt(params.fromUserId) : params.fromUserId;
      const toUserId = typeof params.toUserId === 'string' ? parseInt(params.toUserId) : params.toUserId;
      const bookingId = typeof params.bookingId === 'string' ? parseInt(params.bookingId) : params.bookingId;
      
      const studentId = params.studentId || fromUserId;
      const barberId = params.barberId || toUserId;
      const amountCents = params.amountCents || (params.amount ? Math.round(params.amount * 100) : 0);
      
      if (!barberId) {
        throw new Error('Barber ID is required');
      }
      
      // Get barber's Stripe account
      const barberResult = await pool.query(
        'SELECT stripe_account_id FROM users WHERE id = $1',
        [barberId]
      );
      
      if (barberResult.rows.length === 0 || !barberResult.rows[0].stripe_account_id) {
        throw new Error('Barber Stripe account not found');
      }
      
      // Create direct charge with transfer to barber
      const paymentIntent = await this.getStripe().paymentIntents.create({
        amount: amountCents,
        currency: 'usd',
        metadata: {
          type: 'tip',
          studentId: studentId?.toString() || '',
          barberId: barberId.toString(),
          bookingId: bookingId?.toString() || ''
        },
        description: `Tip for barber`,
        transfer_data: {
          destination: barberResult.rows[0].stripe_account_id
        }
      });
      
      logger.info(`Processed tip of $${amountCents / 100} from user ${studentId} to barber ${barberId}`);
      
      return {
        success: true,
        clientSecret: paymentIntent.client_secret || undefined
      };
    } catch (error: any) {
      logger.error('Failed to process tip:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  /**
   * Issue promotional credit (legacy method)
   * Simplified implementation - logs the credit
   */
  async issuePromotionalCredit(params: {
    userId: number | string;
    amount?: number;
    amountCents?: number;
    reason?: string;
    description?: string;
    adminId?: number | string;
  }): Promise<PaymentResult> {
    try {
      const userId = typeof params.userId === 'string' ? parseInt(params.userId) : params.userId;
      const adminId = typeof params.adminId === 'string' ? parseInt(params.adminId) : params.adminId;
      const amountCents = params.amountCents || (params.amount ? Math.round(params.amount * 100) : 0);
      const reason = params.reason || params.description || 'No reason provided';
      
      // In a full implementation, you'd update a user's credit balance
      // For now, just log it
      logger.info(`Issued promotional credit: $${amountCents / 100} to user ${userId}. Reason: ${reason}. Admin ID: ${adminId || 'system'}`);
      
      // TODO: Implement actual credit system in database
      // await pool.query(
      //   'UPDATE users SET promotional_credits = promotional_credits + $1 WHERE id = $2',
      //   [amountCents, userId]
      // );
      
      return {
        success: true
      };
    } catch (error: any) {
      logger.error('Failed to issue promotional credit:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  // ==========================================
  // Utilities
  // ==========================================
  
  private mapDbRowToEscrow(row: any): Escrow {
    return {
      id: row.id.toString(),
      bookingId: row.booking_id,
      amount: parseFloat(row.amount),
      status: row.status,
      type: row.type,
      stripePaymentIntentId: row.stripe_payment_intent_id,
      stripeTransferId: row.stripe_transfer_id,
      blockchainTxHash: row.blockchain_tx_hash,
      blockchainEscrowId: row.blockchain_escrow_id,
      usdcAmount: row.usdc_amount ? parseFloat(row.usdc_amount) : undefined,
      createdAt: row.created_at,
      updatedAt: row.updated_at
    };
  }
}

// Export singleton instance
export const paymentService = new PaymentService();
export default paymentService;
