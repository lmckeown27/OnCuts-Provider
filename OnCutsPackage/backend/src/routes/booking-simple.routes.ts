/**
 * Simple Booking Routes
 * 
 * Creates booking records that match the production database schema.
 * Used by the consumer booking flow.
 */

import express from 'express';
import { pool } from '../database/connection';
import { authenticate } from '../middleware/auth';
import { logger } from '../utils/logger';
import notificationService from '../services/notification.service';
import pushNotificationService from '../services/pushNotification.service';
import { sendPendingBookingEmails, sendBookingEditEmails, sendBookingCompletedEmails, sendBookingCancellationEmails } from '../services/email.service';
import { DateTime } from 'luxon';
import {
  getDefaultStripeClient,
  getDefaultStripeSecretKey,
  STRIPE_IOS_SDK_API_VERSION,
} from '../config/stripe';
import { getSocketIO } from '../index';
import { sameUuid } from '../utils/uuid-compare';
import { snapshotBookingLocationFromConversation } from '../services/booking-location-snapshot.service';
import {
  sendStripeClientConfig,
  stripePublishableKeyPrefixForClientVerification,
} from '../controllers/stripe-client-config.controller';

const router = express.Router();

/**
 * Same GET the Stripe iOS SDK uses for PaymentSheet (`Bearer pk_…` + `client_secret`).
 * If this returns 404, `STRIPE_PUBLISHABLE_KEY` on the server is not from the same Stripe account as the secret used to create the PI.
 */
