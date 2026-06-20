/**
 * Booking Request Service (AirBnb-style)
 * 
 * Handles:
 * - Creating booking requests
 * - Accepting/rejecting requests
 * - Customer profile views
 * - Booking statistics
 */

import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import notificationService from './notification.service';
import pushNotificationService from './pushNotification.service';
import { sendBookingConfirmationEmails, sendBookingDeclineEmail } from './email.service';

interface TimeInterval {
  start: string;
  end: string;
}

interface AlternativeBarber {
  id: string;
  name: string;
  avatar?: string;
  average_rating?: number;
  total_reviews?: number;
}

/**
 * Fetch alternative barbers available at the given time
 */
async function fetchAlternativeBarbers(
  campusId: string,
  excludeBarberId: string,
  serviceType: string,
  scheduledTime: Date
): Promise<AlternativeBarber[]> {
  try {
    const dateStr = scheduledTime.toISOString().split('T')[0];
    const dayNames = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const;
    const dayName = dayNames[scheduledTime.getDay()];
    const requestedTimeInMinutes = scheduledTime.getHours() * 60 + scheduledTime.getMinutes();

    // Fetch barbers at the same campus who offer the same service
    const barbersResult = await pool.query(`
      SELECT
        b.id,
        COALESCE(u."displayName", u.first_name || ' ' || u.last_name) as name,
        u.profile_picture_url as avatar,
        b."weeklySchedule" as weekly_schedule,
        (SELECT AVG(r.rating)::numeric(3,2) FROM reviews r WHERE r.barber_id = b.id) as average_rating,
        (SELECT COUNT(*) FROM reviews r WHERE r.barber_id = b.id) as total_reviews
      FROM barbers b
      JOIN users u ON b."userId" = u.id
      WHERE b."campusId" = $1
        AND b.id != $2
        AND b."isActive" = true
        AND b."isOnboarded" = true
        AND EXISTS (
          SELECT 1
          FROM jsonb_array_elements(b.pricing) AS service_item
          WHERE UPPER(service_item ->> 'type') = UPPER($3)
             OR UPPER(service_item ->> 'service_type') = UPPER($3)
        )
      LIMIT 10
    `, [campusId, excludeBarberId, serviceType]);

    const alternativeBarbers: AlternativeBarber[] = [];

    for (const barber of barbersResult.rows) {
      const weeklySchedule = barber.weekly_schedule || {};
      const daySchedule = weeklySchedule[dayName];

      if (!daySchedule || !daySchedule.enabled) continue;

      const intervals: TimeInterval[] = daySchedule.intervals && Array.isArray(daySchedule.intervals)
        ? daySchedule.intervals
        : (daySchedule.start && daySchedule.end ? [{ start: daySchedule.start, end: daySchedule.end }] : []);

      if (intervals.length === 0) continue;

      // Check for conflicting bookings and blocked times
      const conflictsResult = await pool.query(
        `SELECT
          TO_CHAR("requestedAt" AT TIME ZONE 'America/Los_Angeles', 'HH24:MI') as start_time,
          TO_CHAR("requestedAt" AT TIME ZONE 'America/Los_Angeles' + INTERVAL '60 minutes', 'HH24:MI') as end_time
        FROM bookings
        WHERE "barberId" = $1
          AND DATE("requestedAt" AT TIME ZONE 'America/Los_Angeles') = $2
          AND status IN ('ACCEPTED', 'PENDING', 'IN_PROGRESS')
          AND "paidAt" IS NULL
        UNION ALL
        SELECT
          TO_CHAR(start_time, 'HH24:MI') as start_time,
          TO_CHAR(end_time, 'HH24:MI') as end_time
        FROM barber_time_blocks
        WHERE barber_id = $1
          AND block_date = $2
        ORDER BY start_time`,
        [barber.id, dateStr]
      );

      const bookedSlots = conflictsResult.rows.map(row => ({
        start: row.start_time,
        end: row.end_time
      }));

      let isAvailable = false;
      for (const interval of intervals) {
        const [intervalStartHour, intervalStartMin] = interval.start.split(':').map(Number);
        const [intervalEndHour, intervalEndMin] = interval.end.split(':').map(Number);
        const intervalStartTimeMinutes = intervalStartHour * 60 + intervalStartMin;
        const intervalEndTimeMinutes = intervalEndHour * 60 + intervalEndMin;

        if (requestedTimeInMinutes >= intervalStartTimeMinutes && requestedTimeInMinutes < intervalEndTimeMinutes) {
          let isBlocked = false;
          for (const blocked of bookedSlots) {
            const [blockedStartHour, blockedStartMin] = blocked.start.split(':').map(Number);
            const [blockedEndHour, blockedEndMin] = blocked.end.split(':').map(Number);
            const blockedStartTimeMinutes = blockedStartHour * 60 + blockedStartMin;
            const blockedEndTimeMinutes = blockedEndHour * 60 + blockedEndMin;

            if (
              (requestedTimeInMinutes >= blockedStartTimeMinutes && requestedTimeInMinutes < blockedEndTimeMinutes) ||
              (requestedTimeInMinutes + 30 > blockedStartTimeMinutes && requestedTimeInMinutes + 30 <= blockedEndTimeMinutes)
            ) {
              isBlocked = true;
              break;
            }
          }
          if (!isBlocked) {
            isAvailable = true;
            break;
          }
        }
      }

      if (isAvailable) {
        alternativeBarbers.push({
          id: barber.id,
          name: barber.name,
          avatar: barber.avatar,
          average_rating: barber.average_rating ? parseFloat(barber.average_rating) : undefined,
          total_reviews: barber.total_reviews ? parseInt(barber.total_reviews, 10) : undefined,
        });
      }

      // Limit to 5 barbers
      if (alternativeBarbers.length >= 5) break;
    }

    return alternativeBarbers;
  } catch (error) {
    logger.error('Error fetching alternative barbers for decline email:', error);
    return [];
  }
}

