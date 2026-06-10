/**
 * Message Routes for CampusCuts
 * Handles real-time messaging between students and barbers
 */

import express from 'express';
import messageService from '../services/message.service';
import { authenticate } from '../middleware/auth';
import { pool } from '../database/connection';

const router = express.Router();

/**
 * GET /api/messages/conversations
 * Get user's conversations with pagination
 */
router.get('/conversations', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const page = parseInt(req.query.page as string) || 1;
    const limit = parseInt(req.query.limit as string) || 20;

    const result = await messageService.getUserConversations(userId, page, limit);
    
    // Prevent browser caching to ensure fresh data
    res.set('Cache-Control', 'no-store, no-cache, must-revalidate, private');
    res.set('Pragma', 'no-cache');
    res.set('Expires', '0');
    
    res.json(result);
  } catch (error) {
    next(error);
  }
});

/**
 * POST /api/messages/conversations
 * Start a new BOOKING-CENTRIC conversation
 * CampusCuts conversations are always about a scheduled service
 */
router.post('/conversations', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    // Accept both camelCase and snake_case from frontend
    const otherUserId = req.body.otherUserId || req.body.other_user_id;

    if (!otherUserId) {
      return res.status(400).json({ success: false, error: 'other_user_id is required' });
    }

    // Build booking context from request body
    const bookingContext = {
      bookingId: req.body.bookingId || req.body.booking_id,
      serviceName: req.body.serviceName || req.body.service_name,
      servicePrice: req.body.servicePrice || req.body.service_price,
      scheduledTime: req.body.scheduledTime || req.body.scheduled_time,
      location: req.body.location,
      locationDetails: req.body.locationDetails || req.body.location_details,
      notes: req.body.notes,
      barberName: req.body.barberName || req.body.barber_name,
      consumerName: req.body.consumerName || req.body.consumer_name,
      barberProfilePicture: req.body.barberProfilePicture || req.body.barber_profile_picture,
      consumerProfilePicture: req.body.consumerProfilePicture || req.body.consumer_profile_picture,
    };

    console.log('🚀 Starting BOOKING-CENTRIC conversation:', { 
      userId, 
      otherUserId, 
      serviceName: bookingContext.serviceName,
      scheduledTime: bookingContext.scheduledTime 
    });

    const result = await messageService.startConversation(userId, otherUserId, bookingContext);
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
});

/**
 * GET /api/messages/conversations/:conversationId/messages
 * Get messages in a conversation
 */
router.get('/conversations/:conversationId/messages', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const conversationId = parseInt(req.params.conversationId);
    const page = parseInt(req.query.page as string) || 1;
    const limit = parseInt(req.query.limit as string) || 50;

    const result = await messageService.getConversationMessages(conversationId, userId, page, limit);
    res.json(result);
  } catch (error) {
    next(error);
  }
});

/**
 * POST /api/messages/conversations/:conversationId/messages
 * Send a message in a conversation
 */
router.post('/conversations/:conversationId/messages', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const conversationId = parseInt(req.params.conversationId);
    const { content, messageType, mediaUrl } = req.body;

    // Emit via Socket.IO for real-time delivery
    const io = (req.app as any).get('io');
    
    const result = await messageService.sendMessage(
      conversationId,
      userId,
      content,
      messageType || 'text',
      mediaUrl || null
    );

    // Emit to recipient's room
    const conversation = await messageService.getConversationById(conversationId, userId);
    if (conversation.success) {
      const conv = conversation.data.conversation;
      // Compare as strings to handle UUID comparison correctly
      const recipientId = String(conv.user1_id) === String(userId) 
        ? conv.user2_id 
        : conv.user1_id;
      
      console.log(`📨 Socket.IO: Emitting new-message to user-${recipientId} (sender: ${userId})`);
      io.to(`user-${recipientId}`).emit('new-message', result.data.message);
    }

    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
});

/**
 * PUT /api/messages/conversations/:conversationId/read
 * Mark conversation as read
 */
