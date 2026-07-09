/**
 * Booking Reminder Cron Service
 *
 * - Email: ~1h before (consumer + barber), respects booking_reminders + email_notifications.
 * - Push: ~24h, ~12h, ~3h, ~1h before (consumer only), respects booking_reminders + push_notifications.
 *
 * Schedule: Runs every 5 minutes to catch bookings within each reminder window.
 */

import cron from 'node-cron';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { sendBookingReminderEmail, sendBarberReminderEmail } from './email.service';
import pushNotificationService from './pushNotification.service';

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

/** ~10 minute windows around each milestone so a 5-minute cron catches each once. */
const PUSH_REMINDER_STAGES = [
  {
    hoursUntil: 24,
    stage: '24h' as const,
    column: 'reminder_push_24h_sent',
    minInterval: '23 hours 50 minutes',
    maxInterval: '24 hours 10 minutes',
  },
  {
    hoursUntil: 12,
    stage: '12h' as const,
    column: 'reminder_push_12h_sent',
    minInterval: '11 hours 50 minutes',
    maxInterval: '12 hours 10 minutes',
  },
  {
    hoursUntil: 3,
    stage: '3h' as const,
    column: 'reminder_push_3h_sent',
    minInterval: '2 hours 50 minutes',
    maxInterval: '3 hours 10 minutes',
  },
  {
    hoursUntil: 1,
    stage: '1h' as const,
    column: 'reminder_push_1h_sent',
    minInterval: '55 minutes',
    maxInterval: '65 minutes',
  },
] as const;

export class BookingReminderCronService {
  private job: cron.ScheduledTask | null = null;
  private isRunning = false;
  private isPushRunning = false;

  /**
   * Start the booking reminder cron job
   * Runs every 5 minutes to check for upcoming bookings
   */
  start(): void {
    if (this.job) {
      logger.warn('Booking reminder cron job is already running');
      return;
    }

    this.job = cron.schedule('*/5 * * * *', async () => {
      await this.processBookingReminders();
      await this.processBookingPushReminders();
    });

    logger.info('📧 Booking reminder cron job started (email + push, runs every 5 minutes)');
  }

  /**
   * Stop the booking reminder cron job
   */
  stop(): void {
    if (this.job) {
      this.job.stop();
      this.job = null;
      logger.info('Booking reminder cron job stopped');
    }
  }

