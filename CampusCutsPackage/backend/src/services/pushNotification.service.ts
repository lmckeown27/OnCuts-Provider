/**
 * Push Notification Service for CampusCuts
 * Transferred from CampusKinect with CampusCuts adaptations
 * 
 * Handles:
 * - iOS push notifications (APN)
 * - Android push notifications (FCM)
 * - Booking confirmations and reminders
 * - Chat message notifications
 * - Badge management
 */

import { pool } from '../database/connection';

// Optional mobile dependencies - gracefully handle if not installed
let apn: any, admin: any;
try {
  apn = require('apn');
} catch (error) {
  console.log('📱 APN module not installed - iOS push notifications disabled');
}

try {
  admin = require('firebase-admin');
} catch (error) {
  console.log('📱 Firebase Admin module not installed - Android push notifications disabled');
}

interface NotificationData {
  title: string;
  body: string;
  type: string;
  category?: string;
  sound?: string;
  badge?: number;
  data?: Record<string, any>;
}

interface DeviceResult {
  platform: string;
  token: string;
  result?: any;
  error?: string;
}

class PushNotificationService {
  private apnProvider: any = null;
  private fcmApp: any = null;

  constructor() {
    this.initializeServices();
  }

  private initializeServices() {
    console.log('📱 Initializing push notification services...');

    // Initialize Apple Push Notification service
    if (apn && process.env.APN_KEY_ID && process.env.APN_TEAM_ID && process.env.APN_PRIVATE_KEY) {
      try {
        const fs = require('fs');
        const path = require('path');

        let privateKey: string;

        // Check if APN_PRIVATE_KEY is file path or actual key content
        if (process.env.APN_PRIVATE_KEY.includes('BEGIN PRIVATE KEY')) {
          privateKey = process.env.APN_PRIVATE_KEY.replace(/\\n/g, '\n');
          console.log('📱 Using APN private key from environment variable');
        } else {
          const keyPath = path.resolve(process.cwd(), process.env.APN_PRIVATE_KEY);
          console.log('📱 Reading APN private key from file:', keyPath);

          if (!fs.existsSync(keyPath)) {
            throw new Error(`APN private key file not found: ${keyPath}`);
          }

          privateKey = fs.readFileSync(keyPath, 'utf8');
          console.log('✅ APN private key file read successfully');
        }

        // APN sandbox vs production must match the app build (Xcode debug → sandbox; TestFlight/App Store → production).
        // Set APN_PRODUCTION=true|false explicitly. If unset, we fall back to NODE_ENV === 'production'.
        // WARNING: PM2 often sets NODE_ENV=production even when your .env says development — that forces
        // the production APN gateway and breaks Xcode debug tokens (BadDeviceToken). Fix: export
        // APN_PRODUCTION=false in ecosystem.config.cjs env {} or pm2 start --env.
        const apnProduction =
          process.env.APN_PRODUCTION === 'true'
            ? true
            : process.env.APN_PRODUCTION === 'false'
              ? false
              : process.env.NODE_ENV === 'production';

        const apnOptions = {
          token: {
            key: privateKey,
            keyId: process.env.APN_KEY_ID,
            teamId: process.env.APN_TEAM_ID,
          },
          production: apnProduction,
        };

        this.apnProvider = new apn.Provider(apnOptions);
        console.log(
          `✅ APN Provider initialized (${apnProduction ? 'PRODUCTION api.push.apple.com' : 'SANDBOX api.sandbox.push.apple.com'}) ` +
            `[APN_PRODUCTION=${JSON.stringify(process.env.APN_PRODUCTION)}, NODE_ENV=${JSON.stringify(process.env.NODE_ENV)}]`
        );
      } catch (error: any) {
        console.error('❌ Failed to initialize APN Provider:', error.message);
        this.apnProvider = null;
      }
    } else {
      console.log('❌ APN Provider not initialized - missing environment variables');
    }

    // Initialize Firebase Cloud Messaging
    if (admin && process.env.FIREBASE_SERVICE_ACCOUNT) {
      try {
        const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);

        this.fcmApp = admin.initializeApp(
          {
            credential: admin.credential.cert(serviceAccount),
          },
          'campuscuts-mobile'
        );

        console.log('✅ FCM initialized');
      } catch (error: any) {
        console.error('❌ FCM initialization failed:', error.message);
        this.fcmApp = null;
      }
    } else {
      console.log('❌ FCM not initialized - missing FIREBASE_SERVICE_ACCOUNT');
    }
  }

  /**
   * Unread messages (from others) + barber pending inbound requests.
   * Does **not** count the consumer’s own outgoing PENDING booking requests (those are not “notifications” to the sender).
   * Used for APNs badge and kept in sync with push payloads.
   */
  async getCombinedBadgeCount(userId: string | number): Promise<number> {
    try {
      const result = await pool.query(
        `SELECT (
            (SELECT COUNT(*)::int FROM messages m
             JOIN conversations c ON m.conversation_id = c.id
             WHERE (c.user1_id::text = $1::text OR c.user2_id::text = $1::text)
             AND m.sender_id::text != $1::text AND m.is_read = false)
          + (SELECT COUNT(*)::int FROM bookings b
             INNER JOIN barbers br ON b."barberId" = br.id
             WHERE br."userId"::text = $1::text AND b.status = 'PENDING')
        ) AS count`,
        [String(userId)]
      );
      return Math.min(9999, Math.max(0, parseInt(result.rows[0]?.count ?? '0', 10)));
    } catch (error) {
      console.error('📱 getCombinedBadgeCount failed:', error);
      return 1;
    }
  }

  /**
   * Send notification to a user
   */
  async sendNotification(userId: string | number, notification: NotificationData): Promise<any> {
    try {
      let n: NotificationData = { ...notification };
      if (!(n.type === 'badge_update' && n.badge === 0)) {
        n.badge = await this.getCombinedBadgeCount(userId);
      }

      console.log(`📱 Sending notification to user ${userId}:`, {
        title: n.title,
        body: n.body,
        type: n.type,
        badge: n.badge,
      });

      // Get user's registered devices.
      //
      // We pull two pieces of metadata alongside the token:
      //   * `bundle_id` — the bundle the device sent at `register-device` time (migration 029).
      //     When present this is the **source of truth** for the APN `apns-topic` header.
      //   * `is_barber`  — whether the user owning the device has an active row in `barbers`.
      //     Only consulted when `bundle_id IS NULL` (legacy rows that registered before
      //     migration 029). Lets us pick `PROVIDER_APN_BUNDLE_ID` vs `CONSUMER_APN_BUNDLE_ID`
      //     without forcing every user to reinstall + re-register the device.
      //
      // Without the LEFT JOIN, legacy provider devices keep getting topic
      // `com.campuscuts.ios`, which APN rejects as `DeviceTokenNotForTopic` for the provider
      // bundle `Liam.Intera---Provider` (note: three hyphens, must not be normalized).
      const devices = await pool.query(
        `SELECT md.device_token,
                md.platform,
                md.bundle_id,
                (b.id IS NOT NULL) AS is_barber
           FROM mobile_devices md
           LEFT JOIN barbers b
             ON b."userId" = md.user_id AND b."isActive" = true
          WHERE md.user_id = $1 AND md.is_active = true`,
        [userId]
      );

      console.log(`📱 Found ${devices.rows.length} registered devices`);

      if (devices.rows.length === 0) {
        return { success: false, reason: 'No registered devices' };
      }

      const results: DeviceResult[] = [];

      for (const device of devices.rows) {
        try {
          if (device.platform === 'ios' && this.apnProvider) {
            const result = await this.sendIOSNotification(
              device.device_token,
              n,
              device.bundle_id,
              device.is_barber === true
            );
            results.push({ platform: 'ios', token: device.device_token, result });
          } else if (device.platform === 'android' && this.fcmApp) {
            const result = await this.sendAndroidNotification(device.device_token, n);
            results.push({ platform: 'android', token: device.device_token, result });
          }
        } catch (deviceError: any) {
          console.error(`❌ Error sending to device:`, deviceError);
          results.push({
            platform: device.platform,
            token: device.device_token,
            error: deviceError.message,
          });
        }
      }

      // Log notification
      await this.logNotification(userId, n, results);

      return { success: true, results };
    } catch (error) {
      console.error('❌ Push notification error:', error);
      return { success: false, error };
    }
  }

  /**
   * Send iOS notification via APN.
   *
   * Topic resolution (in order of trust). Each step yields a bundle-id string that is sent
   * **verbatim** as the APN `apns-topic` header. The string is never lower-cased, normalized,
   * URL-encoded, or run through any `replace()` — Apple compares the topic byte-for-byte
   * against the device's app bundle id, and CampusCuts's provider bundle (`Liam.Intera---Provider`)
   * contains a literal three-hyphen run that any sanitation would corrupt.
   *
   *   1. `deviceBundleId` — the exact value the client sent at `register-device` time
   *      (`mobile_devices.bundle_id`). Set per-device, so it works for any future bundle
   *      without code changes.
   *   2. `process.env.PROVIDER_APN_BUNDLE_ID` — used when `deviceBundleId` is NULL **and**
   *      the device's owner is an active barber. Handles legacy provider devices that
   *      registered before migration 029 added the column.
   *   3. `process.env.CONSUMER_APN_BUNDLE_ID` — used when `deviceBundleId` is NULL **and**
   *      the device's owner is not a barber. Handles legacy consumer devices.
   *   4. `process.env.APN_BUNDLE_ID` — single-bundle legacy variable, kept for backwards
   *      compatibility with the original consumer-only deployment.
   *   5. Hardcoded `com.campuscuts.ios` — final safety net so the topic is never empty.
   */
  private async sendIOSNotification(
    deviceToken: string,
    notification: NotificationData,
    deviceBundleId?: string | null,
    deviceIsBarber: boolean = false
  ): Promise<any> {
    if (!this.apnProvider) {
      throw new Error('APN Provider not initialized');
    }

    const silentBadgeOnly =
      notification.type === 'badge_update' && notification.data?.silent === true;

    const note = new apn.Notification();
    note.expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour
    note.badge = notification.badge ?? 0;

    // Resolve the topic. We deliberately do **not** call `.trim()`, `.replace()`, or any
    // normalization on the stored device value — only on env-var fallbacks (defensive against
    // hand-edited `.env` files that may have trailing whitespace). The `Liam.Intera---Provider`
    // three-hyphen run is preserved end-to-end.
    const envProvider = (process.env.PROVIDER_APN_BUNDLE_ID || '').trim();
    const envConsumer = (process.env.CONSUMER_APN_BUNDLE_ID || '').trim();
    const envLegacy = (process.env.APN_BUNDLE_ID || '').trim();

    let topic: string;
    let topicSource: string;
    if (typeof deviceBundleId === 'string' && deviceBundleId.length > 0) {
      // Use the stored value verbatim. No mutation.
      topic = deviceBundleId;
      topicSource = 'device.bundle_id';
    } else if (deviceIsBarber && envProvider.length > 0) {
      topic = envProvider;
      topicSource = 'PROVIDER_APN_BUNDLE_ID';
    } else if (!deviceIsBarber && envConsumer.length > 0) {
      topic = envConsumer;
      topicSource = 'CONSUMER_APN_BUNDLE_ID';
    } else if (envLegacy.length > 0) {
      topic = envLegacy;
      topicSource = 'APN_BUNDLE_ID';
    } else {
      topic = 'com.campuscuts.ios';
      topicSource = 'hardcoded-fallback';
    }
    note.topic = topic;

    // Audit guard: if both the device value and a matching env var are present, they should
    // agree. Disagreement indicates either an env-var typo or a stale device row, both of
    // which silently break delivery — surface them at warn level so they're greppable.
    const envForRole = deviceIsBarber ? envProvider : envConsumer;
    if (
      typeof deviceBundleId === 'string' &&
      deviceBundleId.length > 0 &&
      envForRole.length > 0 &&
      deviceBundleId !== envForRole
    ) {
      console.warn(
        `📱 APN topic disagreement: device.bundle_id="${deviceBundleId}" but ` +
          `${deviceIsBarber ? 'PROVIDER_APN_BUNDLE_ID' : 'CONSUMER_APN_BUNDLE_ID'}="${envForRole}" — ` +
          `using device value, but check your env vars`
      );
    }

    if (silentBadgeOnly) {
      // Badge-only: do not set alert/sound — avoids empty banners; icon badge still updates
      note.sound = undefined;
    } else {
      note.sound = notification.sound || 'default';
      note.alert = {
        title: notification.title,
        body: notification.body,
      };
    }

    note.payload = {
      ...notification.data,
      type: notification.type,
      category: notification.category,
    };

    if (notification.category) {
      note.category = notification.category;
    }

    console.log(
      `📱 APN send → topic=${topic} (source=${topicSource}, isBarber=${deviceIsBarber}) ` +
        `token=…${String(deviceToken).slice(-8)} type=${notification.type}`
    );

    const result = await this.apnProvider.send(note, deviceToken);

    // Only deactivate on 410 (Unregistered). Status 400 (BadDeviceToken) is often sandbox/production mismatch —
    // the same token is still valid in the other environment; deactivating it breaks pushes until re-register.
    if (result.failed && result.failed.length > 0) {
      for (const failure of result.failed) {
        const reason =
          (failure as any).response?.reason ||
          (failure as any).reason ||
          (failure as any).error ||
          JSON.stringify(failure);
        if (failure.status === '410') {
          console.warn(
            `📱 APN permanent failure for token …${String(deviceToken).slice(-8)} status=410 reason=${reason}`
          );
          await this.deactivateDevice(deviceToken, `APN 410: ${reason}`);
        } else {
          console.warn(
            `📱 APN send failed (not deactivating token) status=${failure.status} reason=${reason}`
          );
        }
      }
    }

    return result;
  }

  /**
   * Send Android notification via FCM
   */
  private async sendAndroidNotification(
    deviceToken: string,
    notification: NotificationData
  ): Promise<any> {
    if (!this.fcmApp) {
      throw new Error('FCM not initialized');
    }

    const message = {
      token: deviceToken,
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data || {},
      android: {
        priority: 'high' as const,
        notification: {
          sound: notification.sound || 'default',
          channelId: 'campuscuts_notifications',
        },
      },
    };

    try {
      const result = await admin.messaging(this.fcmApp).send(message);
      return { success: true, messageId: result };
    } catch (error: any) {
      if (
        error.code === 'messaging/registration-token-not-registered' ||
        error.code === 'messaging/invalid-registration-token'
      ) {
        await this.deactivateDevice(deviceToken);
      }
      throw error;
    }
  }

  /**
   * Deactivate invalid device token
   */
  private async deactivateDevice(deviceToken: string): Promise<void> {
    try {
      await pool.query('UPDATE mobile_devices SET is_active = false WHERE device_token = $1', [
        deviceToken,
      ]);
      console.log(`Deactivated invalid device token`);
    } catch (error) {
      console.error('Error deactivating device:', error);
    }
  }

  /**
   * Log notification for analytics
   */
  private async logNotification(
    userId: string | number,
    notification: NotificationData,
    results: DeviceResult[]
  ): Promise<void> {
    try {
      await pool.query(
        `INSERT INTO notification_logs (user_id, title, body, type, results, created_at)
         VALUES ($1, $2, $3, $4, $5, NOW())`,
        [userId, notification.title, notification.body, notification.type || 'general', JSON.stringify(results)]
      );
    } catch (error) {
      console.error('Error logging notification:', error);
    }
  }

  // MARK: - Notification Templates

  /**
   * Send booking confirmation notification
   */
  async sendBookingConfirmationNotification(
    userId: string | number,
    barberName: string,
    service: string,
    dateTime: string,
    bookingId: string | number
  ): Promise<any> {
    const notification: NotificationData = {
      title: 'Booking Confirmed!',
      body: `${barberName} confirmed your ${service} appointment for ${dateTime}`,
      type: 'booking_confirmation',
      category: 'BOOKING_CATEGORY',
      sound: 'default',
      badge: 1,
      data: {
        type: 'booking_confirmation',
        action: 'open_booking_detail',
        bookingId: String(bookingId),
      },
    };

    return await this.sendNotification(userId, notification);
  }

  /**
   * Consumer: barber accepted their booking request (deep-link to booking detail).
   */
  async sendBookingAcceptedNotification(
    userId: string | number,
    barberName: string,
    bookingId: string | number
  ): Promise<any> {
    const notification: NotificationData = {
      title: 'Booking Accepted!',
      body: `${barberName} accepted your booking request`,
      type: 'booking_accepted',
      category: 'BOOKING_CATEGORY',
      sound: 'default',
      badge: 1,
      data: {
        type: 'booking_accepted',
        action: 'open_booking_detail',
        bookingId: String(bookingId),
      },
    };

    return await this.sendNotification(userId, notification);
  }

  /**
   * Other party cancelled the booking — deep-link to booking detail (same as confirmation / reminder payloads).
   */
  async sendBookingCancelledNotification(
    userId: string | number,
    title: string,
    body: string,
    bookingId: string | number,
    extraData?: Record<string, any>
  ): Promise<any> {
    const notification: NotificationData = {
      title,
      body,
      type: 'booking_cancelled',
      category: 'BOOKING_CATEGORY',
      sound: 'default',
      badge: 1,
      data: {
        type: 'booking_cancelled',
        action: 'open_booking_detail',
        bookingId: String(bookingId),
        ...(extraData || {}),
      },
    };

    return await this.sendNotification(userId, notification);
  }

  /**
   * Send appointment reminder notification (scheduled push at 24h / 12h / 3h / 1h before start).
   */
  async sendAppointmentReminderNotification(
    userId: string | number,
    barberName: string,
    service: string,
    hoursUntil: number,
    bookingId: string | number,
    reminderStage?: '24h' | '12h' | '3h' | '1h'
  ): Promise<any> {
    const title =
      hoursUntil === 1 ? 'Appointment in 1 hour' : `Appointment in ${hoursUntil} hours`;
    const notification: NotificationData = {
      title,
      body: `${service} with ${barberName} is coming up soon!`,
      type: 'booking_reminder',
      category: 'REMINDER_CATEGORY',
      sound: 'default',
      badge: 1,
      data: {
        type: 'booking_reminder',
        action: 'open_booking_detail',
        bookingId: String(bookingId),
        hoursUntil: String(hoursUntil),
        ...(reminderStage ? { reminderStage } : {}),
      },
    };

    return await this.sendNotification(userId, notification);
  }

  /**
   * Send chat message notification
   */
  async sendMessageNotification(
    recipientId: string | number,
    senderName: string,
    messagePreview: string,
    conversationId: string | number
  ): Promise<any> {
    // Unread count for payload only; sendNotification() sets APNs badge to combined (messages + bookings)
    let unreadCount = 1;
    try {
      const result = await pool.query(
        `SELECT COUNT(*)::int as count FROM messages m
         JOIN conversations c ON m.conversation_id = c.id
         WHERE (c.user1_id::text = $1::text OR c.user2_id::text = $1::text)
         AND m.sender_id::text != $1::text AND m.is_read = false`,
        [String(recipientId)]
      );
      unreadCount = parseInt(result.rows[0]?.count || '1', 10);
    } catch (error) {
      console.error('Failed to get unread count:', error);
    }

    const notification: NotificationData = {
      title: senderName,
      body: messagePreview.length > 50 ? `${messagePreview.substring(0, 50)}...` : messagePreview,
      type: 'message',
      category: 'MESSAGE_CATEGORY',
      sound: 'default',
      badge: 1,
      data: {
        type: 'message',
        action: 'open_chat',
        conversationId: String(conversationId),
        unreadCount,
      },
    };

    return await this.sendNotification(recipientId, notification);
  }

  /**
   * Send payment received notification (for barbers)
   */
  async sendPaymentReceivedNotification(
    barberId: string | number,
    amount: number,
    studentName: string
  ): Promise<any> {
    const notification: NotificationData = {
      title: 'Payment Received!',
      body: `You received $${amount.toFixed(2)} from ${studentName}`,
      type: 'payment_received',
      category: 'PAYMENT_CATEGORY',
      sound: 'default',
      badge: 1,
      data: {
        type: 'payment_received',
        action: 'open_earnings',
      },
    };

    return await this.sendNotification(barberId, notification);
  }

  /**
   * Send review notification (for barbers)
   */
  async sendReviewNotification(
    barberId: string | number,
    studentName: string,
    rating: number
  ): Promise<any> {
    const notification: NotificationData = {
      title: 'New Review!',
      body: `${studentName} rated you ${rating} stars`,
      type: 'review',
      category: 'REVIEW_CATEGORY',
      sound: 'default',
      badge: 1,
      data: {
        type: 'review',
        action: 'open_reviews',
      },
    };

    return await this.sendNotification(barberId, notification);
  }

  /**
   * Send system notification
   */
  async sendSystemNotification(
    userId: string | number,
    title: string,
    body: string,
    data: Record<string, any> = {}
  ): Promise<any> {
    const notification: NotificationData = {
      title,
      body,
      type: 'system',
      category: 'SYSTEM_CATEGORY',
      sound: 'default',
      data: {
        type: 'system',
        ...data,
      },
    };

    return await this.sendNotification(userId, notification);
  }

  /**
   * Update badge count
   */
  async updateBadgeCount(userId: string | number, badgeCount: number | null = null): Promise<any> {
    try {
      if (badgeCount === null) {
        badgeCount = await this.getCombinedBadgeCount(userId);
      }

      const notification: NotificationData = {
        title: '',
        body: '',
        type: 'badge_update',
        badge: badgeCount,
        data: {
          type: 'badge_update',
          silent: true,
        },
      };

      return await this.sendNotification(userId, notification);
    } catch (error) {
      console.error('Failed to update badge count:', error);
      return { success: false, error };
    }
  }

  /**
   * Clear badge
   */
  async clearBadge(userId: string | number): Promise<any> {
    return await this.updateBadgeCount(userId, 0);
  }

  /**
   * Get notification preferences
   */
  async getNotificationPreferences(userId: string | number): Promise<any> {
    try {
      const result = await pool.query(
        'SELECT notification_preferences FROM users WHERE id = $1',
        [userId]
      );

      if (result.rows.length === 0) {
        return this.getDefaultPreferences();
      }

      return result.rows[0].notification_preferences || this.getDefaultPreferences();
    } catch (error) {
      console.error('Error getting notification preferences:', error);
      return this.getDefaultPreferences();
    }
  }

  /**
   * Default notification preferences
   */
  private getDefaultPreferences() {
    return {
      bookings: true,
      messages: true,
      payments: true,
      reviews: true,
      reminders: true,
      system: true,
      marketing: false,
      quietHours: {
        enabled: false,
        start: '22:00',
        end: '08:00',
      },
    };
  }

  /**
   * Update notification preferences
   */
  async updateNotificationPreferences(userId: string | number, preferences: any): Promise<any> {
    try {
      await pool.query('UPDATE users SET notification_preferences = $1 WHERE id = $2', [
        JSON.stringify(preferences),
        userId,
      ]);
      return { success: true };
    } catch (error) {
      console.error('Error updating notification preferences:', error);
      return { success: false, error };
    }
  }

  /**
   * Check if user should receive notification
   */
  async shouldSendNotification(userId: string | number, notificationType: string): Promise<boolean> {
    try {
      const preferences = await this.getNotificationPreferences(userId);

      // Check if notification type is enabled
      if (!preferences[notificationType]) {
        return false;
      }

      // Check quiet hours
      if (preferences.quietHours && preferences.quietHours.enabled) {
        const now = new Date();
        const currentTime = now.toTimeString().slice(0, 5);

        const { start, end } = preferences.quietHours;

        if (start < end) {
          if (currentTime >= start || currentTime <= end) {
            return false;
          }
        } else {
          if (currentTime >= start && currentTime <= end) {
            return false;
          }
        }
      }

      return true;
    } catch (error) {
      console.error('Error checking notification preferences:', error);
      return true; // Default to sending
    }
  }
}

export default new PushNotificationService();