interface BookingRequest {
  bookingId: string;
  customerId: string;
  customerName: string;
  customerProfile: any;
  barberId: string;
  serviceType: string;
  requestedDate: Date;
  requestedTime: string;
  price: number;
  location?: string | null;
  message?: string;
  status: string;
  requestedAt: Date;
}

export class BookingRequestService {
  /**
   * Create a booking request (customer initiates)
   */
  async createBookingRequest(data: {
    customerId: string;
    barberId: string;
    serviceType: string;
    requestedDate: Date;
    requestedTime: string;
    price: number;
    message?: string;
  }): Promise<{ bookingId: string; success: boolean }> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      // Create booking with 'pending' status
      const bookingResult = await client.query(`
        INSERT INTO bookings (
          customer_id,
          barber_id,
          service_type,
          booking_date,
          booking_time,
          price_charged,
          status,
          requested_at
        ) VALUES ($1, $2, $3, $4, $5, $6, 'pending', NOW())
        RETURNING id
      `, [
        data.customerId,
        data.barberId,
        data.serviceType,
        data.requestedDate,
        data.requestedTime,
        data.price,
      ]);

      const bookingId = bookingResult.rows[0].id;

      // Add initial message if provided
      if (data.message) {
        await client.query(`
          INSERT INTO booking_messages (
            booking_id,
            sender_id,
            sender_type,
            message
          ) VALUES ($1, $2, 'customer', $3)
        `, [bookingId, data.customerId, data.message]);
      }

      // Create notification for barber
      await client.query(`
        INSERT INTO booking_request_notifications (
          user_id,
          booking_id,
          type,
          title,
          message
        ) SELECT 
          user_id,
          $1,
          'new_request',
          'New Booking Request',
          'You have a new booking request from ' || u.name
        FROM barbers b
        JOIN users u ON b.user_id = u.id
        WHERE b.barber_id = $2
      `, [bookingId, data.barberId]);

      await client.query('COMMIT');

      logger.info(`Booking request created: ${bookingId} for barber ${data.barberId}`);