async function logIfPublishableKeyCannotRetrievePaymentIntent(
  publishableKey: string,
  paymentIntentId: string,
  clientSecret: string | null | undefined
): Promise<void> {
  const pk = publishableKey.trim();
  const secret = clientSecret?.trim();
  if (!secret) return;
  if (!pk.startsWith('pk_')) {
    logger.warn(
      '[stripe] Skipping PaymentIntent retrieval probe: no STRIPE_PUBLISHABLE_KEY* configured (iOS cannot validate pk vs client_secret)'
    );
    return;
  }
  const url = `https://api.stripe.com/v1/payment_intents/${encodeURIComponent(paymentIntentId)}?client_secret=${encodeURIComponent(secret)}`;
  try {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${pk}` } });
    const body = await res.text();
    if (res.status === 404) {
      const modeHint =
        body.includes('test mode') && body.includes('live mode')
          ? 'Stripe often means the PaymentIntent is in test mode but this probe used a live publishable key (or the reverse). '
          : '';
      logger.error(
        `Stripe: publishable-key probe failed (HTTP 404) for ${paymentIntentId}. ` +
          `This probe uses only STRIPE_PUBLISHABLE_KEY / VITE_STRIPE_PUBLISHABLE_KEY on **this server** — not the iOS plist key. ` +
          `If that env value is wrong account or mode vs the secret that created the PI, you see 404 here even when the app bundles a correct pk_live. ` +
          modeHint +
          `Fix: set server STRIPE_PUBLISHABLE_KEY to the standard pk_ from the same Dashboard account as your API secret. Stripe: ${body.slice(0, 500)}`
      );
    } else if (!res.ok) {
      logger.warn(
        `Stripe: publishable-key verify GET payment_intents/${paymentIntentId} → HTTP ${res.status}: ${body.slice(0, 400)}`
      );
    }
  } catch (e: any) {
    logger.warn(`Stripe: publishable-key verify fetch failed: ${e?.message || e}`);
  }
}

/** Alias of `GET /api/v1/stripe/client-config` — registered before `/:id` so older deployments / proxies still resolve. */
router.get('/stripe/client-config', sendStripeClientConfig);

/**
 * Archive messages for a booking before deletion
 * This preserves message history for admin viewing
 */
async function archiveBookingMessages(bookingId: string, client: any = pool): Promise<void> {
  try {
    // Archive messages with sender info before deletion
    await client.query(`
      INSERT INTO archived_booking_messages (
        booking_id, original_message_id, original_conversation_id,
        sender_id, sender_first_name, sender_last_name, sender_avatar, sender_role,
        content, message_type, created_at
      )
      SELECT 
        c.booking_id,
        m.id,
        m.conversation_id,
        m.sender_id,
        u.first_name,
        u.last_name,
        u."avatarUrl",
        u.role,
        m.content,
        m.message_type,
        m.created_at
      FROM messages m
      JOIN conversations c ON m.conversation_id = c.id
      JOIN users u ON m.sender_id = u.id
      WHERE c.booking_id = $1
    `, [bookingId]);
    logger.info(`Archived messages for booking ${bookingId}`);
  } catch (error: any) {
    // Table might not exist yet or no messages to archive - that's fine
    logger.warn(`Could not archive messages for booking ${bookingId}: ${error.message}`);
  }
}

/**
 * POST /api/v1/bookings-simple
 * Create a simple booking record
 */
router.post('/', authenticate, async (req, res, next) => {
  try {
    const consumerId = (req as any).user.userId;
    const {
      barberId,
      serviceType,
      priceUsdCents,
      scheduledTime,
      location,
      locationDetails,
      notes,
    } = req.body;

    // Validate required fields
    if (!barberId) {
      return res.status(400).json({ success: false, error: 'barberId is required' });
    }
    if (!serviceType) {
      return res.status(400).json({ success: false, error: 'serviceType is required' });
    }

    // Get barber record ID from barbers table (bookings.barberId references barbers.id, not users.id)
    const barberResult = await pool.query(
      'SELECT id FROM barbers WHERE id = $1 OR "userId" = $1',
      [barberId]
    );
    
    if (barberResult.rows.length === 0) {
      return res.status(400).json({ success: false, error: 'Barber not found' });
    }
    
    const barberRecordId = barberResult.rows[0].id;

    // Check for time slot conflicts - barber can only have one booking at a time
    if (scheduledTime) {
      // Parse the scheduled time to check for conflicts
      let checkTime: Date;
      if (scheduledTime.includes('Z') || scheduledTime.match(/[+-]\d{2}:\d{2}$/)) {
        checkTime = new Date(scheduledTime);
      } else {
        const pacificTime = DateTime.fromISO(scheduledTime, { zone: 'America/Los_Angeles' });
        checkTime = pacificTime.toJSDate();
      }
      
      // Check for existing bookings within 60 minutes of the requested time
      // Only check PENDING and ACCEPTED bookings (not COMPLETED, PAID, CANCELLED, REJECTED)
      // Each appointment blocks 1 hour (3600 seconds)
      const conflictCheck = await pool.query(
        `SELECT id, "requestedAt", status 
         FROM bookings 
         WHERE "barberId" = $1 
           AND status IN ('PENDING', 'ACCEPTED')
           AND ABS(EXTRACT(EPOCH FROM ("requestedAt" - $2::timestamp))) < 3600`,
        [barberRecordId, checkTime.toISOString()]
      );
      
      if (conflictCheck.rows.length > 0) {
        const conflictingBooking = conflictCheck.rows[0];
        const conflictTime = new Date(conflictingBooking.requestedAt);
        logger.warn(`Time slot conflict for barber ${barberRecordId}: requested ${checkTime.toISOString()}, existing booking at ${conflictTime.toISOString()}`);
        
        return res.status(409).json({ 
          success: false, 
          error: 'This time slot is no longer available. The barber already has an appointment at this time. Please choose a different time.',
          conflictAt: conflictTime.toISOString(),
        });
      }
    }

    // Map frontend service names to database enum values
    // NOTE: The original service name is preserved in conversations.service_name for display
    // This mapping is for database storage - the display will show the original name
    // 
    // Frontend services (from web-app/src/config/services.ts):
    //   'Buzz Cut', 'Line Up', 'Beard Trim', 'Haircut', 'Taper', 'Hot Shave',
    //   'Kids Cut', 'Fade', 'Haircut & Fade', 'Design/Art', 'Afro Textures',
    //   "Women's Cut", 'Color Treatment', 'Perm'
    //
    // Database enum: HAIRCUT, FADE, BEARD_TRIM, FULL_SERVICE, HOT_TOWEL_SHAVE, 
    //   COLOR, STYLING, LINEUP, BUZZ_CUT, SHAPE_UP, PERM, BRAIDS, LOCS, TAPER
    const serviceTypeMap: Record<string, string> = {
      // Exact matches from frontend config
      'Buzz Cut': 'BUZZ_CUT',
      'Line Up': 'LINEUP',
      'Beard Trim': 'BEARD_TRIM',
      'Haircut': 'HAIRCUT',
      'Taper': 'TAPER',
      'Hot Shave': 'HOT_TOWEL_SHAVE',
      'Kids Cut': 'HAIRCUT',           // Maps to HAIRCUT (no KIDS_CUT enum)
      'Fade': 'FADE',
      'Haircut & Fade': 'FADE',        // Maps to FADE (combo service)
      'Mullet': 'MULLET',              // Mullet haircut
      'Design/Art': 'STYLING',         // Maps to STYLING
      'Afro Textures': 'STYLING',      // Maps to STYLING
      "Women's Cut": 'HAIRCUT',        // Maps to HAIRCUT
      'Color Treatment': 'COLOR',
      'Perm': 'PERM',
      
      // Legacy/alternative names for backwards compatibility
      'Lineup': 'LINEUP',
      'Shape Up': 'SHAPE_UP',
      'Full Service': 'FULL_SERVICE',
      'Hot Towel Shave': 'HOT_TOWEL_SHAVE',
      'Color': 'COLOR',
      'Styling': 'STYLING',
      'Braids': 'BRAIDS',
      'Locs': 'LOCS',
    };
    
    // Convert to enum value or fallback to HAIRCUT as default
    const dbServiceType = serviceTypeMap[serviceType] || 'HAIRCUT';
    
    // Store the original display name for later retrieval (passed to conversation)
    const originalServiceName = serviceType;

    // Create booking record (all NOT NULL columns in production)
    // Platform fee is 15% of price, barber gets 85%
    const price = priceUsdCents || 0;
    const platformFee = Math.round(price * 0.15);
    const barberEarnings = price - platformFee;
    
    // Parse scheduled time - all times are in Pacific timezone (Cal Poly SLO)
    // The frontend sends time like "2026-01-07T16:45:00" without timezone
    // We need to interpret this as Pacific time and convert to UTC for storage
    let requestedTime: Date;
    if (scheduledTime) {
      // Check if already has timezone (ISO format with Z or offset)
      if (scheduledTime.includes('Z') || scheduledTime.match(/[+-]\d{2}:\d{2}$/)) {
        // Already in UTC/ISO format - parse directly
        requestedTime = new Date(scheduledTime);
        logger.info(`Parsed UTC time directly: ${scheduledTime} -> ${requestedTime.toISOString()}`);
      } else {
        // No timezone specified - interpret as Pacific time using luxon
        // This correctly handles DST automatically
        const pacificTime = DateTime.fromISO(scheduledTime, { zone: 'America/Los_Angeles' });
        
        if (!pacificTime.isValid) {
          logger.error(`Invalid scheduled time format: ${scheduledTime}`);
          requestedTime = new Date();
        } else {
          // Convert to UTC for database storage
          requestedTime = pacificTime.toUTC().toJSDate();
          logger.info(`Parsed Pacific time: ${scheduledTime} (${pacificTime.offsetNameShort}) -> UTC: ${requestedTime.toISOString()}`);
        }
      }
    } else {
      requestedTime = new Date();
    }
    
    // Get or create location (requires campus -> location chain)
    let locationId: string;
    
    // First check for existing location
    let locationResult = await pool.query('SELECT id FROM locations LIMIT 1');
    
    if (locationResult.rows.length > 0) {
      locationId = locationResult.rows[0].id;
    } else {
      // Need to create campus first, then location
      let campusResult = await pool.query('SELECT id FROM campuses LIMIT 1');
      let campusId: string;
      
      if (campusResult.rows.length > 0) {
        campusId = campusResult.rows[0].id;
      } else {
        // Create a default campus
        const newCampusResult = await pool.query(
          `INSERT INTO campuses (id, name, "shortCode", city, state, latitude, longitude, "isActive", "createdAt", "updatedAt")
           VALUES (gen_random_uuid(), 'Default Campus', 'DEFAULT', 'San Luis Obispo', 'CA', 35.3050, -120.6625, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
           RETURNING id`
        );
        campusId = newCampusResult.rows[0].id;
      }
      
      // Create location with campus
      const newLocationResult = await pool.query(
        `INSERT INTO locations (id, "campusId", name, "normalizedName", type, cohort, "usageCount", confidence, "isVerified", "updatedAt")
         VALUES (gen_random_uuid(), $1, 'Default Location', 'default-location', 'DORM'::"LocationType", 'UNKNOWN'::"LocationCohort", 1, 0.50, false, CURRENT_TIMESTAMP)
         RETURNING id`,
        [campusId]
      );
      locationId = newLocationResult.rows[0].id;
    }
    
    // Create availability slot for this booking (availabilityId is a required FK)
    const availabilityResult = await pool.query(
      `INSERT INTO availability (
        id,
        "barberId",
        "locationId",
        "startTime",
        "endTime",
        "priceUsdCents",
        "serviceTypes",
        status,
        "updatedAt"
      ) VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, ARRAY[$6::"ServiceType"], 'BOOKED', CURRENT_TIMESTAMP)
      RETURNING id`,
      [
        barberRecordId,
        locationId,
        requestedTime,
        new Date(requestedTime.getTime() + 30 * 60 * 1000), // 30 min later
        price,
        dbServiceType,
      ]
    );
    
    const availabilityId = availabilityResult.rows[0].id;
    
    // Now create the booking with the availability ID
    const result = await pool.query(
      `INSERT INTO bookings (
        id,
        "consumerId", 
        "barberId", 
        "serviceType", 
        "priceUsdCents",
        "platformFeeUsdCents",
        "barberEarningsUsdCents",
        "requestedAt",
        "availabilityId",
        "updatedAt",
        status
      ) VALUES (gen_random_uuid(), $1, $2, $3::"ServiceType", $4, $5, $6, $7, $8, CURRENT_TIMESTAMP, 'PENDING')
      RETURNING id, "consumerId", "barberId", "serviceType", "priceUsdCents", "requestedAt", status, "createdAt"`,
      [
        consumerId,
        barberRecordId,
        dbServiceType,
        price,
        platformFee,
        barberEarnings,
        requestedTime,
        availabilityId,
      ]
    );

    const booking = result.rows[0];

    logger.info('Simple booking created', {
      booking_id: booking.id,
      consumer_id: consumerId,
      barber_id: barberRecordId,
      service_type: serviceType,
    });

    // Get consumer name and barber user ID for notification
    const consumerResult = await pool.query(
      `SELECT first_name || ' ' || last_name as name FROM users WHERE id = $1`,
      [consumerId]
    );
    const consumerName = consumerResult.rows[0]?.name || 'A customer';
    
    const barberUserResult = await pool.query(
      `SELECT "userId", b.id as barber_id FROM barbers b WHERE b.id = $1`,
      [barberRecordId]
    );
    const barberUserId = barberUserResult.rows[0]?.userId;

    // Create a conversation linked to the booking with the original service name
    // This ensures the service name is preserved for display (not the enum value)
    if (barberUserId) {
      try {
        await pool.query(
          `INSERT INTO conversations (
            user1_id, user2_id, booking_id, 
            service_name, service_price, scheduled_time,
            location, location_details, notes, booking_status,
            is_active, created_at, updated_at
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          ON CONFLICT (user1_id, user2_id, booking_id) DO UPDATE SET 
            service_name = EXCLUDED.service_name,
            service_price = EXCLUDED.service_price,
            scheduled_time = EXCLUDED.scheduled_time,
            location = EXCLUDED.location,
            location_details = EXCLUDED.location_details,
            notes = EXCLUDED.notes`,
          [
            consumerId,
            barberUserId,
            booking.id,
            serviceType,
            price,
            requestedTime,
            location || null,
            locationDetails || null,
            notes || null,
          ]
        );
        logger.info(`Created conversation for booking ${booking.id} with service name: ${serviceType}`);
      } catch (convError) {
        // Non-fatal - conversation can be created later
        logger.warn(`Failed to create conversation for booking ${booking.id}:`, convError);
      }
    }
    
    // Send notification to barber about new booking request
    if (barberUserId) {
      await notificationService.saveNotification({
        userId: barberUserId,
        type: 'new_booking_request',
        title: 'New Booking Request!',
        message: `${consumerName} wants to book a ${serviceType} with you`,
        data: { bookingId: booking.id, consumerId, serviceType },
      });
      logger.info(`Notification sent to barber ${barberUserId} for new booking ${booking.id}`);
      
      // Emit new-booking-request event via WebSocket for live updates
      const newBookingEvent = {
        id: booking.id,
        consumerId,
        barberId: barberRecordId,
        serviceType,
        priceUsdCents: price,
        scheduledTime: requestedTime,
        location,
        notes,
        status: 'PENDING',
        consumerName,
        createdAt: new Date().toISOString(),
      };
      
      logger.info(`[new-booking-request] Attempting to emit to barber user ${barberUserId}`);
      try {
        const io = getSocketIO();
        logger.info(`[new-booking-request] Socket.IO instance available: ${!!io}`);
        if (io) {
          io.to(`user-${barberUserId}`).emit('new-booking-request', newBookingEvent);
          logger.info(`[new-booking-request] ✅ Emitted to room user-${barberUserId} for booking ${booking.id}`);
        } else {
          logger.warn(`[new-booking-request] ❌ Socket.IO not available`);
        }
      } catch (wsError) {
        logger.error(`[new-booking-request] ❌ Error emitting:`, wsError);
      }
    }

    // Send pending booking emails to both consumer and barber
    try {
      // Get consumer and barber emails, plus campus timezone
      const emailDetailsResult = await pool.query(
        `SELECT 
          u_consumer.email as consumer_email,
          u_consumer.first_name || ' ' || u_consumer.last_name as consumer_full_name,
          u_barber.email as barber_email,
          u_barber.first_name || ' ' || u_barber.last_name as barber_full_name,
          COALESCE(c.timezone, 'America/New_York') as campus_timezone
         FROM users u_consumer
         CROSS JOIN users u_barber
         LEFT JOIN barbers b ON b."userId" = u_barber.id
         LEFT JOIN campuses c ON b."campusId" = c.id
         WHERE u_consumer.id = $1 AND u_barber.id = $2`,
        [consumerId, barberUserId]
      );
      
      if (emailDetailsResult.rows.length > 0) {
        const emailDetails = emailDetailsResult.rows[0];
        const scheduledDate = new Date(requestedTime);
        const campusTimezone = emailDetails.campus_timezone || 'America/New_York';
        
        // Send pending booking emails (non-blocking)
        sendPendingBookingEmails({
          consumerEmail: emailDetails.consumer_email,
          consumerName: emailDetails.consumer_full_name,
          barberEmail: emailDetails.barber_email,
          barberName: emailDetails.barber_full_name,
          serviceName: serviceType.replace(/_/g, ' ').toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase()),
          scheduledDate: scheduledDate.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', timeZone: campusTimezone }),
          scheduledTime: scheduledDate.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: campusTimezone }),
          price: price / 100, // Convert cents to dollars
          location: location || undefined,
          notes: notes || undefined,
          bookingId: booking.id,
        }).catch(err => logger.error('Failed to send pending booking emails:', err));
      }
    } catch (emailError) {
      logger.error('Error preparing pending booking emails:', emailError);
    }

    res.status(201).json({
      success: true,
      data: {
        booking: {
          id: booking.id,
          consumerId: booking.consumerId,
          barberId: booking.barberId,
          serviceType: booking.serviceType,
          priceUsdCents: booking.priceUsdCents,
          scheduledTime: booking.requestedAt,
          status: booking.status,
          createdAt: booking.createdAt,
        },
      },
      message: 'Booking created successfully',
    });
  } catch (error: any) {
    logger.error('Error creating simple booking:', error.message || error);
    next(error);
  }
});

// ============================================================================
// WALK-IN PAYMENT ENDPOINTS - FEATURE DISABLED
// ============================================================================
/*
router.post('/walk-in/create-payment', authenticate, async (req, res, next) => {
  // Walk-in feature disabled
});

router.post('/walk-in/confirm-payment', authenticate, async (req, res, next) => {
  // Walk-in feature disabled
});

router.post('/walk-in/record-cash', authenticate, async (req, res, next) => {
  // Walk-in feature disabled
});
*/

// ============================================================================
// CAMPUS MANAGER ENDPOINT
// ============================================================================

/**
 * GET /api/v1/bookings-simple/campus/:campusId
 * Get bookings for a campus (Campus Managers only)
 * Query params:
 *   - barberId: filter by specific barber
 *   - limit: max number of results (default 100)
 *   - statusFilter: 'upcoming' (PENDING, ACCEPTED), 'completed' (COMPLETED, PAID), or 'cancelled' (CANCELLED, REJECTED)
 */
router.get('/campus/:campusId', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const { campusId } = req.params;
    const { barberId, limit = '100', statusFilter = 'completed', paymentMethod } = req.query;

    // Check if user is an admin (admins have campus manager access to all campuses)
    const adminCheck = await pool.query(
      `SELECT role FROM users WHERE id = $1`,
      [userId]
    );
    const isAdmin = adminCheck.rows[0]?.role === 'ADMIN';

    // If not admin, verify user is a campus manager for this specific campus
    if (!isAdmin) {
      const managerCheck = await pool.query(
        `SELECT b.id FROM barbers b
         JOIN users u ON b."userId" = u.id
         WHERE b."userId" = $1 
           AND b."isCampusManager" = true 
           AND b."campusId" = $2`,
        [userId, campusId]
      );

      if (managerCheck.rows.length === 0) {
        return res.status(403).json({
          success: false,
          error: 'You are not a campus manager for this campus'
        });
      }
    }

    // Build query to get bookings for all barbers on this campus
    // statusFilter determines which bookings to show:
    //   - 'upcoming': PENDING, ACCEPTED (future bookings)
    //   - 'completed': COMPLETED, PAID (finished bookings)
    //   - 'cancelled': CANCELLED, REJECTED (cancelled/declined bookings)
    let statusClause: string;
    let dateFilter: string;
    
    if (statusFilter === 'upcoming') {
      // Upcoming: PENDING or ACCEPTED, scheduled for today or future
      statusClause = `b.status IN ('PENDING', 'ACCEPTED')`;
      dateFilter = `b."requestedAt" >= NOW() - INTERVAL '1 day'`; // Include yesterday to catch late bookings
    } else if (statusFilter === 'cancelled') {
      // Cancelled: CANCELLED only from last 30 days
      statusClause = `b.status = 'CANCELLED'`;
      dateFilter = `b."requestedAt" >= NOW() - INTERVAL '30 days'`;
    } else {
      // Completed: COMPLETED or PAID, from last 30 days
      statusClause = `b.status IN ('COMPLETED', 'PAID')`;
      dateFilter = `b."requestedAt" >= NOW() - INTERVAL '30 days'`;
    }
    
    let whereClause = `barber_user."campusId" = $1 AND ${statusClause} AND ${dateFilter}`;
    const params: any[] = [campusId];
    let paramIndex = 2;

    // Optionally filter by specific barber
    if (barberId) {
      whereClause += ` AND barber.id = $${paramIndex}`;
      params.push(barberId);
      paramIndex++;
    }

    // Optionally filter by payment method (card or cash)
    if (paymentMethod && paymentMethod !== 'all') {
      whereClause += ` AND b."paymentMethod" = $${paramIndex}`;
      params.push(paymentMethod);
      paramIndex++;
    }

    const result = await pool.query(
      `SELECT 
        b.id,
        b."consumerId",
        b."barberId",
        b."serviceType",
        b."priceUsdCents",
        b."tipAmountCents",
        b."totalPaidCents",
        COALESCE(b."requestedAt", c.scheduled_time) as "scheduledTime",
        b.status,
        b."createdAt",
        b."paidAt",
        b."completedAt",
        b."paymentMethod",
        b."reviewRating",
        b."reviewComment",
        b."reviewedAt",
        consumer.first_name as consumer_first_name,
        consumer.last_name as consumer_last_name,
        consumer."avatarUrl" as consumer_avatar,
        barber_user.first_name as barber_first_name,
        barber_user.last_name as barber_last_name,
        barber_user."avatarUrl" as barber_avatar,
        barber.id as barber_record_id,
        c.id as conversation_id,
        COALESCE(
          NULLIF(TRIM(b."serviceLocation"), ''),
          NULLIF(TRIM(COALESCE(c.location, '')), ''),
          NULLIF(TRIM(COALESCE(c.location_details, '')), ''),
          NULLIF(TRIM(b."serviceLocationDetails"), '')
        ) as conv_location,
        c.notes as conv_notes,
        c.service_name as conv_service_name
      FROM bookings b
      LEFT JOIN users consumer ON b."consumerId" = consumer.id
      LEFT JOIN barbers barber ON b."barberId" = barber.id
      LEFT JOIN users barber_user ON barber."userId" = barber_user.id
      LEFT JOIN conversations c ON c.booking_id = b.id
      WHERE ${whereClause}
      ORDER BY b."requestedAt" DESC
      LIMIT $${paramIndex}`,
      [...params, parseInt(limit as string)]
    );

    // Get list of barbers for the filter dropdown
    const barbersResult = await pool.query(
      `SELECT b.id, u.first_name, u.last_name
       FROM barbers b
       JOIN users u ON b."userId" = u.id
       WHERE u."campusId" = $1 AND b."isActive" = true
       ORDER BY u.first_name, u.last_name`,
      [campusId]
    );

    // Helper to format service type
    const formatServiceType = (type: string) => {
      if (!type) return 'Haircut';
      return type
        .toLowerCase()
        .replace(/_/g, ' ')
        .replace(/\b\w/g, c => c.toUpperCase());
    };

    res.json({
      success: true,
      data: {
        bookings: result.rows.map(row => ({
          id: row.id,
          consumerId: row.consumerId,
          barberId: row.barberId,
          barberRecordId: row.barber_record_id,
          serviceType: row.conv_service_name || formatServiceType(row.serviceType),
          priceUsdCents: row.priceUsdCents,
          tipAmountCents: row.tipAmountCents || null,
          totalPaidCents: row.totalPaidCents || null,
          scheduledTime: row.scheduledTime,
          status: row.status,
          createdAt: row.createdAt,
          paidAt: row.paidAt,
          completedAt: row.completedAt || null,
          paymentMethod: row.paymentMethod || null,
          location: row.conv_location || null,
          notes: row.conv_notes || null,
          review: row.reviewRating ? {
            rating: row.reviewRating,
            comment: row.reviewComment || null,
            reviewedAt: row.reviewedAt,
          } : null,
          barberName: `${row.barber_first_name || ''} ${row.barber_last_name || ''}`.trim() || 'Barber',
          barberAvatar: row.barber_avatar || null,
          consumerName: `${row.consumer_first_name || ''} ${row.consumer_last_name || ''}`.trim() || 'Customer',
          consumerAvatar: row.consumer_avatar || null,
          conversationId: row.conversation_id || null,
        })),
        barbers: barbersResult.rows.map(row => ({
          id: row.id,
          name: `${row.first_name || ''} ${row.last_name || ''}`.trim(),
        })),
      },
      count: result.rows.length,
    });
  } catch (error: any) {
    logger.error('Error fetching campus bookings:', error.message || error);
    logger.error('Full error:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to fetch campus bookings',
      details: error.detail || null,
    });
  }
});

// ============================================================================
// BOOKING-SPECIFIC ENDPOINTS (with :id parameter)
// ============================================================================

/**
 * POST /api/v1/bookings-simple/:id/hide-from-list
 * Consumer: hide a past booking from GET /bookings-simple lists (does not delete the booking).
 */
router.post('/:id/hide-from-list', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const userId = (req as any).user.userId;

    const result = await pool.query(
      `SELECT b.id, b."consumerId", b.status, b."requestedAt" as "scheduledTime"
       FROM bookings b
       WHERE b.id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Booking not found' });
    }

    const row = result.rows[0];
    if (!sameUuid(row.consumerId, userId)) {
      return res.status(403).json({ success: false, error: 'Only the customer can hide this booking' });
    }

    const st = String(row.status || '').toUpperCase();
    const terminal = new Set([
      'PAID',
      'COMPLETED',
      'CANCELLED',
      'REJECTED',
      'DECLINED',
      'REFUNDED',
      'NO_SHOW',
    ]);
    const scheduledTime: Date = row.scheduledTime instanceof Date ? row.scheduledTime : new Date(row.scheduledTime);
    const isPastSlot = scheduledTime.getTime() < Date.now();
    if (!terminal.has(st) && !isPastSlot) {
      return res.status(400).json({
        success: false,
        error: 'Only past bookings can be removed from your list',
      });
    }

    await pool.query(
      `INSERT INTO consumer_hidden_bookings (consumer_id, booking_id)
       VALUES ($1, $2)
       ON CONFLICT (consumer_id, booking_id) DO NOTHING`,
      [userId, id]
    );

    logger.info(`Consumer ${userId} hid booking ${id} from their list`);

    return res.json({ success: true, message: 'Booking hidden from your list' });
  } catch (error: any) {
    logger.error('Error hiding booking from consumer list:', error.message || error);
    next(error);
  }
});

