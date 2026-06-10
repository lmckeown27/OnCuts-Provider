import { Response, NextFunction } from 'express';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest } from '../middleware/auth';
import suiChainService from '../services/sui-chain.service';
import { logger } from '../utils/logger';
import crypto from 'crypto';
import { USER_PRIMARY_WALLET_SQL, USER_PRIMARY_WALLET_SQL_U } from '../utils/user-wallet-address';

export const submitReview = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { bookingId, rating, reviewText, images } = req.body;
    const clientId = req.user!.userId;

    // Verify booking exists, is completed, and belongs to client
    const booking = await pool.query(
      `SELECT bm.*, ${USER_PRIMARY_WALLET_SQL_U} as barber_address, u.campus_id
       FROM booking_metadata bm
       JOIN barbers b ON bm.barber_id = b.id
       JOIN users u ON b.user_id = u.id
       WHERE bm.blockchain_booking_id = $1 AND bm.client_id = $2`,
      [bookingId, clientId]
    );

    if (booking.rows.length === 0) {
      throw new ApiError(404, 'Booking not found or not authorized');
    }

    // Check if already reviewed
    const existing = await pool.query(
      'SELECT id FROM review_metadata WHERE booking_id = $1',
      [bookingId]
    );

    if (existing.rows.length > 0) {
      throw new ApiError(400, 'Booking already reviewed');
    }

    const { barber_address, campus_id } = booking.rows[0];

    const clientResult = await pool.query(
      `SELECT ${USER_PRIMARY_WALLET_SQL} AS primary_wallet FROM users WHERE id = $1`,
      [clientId]
    );
    const clientAddress = clientResult.rows[0]?.primary_wallet;

    // Hash review text for blockchain
    const reviewHash = crypto.createHash('sha256').update(reviewText).digest('hex');

    // Submit review to blockchain
    const txHash = await suiChainService.submitReview({
      clientAddress,
      bookingId,
      barberAddress: barber_address,
      rating,
      reviewTextHash: reviewHash,
      campusId: campus_id,
    });

    // Store full review text off-chain
    const blockchainReviewId = Date.now(); // Simplified: would parse from transaction events

    const result = await pool.query(
      `INSERT INTO review_metadata (blockchain_review_id, booking_id, review_text, images)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [blockchainReviewId, bookingId, reviewText, JSON.stringify(images || [])]
    );

    // Update barber's average rating
    await updateBarberAverageRating(booking.rows[0].barber_id);

    logger.info(`Review submitted for booking ${bookingId} (tx: ${txHash})`);

    res.status(201).json({
      success: true,
      data: result.rows[0],
      transactionHash: txHash,
      message: 'Review submitted successfully',
    });
  } catch (error) {
    next(error);
  }
};

export const getBarberReviews = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { barberId } = req.params;
    const page = parseInt(req.query.page as string) || 1;
    const limit = parseInt(req.query.limit as string) || 20;
    const offset = (page - 1) * limit;

    const result = await pool.query(
      `SELECT rm.*, 
        u.first_name as client_first_name,
        u.last_name as client_last_name,
        bm.blockchain_booking_id
      FROM review_metadata rm
      JOIN booking_metadata bm ON rm.booking_id = bm.blockchain_booking_id
      JOIN users u ON bm.client_id = u.id
      WHERE bm.barber_id = $1
      ORDER BY rm.created_at DESC
      LIMIT $2 OFFSET $3`,
      [barberId, limit, offset]
    );

    // Get total count
    const countResult = await pool.query(
      `SELECT COUNT(*) as total
       FROM review_metadata rm
       JOIN booking_metadata bm ON rm.booking_id = bm.blockchain_booking_id
       WHERE bm.barber_id = $1`,
      [barberId]
    );

    res.json({
      success: true,
      data: result.rows,
      pagination: {
        page,
        limit,
        total: parseInt(countResult.rows[0].total),
        pages: Math.ceil(countResult.rows[0].total / limit),
      },
    });
  } catch (error) {
    next(error);
  }
};

export const getReviewById = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;

    const result = await pool.query(
      `SELECT rm.*,
        u.first_name as client_first_name,
        u.last_name as client_last_name
      FROM review_metadata rm
      JOIN booking_metadata bm ON rm.booking_id = bm.blockchain_booking_id
      JOIN users u ON bm.client_id = u.id
      WHERE rm.id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'Review not found');
    }

    res.json({
      success: true,
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

export const markReviewHelpful = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;

    await pool.query(
      'UPDATE review_metadata SET helpful_count = helpful_count + 1 WHERE id = $1',
      [id]
    );

    res.json({
      success: true,
      message: 'Review marked as helpful',
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Helper: Update barber's average rating from all reviews
 */
async function updateBarberAverageRating(barberId: string): Promise<void> {
  const result = await pool.query(
    `SELECT AVG(
      (SELECT rating FROM review_metadata rm 
       JOIN booking_metadata bm ON rm.booking_id = bm.blockchain_booking_id 
       WHERE bm.barber_id = $1)
    ) as avg_rating`,
    [barberId]
  );

  // This is simplified - would need proper aggregation
  await pool.query(
    'UPDATE barbers SET average_rating = $1 WHERE id = $2',
    [result.rows[0].avg_rating || 0, barberId]
  );
}