      return { bookingId, success: true };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Error creating booking request:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get pending booking requests for a barber
   * Checks both the bookings table AND conversations with pending booking_status
   */
  async getBarberPendingRequests(barberIdOrUserId: string): Promise<BookingRequest[]> {
    try {
      // Check if PostgreSQL is available
      await pool.query('SELECT 1');
      
      const requests: BookingRequest[] = [];
      
      // First, try to find the barber ID - the input could be either barber ID or user ID
      let barberId = barberIdOrUserId;
      let barberUserId = barberIdOrUserId;
      
      // Check if this is a user ID by looking up the barbers table
      const barberCheck = await pool.query(
        'SELECT id, "userId" FROM barbers WHERE id = $1 OR "userId" = $1',
        [barberIdOrUserId]
      );
      
      if (barberCheck.rows.length > 0) {
        barberId = barberCheck.rows[0].id;
        barberUserId = barberCheck.rows[0].userId;
      }
      
      // Query 1: Get from bookings table (traditional flow)
      // Also LEFT JOIN conversations to get the original service_name for display (include campus timezone)
      const bookingsResult = await pool.query(`
        SELECT 
          b.id as booking_id,
          b."consumerId" as customer_id,
          u.first_name || ' ' || u.last_name as customer_name,
          b."barberId" as barber_id,
          b."serviceType" as service_type,
          c.service_name as original_service_name,
          COALESCE(c.scheduled_time, b."requestedAt") as requested_date,
          COALESCE(c.scheduled_time, b."requestedAt") as requested_time,
          b."priceUsdCents" / 100.0 as price,
          b.status,
          b."createdAt" as requested_at,
          u."displayName" as display_name,
          u.bio,
          u."avatarUrl" as profile_image_url,
          c.location as booking_location,
          c.notes as booking_notes,
          COALESCE(campus.timezone, 'America/New_York') as campus_timezone
        FROM bookings b
        JOIN users u ON b."consumerId" = u.id
        JOIN barbers bar ON b."barberId" = bar.id
        LEFT JOIN conversations c ON c.booking_id = b.id
        LEFT JOIN campuses campus ON bar."campusId" = campus.id
        WHERE b."barberId" = $1 
          AND b.status = 'PENDING'
        ORDER BY b."createdAt" DESC
      `, [barberId]);

      bookingsResult.rows.forEach(row => {
        // Format service type: "HAIRCUT" -> "Haircut", "BEARD_TRIM" -> "Beard Trim"
        const formatServiceType = (type: string) => {
          if (!type) return 'Haircut';
          return type
            .toLowerCase()
            .replace(/_/g, ' ')
            .replace(/\b\w/g, c => c.toUpperCase());
        };
        
        // Use the campus timezone for this barber
        const campusTimezone = row.campus_timezone || 'America/New_York';
        
        // Format time: ISO string -> "6:15 PM"
        // Use campus timezone for correct local time display
        const formatTime = (date: Date | string) => {
          if (!date) return '';
          const d = new Date(date);
          return d.toLocaleTimeString('en-US', { 
            hour: 'numeric', 
            minute: '2-digit', 
            hour12: true,
            timeZone: campusTimezone
          });
        };
        
        logger.info(`Pending request time: raw=${row.requested_time}, formatted=${formatTime(row.requested_time)}, timezone=${campusTimezone}`);
        
        // Prefer original service name from conversation, fallback to formatted enum
        const displayServiceType = row.original_service_name || formatServiceType(row.service_type);
        
        requests.push({
          bookingId: row.booking_id,
          customerId: row.customer_id,
          customerName: row.customer_name,
          customerProfile: {
            displayName: row.display_name || row.customer_name,
            bio: row.bio,
            profileImageUrl: row.profile_image_url,
            stats: {
              totalBookings: 0,
              completedBookings: 0,
              cancelledBookings: 0,
              noShowCount: 0,
              avgRating: 0,
              totalReviews: 0,
              isReliable: true,
              completionRate: 100,
              responseRate: 100,
            },
          },
          barberId: row.barber_id,
          serviceType: displayServiceType,
          requestedDate: row.requested_date,
          requestedTime: formatTime(row.requested_time),
          price: parseFloat(row.price) || 0,
          location: row.booking_location || null,
          message: row.booking_notes || '',
          status: row.status,
          requestedAt: row.requested_at,
        });
      });

      // First, get the barber's campus timezone
      const barberCampusResult = await pool.query(`
        SELECT COALESCE(campus.timezone, 'America/New_York') as campus_timezone
        FROM barbers bar
        LEFT JOIN campuses campus ON bar."campusId" = campus.id
        WHERE bar.id = $1 OR bar."userId" = $1
        LIMIT 1
      `, [barberIdOrUserId]);
      const barberCampusTimezone = barberCampusResult.rows[0]?.campus_timezone || 'America/New_York';

      // Query 2: Get from conversations with pending booking_status
      // This handles the case where consumer scheduled a service via messages
      // EXCLUDE conversations that have a booking_id (those are already captured in Query 1)
      const conversationsResult = await pool.query(`
        SELECT 
          c.id as conversation_id,
          c.user1_id,
          c.user2_id,
          c.service_name,
          c.service_price,
          c.scheduled_time,
          c.location,
          c.notes,
          c.booking_status,
          c.consumer_name,
          c.created_at,
          c.booking_id,
          u.id as customer_id,
          u.first_name || ' ' || u.last_name as customer_name,
          u."displayName" as display_name,
          u.bio,
          u."avatarUrl" as profile_image_url
        FROM conversations c
        JOIN users u ON (
          CASE 
            WHEN c.user1_id = $1 THEN c.user2_id
            ELSE c.user1_id
          END = u.id
        )
        WHERE (c.user1_id = $1 OR c.user2_id = $1)
          AND c.booking_status = 'pending'
          AND c.is_active = true
          AND c.service_name IS NOT NULL
          AND c.booking_id IS NULL  -- Only get conversations WITHOUT a linked booking (to prevent duplicates)
        ORDER BY c.created_at DESC
      `, [barberUserId]);

      conversationsResult.rows.forEach(row => {
        // Skip if this conversation has a linked booking (already captured above)
        if (row.booking_id) {
          return;
        }
        // Don't add if we already have this from bookings
        const alreadyExists = requests.some(r => r.bookingId === `conv-${row.conversation_id}`);
        if (!alreadyExists) {
          requests.push({
            bookingId: `conv-${row.conversation_id}`, // Prefix to identify it's from conversations
            customerId: row.customer_id,
            customerName: row.customer_name || row.consumer_name || 'Customer',
            customerProfile: {
              displayName: row.display_name || row.customer_name || 'Customer',
              bio: row.bio,
              profileImageUrl: row.profile_image_url,
              stats: {
                totalBookings: 0,
                completedBookings: 0,
                cancelledBookings: 0,
                noShowCount: 0,
                avgRating: 0,
                totalReviews: 0,
                isReliable: true,
                completionRate: 100,
                responseRate: 100,
              },
            },
            barberId: barberId,
            serviceType: row.service_name || 'Haircut',
            requestedDate: row.scheduled_time || row.created_at,
            requestedTime: row.scheduled_time 
              ? new Date(row.scheduled_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: barberCampusTimezone })
              : '',
            price: parseFloat(row.service_price) || 0,
            location: row.location || null,
            message: row.notes || '',
            status: 'pending',
            requestedAt: row.created_at,
          });
        }
      });

      logger.info(`Found ${requests.length} pending requests for barber ${barberIdOrUserId}`);
      return requests;
    } catch (error) {
      logger.error('Error getting pending requests (using empty array):', error);
      
      // Return empty array instead of mock data
      return [];
    }
  }

  /**
   * Get mock booking requests for testing without PostgreSQL
   */
  private getMockPendingRequests(barberId: string): BookingRequest[] {
    const mockRequests: BookingRequest[] = [
      {
        bookingId: 'mock-booking-1',
        customerId: 'customer-alex-2024',
        customerName: 'Alex Rivera',
        customerProfile: {
          displayName: 'Alex R.',
          bio: 'Cal Poly student, engineering major. Love a clean fade!',
          profileImageUrl: null,
          stats: {
            totalBookings: 15,
            completedBookings: 14,
            cancelledBookings: 1,
            noShowCount: 0,
            avgRating: 4.9,
            totalReviews: 12,
            isReliable: true,
            responseRate: 95,
          },
        },
        barberId,
        serviceType: 'Fade',
        requestedDate: new Date(Date.now() + 86400000), // Tomorrow
        requestedTime: '14:00',
        price: 35.00,
        message: 'Hey! Looking for a clean mid-fade. Can we do it at the campus center?',
        status: 'pending',
        requestedAt: new Date(Date.now() - 3600000), // 1 hour ago
      },
      {
        bookingId: 'mock-booking-2',
        customerId: 'customer-jordan-2024',
        customerName: 'Jordan Lee',
        customerProfile: {
          displayName: 'Jordan L.',
          bio: 'Business major, need to look professional for interviews.',
          profileImageUrl: null,
          stats: {
            totalBookings: 8,
            completedBookings: 7,
            cancelledBookings: 0,
            noShowCount: 1,
            avgRating: 4.3,
            totalReviews: 5,
            isReliable: true,
            responseRate: 88,
          },
        },
        barberId,
        serviceType: 'Haircut',
        requestedDate: new Date(Date.now() + 172800000), // 2 days from now
        requestedTime: '10:30',
        price: 30.00,
        message: 'Need a professional cut for job interviews. Can you help?',
        status: 'pending',
        requestedAt: new Date(Date.now() - 7200000), // 2 hours ago
      },
      {
        bookingId: 'mock-booking-3',
        customerId: 'customer-sam-2024',
        customerName: 'Sam Martinez',
        customerProfile: {
          displayName: 'Sam M.',
          bio: null,
          profileImageUrl: null,
          stats: {
            totalBookings: 3,
            completedBookings: 2,
            cancelledBookings: 0,
            noShowCount: 1,
            avgRating: 3.5,
            totalReviews: 2,
            isReliable: false,
            responseRate: 67,
          },
        },
        barberId,
        serviceType: 'Full Service',
        requestedDate: new Date(Date.now() + 259200000), // 3 days from now
        requestedTime: '16:00',
        price: 50.00,
        message: 'Haircut and beard trim please. My dorm room works.',
        status: 'pending',
        requestedAt: new Date(Date.now() - 10800000), // 3 hours ago
      },
    ];

    logger.info(`Returning ${mockRequests.length} mock booking requests for barber ${barberId}`);
    return mockRequests;
  }

  /**
   * Accept a booking request
   * Handles both traditional bookings and conversation-based requests
   */
  async acceptBookingRequest(
    bookingId: string,
    barberId: string,
    message?: string
  ): Promise<{ success: boolean }> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      // Check if this is a conversation-based request
      if (bookingId.startsWith('conv-')) {
        const conversationId = bookingId.replace('conv-', '');
        
        // Update conversation booking_status and get the linked booking_id
        const updateResult = await client.query(`
          UPDATE conversations
          SET 
            booking_status = 'accepted',
            updated_at = CURRENT_TIMESTAMP
          WHERE id = $1 AND booking_status = 'pending'
          RETURNING user1_id, user2_id, booking_id
        `, [conversationId]);

        if (updateResult.rows.length === 0) {
          throw new Error('Conversation not found or already responded to');
        }

        // Also update the linked booking record if it exists
        const linkedBookingId = updateResult.rows[0].booking_id;
        if (linkedBookingId) {
          await client.query(`
            UPDATE bookings
            SET 
              status = 'ACCEPTED',
              "updatedAt" = CURRENT_TIMESTAMP
            WHERE id = $1
          `, [linkedBookingId]);
          logger.info(`Linked booking ${linkedBookingId} also marked as ACCEPTED`);
        }

        // Send notification to consumer about acceptance
        const consumerUserId = updateResult.rows[0].user1_id === barberId 
          ? updateResult.rows[0].user2_id 
          : updateResult.rows[0].user1_id;
        
        // Get barber name for notification
        const barberNameResult = await client.query(
          `SELECT u.first_name || ' ' || u.last_name as name 
           FROM users u 
           WHERE u.id = $1`,
          [barberId]
        );
        const barberName = barberNameResult.rows[0]?.name || 'Your barber';
        
        await notificationService.saveNotification({
          userId: consumerUserId,
          type: 'booking_accepted',
          title: 'Booking Accepted!',
          message: `${barberName} accepted your booking request`,
          data: { conversationId, bookingId: linkedBookingId },
        });

        await client.query('COMMIT');
        logger.info(`Conversation ${conversationId} booking accepted by barber ${barberId}`);

        // Send confirmation emails + push if there's a linked booking (non-blocking)
        if (linkedBookingId) {
          pushNotificationService
            .sendBookingAcceptedNotification(consumerUserId, barberName, linkedBookingId)
            .catch((err) => logger.error(`Failed to send booking accepted push for ${linkedBookingId}:`, err));
          this.sendBookingConfirmationEmailsAsync(linkedBookingId).catch(err => {
            logger.error(`Failed to send booking confirmation emails for ${linkedBookingId}:`, err);
          });
        }

        return { success: true };
      }

      // Traditional booking flow
      const updateResult = await client.query(`
        UPDATE bookings
        SET 
          status = 'ACCEPTED',
          "acceptedAt" = NOW(),
          "updatedAt" = NOW()
        WHERE id = $1 AND status = 'PENDING'
        RETURNING "consumerId"
      `, [bookingId]);

      if (updateResult.rows.length === 0) {
        throw new Error('Booking not found or already responded to');
      }

      const consumerId = updateResult.rows[0].consumerId;
      
      // Also update any linked conversation's booking_status
      await client.query(`
        UPDATE conversations
        SET booking_status = 'accepted', updated_at = CURRENT_TIMESTAMP
        WHERE booking_id = $1
      `, [bookingId]);
      logger.info(`Updated linked conversation booking_status for booking ${bookingId}`);
      
      // Get barber name for notification
      const barberNameResult = await client.query(
        `SELECT u.first_name || ' ' || u.last_name as name 
         FROM barbers b
         JOIN users u ON b."userId" = u.id
         WHERE b.id = $1 OR b."userId" = $1`,
        [barberId]
      );
      const barberName = barberNameResult.rows[0]?.name || 'Your barber';
      
      // Send notification to consumer
      await notificationService.saveNotification({
        userId: consumerId,
        type: 'booking_accepted',
        title: 'Booking Accepted!',
        message: `${barberName} accepted your booking request`,
        data: { bookingId },
      });

      await client.query('COMMIT');
      logger.info(`Booking ${bookingId} accepted by barber ${barberId}`);

      pushNotificationService
        .sendBookingAcceptedNotification(consumerId, barberName, bookingId)
        .catch((err) => logger.error(`Failed to send booking accepted push for ${bookingId}:`, err));

      // Send confirmation emails to both consumer and barber (non-blocking)
      this.sendBookingConfirmationEmailsAsync(bookingId).catch(err => {
        logger.error(`Failed to send booking confirmation emails for ${bookingId}:`, err);
      });

      return { success: true };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Error accepting booking request:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Reject a booking request
   * Handles both traditional bookings and conversation-based requests
   */
  async rejectBookingRequest(
    bookingId: string,
    barberId: string,
    reason?: string
  ): Promise<{ success: boolean }> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      // Check if this is a conversation-based request
      if (bookingId.startsWith('conv-')) {
        const conversationId = bookingId.replace('conv-', '');
        
        // Get conversation details before deleting (including booking info for email)
        const convResult = await client.query(`
          SELECT 
            c.user1_id, c.user2_id, c.booking_id,
            c.service_name, c.service_price, c.scheduled_time, c.location,
            b."serviceType", b."priceUsdCents", b."requestedAt", b."barberId",
            bar."campusId" as campus_id,
            COALESCE(campus.timezone, 'America/New_York') as campus_timezone
          FROM conversations c
          LEFT JOIN bookings b ON c.booking_id = b.id
          LEFT JOIN barbers bar ON b."barberId" = bar.id
          LEFT JOIN campuses campus ON bar."campusId" = campus.id
          WHERE c.id = $1 AND c.booking_status = 'pending'
        `, [conversationId]);

        if (convResult.rows.length === 0) {
          throw new Error('Conversation not found or already responded to');
        }

        const linkedBookingId = convResult.rows[0].booking_id;

        // Update the linked booking record to REJECTED if it exists
        if (linkedBookingId) {
          await client.query(`
            UPDATE bookings
            SET 
              status = 'REJECTED',
              "updatedAt" = CURRENT_TIMESTAMP
            WHERE id = $1
          `, [linkedBookingId]);
          logger.info(`Linked booking ${linkedBookingId} marked as REJECTED`);
        }

        // Get barber's user ID for notification
        const barberResult = await client.query(
          'SELECT "userId" FROM barbers WHERE id = $1 OR "userId" = $1',
          [barberId]
        );
        const barberUserId = barberResult.rows[0]?.userId || barberId;

        // Determine consumer user ID
        const consumerUserId = convResult.rows[0].user1_id === barberUserId 
          ? convResult.rows[0].user2_id 
          : convResult.rows[0].user1_id;
        
        // Get barber name for notification and consumer details for email
        const userDetailsResult = await client.query(
          `SELECT 
            barber.first_name || ' ' || barber.last_name as barber_name,
            consumer.first_name || ' ' || consumer.last_name as consumer_name,
            consumer.email as consumer_email
           FROM users barber, users consumer
           WHERE barber.id = $1 AND consumer.id = $2`,
          [barberUserId, consumerUserId]
        );
        const barberName = userDetailsResult.rows[0]?.barber_name || 'The barber';
        const consumerName = userDetailsResult.rows[0]?.consumer_name || 'Customer';
        const consumerEmail = userDetailsResult.rows[0]?.consumer_email;
        
        // Send notification to consumer about rejection BEFORE deleting conversation
        await notificationService.saveNotification({
          userId: consumerUserId,
          type: 'booking_rejected',
          title: 'Booking Declined',
          message: `${barberName} was unable to accept your booking request${reason ? `: ${reason}` : ''}`,
          data: { bookingId: linkedBookingId, reason },
        });

        // Send decline email to consumer with alternative barbers
        if (consumerEmail) {
          const convData = convResult.rows[0];
          const campusTimezone = convData.campus_timezone || 'America/New_York';
          const scheduledTime = convData.requestedAt || convData.scheduled_time || new Date();
          const scheduledDate = new Date(scheduledTime);
          const serviceName = convData.service_name || convData.serviceType || 'Haircut';
          const declinedBarberId = convData.barberId || barberId;
          const campusId = convData.campus_id;
          
          // Fetch alternative barbers asynchronously
          (async () => {
            let alternativeBarbers: AlternativeBarber[] = [];
            if (campusId && declinedBarberId) {
              alternativeBarbers = await fetchAlternativeBarbers(
                campusId,
                declinedBarberId,
                serviceName,
                scheduledDate
              );
            }
            
            sendBookingDeclineEmail({
              consumerEmail,
              consumerName,
              barberName,
              barberId: declinedBarberId,
              serviceName,
              scheduledDate: scheduledDate.toLocaleDateString('en-US', { 
                weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', 
                timeZone: campusTimezone 
              }),
              scheduledTime: scheduledDate.toLocaleTimeString('en-US', { 
                hour: 'numeric', minute: '2-digit', hour12: true, 
                timeZone: campusTimezone 
              }),
              price: (convData.priceUsdCents || convData.service_price * 100 || 0) / 100,
              location: convData.location || undefined,
              reason: reason || undefined,
              bookingId: linkedBookingId || conversationId,
              campusId,
              originalScheduledTime: scheduledDate.toISOString(),
              alternativeBarbers,
            }).catch(err => logger.error('Failed to send decline email:', err));
          })();
        }

        // Delete the conversation and its messages (cascading delete should handle messages)
        await client.query(`DELETE FROM messages WHERE conversation_id = $1`, [conversationId]);
        await client.query(`DELETE FROM conversations WHERE id = $1`, [conversationId]);
        logger.info(`Deleted conversation ${conversationId} and its messages after rejection`);

        await client.query('COMMIT');
        logger.info(`Booking rejected by barber ${barberId}, conversation deleted`);
        return { success: true };
      }

      // Traditional booking flow - first get booking details for email
      const bookingDetailsResult = await client.query(`
        SELECT 
          b.id, b."consumerId", b."serviceType", b."priceUsdCents", b."requestedAt", b."barberId",
          c.service_name, c.location,
          bar."campusId" as campus_id,
          u_consumer.first_name || ' ' || u_consumer.last_name as consumer_name,
          u_consumer.email as consumer_email,
          u_barber.first_name || ' ' || u_barber.last_name as barber_name,
          COALESCE(campus.timezone, 'America/New_York') as campus_timezone
        FROM bookings b
        JOIN users u_consumer ON b."consumerId" = u_consumer.id
        JOIN barbers bar ON b."barberId" = bar.id
        JOIN users u_barber ON bar."userId" = u_barber.id
        LEFT JOIN conversations c ON c.booking_id = b.id
        LEFT JOIN campuses campus ON bar."campusId" = campus.id
        WHERE b.id = $1 AND b.status = 'PENDING'
      `, [bookingId]);

      if (bookingDetailsResult.rows.length === 0) {
        throw new Error('Booking not found or already responded to');
      }

      const bookingData = bookingDetailsResult.rows[0];
      const consumerId = bookingData.consumerId;
      
      // Now update the booking status
      await client.query(`
        UPDATE bookings
        SET 
          status = 'CANCELLED',
          "cancelledAt" = NOW(),
          "cancellationReason" = $2,
          "updatedAt" = NOW()
        WHERE id = $1
      `, [bookingId, reason]);
      
      // Delete any linked conversation and its messages when booking is cancelled
      // First delete messages, then conversation
      await client.query(`
        DELETE FROM messages 
        WHERE conversation_id IN (SELECT id FROM conversations WHERE booking_id = $1)
      `, [bookingId]);
      await client.query(`
        DELETE FROM conversations
        WHERE booking_id = $1
      `, [bookingId]);
      logger.info(`Deleted linked conversation and messages for cancelled booking ${bookingId}`);
      
      const barberName = bookingData.barber_name || 'The barber';
      const consumerName = bookingData.consumer_name || 'Customer';
      const consumerEmail = bookingData.consumer_email;
      
      // Send notification to consumer
      await notificationService.saveNotification({
        userId: consumerId,
        type: 'booking_rejected',
        title: 'Booking Declined',
        message: `${barberName} was unable to accept your booking request`,
        data: { bookingId, reason },
      });

      // Send decline email to consumer with alternative barbers
      if (consumerEmail) {
        const campusTimezone = bookingData.campus_timezone || 'America/New_York';
        const scheduledDate = new Date(bookingData.requestedAt);
        const serviceName = bookingData.service_name || bookingData.serviceType || 'Haircut';
        const declinedBarberId = bookingData.barberId;
        const campusId = bookingData.campus_id;
        
        // Fetch alternative barbers asynchronously
        (async () => {
          let alternativeBarbers: AlternativeBarber[] = [];
          if (campusId && declinedBarberId) {
            alternativeBarbers = await fetchAlternativeBarbers(
              campusId,
              declinedBarberId,
              serviceName,
              scheduledDate
            );
          }
          
          sendBookingDeclineEmail({
            consumerEmail,
            consumerName,
            barberName,
            barberId: declinedBarberId,
            serviceName,
            scheduledDate: scheduledDate.toLocaleDateString('en-US', { 
              weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', 
              timeZone: campusTimezone 
            }),
            scheduledTime: scheduledDate.toLocaleTimeString('en-US', { 
              hour: 'numeric', minute: '2-digit', hour12: true, 
              timeZone: campusTimezone 
            }),
            price: (bookingData.priceUsdCents || 0) / 100,
            location: bookingData.location || undefined,
            reason: reason || undefined,
            bookingId,
            campusId,
            originalScheduledTime: scheduledDate.toISOString(),
            alternativeBarbers,
          }).catch(err => logger.error('Failed to send decline email:', err));
        })();
      }

      await client.query('COMMIT');
      logger.info(`Booking ${bookingId} rejected by barber ${barberId}`);

      return { success: true };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Error rejecting booking request:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get customer profile (for barber view)
   */
  async getCustomerProfile(customerId: string, viewingBarberId: string) {
    try {
      const result = await pool.query(`
        SELECT 
          u.id,
          u.name,
          u.email,
          cp.display_name,
          cp.bio,
          cp.profile_image_url,
          cp.verified,
          cp.total_bookings,
          cp.completed_bookings,
          cp.cancelled_bookings,
          cp.no_show_count,
          cp.avg_rating,
          cp.total_reviews,
          cp.is_reliable,
          cp.response_rate,
          cp.created_at as member_since,
          -- Get reviews from this barber about this customer
          (SELECT json_agg(json_build_object(
            'rating', rating,
            'comment', comment,
            'showedUp', showed_up,
            'wasOnTime', was_on_time,
            'wasRespectful', was_respectful,
            'createdAt', created_at
          ))
          FROM customer_reviews
          WHERE customer_id = $1 AND barber_id = $2) as previous_reviews
        FROM users u
        LEFT JOIN customer_profiles cp ON u.id = cp.user_id
        WHERE u.id = $1
      `, [customerId, viewingBarberId]);

      if (result.rows.length === 0) {
        throw new Error('Customer not found');
      }

      const profile = result.rows[0];

      return {
        id: profile.id,
        name: profile.name,
        displayName: profile.display_name || profile.name,
        bio: profile.bio,
        profileImageUrl: profile.profile_image_url,
        verified: profile.verified,
        memberSince: profile.member_since,
        stats: {
          totalBookings: parseInt(profile.total_bookings) || 0,
          completedBookings: parseInt(profile.completed_bookings) || 0,
          cancelledBookings: parseInt(profile.cancelled_bookings) || 0,
          noShowCount: parseInt(profile.no_show_count) || 0,
          avgRating: parseFloat(profile.avg_rating) || 0,
          totalReviews: parseInt(profile.total_reviews) || 0,
          completionRate: profile.total_bookings > 0
            ? Math.round((profile.completed_bookings / profile.total_bookings) * 100)
            : 0,
          isReliable: profile.is_reliable !== false,
          responseRate: parseFloat(profile.response_rate) || 100,
        },
        previousReviews: profile.previous_reviews || [],
      };
    } catch (error) {
      logger.error('Error getting customer profile (using mock data):', error);
      
      // Return mock customer profile
      return {
        id: customerId,
        name: 'Mock Customer',
        displayName: 'Mock Student',
        bio: 'This is a mock customer profile. Connect PostgreSQL to see real data.',
        profileImageUrl: null,
        verified: false,
        memberSince: new Date('2024-09-01'),
        stats: {
          totalBookings: 10,
          completedBookings: 9,
          cancelledBookings: 1,
          noShowCount: 0,
          avgRating: 4.5,
          totalReviews: 8,
          completionRate: 90,
          isReliable: true,
          responseRate: 95,
        },
        previousReviews: [],
      };
    }
  }

  /**
   * Get customer's pending and active bookings
   */
  async getCustomerBookingStatus(customerId: string) {
    try {
      const result = await pool.query(`
        SELECT 
          b.id,
          b.status,
          b.service_type,
          b.booking_date,
          b.booking_time,
          b.price_charged,
          b.requested_at,
          b.responded_at,
          ba.barber_id,
          u.name as barber_name,
          (SELECT COUNT(*) FROM booking_messages 
           WHERE booking_id = b.id AND read = false AND sender_type = 'barber') as unread_messages
        FROM bookings b
        JOIN barbers ba ON b.barber_id = ba.barber_id
        JOIN users u ON ba.user_id = u.id
        WHERE b.customer_id = $1
          AND b.status IN ('pending', 'accepted')
        ORDER BY b.requested_at DESC
      `, [customerId]);

      return result.rows.map(row => ({
        bookingId: row.id,
        status: row.status,
        serviceType: row.service_type,
        bookingDate: row.booking_date,
        bookingTime: row.booking_time,
        price: parseFloat(row.price_charged),
        requestedAt: row.requested_at,
        respondedAt: row.responded_at,
        barber: {
          id: row.barber_id,
          name: row.barber_name,
        },
        unreadMessages: parseInt(row.unread_messages) || 0,
      }));
    } catch (error) {
      logger.error('Error getting customer booking status:', error);
      throw error;
    }
  }

  /**
   * Send booking confirmation emails asynchronously
   * Fetches full booking details and sends emails to both consumer and barber
   */
  private async sendBookingConfirmationEmailsAsync(bookingId: string): Promise<void> {
    try {
      // Fetch complete booking details with consumer and barber info (include campus timezone)
      const result = await pool.query(`
        SELECT 
          b.id,
          b."serviceType",
          b."priceUsdCents",
          b."requestedAt" as "scheduledTime",
          c.service_name as "serviceName",
          c.location,
          c.notes,
          u_consumer.id as consumer_id,
          u_consumer.first_name as consumer_first_name,
          u_consumer.last_name as consumer_last_name,
          u_consumer.email as consumer_email,
          u_barber.id as barber_user_id,
          u_barber.first_name as barber_first_name,
          u_barber.last_name as barber_last_name,
          u_barber.email as barber_email,
          COALESCE(campus.timezone, 'America/New_York') as campus_timezone
        FROM bookings b
        JOIN users u_consumer ON b."consumerId" = u_consumer.id
        JOIN barbers bar ON b."barberId" = bar.id
        JOIN users u_barber ON bar."userId" = u_barber.id
        LEFT JOIN conversations c ON c.booking_id = b.id
        LEFT JOIN campuses campus ON bar."campusId" = campus.id
        WHERE b.id = $1
      `, [bookingId]);

      if (result.rows.length === 0) {
        logger.error(`Booking ${bookingId} not found for email confirmation`);
        return;
      }

      const booking = result.rows[0];
      const scheduledTime = new Date(booking.scheduledTime);
      const campusTimezone = booking.campus_timezone || 'America/New_York';

      await sendBookingConfirmationEmails({
        bookingId: booking.id,
        serviceName: booking.serviceName || booking.serviceType,
        price: (booking.priceUsdCents || 0) / 100,
        scheduledDate: scheduledTime.toLocaleDateString('en-US', { 
          weekday: 'long', 
          year: 'numeric', 
          month: 'long', 
          day: 'numeric',
          timeZone: campusTimezone
        }),
        scheduledTime: scheduledTime.toLocaleTimeString('en-US', { 
          hour: 'numeric', 
          minute: '2-digit',
          hour12: true,
          timeZone: campusTimezone
        }),
        location: booking.location || undefined,
        notes: booking.notes || undefined,
        consumerName: `${booking.consumer_first_name} ${booking.consumer_last_name}`,
        consumerEmail: booking.consumer_email,
        barberName: `${booking.barber_first_name} ${booking.barber_last_name}`,
        barberEmail: booking.barber_email,
      });

      logger.info(`Booking confirmation emails sent for booking ${bookingId}`);
    } catch (error) {
      logger.error(`Error sending booking confirmation emails for ${bookingId}:`, error);
      throw error;
    }
  }
}

export const bookingRequestService = new BookingRequestService();

