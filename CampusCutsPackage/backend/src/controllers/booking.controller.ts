/**
 * DEPRECATED: Legacy Booking Controller
 * 
 * This controller contains legacy custodial-chain booking stubs.
 * Platform now uses Stripe for off-chain payments only.
 * 
 * Use booking-v2.controller.ts for production booking flows.
 * This controller is kept for reference and backward compatibility.
 * 
 * To migrate: Update routes to use /api/v2/bookings endpoints
 */

import { Response, NextFunction } from 'express';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest } from '../middleware/auth';
import stripeService from '../services/stripe.service';
import paymentService from '../services/payment.service';
import ledgerService from '../services/ledger.service';
import { logger } from '../utils/logger';
import { dollarsToCents } from '../types/wallet.types';
import { USER_PRIMARY_WALLET_SQL, USER_PRIMARY_WALLET_SQL_U } from '../utils/user-wallet-address';

/** Legacy custodial-chain booking API; all methods throw — use v2 bookings + Stripe. */
const disabledLegacyChainBookingStub = {
  createBooking: async (_params: any): Promise<string> => {
    throw new Error('Legacy on-chain booking disabled — use Stripe / v2 bookings');
  },
  getBooking: async (_id: number): Promise<any> => {
    throw new Error('Legacy on-chain booking disabled');
  },
  confirmBooking: async (_address: string, _id: number): Promise<string> => {
    throw new Error('Legacy on-chain booking disabled');
  },
  completeBooking: async (_id: number): Promise<string> => {
    throw new Error('Legacy on-chain booking disabled');
  },
  cancelBooking: async (_id: number): Promise<string> => {
    throw new Error('Legacy on-chain booking disabled');
  },
};

