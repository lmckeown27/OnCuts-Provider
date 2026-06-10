/**
 * Booking Messaging Service
 * 
 * Handles pre and post booking messages between barbers and customers
 * Similar to AirBnb messaging
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';

interface Message {
  messageId: string;
  bookingId: string;
  senderId: string;
  senderType: 'barber' | 'customer';
  senderName: string;
  message: string;
  messageType: string;
  read: boolean;
  readAt?: Date;
  createdAt: Date;
}

export class BookingMessagingService {
  /**
   * Send a message in a booking conversation
   */
  async sendMessage(data: {
    bookingId: string;
    senderId: string;
    senderType: 'barber' | 'customer';
    message: string;
    messageType?: string;
  }): Promise<{ messageId: string; success: boolean }> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      // Insert message
      const result = await client.query(`
        INSERT INTO booking_messages (
          booking_id,
          sender_id,
          sender_type,
          message,
          message_type
        ) VALUES ($1, $2, $3, $4, $5)
        RETURNING message_id
      `, [
        data.bookingId,
        data.senderId,
        data.senderType,
        data.message,
        data.messageType || 'text',
      ]);

      const messageId = result.rows[0].message_id;

      // Get recipient
      const recipientResult = await client.query(`
        SELECT 
          CASE 
            WHEN $2 = 'barber' THEN b.customer_id
            ELSE ba.user_id
          END as recipient_id
        FROM bookings b
        LEFT JOIN barbers ba ON b.barber_id = ba.barber_id
        WHERE b.id = $1
      `, [data.bookingId, data.senderType]);

      if (recipientResult.rows.length > 0) {
        const recipientId = recipientResult.rows[0].recipient_id;

        // Create notification for recipient
        await client.query(`
          INSERT INTO booking_request_notifications (
            user_id,
            booking_id,
            type,
            title,
            message
          ) VALUES ($1, $2, 'new_message', 'New Message', 'You have a new message about your booking')
        `, [recipientId, data.bookingId]);
      }

      await client.query('COMMIT');

      logger.info(`Message sent in booking ${data.bookingId}`);

      return { messageId, success: true };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Error sending message:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get messages for a booking
   */
  async getBookingMessages(bookingId: string, userId: string): Promise<Message[]> {
    try {
      const result = await pool.query(`
        SELECT 
          bm.message_id,
          bm.booking_id,
          bm.sender_id,
          bm.sender_type,
          u.name as sender_name,
          bm.message,
          bm.message_type,
          bm.read,
          bm.read_at,
          bm.created_at
        FROM booking_messages bm
        JOIN users u ON bm.sender_id = u.id
        WHERE bm.booking_id = $1
        ORDER BY bm.created_at ASC
      `, [bookingId]);

      // Mark messages as read (where user is recipient)
      await pool.query(`
        UPDATE booking_messages
        SET read = true, read_at = NOW()
        WHERE booking_id = $1 
          AND sender_id != $2
          AND read = false
      `, [bookingId, userId]);

      return result.rows.map(row => ({
        messageId: row.message_id,
        bookingId: row.booking_id,
        senderId: row.sender_id,
        senderType: row.sender_type,
        senderName: row.sender_name,
        message: row.message,
        messageType: row.message_type,
        read: row.read,
        readAt: row.read_at,
        createdAt: row.created_at,
      }));
    } catch (error) {
      logger.error('Error getting booking messages:', error);
      throw error;
    }
  }

  /**
   * Get unread message count for a user
   */
  async getUnreadCount(userId: string): Promise<number> {
    try {
      const result = await pool.query(`
        SELECT COUNT(*) as count
        FROM booking_messages bm
        JOIN bookings b ON bm.booking_id = b.id
        WHERE bm.read = false
          AND (
            (bm.sender_type = 'customer' AND b.barber_id IN (SELECT barber_id FROM barbers WHERE user_id = $1))
            OR
            (bm.sender_type = 'barber' AND b.customer_id = $1)
          )
      `, [userId]);

      return parseInt(result.rows[0].count) || 0;
    } catch (error) {
      logger.error('Error getting unread count:', error);
      throw error;
    }
  }

  /**
   * Get all conversations for a user
   */
  async getUserConversations(userId: string, userType: 'barber' | 'customer') {
    try {
      const result = await pool.query(`
        SELECT DISTINCT ON (b.id)
          b.id as booking_id,
          b.status,
          b.service_type,
          b.booking_date,
          b.booking_time,
          CASE 
            WHEN $2 = 'barber' THEN customer_u.name
            ELSE barber_u.name
          END as other_party_name,
          CASE 
            WHEN $2 = 'barber' THEN b.customer_id
            ELSE ba.user_id
          END as other_party_id,
          (SELECT message FROM booking_messages 
           WHERE booking_id = b.id 
           ORDER BY created_at DESC LIMIT 1) as last_message,
          (SELECT created_at FROM booking_messages 
           WHERE booking_id = b.id 
           ORDER BY created_at DESC LIMIT 1) as last_message_at,
          (SELECT COUNT(*) FROM booking_messages 
           WHERE booking_id = b.id 
           AND sender_id != $1
           AND read = false) as unread_count
        FROM bookings b
        LEFT JOIN barbers ba ON b.barber_id = ba.barber_id
        LEFT JOIN users barber_u ON ba.user_id = barber_u.id
        LEFT JOIN users customer_u ON b.customer_id = customer_u.id
        WHERE ($2 = 'barber' AND ba.user_id = $1)
           OR ($2 = 'customer' AND b.customer_id = $1)
        ORDER BY b.id, last_message_at DESC NULLS LAST
      `, [userId, userType]);

      return result.rows.map(row => ({
        bookingId: row.booking_id,
        status: row.status,
        serviceType: row.service_type,
        bookingDate: row.booking_date,
        bookingTime: row.booking_time,
        otherParty: {
          id: row.other_party_id,
          name: row.other_party_name,
        },
        lastMessage: row.last_message,
        lastMessageAt: row.last_message_at,
        unreadCount: parseInt(row.unread_count) || 0,
      }));
    } catch (error) {
      logger.error('Error getting user conversations:', error);
      throw error;
    }
  }

  /**
   * Mark all messages in a conversation as read
   */
  async markConversationAsRead(bookingId: string, userId: string): Promise<void> {
    try {
      await pool.query(`
        UPDATE booking_messages
        SET read = true, read_at = NOW()
        WHERE booking_id = $1
          AND sender_id != $2
          AND read = false
      `, [bookingId, userId]);
    } catch (error) {
      logger.error('Error marking conversation as read:', error);
      throw error;
    }
  }
}

export const bookingMessagingService = new BookingMessagingService();