  /**
   * Process booking reminders
   * Finds bookings that are scheduled approximately 1 hour from now
   * and sends reminder emails to consumers who have booking_reminders enabled
   */
  async processBookingReminders(): Promise<void> {
    if (this.isRunning) {
      logger.debug('Booking reminder job already running, skipping...');
      return;
    }

    this.isRunning = true;
    const startTime = Date.now();
    let emailsSent = 0;
    let emailsFailed = 0;

    try {
      logger.debug('Checking for bookings needing reminders...');

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
          consumer.email as consumer_email,
          consumer.first_name as consumer_first_name,
          consumer.last_name as consumer_last_name,
          consumer.notification_preferences as consumer_notification_preferences,
          barber_user.first_name as barber_first_name,
          barber_user.last_name as barber_last_name,
          barber_user.email as barber_email,
          COALESCE(campus.timezone, 'America/Los_Angeles') as campus_timezone
        FROM bookings b
        LEFT JOIN conversations c ON c.booking_id = b.id
        LEFT JOIN users consumer ON b."consumerId" = consumer.id
        LEFT JOIN barbers barber ON b."barberId" = barber.id
        LEFT JOIN users barber_user ON barber."userId" = barber_user.id
        LEFT JOIN campuses campus ON barber_user."campusId" = campus.id
        WHERE b.status = 'ACCEPTED'
          AND b."requestedAt" BETWEEN NOW() + INTERVAL '55 minutes' AND NOW() + INTERVAL '65 minutes'
          AND b.reminder_sent IS NOT TRUE
          AND consumer.email IS NOT NULL
      `);

      if (result.rows.length === 0) {
        logger.debug('No bookings found needing email reminders');
        return;
      }

      logger.info(`Found ${result.rows.length} bookings needing reminders`);

      for (const booking of result.rows) {
        try {
          const prefs = booking.consumer_notification_preferences || {};
          const bookingRemindersEnabled = prefs.booking_reminders !== false;

          if (!bookingRemindersEnabled) {
            logger.debug(`Skipping reminder for booking ${booking.id} - consumer has disabled booking reminders`);
            await this.markReminderSent(booking.id);
            continue;
          }

          const emailEnabled = prefs.email_notifications !== false;
          if (!emailEnabled) {
            logger.debug(`Skipping reminder for booking ${booking.id} - consumer has disabled email notifications`);
            await this.markReminderSent(booking.id);
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
            timeZone: campusTimezone,
          });
          const scheduledTimeStr = scheduledTime.toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true,
            timeZone: campusTimezone,
          });

          const emailDetails = {
            bookingId: booking.id.toString(),
            serviceName,
            price: (booking.priceUsdCents || 0) / 100,
            scheduledDate,
            scheduledTime: scheduledTimeStr,
            location: booking.location,
            notes: booking.notes,
            consumerName: `${booking.consumer_first_name || ''} ${booking.consumer_last_name || ''}`.trim() || 'Customer',
            consumerEmail: booking.consumer_email,
            barberName: `${booking.barber_first_name || ''} ${booking.barber_last_name || ''}`.trim() || 'Your Barber',
            barberEmail: booking.barber_email || '',
          };

          await sendBookingReminderEmail(emailDetails);
          logger.info(`✅ Consumer reminder sent for booking ${booking.id} to ${booking.consumer_email}`);

          if (booking.barber_email) {
            try {
              await sendBarberReminderEmail(emailDetails);
              logger.info(`✅ Barber reminder sent for booking ${booking.id} to ${booking.barber_email}`);
            } catch (barberError: any) {
              logger.error(`Failed to send barber reminder for booking ${booking.id}:`, barberError.message);
            }
          }

          await this.markReminderSent(booking.id);

          emailsSent++;
          logger.info(`✅ Reminders sent for booking ${booking.id}`);
        } catch (error: any) {
          emailsFailed++;
          logger.error(`Failed to send reminder for booking ${booking.id}:`, error.message);
        }
      }

      const duration = Date.now() - startTime;
      logger.info(`📧 Booking reminders processed: ${emailsSent} sent, ${emailsFailed} failed (${duration}ms)`);
    } catch (error: any) {
      logger.error('Error processing booking reminders:', error.message);
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * Ensure columns exist for per-stage push reminders (idempotent).
   */
  private async ensurePushReminderColumns(): Promise<void> {
    await pool.query(`
      ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_push_24h_sent BOOLEAN DEFAULT FALSE;
      ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_push_12h_sent BOOLEAN DEFAULT FALSE;
      ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_push_3h_sent BOOLEAN DEFAULT FALSE;
      ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_push_1h_sent BOOLEAN DEFAULT FALSE;
    `);
  }

  /**
   * Send APNs/FCM booking reminders at 24h, 12h, 3h, and 1h before `requestedAt`.
   */
  async processBookingPushReminders(): Promise<void> {
    if (this.isPushRunning) {
      logger.debug('Booking push reminder job already running, skipping...');
      return;
    }

    this.isPushRunning = true;
    const startTime = Date.now();
    let pushesSent = 0;
    let pushesFailed = 0;

    try {
      await this.ensurePushReminderColumns();

      for (const stage of PUSH_REMINDER_STAGES) {
        const result = await pool.query(
          `
        SELECT 
          b.id,
          b."consumerId",
          b."serviceType",
          c.service_name,
          consumer.notification_preferences as consumer_notification_preferences,
          barber_user.first_name as barber_first_name,
          barber_user.last_name as barber_last_name
        FROM bookings b
        LEFT JOIN conversations c ON c.booking_id = b.id
        LEFT JOIN users consumer ON b."consumerId" = consumer.id
        LEFT JOIN barbers barber ON b."barberId" = barber.id
        LEFT JOIN users barber_user ON barber."userId" = barber_user.id
        WHERE b.status = 'ACCEPTED'
          AND b."requestedAt" BETWEEN NOW() + $1::interval AND NOW() + $2::interval
          AND b.${stage.column} IS NOT TRUE
          AND b."consumerId" IS NOT NULL
        `,
          [stage.minInterval, stage.maxInterval]
        );

        for (const booking of result.rows) {
          try {
            const prefs = booking.consumer_notification_preferences || {};
            const bookingRemindersEnabled = prefs.booking_reminders !== false;
            const pushEnabled = prefs.push_notifications !== false;

            if (!bookingRemindersEnabled) {
              logger.debug(
                `Skipping push (${stage.stage}) for booking ${booking.id} — booking reminders disabled`
              );
              await this.markPushReminderSent(booking.id, stage.column);
              continue;
            }

            if (!pushEnabled) {
              logger.debug(
                `Skipping push (${stage.stage}) for booking ${booking.id} — push notifications disabled`
              );
              await this.markPushReminderSent(booking.id, stage.column);
              continue;
            }

            const serviceName =
              booking.service_name || formatServiceType(booking.serviceType) || 'Haircut';
            const barberName =
              `${booking.barber_first_name || ''} ${booking.barber_last_name || ''}`.trim() || 'Your provider';

            const sendResult = await pushNotificationService.sendAppointmentReminderNotification(
              booking.consumerId,
              barberName,
              serviceName,
              stage.hoursUntil,
              booking.id,
              stage.stage
            );

            const success = (sendResult as any)?.success === true;
            const noDevices = (sendResult as any)?.reason === 'No registered devices';

            if (success || noDevices) {
              await this.markPushReminderSent(booking.id, stage.column);
              pushesSent++;
              if (noDevices) {
                logger.debug(
                  `Push (${stage.stage}) for booking ${booking.id}: no devices — marked sent`
                );
              } else {
                logger.info(`📱 Push reminder (${stage.stage}) sent for booking ${booking.id}`);
              }
            } else {
              pushesFailed++;
              logger.warn(
                `Push (${stage.stage}) failed for booking ${booking.id}:`,
                JSON.stringify(sendResult)
              );
            }
          } catch (rowErr: any) {
            pushesFailed++;
            logger.error(
              `Push (${stage.stage}) error for booking ${booking.id}:`,
              rowErr?.message || rowErr
            );
          }
        }
      }

      const duration = Date.now() - startTime;
      logger.debug(
        `📱 Booking push reminders finished in ${duration}ms (ok: ${pushesSent}, fail: ${pushesFailed})`
      );
    } catch (error: any) {
      logger.error('Error processing booking push reminders:', error.message);
    } finally {
      this.isPushRunning = false;
    }
  }

  private async markPushReminderSent(bookingId: number | string, column: string): Promise<void> {
    const allowed = new Set<string>(PUSH_REMINDER_STAGES.map(s => s.column));
    if (!allowed.has(column)) {
      logger.error(`Invalid push reminder column: ${column}`);
      return;
    }
    try {
      await pool.query(`UPDATE bookings SET ${column} = TRUE WHERE id = $1`, [bookingId]);
    } catch (error: any) {
      logger.error(`Failed to mark ${column} for booking ${bookingId}:`, error.message);
    }
  }

  /**
   * Mark a booking's reminder as sent
   */
  private async markReminderSent(bookingId: number | string): Promise<void> {
    try {
      await pool.query(`
        ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN DEFAULT FALSE
      `);

      await pool.query('UPDATE bookings SET reminder_sent = TRUE WHERE id = $1', [bookingId]);
    } catch (error: any) {
      logger.error(`Failed to mark reminder sent for booking ${bookingId}:`, error.message);
    }
  }

  /**
   * Run reminders manually (for testing)
   */
  async runManually(): Promise<{ sent: number; failed: number }> {
    await this.processBookingReminders();
    await this.processBookingPushReminders();
    return { sent: 0, failed: 0 };
  }
}

export const bookingReminderCronService = new BookingReminderCronService();
