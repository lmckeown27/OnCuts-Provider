/**
 * Booking Request Controller (AirBnb-style)
 * 
 * API endpoints for booking request workflow
 */

import { Request, Response } from 'express';
import { logger } from '../utils/logger';
import { bookingRequestService } from '../services/booking-request.service';
import { bookingMessagingService } from '../services/booking-messaging.service';
import { pool } from '../database/connection';
import { getSocketIO } from '../index';

/**
 * POST /api/booking-requests
 * Create a new booking request
 */
export async function createBookingRequest(req: Request, res: Response) {
  try {
    const {
      customerId,
      barberId,
      serviceType,
      requestedDate,
      requestedTime,
      price,
      message,
    } = req.body;

    if (!customerId || !barberId || !serviceType || !requestedDate || !requestedTime || !price) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
      });
    }

    const result = await bookingRequestService.createBookingRequest({
      customerId,
      barberId,
      serviceType,
      requestedDate: new Date(requestedDate),
      requestedTime,
      price: parseFloat(price),
      message,
    });

    res.json({
      success: true,
      bookingId: result.bookingId,
      message: 'Booking request sent! The barber will review and respond shortly.',
    });
  } catch (error: any) {
    logger.error('Error creating booking request:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to create booking request',
    });
  }
}

/**
 * GET /api/booking-requests/barber/:barberId/pending
 * Get pending booking requests for a barber
 */
export async function getBarberPendingRequests(req: Request, res: Response) {
  try {
    const { barberId } = req.params;

    const requests = await bookingRequestService.getBarberPendingRequests(barberId);

    // Prevent caching to ensure fresh data
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');

    res.json({
      success: true,
      count: requests.length,
      requests,
    });
  } catch (error: any) {
    logger.error('Error getting pending requests:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to get pending requests',
    });
  }
}

/**
 * POST /api/booking-requests/:bookingId/accept
 * Accept a booking request
 */
export async function acceptBookingRequest(req: Request, res: Response) {
  try {
    const { bookingId } = req.params;
    const { barberId, message } = req.body;

    if (!barberId) {
      return res.status(400).json({
        success: false,
        error: 'barber ID is required',
      });
    }

    await bookingRequestService.acceptBookingRequest(bookingId, barberId, message);

    // Emit WebSocket event to barber for live dashboard updates (non-blocking)
    // This runs in the background so it doesn't affect the response
    (async () => {
      try {
        logger.info(`[booking-confirmed] Starting WebSocket emission for bookingId: ${bookingId}, barberId: ${barberId}`);
        
        // Handle both conv-* prefixed IDs and regular booking IDs
        let actualBookingId = bookingId;
        const isConversationBased = bookingId.startsWith('conv-');
        
        if (isConversationBased) {
          const conversationId = bookingId.replace('conv-', '');
          logger.info(`[booking-confirmed] This is a conversation-based booking, conversationId: ${conversationId}`);
          
          // Get the linked booking_id from the conversation
          const convResult = await pool.query(
            `SELECT booking_id FROM conversations WHERE id = $1`,
            [conversationId]
          );
          logger.info(`[booking-confirmed] Conversation lookup returned ${convResult.rows.length} rows, booking_id: ${convResult.rows[0]?.booking_id || 'NULL'}`);
          
          if (convResult.rows.length > 0 && convResult.rows[0].booking_id) {
            actualBookingId = convResult.rows[0].booking_id;
            logger.info(`[booking-confirmed] Using linked booking_id: ${actualBookingId}`);
          } else {
            logger.warn(`[booking-confirmed] No linked booking_id found for conversation ${conversationId}, cannot emit event`);
            return; // Exit early - we can't emit without a booking record
          }
        }

        // Get full booking details for the barber's dashboard
        logger.info(`[booking-confirmed] Looking up booking details, actualBookingId: ${actualBookingId}`);
        const bookingResult = await pool.query(
          `SELECT 
            b.id,
            b."consumerId",
            b."barberId",
            b."serviceType",
            b."priceUsdCents",
            b."requestedAt" as "scheduledTime",
            b.status,
            b."createdAt",
            c.location,
            c.notes,
            c.service_name,
            consumer.first_name as consumer_first_name,
            consumer.last_name as consumer_last_name,
            consumer.email as consumer_email,
            consumer."avatarUrl" as consumer_profile_url,
            barber."userId" as barber_user_id
          FROM bookings b
          LEFT JOIN conversations c ON c.booking_id = b.id
          LEFT JOIN users consumer ON b."consumerId" = consumer.id
          LEFT JOIN barbers barber ON b."barberId" = barber.id
          WHERE b.id = $1`,
          [actualBookingId]
        );
        
        logger.info(`[booking-confirmed] Booking query returned ${bookingResult.rows.length} rows`);
        if (bookingResult.rows.length > 0) {
          const b = bookingResult.rows[0];
          logger.info(`[booking-confirmed] Found booking: id=${b.id}, barber_user_id=${b.barber_user_id}, barberId=${b.barberId}, status=${b.status}`);
        } else {
          logger.warn(`[booking-confirmed] No booking found with id: ${actualBookingId}`);
        }

        // Emit WebSocket event to barber for live dashboard updates
        const io = getSocketIO();
        logger.info(`[booking-confirmed] Socket.IO instance available: ${!!io}`);
        if (io && bookingResult.rows.length > 0) {
          const booking = bookingResult.rows[0];
          const barberUserId = booking.barber_user_id;
          
          logger.info(`[booking-confirmed] Emitting to room user-${barberUserId}`);
          const eventData = {
            id: booking.id,
            consumerId: booking.consumerId,
            barberId: booking.barberId,
            serviceType: booking.service_name || booking.serviceType,
            priceUsdCents: booking.priceUsdCents,
            scheduledTime: booking.scheduledTime,
            status: 'ACCEPTED',
            location: booking.location,
            notes: booking.notes,
            consumer: {
              firstName: booking.consumer_first_name,
              lastName: booking.consumer_last_name,
              email: booking.consumer_email,
              profilePictureUrl: booking.consumer_profile_url,
            },
          };
          logger.info(`[booking-confirmed] Event data: ${JSON.stringify(eventData)}`);
          io.to(`user-${barberUserId}`).emit('booking-confirmed', eventData);
          logger.info(`[booking-confirmed] ✅ Successfully emitted to barber user ${barberUserId}`);
        } else {
          logger.warn(`[booking-confirmed] ❌ Could not emit: io=${!!io}, rows=${bookingResult.rows.length}`);
        }
      } catch (wsError) {
        logger.error('[booking-confirmed] ❌ Error emitting WebSocket event:', wsError);
        // Don't throw - this is non-blocking
      }
    })();

    res.json({
      success: true,
      message: 'Booking accepted successfully!',
    });
  } catch (error: any) {
    logger.error('Error accepting booking:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to accept booking',
    });
  }
}

