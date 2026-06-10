/**
 * Barber Check-In Cron Service
 * 
 * Sends check-in emails to barbers when 1 hour has passed since their
 * scheduled booking time and they have not updated the booking status.
 * 
 * This prompts barbers to either:
 * - Mark the booking as complete (request payment)
 * - Edit the booking (reschedule)
 * - Cancel the booking (if unable to complete)
 * 
 * Schedule: Runs every 5 minutes to catch overdue bookings.
 */

import cron from 'node-cron';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { sendBarberCheckInEmail, sendBarber24HFollowupEmail, sendConsumerCheckInEmail } from './email.service';

/**
 * Helper to format service type: "HAIRCUT" -> "Haircut", "BEARD_TRIM" -> "Beard Trim"
 */
function formatServiceType(type: string): string {
  if (!type) return 'Haircut';
  return type
    .toLowerCase()
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

export class BarberCheckInCronService {
  private job: cron.ScheduledTask | null = null;
  private isRunning = false;

  /**
   * Start the barber check-in cron job
   * Runs every 5 minutes to check for overdue bookings
   */
  start(): void {
    if (this.job) {
      logger.warn('Barber check-in cron job is already running');
      return;
    }

    // Run every 5 minutes
    this.job = cron.schedule('*/5 * * * *', async () => {
      await this.processBarberCheckIns();
      await this.process24HourFollowups();
    });

    logger.info('📧 Barber check-in cron job started (runs every 5 minutes)');
  }

  /**
   * Stop the barber check-in cron job
   */
  stop(): void {
    if (this.job) {
      this.job.stop();
      this.job = null;
      logger.info('Barber check-in cron job stopped');
    }
  }

  /**
   * Process barber check-ins
   * Finds bookings that are more than 1 hour past their scheduled time
   * but still in 'accepted' status and sends check-in emails to barbers
   */
  async processBarberCheckIns(): Promise<void> {
    if (this.isRunning) {
      logger.debug('Barber check-in job already running, skipping...');
      return;
    }

    this.isRunning = true;
    const startTime = Date.now();
    let emailsSent = 0;
    let emailsFailed = 0;

    try {
      logger.debug('Checking for overdue bookings needing barber check-in...');

      // Ensure the barber_checkin_sent column exists
      await this.ensureColumnExists();

      // Find bookings that:
      // 1. Are in 'accepted' status (confirmed but not completed)
      // 2. Are more than 1 hour past their scheduled time (but not more than 48 hours to avoid spamming very old bookings)
      // 3. Have not already had a barber check-in email sent
      // 4. Barber has email notifications enabled (or default true if not set)
      const result = await pool.query(`
        SELECT 
          b.id,
          b."consumerId",
          b."barberId",
          b."serviceType",
          b."priceUsdCents",
          b."requestedAt" as scheduled_time,
          b.status,
          c.location,
          c.notes,
          c.service_name,
          consumer.first_name as consumer_first_name,
          consumer.last_name as consumer_last_name,
          consumer.email as consumer_email,
          consumer.notification_preferences as consumer_notification_preferences,
          barber_user.first_name as barber_first_name,
          barber_user.last_name as barber_last_name,
          barber_user.email as barber_email,
          barber_user.notification_preferences as barber_notification_preferences,
          COALESCE(campus.timezone, 'America/Los_Angeles') as campus_timezone
        FROM bookings b
        LEFT JOIN conversations c ON c.booking_id = b.id
        LEFT JOIN users consumer ON b."consumerId" = consumer.id
        LEFT JOIN barbers barber ON b."barberId" = barber.id
        LEFT JOIN users barber_user ON barber."userId" = barber_user.id
        LEFT JOIN campuses campus ON barber_user."campusId" = campus.id
        WHERE b.status = 'ACCEPTED'
          AND b."requestedAt" < NOW() - INTERVAL '1 hour'
          AND b."requestedAt" > NOW() - INTERVAL '48 hours'
          AND b.barber_checkin_sent IS NOT TRUE
          AND barber_user.email IS NOT NULL
      `);

      if (result.rows.length === 0) {
        logger.debug('No overdue bookings found needing barber check-in');
        this.isRunning = false;
        return;
      }

      logger.info(`Found ${result.rows.length} overdue bookings needing barber check-in`);

      for (const booking of result.rows) {
        try {
          // Check if barber has email notifications enabled
          const prefs = booking.barber_notification_preferences || {};
          const emailEnabled = prefs.email_notifications !== false; // Default to true
          const bookingNotificationsEnabled = prefs.bookings !== false; // Default to true

          if (!emailEnabled || !bookingNotificationsEnabled) {
            logger.debug(`Skipping check-in for booking ${booking.id} - barber has disabled email/booking notifications`);
            // Mark as sent so we don't keep checking
            await this.markCheckInSent(booking.id);
            continue;
          }

          // Get service display name
          // Prefer original service name from conversation, fallback to formatted enum
          const serviceName = booking.service_name || formatServiceType(booking.serviceType) || 'Haircut';

          // Format date and time using the barber's campus timezone
          const scheduledTime = new Date(booking.scheduled_time);
          const campusTimezone = booking.campus_timezone || 'America/Los_Angeles';
          const scheduledDate = scheduledTime.toLocaleDateString('en-US', {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            timeZone: campusTimezone
          });
          const scheduledTimeStr = scheduledTime.toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true,
            timeZone: campusTimezone
          });

          // Build email details
          const emailDetails = {
            bookingId: booking.id.toString(),
            serviceName,
            price: (booking.priceUsdCents || 0) / 100,
            scheduledDate,
            scheduledTime: scheduledTimeStr,
            location: booking.location,
            consumerName: `${booking.consumer_first_name || ''} ${booking.consumer_last_name || ''}`.trim() || 'Customer',
            barberName: `${booking.barber_first_name || ''} ${booking.barber_last_name || ''}`.trim() || 'Barber',
            barberEmail: booking.barber_email
          };

          // Send the barber check-in email
          await sendBarberCheckInEmail(emailDetails);
          emailsSent++;
          logger.info(`✅ Barber check-in email sent for booking ${booking.id} to ${booking.barber_email}`);

          // Send consumer check-in email if they have notifications enabled
          if (booking.consumer_email) {
            const consumerPrefs = booking.consumer_notification_preferences || {};
            const consumerEmailEnabled = consumerPrefs.email_notifications !== false;
            const consumerBookingNotifications = consumerPrefs.bookings !== false;

            if (consumerEmailEnabled && consumerBookingNotifications) {
              try {
                const consumerEmailDetails = {
                  bookingId: booking.id.toString(),
                  serviceName,
                  price: (booking.priceUsdCents || 0) / 100,
                  scheduledDate,
                  scheduledTime: scheduledTimeStr,
                  location: booking.location,
                  consumerName: `${booking.consumer_first_name || ''} ${booking.consumer_last_name || ''}`.trim() || 'Customer',
                  consumerEmail: booking.consumer_email,
                  barberName: `${booking.barber_first_name || ''} ${booking.barber_last_name || ''}`.trim() || 'Barber',
                };
                await sendConsumerCheckInEmail(consumerEmailDetails);
                emailsSent++;
                logger.info(`✅ Consumer check-in email sent for booking ${booking.id} to ${booking.consumer_email}`);
              } catch (consumerError: any) {
                logger.error(`Failed to send consumer check-in for booking ${booking.id}:`, consumerError.message);
              }
            }
          }

          // Mark check-in as sent
          await this.markCheckInSent(booking.id);

        } catch (error: any) {
          emailsFailed++;
          logger.error(`Failed to send barber check-in for booking ${booking.id}:`, error.message);
        }
      }

      const duration = Date.now() - startTime;
      logger.info(`📧 Barber check-ins processed: ${emailsSent} sent, ${emailsFailed} failed (${duration}ms)`);

    } catch (error: any) {
      logger.error('Error processing barber check-ins:', error.message);
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * Ensure the barber_checkin_sent and barber_24h_followup_sent columns exist in the bookings table
   */
  private async ensureColumnExists(): Promise<void> {
    try {
      await pool.query(`
        ALTER TABLE bookings ADD COLUMN IF NOT EXISTS barber_checkin_sent BOOLEAN DEFAULT FALSE
      `);
      await pool.query(`
        ALTER TABLE bookings ADD COLUMN IF NOT EXISTS barber_24h_followup_sent BOOLEAN DEFAULT FALSE
      `);
    } catch (error: any) {
      // Columns might already exist, that's fine
      logger.debug('Columns already exist or creation failed:', error.message);
    }
  }

  /**
   * Mark a booking's barber check-in as sent
   */
  private async markCheckInSent(bookingId: number | string): Promise<void> {
    try {
      await pool.query(
        'UPDATE bookings SET barber_checkin_sent = TRUE WHERE id = $1',
        [bookingId]
      );
    } catch (error: any) {
      logger.error(`Failed to mark barber check-in sent for booking ${bookingId}:`, error.message);
    }
  }

  /**
   * Mark a booking's 24-hour follow-up as sent
   */
  private async mark24HFollowupSent(bookingId: number | string): Promise<void> {
    try {
      await pool.query(
        'UPDATE bookings SET barber_24h_followup_sent = TRUE WHERE id = $1',
        [bookingId]
      );
    } catch (error: any) {
      logger.error(`Failed to mark 24h follow-up sent for booking ${bookingId}:`, error.message);
    }
  }

  /**
   * Process 24-hour follow-ups
   * Finds bookings that are more than 24 hours past their scheduled time
   * but still in 'accepted' status and sends urgent follow-up emails to barbers
   */
  async process24HourFollowups(): Promise<void> {
    let emailsSent = 0;
    let emailsFailed = 0;

    try {
      logger.debug('Checking for 24-hour overdue bookings needing follow-up...');

      // Ensure columns exist
      await this.ensureColumnExists();

      // Find bookings that:
      // 1. Are in 'accepted' status (confirmed but not completed)
      // 2. Are more than 24 hours past their scheduled time (but not more than 7 days to avoid spamming old bookings)
      // 3. Have already received the 1-hour check-in email (barber_checkin_sent = TRUE)
      // 4. Have not already had a 24-hour follow-up email sent
      // 5. Barber has email notifications enabled
      const result = await pool.query(`
        SELECT 
          b.id,
          b."consumerId",
          b."barberId",
          b."serviceType",
          b."priceUsdCents",
          b."requestedAt" as scheduled_time,
          b.status,
          c.location,
          c.notes,
          c.service_name,
          consumer.first_name as consumer_first_name,
          consumer.last_name as consumer_last_name,
          barber_user.first_name as barber_first_name,
          barber_user.last_name as barber_last_name,
          barber_user.email as barber_email,
          barber_user.notification_preferences as barber_notification_preferences,
          COALESCE(campus.timezone, 'America/Los_Angeles') as campus_timezone
        FROM bookings b
        LEFT JOIN conversations c ON c.booking_id = b.id
        LEFT JOIN users consumer ON b."consumerId" = consumer.id
        LEFT JOIN barbers barber ON b."barberId" = barber.id
        LEFT JOIN users barber_user ON barber."userId" = barber_user.id
        LEFT JOIN campuses campus ON barber_user."campusId" = campus.id
        WHERE b.status = 'ACCEPTED'
          AND b."requestedAt" < NOW() - INTERVAL '24 hours'
          AND b."requestedAt" > NOW() - INTERVAL '7 days'
          AND b.barber_checkin_sent = TRUE
          AND b.barber_24h_followup_sent IS NOT TRUE
          AND barber_user.email IS NOT NULL
      `);

      if (result.rows.length === 0) {
        logger.debug('No 24-hour overdue bookings found needing follow-up');
        return;
      }

      logger.info(`Found ${result.rows.length} bookings needing 24-hour follow-up`);

      for (const booking of result.rows) {
        try {
          // Check if barber has email notifications enabled
          const prefs = booking.barber_notification_preferences || {};
          const emailEnabled = prefs.email_notifications !== false;
          const bookingNotificationsEnabled = prefs.bookings !== false;

          if (!emailEnabled || !bookingNotificationsEnabled) {
            logger.debug(`Skipping 24h follow-up for booking ${booking.id} - barber has disabled notifications`);
            await this.mark24HFollowupSent(booking.id);
            continue;
          }

          // Get service display name
          const serviceName = booking.service_name || formatServiceType(booking.serviceType) || 'Haircut';

          // Format date and time using the barber's campus timezone
          const scheduledTime = new Date(booking.scheduled_time);
          const campusTimezone = booking.campus_timezone || 'America/Los_Angeles';
          const scheduledDate = scheduledTime.toLocaleDateString('en-US', {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            timeZone: campusTimezone
          });
          const scheduledTimeStr = scheduledTime.toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true,
            timeZone: campusTimezone
          });

          // Build email details
          const emailDetails = {
            bookingId: booking.id.toString(),
            serviceName,
            price: (booking.priceUsdCents || 0) / 100,
            scheduledDate,
            scheduledTime: scheduledTimeStr,
            location: booking.location,
            consumerName: `${booking.consumer_first_name || ''} ${booking.consumer_last_name || ''}`.trim() || 'Customer',
            barberName: `${booking.barber_first_name || ''} ${booking.barber_last_name || ''}`.trim() || 'Barber',
            barberEmail: booking.barber_email
          };

          // Send the 24-hour follow-up email
          await sendBarber24HFollowupEmail(emailDetails);

          // Mark follow-up as sent
          await this.mark24HFollowupSent(booking.id);

          emailsSent++;
          logger.info(`✅ 24h follow-up email sent for booking ${booking.id} to ${booking.barber_email}`);

        } catch (error: any) {
          emailsFailed++;
          logger.error(`Failed to send 24h follow-up for booking ${booking.id}:`, error.message);
        }
      }

      if (emailsSent > 0 || emailsFailed > 0) {
        logger.info(`📧 24h follow-ups processed: ${emailsSent} sent, ${emailsFailed} failed`);
      }

    } catch (error: any) {
      logger.error('Error processing 24h follow-ups:', error.message);
    }
  }

  /**
   * Run check-ins manually (for testing)
   */
  async runManually(): Promise<{ sent: number; failed: number }> {
    await this.processBarberCheckIns();
    return { sent: 0, failed: 0 }; // Return placeholder - actual counts logged
  }
}

// Singleton instance
export const barberCheckInCronService = new BarberCheckInCronService();