router.put('/conversations/:conversationId/read', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const conversationId = parseInt(req.params.conversationId);

    const result = await messageService.markConversationAsRead(conversationId, userId);
    res.json(result);
  } catch (error) {
    next(error);
  }
});

/**
 * DELETE /api/messages/conversations/:conversationId
 * Delete a conversation
 */
router.delete('/conversations/:conversationId', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const conversationId = parseInt(req.params.conversationId);

    // Get conversation details before deleting to notify the other user
    const convResult = await pool.query(
      `SELECT c.*, c.service_name, c.booking_status,
              u1.first_name as user1_first_name, u1.last_name as user1_last_name,
              u2.first_name as user2_first_name, u2.last_name as user2_last_name
       FROM conversations c
       JOIN users u1 ON c.user1_id = u1.id
       JOIN users u2 ON c.user2_id = u2.id
       WHERE c.id = $1`,
      [conversationId]
    );

    if (convResult.rows.length > 0) {
      const conv = convResult.rows[0];
      const otherUserId = conv.user1_id === userId ? conv.user2_id : conv.user1_id;
      const deletingUserName = conv.user1_id === userId 
        ? `${conv.user1_first_name} ${conv.user1_last_name}`
        : `${conv.user2_first_name} ${conv.user2_last_name}`;
      const serviceName = conv.service_name || 'a service';

      // Create notification for the other user (if table exists)
      try {
        await pool.query(
          `INSERT INTO notifications (user_id, type, title, message, data)
           VALUES ($1, $2, $3, $4, $5)`,
          [
            otherUserId,
            'booking_cancelled',
            'Booking Cancelled',
            `${deletingUserName} has cancelled the conversation about ${serviceName}.`,
            JSON.stringify({
              conversation_id: conversationId,
              service_name: conv.service_name,
              cancelled_by: userId,
            }),
          ]
        );
      } catch (notifError) {
        // Don't fail the delete if notification fails (table might not exist)
        console.warn('Failed to create cancellation notification:', notifError);
      }
    }

    const result = await messageService.deleteConversation(conversationId, userId);
    res.json(result);
  } catch (error) {
    next(error);
  }
});

/**
 * GET /api/messages/unread-count
 * Get unread message count for badge
 */
router.get('/unread-count', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const count = await messageService.getUnreadMessageCount(userId);
    
    res.json({
      success: true,
      data: { count },
    });
  } catch (error) {
    next(error);
  }
});

/**
 * GET /api/messages/stats
 * Get message statistics
 */