/**
 * POST /api/booking-requests/:bookingId/reject
 * Reject a booking request
 */
export async function rejectBookingRequest(req: Request, res: Response) {
  try {
    const { bookingId } = req.params;
    const { barberId, reason } = req.body;

    if (!barberId) {
      return res.status(400).json({
        success: false,
        error: 'barberId is required',
      });
    }

    await bookingRequestService.rejectBookingRequest(bookingId, barberId, reason);

    res.json({
      success: true,
      message: 'Booking request declined',
    });
  } catch (error: any) {
    logger.error('Error rejecting booking:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to reject booking',
    });
  }
}

/**
 * GET /api/booking-requests/customer/:customerId/profile
 * Get customer profile (for barber view)
 */
export async function getCustomerProfile(req: Request, res: Response) {
  try {
    const { customerId } = req.params;
    const { barberId } = req.query;

    if (!barberId) {
      return res.status(400).json({
        success: false,
        error: 'barberId is required',
      });
    }

    const profile = await bookingRequestService.getCustomerProfile(
      customerId,
      barberId as string
    );

    res.json({
      success: true,
      profile,
    });
  } catch (error: any) {
    logger.error('Error getting customer profile:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to get customer profile',
    });
  }
}

/**
 * GET /api/booking-requests/customer/:customerId/status
 * Get customer's booking status
 */
export async function getCustomerBookingStatus(req: Request, res: Response) {
  try {
    const { customerId } = req.params;

    const bookings = await bookingRequestService.getCustomerBookingStatus(customerId);

    res.json({
      success: true,
      bookings,
    });
  } catch (error: any) {
    logger.error('Error getting customer booking status:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to get booking status',
    });
  }
}

/**
 * POST /api/booking-requests/:bookingId/messages
 * Send a message
 */
export async function sendMessage(req: Request, res: Response) {
  try {
    const { bookingId } = req.params;
    const { senderId, senderType, message } = req.body;

    if (!senderId || !senderType || !message) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
      });
    }

    const result = await bookingMessagingService.sendMessage({
      bookingId,
      senderId,
      senderType,
      message,
    });

    res.json({
      success: true,
      messageId: result.messageId,
    });
  } catch (error: any) {
    logger.error('Error sending message:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to send message',
    });
  }
}

/**
 * GET /api/booking-requests/:bookingId/messages
 * Get messages for a booking
 */
export async function getBookingMessages(req: Request, res: Response) {
  try {
    const { bookingId } = req.params;
    const { userId } = req.query;

    if (!userId) {
      return res.status(400).json({
        success: false,
        error: 'userId is required',
      });
    }

    const messages = await bookingMessagingService.getBookingMessages(
      bookingId,
      userId as string
    );

    res.json({
      success: true,
      messages,
    });
  } catch (error: any) {
    logger.error('Error getting messages:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to get messages',
    });
  }
}

/**
 * GET /api/booking-requests/user/:userId/conversations
 * Get all conversations for a user
 */
export async function getUserConversations(req: Request, res: Response) {
  try {
    const { userId } = req.params;
    const { userType } = req.query;

    if (!userType || (userType !== 'barber' && userType !== 'customer')) {
      return res.status(400).json({
        success: false,
        error: 'Valid userType (barber or customer) is required',
      });
    }

    const conversations = await bookingMessagingService.getUserConversations(
      userId,
      userType as 'barber' | 'customer'
    );

    res.json({
      success: true,
      conversations,
    });
  } catch (error: any) {
    logger.error('Error getting conversations:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to get conversations',
    });
  }
}

/**
 * GET /api/booking-requests/user/:userId/unread-count
 * Get unread message count
 */
export async function getUnreadCount(req: Request, res: Response) {
  try {
    const { userId } = req.params;

    const count = await bookingMessagingService.getUnreadCount(userId);

    res.json({
      success: true,
      unreadCount: count,
    });
  } catch (error: any) {
    logger.error('Error getting unread count:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to get unread count',
    });
  }
}