/**
 * GET /api/v1/bookings-simple/:id
 * Get booking by ID
 */
router.get('/:id', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const userId = (req as any).user.userId;

    const result = await pool.query(
      `SELECT 
        b.id,
        b."consumerId",
        b."barberId",
        b."serviceType",
        b."priceUsdCents",
        COALESCE(b."requestedAt", c.scheduled_time) as "scheduledTime",
        b.status,
        b."createdAt",
        b."paidAt",
        b."tipAmountCents",
        b."totalPaidCents",
        b."reviewRating",
        b."reviewComment",
        b."reviewedAt",
        conv.id as conversation_id,
        conv.service_name,
        COALESCE(
          NULLIF(TRIM(b."serviceLocation"), ''),
          conv.location,
          NULLIF(TRIM(b."serviceLocationDetails"), ''),
          conv.location_details
        ) as location,
        conv.notes,
        barber_record.id as barber_record_id,
        barber_user.id as barber_user_id,
        barber_user.first_name as barber_first_name,
        barber_user.last_name as barber_last_name,
        barber_user."avatarUrl" as barber_profile_url,
        consumer.id as consumer_user_id,
        consumer.first_name as consumer_first_name,
        consumer.last_name as consumer_last_name,
        consumer."avatarUrl" as consumer_profile_url
      FROM bookings b
      LEFT JOIN conversations conv ON conv.booking_id = b.id
      LEFT JOIN barbers barber_record ON b."barberId" = barber_record.id
      LEFT JOIN users barber_user ON barber_record."userId" = barber_user.id
      LEFT JOIN users consumer ON b."consumerId" = consumer.id
      WHERE b.id = $1 AND (b."consumerId" = $2 OR barber_user.id = $2)`,
      [id, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Booking not found' });
    }

    const row = result.rows[0];
    
    // Format response with nested barber/consumer objects
    const booking = {
      id: row.id,
      consumerId: row.consumerId,
      barberId: row.barberId,
      serviceType: row.serviceType,
      serviceName: row.service_name || row.serviceType,
      priceUsdCents: row.priceUsdCents,
      scheduledTime: row.scheduledTime,
      status: row.status,
      createdAt: row.createdAt,
      paidAt: row.paidAt,
      tipAmountCents: row.tipAmountCents,
      totalPaidCents: row.totalPaidCents,
      location: row.location,
      notes: row.notes,
      // Review data (from consumer after service completion)
      reviewRating: row.reviewRating || null,
      reviewComment: row.reviewComment || null,
      reviewedAt: row.reviewedAt || null,
      barber: {
        id: row.barber_user_id,
        recordId: row.barber_record_id,
        firstName: row.barber_first_name,
        lastName: row.barber_last_name,
        profileImageUrl: row.barber_profile_url,
      },
      consumer: {
        id: row.consumer_user_id,
        firstName: row.consumer_first_name,
        lastName: row.consumer_last_name,
        profileImageUrl: row.consumer_profile_url,
      },
      conversationId: row.conversation_id || null,
    };

    res.json({
      success: true,
      booking,
    });
  } catch (error: any) {
    logger.error('Error getting booking:', error.message || error);
    next(error);
  }
});

/**
 * PUT /api/v1/bookings-simple/:id/status
 * Update booking status (accept/reject/complete/cancel)
 */