router.get('/stats', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const result = await messageService.getMessageStats(userId);
    res.json(result);
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// CAMPUS MANAGER - BARBER DIRECT MESSAGING
// ============================================================================

/**
 * POST /api/messages/cm-barber
 * Start or get a direct conversation between barber and campus manager
 * No booking required - this is for general communication
 */
router.post('/cm-barber', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;

    // Get user's info including their barber record (if they have one)
    const userResult = await pool.query(
      `SELECT u.id, u.role, u.first_name, u.last_name, u."avatarUrl",
              b.id as barber_id, b."campusId" as barber_campus_id, b."isCampusManager"
       FROM users u
       LEFT JOIN barbers b ON b."userId" = u.id AND b."isActive" = true
       WHERE u.id = $1`,
      [userId]
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'User not found' });
    }

    const user = userResult.rows[0];
    
    // Use barber's campus if available
    const campusId = user.barber_campus_id;

    if (!campusId) {
      return res.status(400).json({ success: false, error: 'You must be an active barber associated with a campus to use this feature' });
    }

    // Find the campus manager for this campus
    // Check BOTH:
    // 1. Barbers with isCampusManager = true on this campus
    // 2. Users with role = 'CAMPUS_MANAGER' whose campusId matches (may not have barber record)
    const cmResult = await pool.query(
      `SELECT u.id as user_id, u.first_name, u.last_name, u."avatarUrl", u.role,
              b.id as barber_id, b."isCampusManager"
       FROM users u
       LEFT JOIN barbers b ON b."userId" = u.id
       WHERE u.id != $2
         AND (
           -- Option 1: Barber with isCampusManager flag on this campus
           (b."campusId" = $1 AND b."isCampusManager" = true)
           OR
           -- Option 2: User with CAMPUS_MANAGER role associated with this campus
           (u."campusId" = $1 AND u.role = 'CAMPUS_MANAGER')
         )
       ORDER BY 
         CASE WHEN u.role = 'CAMPUS_MANAGER' THEN 0 ELSE 1 END,
         CASE WHEN b."isCampusManager" = true THEN 0 ELSE 1 END
       LIMIT 1`,
      [campusId, userId]
    );

    if (cmResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'No campus manager found for your campus' });
    }

    const campusManager = cmResult.rows[0];

    // Determine who is the CM and who is the barber
    const isCM = user.isCampusManager === true || user.role === 'CAMPUS_MANAGER';
    const otherUserId = isCM ? req.body.barberUserId : campusManager.user_id;

    if (!otherUserId) {
      return res.status(400).json({ success: false, error: 'Could not determine conversation partner' });
    }

    // Check if conversation already exists (booking_id = NULL for CM-barber chats)
    // Only find active conversations - deleted ones (is_active = false) should allow new conversation creation
    const existingConv = await pool.query(
      `SELECT * FROM conversations 
       WHERE booking_id IS NULL 
         AND is_active = true
         AND ((user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1))
       LIMIT 1`,
      [userId, otherUserId]
    );

    if (existingConv.rows.length > 0) {
      // Return existing conversation
      const conv = existingConv.rows[0];
      return res.json({
        success: true,
        data: {
          conversation: {
            id: conv.id,
            otherUserId: otherUserId,
            isNew: false
          }
        }
      });
    }

    // Create new CM-barber conversation
    const newConv = await pool.query(
      `INSERT INTO conversations (user1_id, user2_id, booking_id, is_active, created_at, updated_at)
       VALUES ($1, $2, NULL, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       RETURNING id`,
      [userId, otherUserId]
    );

    res.status(201).json({
      success: true,
      data: {
        conversation: {
          id: newConv.rows[0].id,
          otherUserId: otherUserId,
          isNew: true
        }
      }
    });
  } catch (error) {
    next(error);
  }
});

/**
 * GET /api/messages/cm-barber/conversations
 * Get all CM-barber conversations (for campus managers viewing all their barbers)
 */
