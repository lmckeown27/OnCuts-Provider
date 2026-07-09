/**
 * Pending Booking Cron Service
 * 
 * Sends warning emails to barbers for pending bookings that haven't been accepted:
 * 
 * 1. 3 hours before scheduled time: First warning email
 * 2. 2 hours before scheduled time: Second warning email  
 * 3. 1 hour before scheduled time: Final/urgent warning email
 * 
 * NO auto-cancellation - barber must manually accept or decline.
 * 
 * Schedule: Runs every 5 minutes to catch pending bookings.
 */

import cron from 'node-cron';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { sendPendingBookingWarningEmail } from './email.service';

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

export class PendingBookingCronService {
  private job: cron.ScheduledTask | null = null;
  private isRunning = false;

  /**
   * Start the pending booking cron job
   * Runs every 5 minutes to check for pending bookings
   */
  start(): void {
    if (this.job) {
      logger.warn('Pending booking cron job is already running');
      return;
    }

    // Run every 5 minutes
    this.job = cron.schedule('*/5 * * * *', async () => {
      await this.processPendingWarnings();
    });

    logger.info('📧 Pending booking cron job started (runs every 5 minutes)');
  }

  /**
   * Stop the pending booking cron job
   */
  stop(): void {
    if (this.job) {
      this.job.stop();
      this.job = null;
      logger.info('Pending booking cron job stopped');
    }
  }

  /**
   * Ensure required columns exist in the bookings table
   */
  private async ensureColumnsExist(): Promise<void> {
    try {
      // Track which warning emails have been sent
      await pool.query(`
        ALTER TABLE bookings ADD COLUMN IF NOT EXISTS warning_3h_sent BOOLEAN DEFAULT FALSE
      `);
      await pool.query(`
        ALTER TABLE bookings ADD COLUMN IF NOT EXISTS warning_2h_sent BOOLEAN DEFAULT FALSE
      `);
      await pool.query(`
        ALTER TABLE bookings ADD COLUMN IF NOT EXISTS warning_1h_sent BOOLEAN DEFAULT FALSE
      `);
      // Keep legacy column for backwards compatibility
      await pool.query(`
        ALTER TABLE bookings ADD COLUMN IF NOT EXISTS pending_warning_sent BOOLEAN DEFAULT FALSE
      `);
    } catch (error: any) {
      logger.debug('Columns already exist or creation failed:', error.message);
    }
  }

  /**
   * Process pending booking warnings at 3h, 2h, and 1h before scheduled time
   * Sends warning emails to barber for PENDING bookings
   */
  async processPendingWarnings(): Promise<void> {
    if (this.isRunning) {
      logger.debug('Pending booking job already running, skipping...');
      return;
    }

    this.isRunning = true;
    let warningsSent = 0;

    try {
      logger.debug('Checking for pending bookings needing warnings...');

      await this.ensureColumnsExist();

      // Process each warning tier
      warningsSent += await this.processWarningTier(3, 'warning_3h_sent', 'in 3 hours');
      warningsSent += await this.processWarningTier(2, 'warning_2h_sent', 'in 2 hours');
      warningsSent += await this.processWarningTier(1, 'warning_1h_sent', 'in 1 hour');

      if (warningsSent > 0) {
        logger.info(`📧 Pending booking warnings processed: ${warningsSent} sent`);
      }

    } catch (error: any) {
      logger.error('Error processing pending booking warnings:', error.message);
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * Process warnings for a specific time tier
   * @param hoursBeforeMin - Minimum hours before appointment (exclusive lower bound)
   * @param columnName - Database column to track if this warning was sent
   * @param timeDescription - Human readable time for the warning message
   */
  private async processWarningTier(
    hoursBeforeMin: number,
    columnName: string,
    timeDescription: string
  ): Promise<number> {
    let warningsSent = 0;
    const hoursBeforeMax = hoursBeforeMin + 1;

    try {
      // Find PENDING bookings that:
      // 1. Are scheduled between hoursBeforeMin and hoursBeforeMax hours from now
      // 2. Have not already had this specific warning email sent
      // 3. Barber has email notifications enabled
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
        WHERE b.status = 'PENDING'
          AND b."requestedAt" > NOW() + INTERVAL '${hoursBeforeMin} hours'
          AND b."requestedAt" <= NOW() + INTERVAL '${hoursBeforeMax} hours'
          AND b.${columnName} IS NOT TRUE
          AND barber_user.email IS NOT NULL
      `);

      if (result.rows.length === 0) {
        logger.debug(`No pending bookings found needing ${hoursBeforeMin}-hour warning`);
        return 0;
      }

      logger.info(`Found ${result.rows.length} pending bookings needing ${hoursBeforeMin}-hour warning`);

      for (const booking of result.rows) {
        try {
          // Check if barber has email notifications enabled
          const prefs = booking.barber_notification_preferences || {};
          const emailEnabled = prefs.email_notifications !== false;
          const bookingNotificationsEnabled = prefs.bookings !== false;

          if (!emailEnabled || !bookingNotificationsEnabled) {
            logger.debug(`Skipping warning for booking ${booking.id} - barber has disabled notifications`);
            await this.markWarningSent(booking.id, columnName);
            continue;
          }

          const serviceName = booking.service_name || formatServiceType(booking.serviceType) || 'Haircut';
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

          const emailDetails = {
            bookingId: booking.id.toString(),
            serviceName,
            price: (booking.priceUsdCents || 0) / 100,
            scheduledDate,
            scheduledTime: scheduledTimeStr,
            location: booking.location,
            consumerName: `${booking.consumer_first_name || ''} ${booking.consumer_last_name || ''}`.trim() || 'Customer',
            barberName: `${booking.barber_first_name || ''} ${booking.barber_last_name || ''}`.trim() || 'Barber',
            barberEmail: booking.barber_email,
            // Pass urgency level for email customization
            hoursRemaining: hoursBeforeMin,
            timeDescription
          };

          await sendPendingBookingWarningEmail(emailDetails);
          await this.markWarningSent(booking.id, columnName);

          warningsSent++;
          logger.info(`✅ ${hoursBeforeMin}h warning sent for booking ${booking.id} to ${booking.barber_email}`);

        } catch (error: any) {
          logger.error(`Failed to send ${hoursBeforeMin}h warning for booking ${booking.id}:`, error.message);
        }
      }

    } catch (error: any) {
      logger.error(`Error processing ${hoursBeforeMin}-hour warnings:`, error.message);
    }

    return warningsSent;
  }

  /**
   * Mark a booking's warning as sent for a specific tier
   */
  private async markWarningSent(bookingId: number | string, columnName: string): Promise<void> {
    try {
      await pool.query(
        `UPDATE bookings SET ${columnName} = TRUE WHERE id = $1`,
        [bookingId]
      );
    } catch (error: any) {
      logger.error(`Failed to mark ${columnName} sent for booking ${bookingId}:`, error.message);
    }
  }

  /**
   * Run manually (for testing)
   */
  async runManually(): Promise<void> {
    await this.processPendingWarnings();
  }
}

// Singleton instance
export const pendingBookingCronService = new PendingBookingCronService();