router.put('/:id/status', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const { status } = req.body;
    const userId = (req as any).user.userId;

    const validStatuses = ['PENDING', 'ACCEPTED', 'REJECTED', 'COMPLETED', 'PAID', 'CANCELLED'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ 
        success: false, 
        error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` 
      });
    }

    // `bookings.barberId` references `barbers.id`, not `users.id` — join barbers so the provider can update status.
    const result = await pool.query(
      `UPDATE bookings AS b
       SET status = $1, "updatedAt" = CURRENT_TIMESTAMP
       WHERE b.id = $2 AND (
         b."consumerId" = $3
         OR EXISTS (SELECT 1 FROM barbers bar WHERE bar.id = b."barberId" AND bar."userId" = $3)
       )
       RETURNING b.id, b.status`,
      [status, id, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Booking not found or access denied' });
    }

    // If status is CANCELLED or REJECTED, delete the conversation and messages
    if (status === 'CANCELLED' || status === 'REJECTED') {
      const convResult = await pool.query(
        `SELECT id FROM conversations WHERE booking_id = $1`,
        [id]
      );
      
      if (convResult.rows.length > 0) {
        const conversationId = convResult.rows[0].id;
        await pool.query(`DELETE FROM messages WHERE conversation_id = $1`, [conversationId]);
        await pool.query(`DELETE FROM conversations WHERE id = $1`, [conversationId]);
        logger.info(`Deleted conversation ${conversationId} and messages for ${status} booking ${id}`);
      }
    }

    res.json({
      success: true,
      data: { booking: result.rows[0] },
      message: `Booking status updated to ${status}`,
    });
  } catch (error: any) {
    logger.error('Error updating booking status:', error.message || error);
    next(error);
  }
});

/**
 * PUT /api/v1/bookings-simple/:id/complete
 * Mark a booking as complete - triggers payment request to consumer
 * Only the barber can mark a booking as complete
 */
router.put('/:id/complete', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const userId = (req as any).user.userId;

    // Verify user is the barber for this booking - also fetch email addresses and campus timezone for notifications
    const barberCheck = await pool.query(
      `SELECT b.id, b."consumerId", b."priceUsdCents", b."serviceType", b."requestedAt",
              barber."userId" as barber_user_id,
              consumer.first_name || ' ' || consumer.last_name as consumer_name,
              consumer.email as consumer_email,
              barber_user.first_name || ' ' || barber_user.last_name as barber_name,
              barber_user.email as barber_email,
              barber_user.stripe_account_id as barber_stripe_account_id,
              barber_user."avatarUrl" as barber_avatar,
              c.service_name as original_service_name,
              c.location,
              COALESCE(campus.timezone, 'America/New_York') as campus_timezone
       FROM bookings b
       JOIN barbers barber ON b."barberId" = barber.id
       JOIN users consumer ON b."consumerId" = consumer.id
       JOIN users barber_user ON barber."userId" = barber_user.id
       LEFT JOIN conversations c ON c.booking_id = b.id
       LEFT JOIN campuses campus ON barber_user."campusId" = campus.id
       WHERE b.id = $1 AND barber."userId" = $2`,
      [id, userId]
    );

    if (barberCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Only the barber can mark this booking as complete' 
      });
    }

    const booking = barberCheck.rows[0];

    // Update booking status to COMPLETED
    const result = await pool.query(
      `UPDATE bookings 
       SET status = 'COMPLETED', 
           "updatedAt" = CURRENT_TIMESTAMP
       WHERE id = $1
       RETURNING id, status`,
      [id]
    );

    const serviceName = booking.original_service_name || booking.serviceType;
    const priceFormatted = `$${(booking.priceUsdCents / 100).toFixed(2)}`;
    const campusTimezone = booking.campus_timezone || 'America/New_York';
    
    // Format scheduled date/time for emails (use campus timezone)
    const scheduledDate = booking.requestedAt 
      ? new Date(booking.requestedAt).toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric', timeZone: campusTimezone })
      : 'N/A';
    const scheduledTime = booking.requestedAt
      ? new Date(booking.requestedAt).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: campusTimezone })
      : 'N/A';
    
    // Build payment URL
    const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
    const paymentUrl = `${frontendUrl}/web/payment/${id}`;

    // Send payment request notification to consumer
    await notificationService.saveNotification({
      userId: booking.consumerId,
      type: 'payment_request',
      title: 'Payment Request',
      message: `${booking.barber_name} has completed your ${serviceName}. Please complete payment of ${priceFormatted}.`,
      data: { 
        bookingId: id,
        amount: booking.priceUsdCents,
        barberName: booking.barber_name,
        serviceName,
      },
    });

    // APNs/FCM: include `type` + `bookingId` so the app can refetch and show `ConsumerPaymentTakeoverView` when the user opens the banner (Socket may be missed after resume).
    try {
      await pushNotificationService.sendSystemNotification(
        booking.consumerId,
        'Payment Request',
        `${booking.barber_name} has completed your ${serviceName}. Please complete payment of ${priceFormatted}.`,
        {
          type: 'payment_request',
          bookingId: id,
          amount: String(booking.priceUsdCents),
        }
      );
    } catch (pushErr: any) {
      logger.warn(`[COMPLETE] Consumer push failed (non-fatal): ${pushErr?.message ?? pushErr}`);
    }

    // Send booking completed emails to both consumer and barber
    logger.info(`[COMPLETE ENDPOINT] About to send booking completed emails for booking ${id}`);
    logger.info(`[COMPLETE ENDPOINT] Consumer email: ${booking.consumer_email}, Barber email: ${booking.barber_email}`);
    try {
      await sendBookingCompletedEmails({
        bookingId: id,
        serviceName,
        price: booking.priceUsdCents / 100,
        scheduledDate,
        scheduledTime,
        location: booking.location,
        consumerName: booking.consumer_name,
        consumerEmail: booking.consumer_email,
        barberName: booking.barber_name,
        barberEmail: booking.barber_email,
        paymentUrl,
      });
      logger.info(`[COMPLETE ENDPOINT] ✅ Email function completed for booking ${id}`);
    } catch (emailError: any) {
      // Don't fail the request if emails fail - just log it
      logger.error(`[COMPLETE ENDPOINT] ❌ Email function threw error for ${id}:`, emailError.message);
      logger.error(`[COMPLETE ENDPOINT] Full error:`, emailError);
    }

    logger.info(`Booking ${id} marked as COMPLETED by barber ${userId}. Payment request sent to consumer ${booking.consumerId}`);

    // Emit WebSocket event to notify consumer in real-time about payment request
    const io = getSocketIO();
    if (io) {
      io.to(`user-${booking.consumerId}`).emit('booking-completed', {
        bookingId: id,
        status: 'COMPLETED',
        barberName: booking.barber_name,
        serviceName,
        price: booking.priceUsdCents,
        priceFormatted,
        paymentUrl,
        scheduledDate,
        scheduledTime,
        location: booking.location,
        stripeAccountId: booking.barber_stripe_account_id ?? null,
        barberAvatar: booking.barber_avatar ?? null,
        barberProfileImageUrl: booking.barber_avatar ?? null,
      });
      logger.info(`Emitted 'booking-completed' event to consumer ${booking.consumerId} for booking ${id}`);
    }

    res.json({
      success: true,
      data: { booking: result.rows[0] },
      message: 'Booking marked as complete. Payment request sent to customer.',
    });
  } catch (error: any) {
    logger.error('Error completing booking:', error.message || error);
    next(error);
  }
});

/**
 * PUT /api/v1/bookings-simple/:id/undo-complete
 * Revert a booking from COMPLETED back to ACCEPTED
 * Only the barber can undo completion, and only if payment hasn't been made yet
 */
router.put('/:id/undo-complete', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const userId = (req as any).user.userId;

    // Verify user is the barber for this booking
    const barberCheck = await pool.query(
      `SELECT b.id, b.status, b."consumerId",
              barber."userId" as barber_user_id,
              consumer.first_name || ' ' || consumer.last_name as consumer_name
       FROM bookings b
       JOIN barbers barber ON b."barberId" = barber.id
       JOIN users consumer ON b."consumerId" = consumer.id
       WHERE b.id = $1 AND barber."userId" = $2`,
      [id, userId]
    );

    if (barberCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Only the barber can undo completion of this booking' 
      });
    }

    const booking = barberCheck.rows[0];

    logger.info(`[UNDO-COMPLETE] Booking ${id} current status: ${booking.status}`);

    // Only allow undo if status is COMPLETED (not yet paid)
    // Also block if already PAID, CANCELLED, or REJECTED
    if (booking.status === 'PAID') {
      return res.status(400).json({ 
        success: false, 
        error: 'Cannot undo completion. The customer has already paid for this service.' 
      });
    }
    
    if (booking.status === 'CANCELLED' || booking.status === 'REJECTED') {
      return res.status(400).json({ 
        success: false, 
        error: `Cannot undo completion. Booking was ${booking.status.toLowerCase()}.` 
      });
    }
    
    if (booking.status === 'ACCEPTED' || booking.status === 'PENDING') {
      return res.status(400).json({ 
        success: false, 
        error: 'This booking has not been marked as complete yet.' 
      });
    }
    
    // Only proceed if status is COMPLETED
    if (booking.status !== 'COMPLETED') {
      return res.status(400).json({ 
        success: false, 
        error: `Cannot undo completion. Unexpected booking status: ${booking.status}` 
      });
    }

    // Revert booking status back to ACCEPTED and clear paymentRequestedAt
    const result = await pool.query(
      `UPDATE bookings 
       SET status = 'ACCEPTED', 
           "paymentRequestedAt" = NULL,
           "updatedAt" = CURRENT_TIMESTAMP
       WHERE id = $1
       RETURNING id, status`,
      [id]
    );

    // Reactivate the conversation (it was marked inactive on completion)
    await pool.query(
      `UPDATE conversations SET is_active = true WHERE booking_id = $1`,
      [id]
    );
    logger.info(`Reactivated conversation for booking ${id}, cleared paymentRequestedAt`);

    logger.info(`Booking ${id} reverted from COMPLETED to ACCEPTED by barber ${userId}`);

    // Notify consumer that the completion was undone
    const io = getSocketIO();
    if (io) {
      logger.info(`[UNDO-COMPLETE] Emitting booking-status-changed to user-${booking.consumerId} for booking ${id}`);
      io.to(`user-${booking.consumerId}`).emit('booking-status-changed', {
        bookingId: id,
        status: 'ACCEPTED',
        message: 'The barber has reverted the service completion.',
      });
    } else {
      logger.warn(`[UNDO-COMPLETE] Socket.IO not available, could not notify consumer ${booking.consumerId}`);
    }

    res.json({
      success: true,
      data: { booking: result.rows[0] },
      message: 'Booking completion undone. Status reverted to ACCEPTED.',
    });
  } catch (error: any) {
    logger.error('Error undoing booking completion:', error.message || error);
    next(error);
  }
});

/**
 * GET /api/v1/bookings-simple
 * Get bookings for the authenticated user (barber or consumer)
 * Query params:
 *   - status: filter by status (PENDING, ACCEPTED, COMPLETED, etc.)
 *   - startDate: filter from this date
 *   - endDate: filter until this date
 *   - role: 'barber' or 'consumer' to specify which side of the booking
 */
router.get('/', authenticate, async (req, res, next) => {
  try {
    const userId = (req as any).user.userId;
    const { status, startDate, endDate, role } = req.query;

    // Build query based on role
    let whereClause = '';
    const params: any[] = [];
    let paramIndex = 1;

    // Determine if user is a barber
    const barberCheck = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1',
      [userId]
    );
    const isBarber = barberCheck.rows.length > 0;
    const barberRecordId = isBarber ? barberCheck.rows[0].id : null;

    // Build the where clause based on role
    if (role === 'barber' && barberRecordId) {
      whereClause = `b."barberId" = $${paramIndex}`;
      params.push(barberRecordId);
      paramIndex++;
    } else if (role === 'consumer') {
      whereClause = `b."consumerId" = $${paramIndex}`;
      params.push(userId);
      paramIndex++;
    } else {
      // Default: show both consumer and barber bookings
      if (barberRecordId) {
        whereClause = `(b."barberId" = $${paramIndex} OR b."consumerId" = $${paramIndex + 1})`;
        params.push(barberRecordId, userId);
        paramIndex += 2;
      } else {
        whereClause = `b."consumerId" = $${paramIndex}`;
        params.push(userId);
        paramIndex++;
      }
    }

    // Filter by status (supports comma-separated values like "PENDING,ACCEPTED")
    if (status) {
      const statusValues = (status as string).split(',').map(s => s.trim().toUpperCase());
      if (statusValues.length === 1) {
        whereClause += ` AND UPPER(b.status::text) = $${paramIndex}`;
        params.push(statusValues[0]);
        paramIndex++;
      } else {
        // Build IN clause for multiple statuses
        const placeholders = statusValues.map((_, i) => `$${paramIndex + i}`).join(', ');
        whereClause += ` AND UPPER(b.status::text) IN (${placeholders})`;
        statusValues.forEach(sv => params.push(sv));
        paramIndex += statusValues.length;
      }
    }

    // Filter by date range
    if (startDate) {
      whereClause += ` AND b."requestedAt" >= $${paramIndex}`;
      params.push(new Date(startDate as string));
      paramIndex++;
    }
    if (endDate) {
      whereClause += ` AND b."requestedAt" <= $${paramIndex}`;
      params.push(new Date(endDate as string));
      paramIndex++;
    }

    // Consumer hid this booking from their timeline (barber / other roles unaffected)
    whereClause += ` AND NOT EXISTS (
      SELECT 1 FROM consumer_hidden_bookings ch
      WHERE ch.booking_id = b.id AND ch.consumer_id = $${paramIndex}
    )`;
    params.push(userId);
    paramIndex++;

    logger.info('Fetching bookings', { 
      userId, 
      role, 
      status, 
      barberRecordId, 
      whereClause,
      params 
    });

    const result = await pool.query(
      `SELECT 
        b.id,
        b."consumerId",
        b."barberId",
        b."serviceType",
        b."priceUsdCents",
        b."tipAmountCents",
        b."totalPaidCents",
        COALESCE(b."requestedAt", c.scheduled_time) as "scheduledTime",
        b.status,
        b."createdAt",
        b."paymentRequestedAt",
        b."paidAt",
        b."paymentMethod",
        b."reviewRating",
        b."reviewComment",
        b."reviewedAt",
        consumer.first_name as consumer_first_name,
        consumer.last_name as consumer_last_name,
        consumer."avatarUrl" as consumer_avatar,
        barber_user.first_name as barber_first_name,
        barber_user.last_name as barber_last_name,
        barber_user."avatarUrl" as barber_avatar,
        -- Prefer snapshot on booking (survives conversation delete after payment), else conversation
        COALESCE(
          NULLIF(TRIM(b."serviceLocation"), ''),
          c.location,
          NULLIF(TRIM(b."serviceLocationDetails"), ''),
          c.location_details
        ) as conv_location,
        c.notes as conv_notes,
        c.service_name as conv_service_name
      FROM bookings b
      LEFT JOIN users consumer ON b."consumerId" = consumer.id
      LEFT JOIN barbers barber ON b."barberId" = barber.id
      LEFT JOIN users barber_user ON barber."userId" = barber_user.id
      LEFT JOIN conversations c ON c.booking_id = b.id
      WHERE ${whereClause}
      ORDER BY b."requestedAt" ASC`,
      params
    );

    logger.info('Bookings fetched', { count: result.rows.length });

    // Helper to format service type: "HAIRCUT" -> "Haircut", "BEARD_TRIM" -> "Beard Trim"
    const formatServiceType = (type: string) => {
      if (!type) return 'Haircut';
      return type
        .toLowerCase()
        .replace(/_/g, ' ')
        .replace(/\b\w/g, c => c.toUpperCase());
    };

    // Prevent caching to ensure fresh data after edits
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');

    res.json({
      success: true,
      data: {
        bookings: result.rows.map(row => ({
          id: row.id,
          consumerId: row.consumerId,
          barberId: row.barberId,
          // Prefer original service name from conversation, fallback to formatted enum
          serviceType: row.conv_service_name || formatServiceType(row.serviceType),
          priceUsdCents: row.priceUsdCents,
          tipAmountCents: row.tipAmountCents || null,
          totalPaidCents: row.totalPaidCents || null,
          scheduledTime: row.scheduledTime,
          status: row.status,
          createdAt: row.createdAt,
          // Consumer-provided input data from conversation
          location: row.conv_location || null,
          notes: row.conv_notes || null,
          serviceName: row.conv_service_name || null,
          // Payment tracking fields
          paymentRequestedAt: row.paymentRequestedAt || null,
          paidAt: row.paidAt || null,
          paymentMethod: row.paymentMethod || null,
          // Review data (from consumer after service completion)
          review: row.reviewRating ? {
            rating: row.reviewRating,
            comment: row.reviewComment || null,
            reviewedAt: row.reviewedAt,
          } : null,
          // Full barber name for display
          barberName: `${row.barber_first_name || ''} ${row.barber_last_name || ''}`.trim() || 'Barber',
          barberAvatar: row.barber_avatar || null,
          consumer: {
            firstName: row.consumer_first_name,
            lastName: row.consumer_last_name,
            avatar: row.consumer_avatar,
          },
          barber: {
            firstName: row.barber_first_name,
            lastName: row.barber_last_name,
            avatar: row.barber_avatar,
          },
        })),
      },
      count: result.rows.length,
    });
  } catch (error: any) {
    logger.error('Error fetching bookings:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/bookings-simple/:id/request-payment
 * Barber requests payment from consumer (marks service as ready for payment)
 * This triggers a notification to the consumer and sets payment_requested_at
 */
router.post('/:id/request-payment', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const userId = (req as any).user.userId;

    // Verify user is the barber for this booking
    const bookingCheck = await pool.query(
      `SELECT b.id, b."consumerId", b."barberId", b."priceUsdCents", b.status,
              b."requestedAt" as scheduled_time,
              c.service_name, c.location,
              barber."userId" as barber_user_id,
              barber_user.first_name || ' ' || barber_user.last_name as barber_name,
              consumer.first_name || ' ' || consumer.last_name as consumer_name,
              consumer.email as consumer_email,
              COALESCE(campus.timezone, 'America/Los_Angeles') as campus_timezone
       FROM bookings b
       LEFT JOIN conversations c ON c.booking_id = b.id
       JOIN barbers barber ON b."barberId" = barber.id
       JOIN users barber_user ON barber."userId" = barber_user.id
       JOIN users consumer ON b."consumerId" = consumer.id
       LEFT JOIN campuses campus ON barber_user."campusId" = campus.id
       WHERE b.id = $1`,
      [id]
    );

    if (bookingCheck.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Booking not found' 
      });
    }

    const booking = bookingCheck.rows[0];

    // Check if user is the barber (normalize UUIDs — pg vs JWT can differ by case)
    if (!sameUuid(booking.barber_user_id, userId)) {
      return res.status(403).json({ 
        success: false, 
        error: 'Only the barber can request payment' 
      });
    }

    if (booking.status !== 'ACCEPTED') {
      return res.status(400).json({
        success: false,
        error: 'Can only request payment for accepted bookings'
      });
    }

    // Update booking with payment_requested_at timestamp and set status to COMPLETED
    await pool.query(
      `UPDATE bookings 
       SET status = 'COMPLETED',
           "paymentRequestedAt" = CURRENT_TIMESTAMP, 
           "updatedAt" = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [id]
    );

    logger.info(`Payment requested for booking ${id} by barber ${userId}, status set to COMPLETED`);

    // Send notification to consumer
    try {
      const notificationService = (await import('../services/notification.service')).default;
      await notificationService.saveNotification({
        userId: booking.consumerId,
        type: 'payment_request',
        title: 'Payment Required',
        message: `${booking.barber_name} has marked your service as complete. Please complete your payment.`,
        data: {
          bookingId: id,
          barberId: booking.barberId,
          barberName: booking.barber_name,
          serviceName: booking.service_name || 'Haircut',
          amount: booking.priceUsdCents,
        },
      });
    } catch (notifError) {
      logger.error('Failed to send payment request notification:', notifError);
    }

    // Send payment request email to consumer
    const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
    const paymentUrl = `${frontendUrl}/web/payment/${id}`;
    const serviceName = booking.service_name || 'Haircut';
    
    // Format scheduled date/time using the barber's campus timezone
    const campusTimezone = booking.campus_timezone || 'America/Los_Angeles';
    const scheduledDate = booking.scheduled_time 
      ? new Date(booking.scheduled_time).toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric', timeZone: campusTimezone })
      : 'N/A';
    const scheduledTime = booking.scheduled_time
      ? new Date(booking.scheduled_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: campusTimezone })
      : 'N/A';
    
    logger.info(`[REQUEST-PAYMENT] About to send payment request email for booking ${id}`);
    logger.info(`[REQUEST-PAYMENT] Consumer: ${booking.consumer_name} <${booking.consumer_email}>`);
    
    try {
      await sendBookingCompletedEmails({
        bookingId: id,
        serviceName,
        price: booking.priceUsdCents / 100,
        scheduledDate,
        scheduledTime,
        location: booking.location,
        consumerName: booking.consumer_name,
        consumerEmail: booking.consumer_email,
        barberName: booking.barber_name,
        barberEmail: '', // Don't send to barber from this endpoint - they initiated it
        paymentUrl,
      });
      logger.info(`[REQUEST-PAYMENT] ✅ Payment request email sent for booking ${id}`);
    } catch (emailError: any) {
      logger.error(`[REQUEST-PAYMENT] ❌ Failed to send payment request email for ${id}:`, emailError.message);
    }

    res.json({
      success: true,
      message: 'Payment request sent to consumer',
      paymentRequestedAt: new Date().toISOString(),
    });
  } catch (error: any) {
    logger.error('Error requesting payment:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/bookings-simple/:id/create-payment-intent
 * Create a Stripe payment intent for the booking
 * Only the consumer can initiate payment
 */
router.post('/:id/create-payment-intent', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const { tipAmountCents = 0, stripeAccountId: clientStripeAccountId } = req.body;
    const userId = (req as any).user.userId;

    // Verify user is the consumer for this booking
    const bookingCheck = await pool.query(
      `SELECT b.id, b."consumerId", b."barberId", b."priceUsdCents", b.status,
              c.service_name,
              barber."userId" as barber_user_id,
              barber_user.first_name || ' ' || barber_user.last_name as barber_name
       FROM bookings b
       LEFT JOIN conversations c ON c.booking_id = b.id
       JOIN barbers barber ON b."barberId" = barber.id
       JOIN users barber_user ON barber."userId" = barber_user.id
       WHERE b.id = $1 AND b."consumerId" = $2`,
      [id, userId]
    );

    if (bookingCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Booking not found or access denied' 
      });
    }

    const booking = bookingCheck.rows[0];

    if (booking.status !== 'ACCEPTED' && booking.status !== 'COMPLETED') {
      return res.status(400).json({
        success: false,
        error: 'Can only pay for accepted or completed bookings'
      });
    }

    const totalAmountCents = booking.priceUsdCents + tipAmountCents;

    const stripeSecret = getDefaultStripeSecretKey();
    if (process.env.NODE_ENV === 'production' && stripeSecret.startsWith('sk_test_')) {
      logger.error(
        'Stripe: production is using sk_test (check STRIPE_SECRET_KEY / STRIPE_MODE). Test PaymentIntents cannot be loaded with pk_live in the app (Stripe returns resource_missing / 404).'
      );
      return res.status(503).json({
        success: false,
        error: 'Payments are temporarily unavailable. Please try again later.',
      });
    }

    const stripe = getDefaultStripeClient();

    // Get consumer's email and name for Stripe customer creation
    const consumerResult = await pool.query(
      'SELECT email, first_name, last_name FROM users WHERE id = $1',
      [userId]
    );
    const consumer = consumerResult.rows[0];

    // Create or get Stripe customer for this consumer
    let stripeCustomerId: string | undefined;
    if (consumer?.email) {
      try {
        // Check if customer already exists
        const existingCustomers = await stripe.customers.list({
          email: consumer.email,
          limit: 1,
        });

        if (existingCustomers.data.length > 0) {
          stripeCustomerId = existingCustomers.data[0].id;
        } else {
          // Create new customer
          const newCustomer = await stripe.customers.create({
            email: consumer.email,
            name: `${consumer.first_name || ''} ${consumer.last_name || ''}`.trim() || undefined,
            metadata: {
              userId: userId,
              platform: 'CampusCuts',
            },
          });
          stripeCustomerId = newCustomer.id;
          logger.info(`Created Stripe customer: ${stripeCustomerId} for user: ${userId}`);
        }
      } catch (customerError: any) {
        logger.warn(`Failed to create/get Stripe customer for ${consumer.email}: ${customerError.message}`);
        // Continue without customer - payment will still work, just won't be associated
      }
    }

    /** Ephemeral key must accompany a Customer on mobile PaymentSheet; omit customer from the PI if EK creation fails. */
    let customerEphemeralKeySecret: string | undefined;
    let customerIdForPaymentIntent: string | undefined = stripeCustomerId;
    if (stripeCustomerId) {
      try {
        const ek = await stripe.ephemeralKeys.create(
          { customer: stripeCustomerId },
          { apiVersion: STRIPE_IOS_SDK_API_VERSION }
        );
        customerEphemeralKeySecret = ek.secret ?? undefined;
      } catch (ekError: any) {
        logger.warn(
          `Failed to create Stripe ephemeral key for customer ${stripeCustomerId}: ${ekError.message}`
        );
        customerIdForPaymentIntent = undefined;
      }
    }

    // Get barber's Stripe Connect account ID for payment split
    const barberAccountResult = await pool.query(
      'SELECT stripe_account_id FROM users WHERE id = $1',
      [booking.barber_user_id]
    );
    const barberStripeAccountId = barberAccountResult.rows[0]?.stripe_account_id as string | undefined;

    // Optional: client sends Connect account for verification (Stripe Connect / multi-provider).
    if (
      clientStripeAccountId &&
      typeof clientStripeAccountId === 'string' &&
      barberStripeAccountId &&
      clientStripeAccountId.trim() !== barberStripeAccountId.trim()
    ) {
      return res.status(400).json({
        success: false,
        error: 'stripeAccountId does not match this booking’s provider',
      });
    }

    // Calculate platform fee (15% - covers Stripe's ~4% processing fee, nets ~11%)
    // IMPORTANT: Platform fee is calculated ONLY on the service amount, NOT on tips
    // Barbers receive 100% of tips - tips should never have fees deducted
    const PLATFORM_FEE_PERCENTAGE = 0.15;
    const serviceAmountCents = booking.priceUsdCents; // Service price only, excludes tip
    const platformFeeCents = Math.round(serviceAmountCents * PLATFORM_FEE_PERCENTAGE);

    // Build payment intent config — `card` only so PaymentSheet does not offer Link, US bank account, etc.
    // (Apple Pay / Google Pay still use the card network; physical card + phone wallet cards match product intent.)
    const paymentIntentConfig: any = {
      amount: totalAmountCents,
      currency: 'usd',
      payment_method_types: ['card'],
      // Stablecoin "Pay with Crypto" can still appear in Payment Element/MPE when enabled on the account; exclude at PI level.
      excluded_payment_method_types: ['crypto'],
      metadata: {
        booking_id: id,
        consumer_id: userId,
        barber_id: booking.barberId,
        barber_user_id: booking.barber_user_id,
        service_name: booking.service_name || 'Haircut',
        tip_amount_cents: tipAmountCents.toString(),
        platform_fee_cents: platformFeeCents.toString(),
        platform: 'CampusCuts',
      },
      description: `CampusCuts - ${booking.service_name || 'Haircut'} with ${booking.barber_name}`,
    };
    if (customerIdForPaymentIntent) {
      paymentIntentConfig.customer = customerIdForPaymentIntent;
    }

    // If barber has Stripe Connect account, use destination charges for automatic split
    // Platform takes 15% of SERVICE only (not tips), barber receives 85% of service + 100% of tips
    if (barberStripeAccountId) {
      paymentIntentConfig.application_fee_amount = platformFeeCents;
      paymentIntentConfig.transfer_data = {
        destination: barberStripeAccountId,
      };
      const barberEarnings = totalAmountCents - platformFeeCents;
      const tipInfo = tipAmountCents > 0 ? ` (includes $${tipAmountCents / 100} tip - barber keeps 100%)` : '';
      logger.info(`Payment split: $${platformFeeCents / 100} platform fee (15% of $${serviceAmountCents / 100} service), $${barberEarnings / 100} to barber${tipInfo} (${barberStripeAccountId})`);
    } else {
      logger.warn(`Barber ${booking.barber_user_id} has no Stripe Connect account - payment goes to platform. Manual payout required.`);
    }

    // Create payment intent
    const paymentIntent = await stripe.paymentIntents.create(paymentIntentConfig);

    logger.info(
      `Payment intent created for booking ${id}: ${paymentIntent.id} livemode=${paymentIntent.livemode}${barberStripeAccountId ? ' (with Connect split)' : ' (no Connect)'}`
    );

    const pkForVerify =
      process.env.STRIPE_PUBLISHABLE_KEY?.trim() ||
      process.env.VITE_STRIPE_PUBLISHABLE_KEY?.trim() ||
      '';
    await logIfPublishableKeyCannotRetrievePaymentIntent(
      pkForVerify,
      paymentIntent.id,
      paymentIntent.client_secret
    );

    const pkPrefix = stripePublishableKeyPrefixForClientVerification();
    res.json({
      success: true,
      data: {
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        /** Lets the mobile client refuse PaymentSheet when the app’s publishable key mode does not match (avoids opaque 404s). */
        livemode: paymentIntent.livemode,
        ...(pkPrefix ? { stripePublishableKeyPrefix: pkPrefix } : {}),
        ...(customerIdForPaymentIntent && customerEphemeralKeySecret
          ? {
              customerId: customerIdForPaymentIntent,
              customerEphemeralKeySecret,
            }
          : {}),
      },
    });
  } catch (error: any) {
    logger.error('Error creating payment intent:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/bookings-simple/:id/update-payment-intent
 * Update an existing payment intent amount (when tip changes)
 * This avoids recreating the payment intent which would reset payment method selection
 */
router.post('/:id/update-payment-intent', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const { paymentIntentId, tipAmountCents = 0 } = req.body;
    const userId = (req as any).user.userId;

    if (!paymentIntentId) {
      return res.status(400).json({
        success: false,
        error: 'paymentIntentId is required'
      });
    }

    // Verify user is the consumer for this booking
    const bookingCheck = await pool.query(
      `SELECT b.id, b."consumerId", b."priceUsdCents"
       FROM bookings b
       WHERE b.id = $1 AND b."consumerId" = $2`,
      [id, userId]
    );

    if (bookingCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Booking not found or access denied' 
      });
    }

    const booking = bookingCheck.rows[0];
    const totalAmountCents = booking.priceUsdCents + tipAmountCents;

    // Import Stripe and update the payment intent
    const stripe = getDefaultStripeClient();

    await stripe.paymentIntents.update(paymentIntentId, {
      amount: totalAmountCents,
      metadata: {
        booking_id: id,
        tip_amount_cents: tipAmountCents.toString(),
        base_amount_cents: booking.priceUsdCents.toString(),
      },
    });

    logger.info('Payment intent updated', { bookingId: id, paymentIntentId, totalAmountCents, tipAmountCents });

    res.json({
      success: true,
      data: {
        totalAmountCents,
        tipAmountCents,
      },
    });
  } catch (error: any) {
    logger.error('Error updating payment intent:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/bookings-simple/:id/confirm-payment
 * Confirm payment was successful and mark booking as completed
 * Only the consumer can confirm their payment
 */
router.post('/:id/confirm-payment', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const { paymentIntentId, tipAmountCents = 0 } = req.body;
    const userId = (req as any).user.userId;

    // Verify user is the consumer for this booking
    const bookingCheck = await pool.query(
      `SELECT b.id, b."consumerId", b."barberId", b."priceUsdCents", b.status,
              barber."userId" as barber_user_id,
              barber_user.first_name || ' ' || barber_user.last_name as barber_name
       FROM bookings b
       JOIN barbers barber ON b."barberId" = barber.id
       JOIN users barber_user ON barber."userId" = barber_user.id
       WHERE b.id = $1 AND b."consumerId" = $2`,
      [id, userId]
    );

    if (bookingCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Booking not found or access denied' 
      });
    }

    const booking = bookingCheck.rows[0];
    const totalAmountCents = booking.priceUsdCents + tipAmountCents;

    // Verify payment intent with Stripe
    const stripe = getDefaultStripeClient();
    
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    
    if (paymentIntent.status !== 'succeeded') {
      return res.status(400).json({
        success: false,
        error: 'Payment has not been completed'
      });
    }

    // Update booking with payment info and mark as PAID
    await pool.query(
      `UPDATE bookings 
       SET status = 'PAID',
           "completedAt" = CURRENT_TIMESTAMP,
           "tipAmountCents" = $1,
           "totalPaidCents" = $2,
           "paidAt" = CURRENT_TIMESTAMP,
           "paymentMethod" = 'card',
           "updatedAt" = CURRENT_TIMESTAMP
       WHERE id = $3`,
      [tipAmountCents, totalAmountCents, id]
    );

    // Archive messages for admin viewing, then delete the conversation
    try {
      await snapshotBookingLocationFromConversation(id, pool);
      await archiveBookingMessages(id);
      await pool.query(
        `DELETE FROM messages 
         WHERE conversation_id IN (SELECT id FROM conversations WHERE booking_id = $1)`,
        [id]
      );
      await pool.query(
        `DELETE FROM conversations WHERE booking_id = $1`,
        [id]
      );
      logger.info(`Archived and deleted conversation for paid booking ${id}`);
    } catch (convError: any) {
      // Conversation may already be deleted - that's fine
      logger.debug(`No conversation to delete for booking ${id}`);
    }

    // Notify barber of payment received
    await notificationService.saveNotification({
      userId: booking.barber_user_id,
      type: 'payment_received',
      title: 'Payment Received!',
      message: `You received $${(totalAmountCents / 100).toFixed(2)}${tipAmountCents > 0 ? ` (includes $${(tipAmountCents / 100).toFixed(2)} tip)` : ''}`,
      data: { bookingId: id, amount: totalAmountCents, tip: tipAmountCents },
    });

    logger.info(`Payment confirmed for booking ${id}: $${(totalAmountCents / 100).toFixed(2)} (tip: $${(tipAmountCents / 100).toFixed(2)})`);

    // Emit WebSocket event to barber for instant notification
    try {
      const io = getSocketIO();
      if (io) {
        // Get consumer info for the notification
        const consumerResult = await pool.query(
          `SELECT first_name, last_name FROM users WHERE id = $1`,
          [userId]
        );
        const consumer = consumerResult.rows[0];
        const consumerName = consumer ? `${consumer.first_name} ${consumer.last_name}` : 'Customer';

        const paymentData = {
          bookingId: id,
          consumerId: userId,
          consumerName,
          amountPaid: totalAmountCents,
          tipAmount: tipAmountCents,
          totalFormatted: `$${(totalAmountCents / 100).toFixed(2)}`,
          tipFormatted: tipAmountCents > 0 ? `$${(tipAmountCents / 100).toFixed(2)}` : undefined,
        };

        logger.info(`[payment-received] Emitting to barber user ${booking.barber_user_id} for booking ${id}`);
        io.to(`user-${booking.barber_user_id}`).emit('payment-received', paymentData);
        logger.info(`[payment-received] ✅ Emitted to room user-${booking.barber_user_id}`);
      }
    } catch (wsError: any) {
      logger.error(`[payment-received] Error emitting WebSocket event: ${wsError.message}`);
      // Don't fail the request if WebSocket emission fails
    }

    res.json({
      success: true,
      message: 'Payment confirmed and booking completed',
      data: {
        bookingId: id,
        amountPaid: totalAmountCents,
        tipAmount: tipAmountCents,
      },
    });
  } catch (error: any) {
    logger.error('Error confirming payment:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/bookings-simple/:id/pay
 * Process payment for a completed booking (legacy/mock endpoint)
 * Only the consumer can pay for their booking
 */
router.post('/:id/pay', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const { tipAmountCents = 0, paymentMethod = 'card' } = req.body;
    const userId = (req as any).user.userId;

    // Validate payment method
    if (!['card', 'cash'].includes(paymentMethod)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid payment method. Must be "card" or "cash"'
      });
    }

    // Verify user is the consumer for this booking
    const bookingCheck = await pool.query(
      `SELECT b.id, b."consumerId", b."barberId", b."priceUsdCents", b.status,
              barber."userId" as barber_user_id,
              barber_user.first_name || ' ' || barber_user.last_name as barber_name
       FROM bookings b
       JOIN barbers barber ON b."barberId" = barber.id
       JOIN users barber_user ON barber."userId" = barber_user.id
       WHERE b.id = $1 AND b."consumerId" = $2`,
      [id, userId]
    );

    if (bookingCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Booking not found or access denied' 
      });
    }

    const booking = bookingCheck.rows[0];

    // Allow payment for ACCEPTED or COMPLETED bookings
    // ACCEPTED = service agreed upon, COMPLETED = barber marked service done
    if (!['ACCEPTED', 'COMPLETED'].includes(booking.status)) {
      return res.status(400).json({
        success: false,
        error: 'Can only pay for accepted or completed bookings'
      });
    }

    const totalAmountCents = booking.priceUsdCents + tipAmountCents;

    // Update booking with payment info and set status to PAID
    await pool.query(
      `UPDATE bookings 
       SET status = 'PAID',
           "tipAmountCents" = $1,
           "totalPaidCents" = $2,
           "paidAt" = CURRENT_TIMESTAMP,
           "paymentMethod" = $3,
           "updatedAt" = CURRENT_TIMESTAMP
       WHERE id = $4`,
      [tipAmountCents, totalAmountCents, paymentMethod, id]
    );

    // Archive messages for admin viewing, then delete the conversation
    try {
      await snapshotBookingLocationFromConversation(id, pool);
      await archiveBookingMessages(id);
      await pool.query(
        `DELETE FROM messages 
         WHERE conversation_id IN (SELECT id FROM conversations WHERE booking_id = $1)`,
        [id]
      );
      await pool.query(
        `DELETE FROM conversations WHERE booking_id = $1`,
        [id]
      );
      logger.info(`Archived and deleted conversation for paid booking ${id}`);
    } catch (convError: any) {
      // Conversation may already be deleted - that's fine
      logger.debug(`No conversation to delete for booking ${id}`);
    }

    // Notify barber of payment received
    const paymentMethodLabel = paymentMethod === 'cash' ? 'Cash' : 'Card';
    await notificationService.saveNotification({
      userId: booking.barber_user_id,
      type: 'payment_received',
      title: 'Payment Received!',
      message: `You received $${(totalAmountCents / 100).toFixed(2)} (${paymentMethodLabel})${tipAmountCents > 0 ? ` - includes $${(tipAmountCents / 100).toFixed(2)} tip` : ''}`,
      data: { bookingId: id, amount: totalAmountCents, tip: tipAmountCents, paymentMethod },
    });

    logger.info(`Payment processed for booking ${id}: $${(totalAmountCents / 100).toFixed(2)} via ${paymentMethod} (tip: $${(tipAmountCents / 100).toFixed(2)})`);

    // Emit WebSocket event to barber for instant notification (same as card payment)
    try {
      const io = getSocketIO();
      if (io) {
        // Get consumer info for the notification
        const consumerResult = await pool.query(
          `SELECT first_name, last_name FROM users WHERE id = $1`,
          [userId]
        );
        const consumer = consumerResult.rows[0];
        const consumerName = consumer ? `${consumer.first_name} ${consumer.last_name}` : 'Customer';

        const paymentData = {
          bookingId: id,
          consumerId: userId,
          consumerName,
          amountPaid: totalAmountCents,
          tipAmount: tipAmountCents,
          totalFormatted: `$${(totalAmountCents / 100).toFixed(2)}`,
          tipFormatted: tipAmountCents > 0 ? `$${(tipAmountCents / 100).toFixed(2)}` : undefined,
          paymentMethod,
        };

        logger.info(`[payment-received] Emitting to barber user ${booking.barber_user_id} for booking ${id} (${paymentMethod})`);
        io.to(`user-${booking.barber_user_id}`).emit('payment-received', paymentData);
        logger.info(`[payment-received] ✅ Emitted to room user-${booking.barber_user_id}`);
      }
    } catch (wsError: any) {
      logger.error(`[payment-received] Error emitting WebSocket event: ${wsError.message}`);
      // Don't fail the request if WebSocket emission fails
    }

    res.json({
      success: true,
      message: 'Payment processed successfully',
      data: {
        bookingId: id,
        amountPaid: totalAmountCents,
        tipAmount: tipAmountCents,
        paymentMethod,
      },
    });
  } catch (error: any) {
    logger.error('Error processing payment:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/bookings-simple/:id/review
 * Submit a review for a completed booking
 * Only the consumer can review their booking
 */
router.post('/:id/review', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const { rating, comment } = req.body;
    const userId = (req as any).user.userId;

    // Validate rating
    if (!rating || rating < 1 || rating > 5) {
      return res.status(400).json({
        success: false,
        error: 'Rating must be between 1 and 5'
      });
    }

    // Verify user is the consumer for this booking
    const bookingCheck = await pool.query(
      `SELECT b.id, b."consumerId", b."barberId", b.status,
              barber."userId" as barber_user_id,
              barber_user.first_name || ' ' || barber_user.last_name as barber_name,
              consumer.first_name || ' ' || consumer.last_name as consumer_name
       FROM bookings b
       JOIN barbers barber ON b."barberId" = barber.id
       JOIN users barber_user ON barber."userId" = barber_user.id
       JOIN users consumer ON b."consumerId" = consumer.id
       WHERE b.id = $1 AND b."consumerId" = $2`,
      [id, userId]
    );

    if (bookingCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Booking not found or access denied' 
      });
    }

    const booking = bookingCheck.rows[0];

    // Store review in bookings table (simple approach)
    await pool.query(
      `UPDATE bookings 
       SET "reviewRating" = $1,
           "reviewComment" = $2,
           "reviewedAt" = CURRENT_TIMESTAMP,
           "updatedAt" = CURRENT_TIMESTAMP
       WHERE id = $3`,
      [rating, comment || null, id]
    );

    // Update barber's average rating
    const ratingResult = await pool.query(
      `SELECT AVG("reviewRating")::numeric(3,2) as avg_rating, COUNT(*) as review_count
       FROM bookings 
       WHERE "barberId" = $1 AND "reviewRating" IS NOT NULL`,
      [booking.barberId]
    );

    if (ratingResult.rows.length > 0) {
      await pool.query(
        `UPDATE barbers 
         SET "avgRating" = $1, "totalReviews" = $2, "updatedAt" = CURRENT_TIMESTAMP
         WHERE id = $3`,
        [ratingResult.rows[0].avg_rating, ratingResult.rows[0].review_count, booking.barberId]
      );
    }

    // Notify barber of new review
    await notificationService.saveNotification({
      userId: booking.barber_user_id,
      type: 'new_review',
      title: `New ${rating}-Star Review`,
      message: `${booking.consumer_name} left you a ${rating}-star review${comment ? `: "${comment.substring(0, 50)}${comment.length > 50 ? '...' : ''}"` : ''}`,
      data: { bookingId: id, rating, comment },
    });

    logger.info(`Review submitted for booking ${id}: ${rating} stars`);

    res.json({
      success: true,
      message: 'Review submitted successfully',
      data: {
        bookingId: id,
        rating,
        comment,
      },
    });
  } catch (error: any) {
    logger.error('Error submitting review:', error.message || error);
    next(error);
  }
});