router.get('/cm-barber/conversations', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const queryCampusId = req.query.campusId as string | undefined;

    // Verify user is a campus manager (check both barbers.isCampusManager AND users.role)
    // Don't require isActive for the CM's own barber record - they need access regardless
    const cmCheck = await pool.query(
      `SELECT b.id, b."campusId", u.role, u."campusId" as user_campus_id
       FROM users u
       LEFT JOIN barbers b ON b."userId" = u.id
       WHERE u.id = $1 AND (b."isCampusManager" = true OR u.role = 'CAMPUS_MANAGER' OR u.role = 'ADMIN')`,
      [userId]
    );

    if (cmCheck.rows.length === 0) {
      return res.status(403).json({ success: false, error: 'Only campus managers can access this endpoint' });
    }

    const isAdmin = cmCheck.rows[0].role === 'ADMIN';
    
    // Admins can specify any campus via query param, others use their own campus
    let campusId: string;
    if (isAdmin && queryCampusId) {
      campusId = queryCampusId;
    } else {
      // Use barber's campusId if available, otherwise fall back to user's campusId
      campusId = cmCheck.rows[0].campusId || cmCheck.rows[0].user_campus_id;
    }
    
    if (!campusId) {
      return res.status(400).json({ success: false, error: 'You must be associated with a campus to view barber chats' });
    }

    // Get all active barbers in this campus (excluding self and demoted users)
    // Only show users who are still BARBER role AND have isActive = true
    const barbersResult = await pool.query(
      `SELECT 
         u.id as user_id,
         u.first_name,
         u.last_name,
         u."avatarUrl",
         u.email,
         b.id as barber_id,
         b."isCampusManager",
         c.id as conversation_id,
         (SELECT content FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message,
         (SELECT created_at FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message_at,
         (SELECT COUNT(*) FROM messages WHERE conversation_id = c.id AND sender_id != $1 AND is_read = false)::int as unread_count
       FROM barbers b
       JOIN users u ON b."userId" = u.id
       LEFT JOIN conversations c ON c.booking_id IS NULL 
         AND c.is_active = true
         AND ((c.user1_id = $1 AND c.user2_id = u.id) OR (c.user1_id = u.id AND c.user2_id = $1))
       WHERE b."campusId" = $2 
         AND b."isActive" = true 
         AND b."isCampusManager" = false
         AND b."userId" != $1
         AND u.role = 'BARBER'
       ORDER BY COALESCE(c.last_message_at, b."createdAt") DESC`,
      [userId, campusId]
    );

    res.json({
      success: true,
      data: {
        barbers: barbersResult.rows.map(row => ({
          userId: row.user_id,
          barberId: row.barber_id,
          firstName: row.first_name,
          lastName: row.last_name,
          name: `${row.first_name} ${row.last_name}`,
          avatarUrl: row.avatarUrl,
          email: row.email,
          conversationId: row.conversation_id,
          lastMessage: row.last_message,
          lastMessageAt: row.last_message_at,
          unreadCount: row.unread_count || 0
        }))
      }
    });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// BARBER-TO-BARBER DIRECT MESSAGING
// ============================================================================

/**
 * GET /api/messages/barber-chats/barbers
 * Get all other barbers on the same campus for barber-to-barber chat
 * Admins can optionally specify a campusId to view barbers from any campus
 */
router.get('/barber-chats/barbers', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const requestedCampusId = req.query.campusId as string | undefined;

    // Get user's info and role
    const userResult = await pool.query(
      `SELECT u.role, b.id as barber_id, COALESCE(b."campusId", u."campusId") as "campusId"
       FROM users u
       LEFT JOIN barbers b ON b."userId" = u.id
       WHERE u.id = $1 
         AND (
           (b."isActive" = true AND u.role IN ('BARBER', 'CAMPUS_MANAGER', 'ADMIN'))
           OR u.role IN ('CAMPUS_MANAGER', 'ADMIN')
         )`,
      [userId]
    );

    if (userResult.rows.length === 0) {
      return res.status(403).json({ success: false, error: 'Only barbers can access this endpoint' });
    }

    const userRole = userResult.rows[0].role;
    const userCampusId = userResult.rows[0].campusId;

    // Admins can view any campus, others can only view their own
    let campusId: string;
    if (requestedCampusId && userRole === 'ADMIN') {
      campusId = requestedCampusId;
    } else {
      campusId = userCampusId;
    }

    if (!campusId) {
      return res.status(400).json({ success: false, error: 'You must be associated with a campus to view barber chats' });
    }

    // Get all active barbers on the same campus (excluding self)
    const barbersResult = await pool.query(
      `SELECT 
         u.id as user_id,
         u.first_name,
         u.last_name,
         u."avatarUrl",
         u.email,
         b.id as barber_id,
         b."isCampusManager",
         c.id as conversation_id,
         (SELECT content FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message,
         (SELECT created_at FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message_at,
         (SELECT COUNT(*) FROM messages WHERE conversation_id = c.id AND sender_id != $1 AND is_read = false)::int as unread_count
       FROM barbers b
       JOIN users u ON b."userId" = u.id
       LEFT JOIN conversations c ON c.booking_id IS NULL 
         AND c.is_active = true
         AND ((c.user1_id = $1 AND c.user2_id = u.id) OR (c.user1_id = u.id AND c.user2_id = $1))
       WHERE b."campusId" = $2 
         AND b."isActive" = true 
         AND b."userId" != $1
         AND u.role IN ('BARBER', 'CAMPUS_MANAGER', 'ADMIN')
         AND u.stripe_account_id IS NOT NULL
         AND u.stripe_payouts_enabled = true
       ORDER BY 
         b."isCampusManager" DESC,
         COALESCE(c.last_message_at, b."createdAt") DESC`,
      [userId, campusId]
    );

    res.json({
      success: true,
      data: {
        barbers: barbersResult.rows.map(row => ({
          userId: row.user_id,
          barberId: row.barber_id,
          firstName: row.first_name,
          lastName: row.last_name,
          name: `${row.first_name} ${row.last_name}`,
          avatarUrl: row.avatarUrl,
          email: row.email,
          isCampusManager: row.isCampusManager,
          conversationId: row.conversation_id,
          lastMessage: row.last_message,
          lastMessageAt: row.last_message_at,
          unreadCount: row.unread_count || 0
        }))
      }
    });
  } catch (error) {
    next(error);
  }
});