export const createBooking = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { barberId, serviceType, scheduledTime, durationMinutes, locationDetails, specialRequests, tipAmount } = req.body;
    const clientId = req.user!.userId;

    // Get barber and client info
    const barberResult = await pool.query(
      `SELECT b.id, b.user_id, b.pricing, ${USER_PRIMARY_WALLET_SQL_U} as barber_address, u.campus_id
       FROM barbers b
       JOIN users u ON b.user_id = u.id
       WHERE b.id = $1 AND b.is_active = true`,
      [barberId]
    );

    if (barberResult.rows.length === 0) {
      throw new ApiError(404, 'Barber not found');
    }

    // Check if consumer is trying to book with themselves
    if (clientId === barberResult.rows[0].user_id) {
      throw new ApiError(400, 'You cannot book a service with yourself');
    }

    const barber = barberResult.rows[0];
    const pricing = barber.pricing as any;
    const priceDollars = pricing[serviceType];

    if (!priceDollars) {
      throw new ApiError(400, 'Service type not found in barber pricing');
    }

    // Convert to cents
    const priceCents = dollarsToCents(priceDollars);
    const tipCents = tipAmount ? dollarsToCents(tipAmount) : 0;
    const totalCents = priceCents + tipCents;

    // Check customer has sufficient balance
    const customerBalance = await ledgerService.getUserBalance(clientId);
    if (customerBalance.balance_available < totalCents) {
      throw new ApiError(400, 'Insufficient balance. Please add funds to your wallet.');
    }

    const clientResult = await pool.query(
      `SELECT ${USER_PRIMARY_WALLET_SQL} AS primary_wallet FROM users WHERE id = $1`,
      [clientId]
    );
    const clientAddress = clientResult.rows[0]?.primary_wallet;

    // Convert scheduled time to Unix timestamp
    const scheduledTimestamp = Math.floor(new Date(scheduledTime).getTime() / 1000);
    const locationHash = Buffer.from(locationDetails || '').toString('base64');

    const txHash = await disabledLegacyChainBookingStub.createBooking({
      clientAddress,
      barberAddress: barber.barber_address,
      serviceType,
      price: priceCents,
      scheduledTime: scheduledTimestamp,
      campusId: barber.campus_id,
      durationMinutes,
      locationHash,
    });

    // Get blockchain booking ID from transaction (simplified - would parse events)
    const blockchainBookingId = Date.now(); // Temporary: use timestamp as ID

    // Create booking metadata in database
    const metadataResult = await pool.query(
      `INSERT INTO booking_metadata 
       (blockchain_booking_id, barber_id, client_id, location_details, special_requests)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [blockchainBookingId, barberId, clientId, locationDetails, specialRequests]
    );

    const bookingId = metadataResult.rows[0].id;

    // Process payment through custodial wallet
    await paymentService.processBookingPayment({
      bookingId,
      customerId: clientId,
      barberId: barber.user_id,
      totalAmountCents: priceCents,
      stripePaymentIntentId: `booking_${bookingId}`,
    });

    logger.info(`Booking created with custodial wallet payment`, {
      booking_id: bookingId,
      customer_id: clientId,
      barber_id: barber.user_id,
      amount_cents: priceCents,
      tip_cents: tipCents,
      tx_hash: txHash,
    });

    res.status(201).json({
      success: true,
      data: {
        booking: metadataResult.rows[0],
        transactionHash: txHash,
        payment: {
          amount_dollars: priceDollars,
          tip_dollars: tipAmount || 0,
          total_dollars: (priceDollars + (tipAmount || 0)),
        },
      },
      message: 'Booking created successfully. Payment processed from your wallet.',
    });
  } catch (error) {
    next(error);
  }
};

export const getBookings = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { status, startDate, endDate } = req.query;
    const userId = req.user!.userId;
    const userRole = req.user!.role;

    let query: string;
    const params: any[] = [userId];

    if (userRole === 'barber') {
      query = `
        SELECT bm.*, 
          u.first_name as client_first_name, 
          u.last_name as client_last_name,
          u.email as client_email
        FROM booking_metadata bm
        JOIN barbers b ON bm.barber_id = b.id
        JOIN users u ON bm.client_id = u.id
        WHERE b.user_id = $1
      `;
    } else {
      query = `
        SELECT bm.*,
          u.first_name as barber_first_name,
          u.last_name as barber_last_name,
          b.profile_image_url as barber_image
        FROM booking_metadata bm
        JOIN barbers b ON bm.barber_id = b.id
        JOIN users u ON b.user_id = u.id
        WHERE bm.client_id = $1
      `;
    }

    query += ' ORDER BY bm.created_at DESC';

    const result = await pool.query(query, params);

    res.json({
      success: true,
      data: result.rows,
      count: result.rows.length,
    });
  } catch (error) {
    next(error);
  }
};

export const getBookingById = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const userId = req.user!.userId;

    // Get booking metadata
    const result = await pool.query(
      `SELECT bm.*,
        u1.first_name as barber_first_name, u1.last_name as barber_last_name,
        u2.first_name as client_first_name, u2.last_name as client_last_name
      FROM booking_metadata bm
      JOIN barbers b ON bm.barber_id = b.id
      JOIN users u1 ON b.user_id = u1.id
      JOIN users u2 ON bm.client_id = u2.id
      WHERE bm.blockchain_booking_id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'Booking not found');
    }

    const booking = result.rows[0];

    // Verify user is involved in booking
    if (booking.client_id !== userId && booking.barber_id !== userId) {
      throw new ApiError(403, 'Not authorized');
    }

    // Get blockchain data
    const blockchainData = await disabledLegacyChainBookingStub.getBooking(parseInt(id));

    res.json({
      success: true,
      data: {
        ...booking,
        blockchain: blockchainData,
      },
    });
  } catch (error) {
    next(error);
  }
};

export const confirmBooking = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const userId = req.user!.userId;

    // Verify barber owns this booking
    const booking = await pool.query(
      `SELECT bm.blockchain_booking_id, b.user_id, ${USER_PRIMARY_WALLET_SQL_U} AS barber_wallet
       FROM booking_metadata bm
       JOIN barbers b ON bm.barber_id = b.id
       JOIN users u ON b.user_id = u.id
       WHERE bm.blockchain_booking_id = $1`,
      [id]
    );

    if (booking.rows.length === 0) {
      throw new ApiError(404, 'Booking not found');
    }

    if (booking.rows[0].user_id !== userId) {
      throw new ApiError(403, 'Not authorized');
    }

    // Confirm on blockchain
    const txHash = await disabledLegacyChainBookingStub.confirmBooking(
      booking.rows[0].barber_wallet,
      parseInt(id)
    );

    logger.info(`Booking confirmed: ${id} (tx: ${txHash})`);

    res.json({
      success: true,
      message: 'Booking confirmed',
      transactionHash: txHash,
    });
  } catch (error) {
    next(error);
  }
};