/**
 * PUT /api/v1/bookings-simple/:id
 * Edit booking details (barber only for ACCEPTED bookings)
 * - scheduledTime updates the bookings table ("requestedAt" column)
 * - location, notes, and serviceName update the linked conversations table
 */
router.put('/:id', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const userId = (req as any).user.userId;
    const { scheduledTime, location, notes, serviceName } = req.body;

    // Check if user is barber or consumer for this booking
    const bookingCheck = await pool.query(
      `SELECT b.id, b.status, b."consumerId", b."barberId", b."requestedAt", b."serviceType",
              bar."userId" as barber_user_id,
              u_consumer.first_name as consumer_first_name, u_consumer.last_name as consumer_last_name,
              u_consumer.email as consumer_email,
              u_barber.first_name as barber_first_name, u_barber.last_name as barber_last_name,
              u_barber.email as barber_email,
              c.id as conversation_id, c.location as conv_location, c.notes as conv_notes, c.service_name
       FROM bookings b
       JOIN barbers bar ON b."barberId" = bar.id
       JOIN users u_consumer ON b."consumerId" = u_consumer.id
       JOIN users u_barber ON bar."userId" = u_barber.id
       LEFT JOIN conversations c ON c.booking_id = b.id
       WHERE b.id = $1 AND (bar."userId" = $2 OR b."consumerId" = $2)`,
      [id, userId]
    );

    if (bookingCheck.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Booking not found or access denied' });
    }

    const booking = bookingCheck.rows[0];
    const isBarber = sameUuid(booking.barber_user_id, userId);
    const isConsumer = sameUuid(booking.consumerId, userId);

    // Only allow editing PENDING or ACCEPTED bookings
    if (booking.status !== 'ACCEPTED' && booking.status !== 'PENDING') {
      return res.status(400).json({ 
        success: false, 
        error: `Cannot edit a ${booking.status.toLowerCase()} booking` 
      });
    }

    let updatedScheduledTime = booking.requestedAt;
    let updatedLocation = booking.conv_location;
    let updatedNotes = booking.conv_notes;
    let updatedServiceName = booking.service_name;

    // Update scheduledTime on bookings table
    if (scheduledTime !== undefined) {
      await pool.query(
        `UPDATE bookings 
         SET "requestedAt" = $1, "updatedAt" = CURRENT_TIMESTAMP
         WHERE id = $2`,
        [scheduledTime, id]
      );
      updatedScheduledTime = scheduledTime;
      logger.info(`Updated booking ${id} scheduledTime to ${scheduledTime}`);
    }

    // Update scheduled_time, location, notes, and/or service_name on conversations table (if linked)
    if (scheduledTime !== undefined || location !== undefined || notes !== undefined || serviceName !== undefined) {
      if (booking.conversation_id) {
        const convUpdates: string[] = [];
        const convValues: any[] = [];
        let convParamIndex = 1;

        if (scheduledTime !== undefined) {
          convUpdates.push(`scheduled_time = $${convParamIndex++}`);
          convValues.push(scheduledTime);
        }
        if (location !== undefined) {
          convUpdates.push(`location = $${convParamIndex++}`);
          convValues.push(location);
          updatedLocation = location;
        }
        if (notes !== undefined) {
          convUpdates.push(`notes = $${convParamIndex++}`);
          convValues.push(notes);
          updatedNotes = notes;
        }
        if (serviceName !== undefined) {
          convUpdates.push(`service_name = $${convParamIndex++}`);
          convValues.push(serviceName);
          updatedServiceName = serviceName;
        }

        if (convUpdates.length > 0) {
          convUpdates.push(`updated_at = CURRENT_TIMESTAMP`);
          convValues.push(booking.conversation_id);

          await pool.query(
            `UPDATE conversations 
             SET ${convUpdates.join(', ')}
             WHERE id = $${convParamIndex}`,
            convValues
          );
          logger.info(`Updated conversation ${booking.conversation_id} with scheduled_time/location/notes/service_name`);
        }
      } else {
        // No linked conversation - try to find or create one
        logger.warn(`Booking ${id} has no linked conversation, attempting to find by participants`);
        
        // Try to find existing conversation between barber and consumer
        const convSearch = await pool.query(
          `SELECT id FROM conversations 
           WHERE (user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1)
           LIMIT 1`,
          [userId, booking.consumerId]
        );

        if (convSearch.rows.length > 0) {
          const convId = convSearch.rows[0].id;
          
          // Link conversation to booking and update fields
          const convUpdates: string[] = [`booking_id = '${id}'`];
          const convValues: any[] = [];
          let convParamIndex = 1;

          if (scheduledTime !== undefined) {
            convUpdates.push(`scheduled_time = $${convParamIndex++}`);
            convValues.push(scheduledTime);
          }
          if (location !== undefined) {
            convUpdates.push(`location = $${convParamIndex++}`);
            convValues.push(location);
            updatedLocation = location;
          }
          if (notes !== undefined) {
            convUpdates.push(`notes = $${convParamIndex++}`);
            convValues.push(notes);
            updatedNotes = notes;
          }
          if (serviceName !== undefined) {
            convUpdates.push(`service_name = $${convParamIndex++}`);
            convValues.push(serviceName);
            updatedServiceName = serviceName;
          }

          convUpdates.push(`updated_at = CURRENT_TIMESTAMP`);
          convValues.push(convId);

          await pool.query(
            `UPDATE conversations 
             SET ${convUpdates.join(', ')}
             WHERE id = $${convParamIndex}`,
            convValues
          );
          logger.info(`Linked and updated conversation ${convId} for booking ${id}`);
        } else {
          logger.warn(`No conversation found for booking ${id} - scheduled_time/location/notes not saved to conversation`);
          // Still update the response values so frontend shows what user entered
          if (location !== undefined) updatedLocation = location;
          if (notes !== undefined) updatedNotes = notes;
          if (serviceName !== undefined) updatedServiceName = serviceName;
        }
      }
    }

    // If scheduledTime was changed, notify the OTHER party and send emails
    if (scheduledTime) {
      const barberName = `${booking.barber_first_name} ${booking.barber_last_name}`.trim() || 'Your barber';
      const consumerName = `${booking.consumer_first_name} ${booking.consumer_last_name}`.trim() || 'Customer';
      const barberEmail = booking.barber_email;
      const consumerEmail = booking.consumer_email;

      // Use Pacific timezone for consistent display across all platforms
      const timeZone = 'America/Los_Angeles';
      
      const newDate = new Date(scheduledTime);
      const formattedDate = newDate.toLocaleDateString('en-US', { 
        weekday: 'short', month: 'short', day: 'numeric',
        timeZone 
      });
      const formattedTime = newDate.toLocaleTimeString('en-US', { 
        hour: 'numeric', minute: '2-digit',
        timeZone 
      });

      // Get the original scheduled time for comparison in notification data
      const originalScheduledTime = booking.original_scheduled_time || booking.requestedAt;
      const originalDate = new Date(originalScheduledTime);
      const originalFormattedDate = originalDate.toLocaleDateString('en-US', { 
        weekday: 'short', month: 'short', day: 'numeric',
        timeZone 
      });
      const originalFormattedTime = originalDate.toLocaleTimeString('en-US', { 
        hour: 'numeric', minute: '2-digit',
        timeZone 
      });

      // Notify the OTHER party (not the one who made the edit)
      if (isBarber) {
        // Barber edited, notify consumer
        await notificationService.saveNotification({
          userId: booking.consumerId,
          type: 'booking_updated',
          title: 'Booking Updated',
          message: `${barberName} has rescheduled your appointment to ${formattedDate} at ${formattedTime}`,
          data: { 
            bookingId: id, 
            newScheduledTime: scheduledTime,
            originalScheduledTime: originalScheduledTime,
            editedBy: 'barber',
          },
        });
      } else {
        // Consumer edited, notify barber
        await notificationService.saveNotification({
          userId: booking.barber_user_id,
          type: 'booking_updated',
          title: 'Booking Updated',
          message: `${consumerName} has rescheduled their appointment to ${formattedDate} at ${formattedTime}`,
          data: { 
            bookingId: id, 
            newScheduledTime: scheduledTime,
            originalScheduledTime: originalScheduledTime,
            editedBy: 'consumer',
          },
        });
      }

      // Get service details for email
      const serviceName = booking.service_name || booking.serviceType || 'Haircut';
      const priceResult = await pool.query(
        `SELECT "priceUsdCents" FROM bookings WHERE id = $1`,
        [id]
      );
      const priceUsdCents = priceResult.rows[0]?.priceUsdCents || 0;

      if (consumerEmail && barberEmail) {
        sendBookingEditEmails({
          consumerEmail,
          consumerName,
          barberEmail,
          barberName,
          serviceName,
          originalScheduledDate: originalFormattedDate,
          originalScheduledTime: originalFormattedTime,
          newScheduledDate: formattedDate,
          newScheduledTime: formattedTime,
          originalLocation: booking.conv_location || undefined,
          newLocation: updatedLocation || undefined,
          originalNotes: booking.conv_notes || undefined,
          newNotes: updatedNotes || undefined,
          price: priceUsdCents / 100,
          bookingId: id,
        }).catch(err => logger.error('Failed to send booking edit emails:', err));
      }
    }

    logger.info(`Booking ${id} updated by ${isBarber ? 'barber' : 'consumer'} ${userId}`);

    // Emit booking-update event via WebSocket for live updates
    const bookingUpdate = {
      id,
      scheduledTime: updatedScheduledTime,
      location: updatedLocation,
      notes: updatedNotes,
      status: booking.status,
      barberId: booking.barberId,
      consumerId: booking.consumerId,
      serviceType: booking.serviceType,
      updatedBy: isBarber ? 'barber' : 'consumer',
    };
    
    // Emit to both barber and consumer's personal rooms
    const io = getSocketIO();
    if (io) {
      io.to(`user-${booking.barber_user_id}`).emit('booking-update', bookingUpdate);
      io.to(`user-${booking.consumerId}`).emit('booking-update', bookingUpdate);
      logger.info(`Emitted booking-update event for booking ${id}`);
    }

    res.json({
      success: true,
      message: 'Booking updated successfully',
      data: { 
        booking: {
          id,
          scheduledTime: updatedScheduledTime,
          location: updatedLocation,
          notes: updatedNotes,
          serviceName: updatedServiceName,
          status: booking.status,
        }
      },
    });
  } catch (error: any) {
    logger.error('Error updating booking:', error.message || error);
    next(error);
  }
});

