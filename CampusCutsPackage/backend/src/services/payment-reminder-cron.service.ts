/**
 * Payment Reminder Cron Service
 * 
 * Sends reminder emails to consumers when their completed booking
 * has been awaiting payment for a specified period (default: 1 hour).
 * 
 * Schedule: Runs every 15 minutes to catch bookings awaiting payment.
 */

import cron from 'node-cron';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { sendPaymentReminderEmail } from './email.service';

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

export class PaymentReminderCronService {
  private job: cron.ScheduledTask | null = null;
  private isRunning = false;

  // How long to wait after completion before sending reminder (in hours)
  private readonly REMINDER_DELAY_HOURS = 1;

  /**
   * Start the payment reminder cron job
   * Runs every 15 minutes to check for bookings awaiting payment
   */
  start(): void {
    if (this.job) {
      logger.warn('Payment reminder cron job is already running');
      return;
    }

    // Run every 15 minutes
    this.job = cron.schedule('*/15 * * * *', async () => {
      await this.processPaymentReminders();
    });

    logger.info('💳 Payment reminder cron job started (runs every 15 minutes)');
  }

  /**
   * Stop the payment reminder cron job
   */
  stop(): void {
    if (this.job) {
      this.job.stop();
      this.job = null;
      logger.info('Payment reminder cron job stopped');
    }
  }

  /**
   * Process payment reminders
   * Finds bookings that have been in COMPLETED status (awaiting payment)
   * for at least REMINDER_DELAY_HOURS and sends reminder emails
   */
  async processPaymentReminders(): Promise<void> {
    if (this.isRunning) {
      logger.debug('Payment reminder job already running, skipping...');
      return;
    }

    this.isRunning = true;
    const startTime = Date.now();
    let emailsSent = 0;
    let emailsFailed = 0;

    try {
      logger.debug('Checking for bookings awaiting payment...');

      // Find bookings that:
      // 1. Are in 'COMPLETED' status (service done, awaiting payment)
      // 2. Were completed at least REMINDER_DELAY_HOURS ago
      // 3. Have not already had a payment reminder sent
      // 4. Consumer has email_notifications enabled (or default true if not set)
      const result = await pool.query(`
        SELECT 
          b.id,
          b."consumerId",
          b."barberId",
          b."serviceType",
          b."priceUsdCents",
          b."requestedAt" as scheduled_time,
          b."completedAt" as completed_time,
          b.status,
          c.location,
          c.service_name,
          consumer.email as consumer_email,
          consumer.first_name as consumer_first_name,
          consumer.last_name as consumer_last_name,
          consumer.notification_preferences as consumer_notification_preferences,
          barber_user.first_name as barber_first_name,
          barber_user.last_name as barber_last_name,
          COALESCE(campus.timezone, 'America/Los_Angeles') as campus_timezone
        FROM bookings b
        LEFT JOIN conversations c ON c.booking_id = b.id
        LEFT JOIN users consumer ON b."consumerId" = consumer.id
        LEFT JOIN barbers barber ON b."barberId" = barber.id
        LEFT JOIN users barber_user ON barber."userId" = barber_user.id
        LEFT JOIN campuses campus ON barber_user."campusId" = campus.id
        WHERE b.status = 'COMPLETED'
          AND b."completedAt" IS NOT NULL
          AND b."completedAt" < NOW() - INTERVAL '${this.REMINDER_DELAY_HOURS} hours'
          AND b.payment_reminder_sent IS NOT TRUE
          AND consumer.email IS NOT NULL
      `);

      if (result.rows.length === 0) {
        logger.debug('No bookings found needing payment reminders');
        this.isRunning = false;
        return;
      }

      logger.info(`Found ${result.rows.length} bookings needing payment reminders`);

      for (const booking of result.rows) {
        try {
          // Check if consumer has email_notifications enabled
          const prefs = booking.consumer_notification_preferences || {};
          const emailEnabled = prefs.email_notifications !== false; // Default to true

          if (!emailEnabled) {
            logger.debug(`Skipping payment reminder for booking ${booking.id} - consumer has disabled email notifications`);
            await this.markPaymentReminderSent(booking.id);
            continue;
          }

          // Get service display name
          const serviceName = booking.service_name || formatServiceType(booking.serviceType) || 'Haircut';

          // Calculate hours awaiting payment
          const completedTime = new Date(booking.completed_time);
          const hoursAwaiting = Math.floor((Date.now() - completedTime.getTime()) / (1000 * 60 * 60));

          // Format date and time using the barber's campus timezone
          const campusTimezone = booking.campus_timezone || 'America/Los_Angeles';
          const completedDate = completedTime.toLocaleDateString('en-US', {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            timeZone: campusTimezone
          });
          const completedTimeStr = completedTime.toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true,
            timeZone: campusTimezone
          });

          // Build email details
          const emailDetails = {
            bookingId: booking.id.toString(),
            consumerEmail: booking.consumer_email,
            consumerName: `${booking.consumer_first_name || ''} ${booking.consumer_last_name || ''}`.trim() || 'Customer',
            barberName: `${booking.barber_first_name || ''} ${booking.barber_last_name || ''}`.trim() || 'Your Barber',
            serviceName,
            price: (booking.priceUsdCents || 0) / 100,
            completedDate,
            completedTime: completedTimeStr,
            location: booking.location,
            hoursAwaiting
          };

          // Send the payment reminder email
          await sendPaymentReminderEmail(emailDetails);

          // Mark reminder as sent
          await this.markPaymentReminderSent(booking.id);

          emailsSent++;
          logger.info(`✅ Payment reminder sent for booking ${booking.id} to ${booking.consumer_email}`);

        } catch (error: any) {
          emailsFailed++;
          logger.error(`Failed to send payment reminder for booking ${booking.id}:`, error.message);
        }
      }

      const duration = Date.now() - startTime;
      logger.info(`💳 Payment reminders processed: ${emailsSent} sent, ${emailsFailed} failed (${duration}ms)`);

    } catch (error: any) {
      logger.error('Error processing payment reminders:', error.message);
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * Mark a booking's payment reminder as sent
   */
  private async markPaymentReminderSent(bookingId: number | string): Promise<void> {
    try {
      // First, ensure the payment_reminder_sent column exists
      await pool.query(`
        ALTER TABLE bookings ADD COLUMN IF NOT EXISTS payment_reminder_sent BOOLEAN DEFAULT FALSE
      `);

      // Then update the booking
      await pool.query(
        'UPDATE bookings SET payment_reminder_sent = TRUE WHERE id = $1',
        [bookingId]
      );
    } catch (error: any) {
      logger.error(`Failed to mark payment reminder sent for booking ${bookingId}:`, error.message);
    }
  }

  /**
   * Run reminders manually (for testing)
   */
  async runManually(): Promise<{ sent: number; failed: number }> {
    await this.processPaymentReminders();
    return { sent: 0, failed: 0 }; // Return placeholder - actual counts logged
  }
}

// Singleton instance
export const paymentReminderCronService = new PaymentReminderCronService();