export const completeBooking = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const userId = req.user!.userId;

    // Verify barber owns this booking and get booking details
    const booking = await pool.query(
      `SELECT bm.id, bm.blockchain_booking_id, b.id as barber_id, b.user_id, b.pricing
       FROM booking_metadata bm
       JOIN barbers b ON bm.barber_id = b.id
       WHERE bm.blockchain_booking_id = $1`,
      [id]
    );

    if (booking.rows.length === 0) {
      throw new ApiError(404, 'Booking not found');
    }

    const bookingData = booking.rows[0];

    if (bookingData.user_id !== userId) {
      throw new ApiError(403, 'Not authorized');
    }

    // Complete on blockchain
    const txHash = await disabledLegacyChainBookingStub.completeBooking(parseInt(id));

    // Get booking payment details from ledger
    const ledgerHistory = await ledgerService.getLedgerHistory(bookingData.user_id, 100, 0);
    const bookingPayment = ledgerHistory.entries.find(
      (entry: any) => entry.reference_id === bookingData.id && entry.type === 'BOOKING_PAYMENT' && entry.balance_type === 'pending'
    );

    if (bookingPayment) {
      // Release funds from pending to available
      await paymentService.releaseBookingFunds({
        bookingId: bookingData.id,
        barberId: bookingData.user_id,
        amountCents: bookingPayment.amount,
      });

      logger.info(`Booking completed - funds released from pending to available`, {
        booking_id: id,
        barber_id: bookingData.user_id,
        amount_cents: bookingPayment.amount,
        tx_hash: txHash,
      });
    }

    res.json({
      success: true,
      message: 'Booking completed successfully. Funds have been released to your available balance.',
      transactionHash: txHash,
    });
  } catch (error) {
    next(error);
  }
};

export const cancelBooking = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { reason } = req.body;
    const userId = req.user!.userId;

    // Verify user is involved in booking and get details
    const booking = await pool.query(
      `SELECT bm.id, bm.blockchain_booking_id, bm.client_id, b.id as barber_id, b.user_id as barber_user_id, b.pricing
       FROM booking_metadata bm
       JOIN barbers b ON bm.barber_id = b.id
       WHERE bm.blockchain_booking_id = $1`,
      [id]
    );

    if (booking.rows.length === 0) {
      throw new ApiError(404, 'Booking not found');
    }

    const bookingData = booking.rows[0];
    const isClient = bookingData.client_id === userId;
    const isBarber = bookingData.barber_user_id === userId;

    if (!isClient && !isBarber) {
      throw new ApiError(403, 'Not authorized');
    }

    // Cancel on blockchain
    const txHash = await disabledLegacyChainBookingStub.cancelBooking(parseInt(id));

    // Get booking payment details from ledger
    const barberLedgerHistory = await ledgerService.getLedgerHistory(bookingData.barber_user_id, 100, 0);
    const bookingPayment = barberLedgerHistory.entries.find(
      (entry: any) => entry.reference_id === bookingData.id && entry.type === 'BOOKING_PAYMENT' && entry.balance_type === 'pending'
    );

    if (bookingPayment) {
      // Refund the payment (from barber's pending back to customer's available)
      await paymentService.refundBookingPayment({
        bookingId: bookingData.id,
        customerId: bookingData.client_id,
        barberId: bookingData.barber_user_id,
        totalAmountCents: bookingPayment.amount,
      });

      logger.info(`Booking cancelled - refund issued`, {
        booking_id: id,
        customer_id: bookingData.client_id,
        barber_id: bookingData.barber_user_id,
        refund_amount_cents: bookingPayment.amount,
        cancelled_by: isBarber ? 'barber' : 'client',
        reason,
        tx_hash: txHash,
      });
    }

    res.json({
      success: true,
      message: bookingPayment 
        ? 'Booking cancelled successfully. Refund has been issued to your wallet.' 
        : 'Booking cancelled successfully.',
      transactionHash: txHash,
    });
  } catch (error) {
    next(error);
  }
};

export const getUserBookingHistory = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const userRole = req.user!.role;

    let query: string;

    if (userRole === 'barber') {
      query = `
        SELECT bm.blockchain_booking_id, bm.created_at, bm.location_details,
          u.first_name as client_first_name, u.last_name as client_last_name
        FROM booking_metadata bm
        JOIN barbers b ON bm.barber_id = b.id
        JOIN users u ON bm.client_id = u.id
        WHERE b.user_id = $1
        ORDER BY bm.created_at DESC
        LIMIT 50
      `;
    } else {
      query = `
        SELECT bm.blockchain_booking_id, bm.created_at, bm.location_details,
          u.first_name as barber_first_name, u.last_name as barber_last_name,
          b.profile_image_url
        FROM booking_metadata bm
        JOIN barbers b ON bm.barber_id = b.id
        JOIN users u ON b.user_id = u.id
        WHERE bm.client_id = $1
        ORDER BY bm.created_at DESC
        LIMIT 50
      `;
    }

    const result = await pool.query(query, [userId]);

    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    next(error);
  }
};