/**
 * DELETE /api/v1/bookings-simple/:id
 * Cancel/delete a booking (barber or consumer for non-completed bookings)
 */
router.delete('/:id', authenticate, async (req, res, next) => {
  try {
    const { id } = req.params;
    const userId = (req as any).user.userId;
    const { reason } = req.body;

    // Check if user is barber or consumer for this booking (include campus timezone)
    const bookingCheck = await pool.query(
      `SELECT b.id, b.status, b."consumerId", b."serviceType", b."priceUsdCents", COALESCE(b."requestedAt", c.scheduled_time) as "scheduledTime",
              c.location, c.service_name as original_service_name,
              bar.id as "barberId", bar."userId" as barber_user_id, bar."campusId" as campus_id,
              u_consumer.first_name as consumer_first_name, u_consumer.last_name as consumer_last_name, u_consumer.email as consumer_email,
              u_barber.first_name as barber_first_name, u_barber.last_name as barber_last_name, u_barber.email as barber_email,
              COALESCE(campus.timezone, 'America/New_York') as campus_timezone
       FROM bookings b
       JOIN barbers bar ON b."barberId" = bar.id
       JOIN users u_consumer ON b."consumerId" = u_consumer.id
       JOIN users u_barber ON bar."userId" = u_barber.id
       LEFT JOIN conversations c ON c.booking_id = b.id
       LEFT JOIN campuses campus ON bar."campusId" = campus.id
       WHERE b.id = $1 AND (bar."userId" = $2 OR b."consumerId" = $2)`,
      [id, userId]
    );

    if (bookingCheck.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Booking not found or access denied' });
    }

    const booking = bookingCheck.rows[0];
    const isBarber = sameUuid(booking.barber_user_id, userId);
    const isConsumer = sameUuid(booking.consumerId, userId);

    // Check if user is an admin (only admins can remove completed/paid bookings)
    const adminCheck = await pool.query(
      `SELECT role FROM users WHERE id = $1`,
      [userId]
    );
    const isAdmin = adminCheck.rows.length > 0 && adminCheck.rows[0].role === 'ADMIN';

    // Only allow ADMINS to remove completed/paid bookings from schedule
    if ((booking.status === 'COMPLETED' || booking.status === 'PAID') && isAdmin) {
      // For completed bookings, actually delete instead of just cancelling
      // Delete conversation first if exists
      const convResult = await pool.query(
        `SELECT id FROM conversations WHERE booking_id = $1`,
        [id]
      );
      
      if (convResult.rows.length > 0) {
        const conversationId = convResult.rows[0].id;
        await pool.query(`DELETE FROM messages WHERE conversation_id = $1`, [conversationId]);
        await pool.query(`DELETE FROM conversations WHERE id = $1`, [conversationId]);
        logger.info(`Deleted conversation for removed completed booking ${id}`);
      }

      // Delete associated payment records first (foreign key constraint)
      await pool.query(`DELETE FROM payments WHERE booking_id = $1`, [id]);
      logger.info(`Deleted payment records for booking ${id}`);

      // Delete the booking
      await pool.query(`DELETE FROM bookings WHERE id = $1`, [id]);
      
      logger.info(`Admin ${userId} removed completed booking ${id} from schedule`);
      
      return res.json({
        success: true,
        message: 'Booking removed from schedule',
      });
    }

    // Barbers and consumers cannot delete completed bookings
    if (booking.status === 'COMPLETED' || booking.status === 'PAID') {
      return res.status(400).json({ 
        success: false, 
        error: 'Cannot cancel a completed booking' 
      });
    }
    if (booking.status === 'CANCELLED') {
      return res.status(400).json({ 
        success: false, 
        error: 'Booking is already cancelled' 
      });
    }

    // Update booking status to CANCELLED instead of deleting
    await pool.query(
      `UPDATE bookings 
       SET status = 'CANCELLED', "updatedAt" = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [id]
    );

    // Delete the conversation and its messages when booking is cancelled
    const convResult = await pool.query(
      `SELECT id FROM conversations WHERE booking_id = $1`,
      [id]
    );
    
    if (convResult.rows.length > 0) {
      const conversationId = convResult.rows[0].id;
      
      // Delete all messages in the conversation first (foreign key constraint)
      await pool.query(
        `DELETE FROM messages WHERE conversation_id = $1`,
        [conversationId]
      );
      
      // Delete the conversation
      await pool.query(
        `DELETE FROM conversations WHERE id = $1`,
        [conversationId]
      );
      
      logger.info(`Deleted conversation ${conversationId} and its messages for cancelled booking ${id}`);
    }

    const barberName = `${booking.barber_first_name} ${booking.barber_last_name}`.trim() || 'Your barber';
    const consumerName = `${booking.consumer_first_name} ${booking.consumer_last_name}`.trim() || 'Customer';
    const serviceName = booking.original_service_name || booking.serviceType;

    // Notify the OTHER party about the cancellation (in-app history + APNs deep-link to booking detail)
    if (isBarber) {
      const cancelTitle = 'Booking Cancelled';
      const cancelMessage = `${barberName} has cancelled your ${serviceName} appointment${reason ? `. Reason: ${reason}` : ''}`;
      await notificationService.saveNotification({
        userId: booking.consumerId,
        type: 'booking_cancelled',
        title: cancelTitle,
        message: cancelMessage,
        data: {
          bookingId: id,
          reason,
          cancelledBy: 'barber',
          scheduledTime: booking.scheduledTime,
          serviceType: booking.serviceType,
          campusId: booking.campus_id,
          cancelledBarberId: booking.barberId,
        },
      });
      try {
        await pushNotificationService.sendBookingCancelledNotification(
          booking.consumerId,
          cancelTitle,
          cancelMessage,
          id,
          { cancelledBy: 'barber', reason }
        );
      } catch (pushErr: any) {
        logger.error('Push booking_cancelled (consumer) failed:', pushErr?.message || pushErr);
      }
    } else {
      const cancelTitle = 'Booking Cancelled';
      const cancelMessage = `${consumerName} has cancelled their ${serviceName} appointment${reason ? `. Reason: ${reason}` : ''}`;
      await notificationService.saveNotification({
        userId: booking.barber_user_id,
        type: 'booking_cancelled',
        title: cancelTitle,
        message: cancelMessage,
        data: { bookingId: id, reason, cancelledBy: 'consumer' },
      });
      try {
        await pushNotificationService.sendBookingCancelledNotification(
          booking.barber_user_id,
          cancelTitle,
          cancelMessage,
          id,
          { cancelledBy: 'consumer', reason }
        );
      } catch (pushErr: any) {
        logger.error('Push booking_cancelled (barber) failed:', pushErr?.message || pushErr);
      }
    }

    // Send cancellation emails to both parties (use campus timezone)
    const scheduledDate = new Date(booking.scheduledTime);
    const campusTimezone = booking.campus_timezone || 'America/Los_Angeles';
    
    // If barber cancelled, fetch alternative barbers for the consumer email
    let alternativeBarbers: { id: string; name: string; avatar?: string; avgRating?: number; totalReviews?: number }[] = [];
    
    if (isBarber && booking.campus_id) {
      try {
        // Get the date and time in CAMPUS TIMEZONE for availability check
        const dateStr = scheduledDate.toLocaleDateString('en-CA', { timeZone: campusTimezone }); // YYYY-MM-DD
        const timeStr = scheduledDate.toLocaleTimeString('en-US', { 
          timeZone: campusTimezone, 
          hour: '2-digit', 
          minute: '2-digit', 
          hour12: false 
        }); // HH:MM
        const [requestedHour, requestedMinutes] = timeStr.split(':').map(Number);
        const requestedTimeInMinutes = requestedHour * 60 + requestedMinutes;
        
        logger.info(`[Cancellation Email] Checking availability at ${dateStr} ${timeStr} (${requestedTimeInMinutes} min) in timezone ${campusTimezone}`);
        
        // Fetch all barbers at the same campus who offer the same service
        // Services are stored in barbers.pricing JSONB array as objects with 'type' field
        const barbersResult = await pool.query(`
          SELECT 
            b.id,
            COALESCE(u."displayName", u.first_name || ' ' || u.last_name) as name,
            u."avatarUrl" as avatar,
            b."weeklySchedule" as weekly_schedule,
            b.pricing,
            (SELECT AVG(r.rating)::numeric(3,2) FROM reviews r WHERE r."barberId" = b.id) as avg_rating,
            (SELECT COUNT(*) FROM reviews r WHERE r."barberId" = b.id) as total_reviews
          FROM barbers b
          JOIN users u ON b."userId" = u.id
          WHERE b."campusId" = $1 
            AND b.id != $2
            AND b."isActive" = true
        `, [booking.campus_id, booking.barberId]);
        
        // Filter barbers who offer the service
        const serviceType = booking.serviceType?.toUpperCase().replace(/_/g, ' ').replace(/AND/g, '&');
        const barbersWithService = barbersResult.rows.filter(barber => {
          const pricing = barber.pricing || [];
          return pricing.some((service: any) => {
            const serviceName = (service.name || service.type || service.service_type || '').toUpperCase().replace(/_/g, ' ').replace(/AND/g, '&');
            return serviceName === serviceType || 
                   serviceName.includes(serviceType) || 
                   serviceType.includes(serviceName);
          });
        });
        
        logger.info(`Found ${barbersResult.rows.length} barbers at campus, ${barbersWithService.length} offer service ${serviceType}`);
        
        // Check availability for each barber who offers the service
        // Parse the date string (YYYY-MM-DD) to get correct day of week in campus timezone
        const dayNames = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const;
        const [year, month, day] = dateStr.split('-').map(Number);
        const localDate = new Date(year, month - 1, day, 12, 0, 0); // noon to avoid DST edge cases
        const dayName = dayNames[localDate.getDay()];
        
        for (const barber of barbersWithService) {
          const weeklySchedule = barber.weekly_schedule || {};
          const daySchedule = weeklySchedule[dayName];
          
          // Check if barber works on this day
          if (!daySchedule || !daySchedule.enabled) continue;
          
          // Get intervals
          let intervals: { start: string; end: string }[] = [];
          if (daySchedule.intervals && Array.isArray(daySchedule.intervals)) {
            intervals = daySchedule.intervals;
          } else if (daySchedule.start && daySchedule.end) {
            intervals = [{ start: daySchedule.start, end: daySchedule.end }];
          }
          
          // Check if requested time is within any interval
          const inInterval = intervals.some(interval => {
            const [startHour, startMin] = interval.start.split(':').map(Number);
            const [endHour, endMin] = interval.end.split(':').map(Number);
            const intervalStart = startHour * 60 + startMin;
            const intervalEnd = endHour * 60 + endMin;
            return requestedTimeInMinutes >= intervalStart && requestedTimeInMinutes < intervalEnd;
          });
          
          if (!inInterval) continue;
          
          // Check for conflicting bookings
          const conflictCheck = await pool.query(`
            SELECT 1 FROM bookings 
            WHERE "barberId" = $1 
              AND DATE("requestedAt" AT TIME ZONE 'America/Los_Angeles') = $2
              AND status IN ('ACCEPTED', 'PENDING', 'COMPLETED')
              AND (
                EXTRACT(HOUR FROM "requestedAt" AT TIME ZONE 'America/Los_Angeles') * 60 +
                EXTRACT(MINUTE FROM "requestedAt" AT TIME ZONE 'America/Los_Angeles')
              ) BETWEEN $3 AND $4
            LIMIT 1
          `, [barber.id, dateStr, requestedTimeInMinutes - 59, requestedTimeInMinutes + 59]);
          
          if (conflictCheck.rows.length > 0) continue;
          
          // Check for blocked times
          const blockCheck = await pool.query(`
            SELECT 1 FROM barber_time_blocks 
            WHERE barber_id = $1 
              AND block_date = $2
              AND (
                (EXTRACT(HOUR FROM start_time) * 60 + EXTRACT(MINUTE FROM start_time)) <= $3
                AND (EXTRACT(HOUR FROM end_time) * 60 + EXTRACT(MINUTE FROM end_time)) > $3
              )
            LIMIT 1
          `, [barber.id, dateStr, requestedTimeInMinutes]);
          
          if (blockCheck.rows.length > 0) continue;
          
          // Barber is available!
          alternativeBarbers.push({
            id: barber.id,
            name: barber.name,
            avatar: barber.avatar,
            avgRating: barber.avg_rating ? parseFloat(barber.avg_rating) : undefined,
            totalReviews: barber.total_reviews ? parseInt(barber.total_reviews) : undefined,
          });
          
          // Limit to 5 alternative barbers for the email
          if (alternativeBarbers.length >= 5) break;
        }
        
        logger.info(`Found ${alternativeBarbers.length} alternative barbers for cancelled booking ${id}`);
      } catch (altError: any) {
        logger.error('Error fetching alternative barbers for cancellation email:', altError.message);
        // Continue without alternative barbers
      }
    }
    
    await sendBookingCancellationEmails({
      bookingId: id,
      serviceName: serviceName,
      serviceType: booking.serviceType,
      price: (booking.priceUsdCents || 0) / 100,
      scheduledDate: scheduledDate.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', timeZone: campusTimezone }),
      scheduledTime: scheduledDate.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: campusTimezone }),
      scheduledDateTime: booking.scheduledTime,
      location: booking.location,
      consumerName: consumerName,
      consumerEmail: booking.consumer_email,
      barberName: barberName,
      barberEmail: booking.barber_email,
      cancelledBy: isBarber ? 'barber' : 'consumer',
      reason: reason,
      alternativeBarbers: alternativeBarbers.length > 0 ? alternativeBarbers : undefined,
    });

    logger.info(`Booking ${id} cancelled by ${isBarber ? 'barber' : 'consumer'} ${userId}`);

    // Emit booking-update event via WebSocket for live updates
    const bookingUpdate = {
      id,
      status: 'CANCELLED',
      barberId: booking.barberId,
      consumerId: booking.consumerId,
      campusId: booking.campus_id,
      scheduledTime: booking.scheduledTime,
      serviceType: booking.serviceType,
      cancelledBy: isBarber ? 'barber' : 'consumer',
      updatedBy: isBarber ? 'barber' : 'consumer',
      cancelled: true,
    };
    
    // Emit to both barber and consumer's personal rooms
    const io = getSocketIO();
    if (io) {
      io.to(`user-${booking.barber_user_id}`).emit('booking-update', bookingUpdate);
      io.to(`user-${booking.consumerId}`).emit('booking-update', bookingUpdate);
      logger.info(`Emitted booking-update event for cancelled booking ${id}`);
    }

    res.json({
      success: true,
      message: 'Booking cancelled successfully',
    });
  } catch (error: any) {
    logger.error('Error cancelling booking:', error.message || error);
    next(error);
  }
});

export default router;



