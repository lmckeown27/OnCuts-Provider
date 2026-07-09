import admin from 'firebase-admin';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';

// Initialize Firebase Admin
const initializeFirebase = () => {
  try {
    if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_PRIVATE_KEY && process.env.FIREBASE_CLIENT_EMAIL) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        }),
      });
      logger.info('🔔 Firebase Admin initialized');
    } else {
      logger.warn('Firebase credentials not configured - push notifications disabled');
    }
  } catch (error) {
    logger.error('Failed to initialize Firebase:', error);
  }
};

initializeFirebase();

class NotificationService {
  /**
   * Send push notification to user
   */
  async sendPushNotification(params: {
    userId: string;
    title: string;
    body: string;
    data?: any;
  }): Promise<void> {
    try {
      const { userId, title, body, data } = params;

      // Get user's FCM token (would be stored in database)
      // For now, just log and save to notifications table
      
      await this.saveNotification({
        userId,
        type: 'push',
        title,
        message: body,
        data,
      });

      logger.info(`Push notification queued for user ${userId}`);

      // If Firebase is configured, send actual push
      // const message = {
      //   notification: { title, body },
      //   data,
      //   token: userFcmToken,
      // };
      // await admin.messaging().send(message);
    } catch (error) {
      logger.error('Failed to send push notification:', error);
    }
  }

  /**
   * Save notification to database
   */
  async saveNotification(params: {
    userId: string;
    type: string;
    title: string;
    message: string;
    data?: any;
  }): Promise<void> {
    try {
      const { userId, type, title, message, data } = params;

      await pool.query(
        `INSERT INTO notifications (user_id, type, title, message, data)
         VALUES ($1, $2, $3, $4, $5)`,
        [userId, type, title, message, JSON.stringify(data || {})]
      );

      logger.info(`Notification saved for user ${userId}`);
    } catch (error) {
      logger.error('Failed to save notification:', error);
    }
  }

  /**
   * Get user notifications
   */
  async getUserNotifications(userId: string, limit: number = 50): Promise<any[]> {
    try {
      const result = await pool.query(
        `SELECT * FROM notifications 
         WHERE user_id = $1 
         ORDER BY created_at DESC 
         LIMIT $2`,
        [userId, limit]
      );

      return result.rows;
    } catch (error) {
      logger.error('Failed to get notifications:', error);
      return [];
    }
  }

  /**
   * Mark notification as read
   */
  async markAsRead(notificationId: string, userId: string): Promise<void> {
    try {
      await pool.query(
        'UPDATE notifications SET is_read = TRUE WHERE id = $1 AND user_id = $2',
        [notificationId, userId]
      );
    } catch (error) {
      logger.error('Failed to mark notification as read:', error);
    }
  }

  /**
   * Send booking confirmation notification
   */
  async notifyBookingConfirmed(bookingId: number, clientId: string, barberName: string): Promise<void> {
    await this.sendPushNotification({
      userId: clientId,
      title: 'Booking Confirmed!',
      body: `${barberName} confirmed your appointment`,
      data: { bookingId: bookingId.toString(), type: 'booking_confirmed' },
    });
  }

  /**
   * Send booking cancelled notification
   */
  async notifyBookingCancelled(bookingId: number, recipientId: string, cancelledBy: string): Promise<void> {
    await this.sendPushNotification({
      userId: recipientId,
      title: 'Booking Cancelled',
      body: `Your appointment has been cancelled`,
      data: { bookingId: bookingId.toString(), type: 'booking_cancelled' },
    });
  }

  /**
   * Send review request notification
   */
  async notifyReviewRequest(bookingId: number, clientId: string, barberName: string): Promise<void> {
    await this.sendPushNotification({
      userId: clientId,
      title: 'How was your cut?',
      body: `Please review your experience with ${barberName}`,
      data: { bookingId: bookingId.toString(), type: 'review_request' },
    });
  }

  /**
   * Send new booking notification to barber
   */
  async notifyNewBooking(bookingId: number, barberId: string, clientName: string): Promise<void> {
    await this.sendPushNotification({
      userId: barberId,
      title: 'New Booking Request!',
      body: `${clientName} wants to book with you`,
      data: { bookingId: bookingId.toString(), type: 'new_booking' },
    });
  }
}

export default new NotificationService();