/**
 * POST /api/messages/barber-chats
 * Start or get a direct conversation between two barbers
 */
router.post('/barber-chats', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const { otherBarberUserId } = req.body;

    if (!otherBarberUserId) {
      return res.status(400).json({ success: false, error: 'otherBarberUserId is required' });
    }

    // Verify both users are barbers on the same campus
    // Allow active barbers, campus managers, and admins
    const verifyResult = await pool.query(
      `SELECT 
         COALESCE(b1."campusId", u1."campusId") as user_campus, 
         COALESCE(b2."campusId", u2."campusId") as other_campus
       FROM users u1
       LEFT JOIN barbers b1 ON b1."userId" = u1.id
       CROSS JOIN users u2
       LEFT JOIN barbers b2 ON b2."userId" = u2.id
       WHERE u1.id = $1 AND u2.id = $2
         AND (
           (b1."isActive" = true AND u1.role IN ('BARBER', 'CAMPUS_MANAGER', 'ADMIN'))
           OR u1.role IN ('CAMPUS_MANAGER', 'ADMIN')
         )
         AND (
           (b2."isActive" = true AND u2.role IN ('BARBER', 'CAMPUS_MANAGER', 'ADMIN'))
           OR u2.role IN ('CAMPUS_MANAGER', 'ADMIN')
         )`,
      [userId, otherBarberUserId]
    );

    if (verifyResult.rows.length === 0) {
      return res.status(403).json({ success: false, error: 'Both users must be barbers' });
    }

    if (verifyResult.rows[0].user_campus !== verifyResult.rows[0].other_campus) {
      return res.status(403).json({ success: false, error: 'Both barbers must be on the same campus' });
    }

    // Check if conversation already exists (booking_id = NULL for direct chats)
    // Only find active conversations - deleted ones (is_active = false) should allow new conversation creation
    const existingConv = await pool.query(
      `SELECT * FROM conversations 
       WHERE booking_id IS NULL 
         AND is_active = true
         AND ((user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1))
       LIMIT 1`,
      [userId, otherBarberUserId]
    );

    if (existingConv.rows.length > 0) {
      const conv = existingConv.rows[0];
      return res.json({
        success: true,
        data: {
          conversation: {
            id: conv.id,
            otherUserId: otherBarberUserId,
            isNew: false
          }
        }
      });
    }

    // Create new barber-to-barber conversation
    const newConv = await pool.query(
      `INSERT INTO conversations (user1_id, user2_id, booking_id, is_active, created_at, updated_at)
       VALUES ($1, $2, NULL, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       RETURNING id`,
      [userId, otherBarberUserId]
    );

    res.status(201).json({
      success: true,
      data: {
        conversation: {
          id: newConv.rows[0].id,
          otherUserId: otherBarberUserId,
          isNew: true
        }
      }
    });
  } catch (error) {
    next(error);
  }
});

export default router;

