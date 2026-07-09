/**
 * Google Calendar Service
 * Handles OAuth flow and calendar operations for barber availability sync
 */

import { google } from 'googleapis';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CALENDAR_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CALENDAR_CLIENT_SECRET;
const GOOGLE_REDIRECT_URI = process.env.GOOGLE_CALENDAR_REDIRECT_URI || 'https://campuscut.com/api/v1/auth/google-calendar/callback';

// Scopes needed for calendar read/write
const SCOPES = [
  'https://www.googleapis.com/auth/calendar.readonly',
  'https://www.googleapis.com/auth/calendar.events',
];

/**
 * Create an OAuth2 client instance
 */
export function createOAuth2Client() {
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
    throw new Error('Google Calendar credentials not configured');
  }
  
  return new google.auth.OAuth2(
    GOOGLE_CLIENT_ID,
    GOOGLE_CLIENT_SECRET,
    GOOGLE_REDIRECT_URI
  );
}

/**
 * Generate the Google OAuth URL for barber authorization
 * @param barberUserId - The user ID of the barber (used in state for callback)
 */
export function generateAuthUrl(barberUserId: string): string {
  const oauth2Client = createOAuth2Client();
  
  const authUrl = oauth2Client.generateAuthUrl({
    access_type: 'offline', // Required to get refresh_token
    prompt: 'consent', // Force consent screen to ensure we get refresh_token
    scope: SCOPES,
    state: barberUserId, // Pass user ID to callback
  });
  
  return authUrl;
}

/**
 * Exchange authorization code for tokens and save refresh_token
 * @param code - The authorization code from Google
 * @param barberUserId - The user ID of the barber
 */
export async function handleOAuthCallback(code: string, barberUserId: string): Promise<{ success: boolean; error?: string }> {
  try {
    const oauth2Client = createOAuth2Client();
    
    // Exchange code for tokens
    const { tokens } = await oauth2Client.getToken(code);
    
    if (!tokens.refresh_token) {
      logger.warn('Google OAuth: No refresh_token received', { barberUserId });
      // This can happen if the user already authorized before
      // Try to use the access_token anyway
    }
    
    // Find barber record by user ID
    const barberResult = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1',
      [barberUserId]
    );
    
    if (barberResult.rows.length === 0) {
      return { success: false, error: 'Barber profile not found' };
    }
    
    const barberId = barberResult.rows[0].id;
    
    // Save refresh token to database
    await pool.query(
      `UPDATE barbers 
       SET google_refresh_token = $1,
           google_calendar_connected = true,
           google_calendar_connected_at = NOW(),
           "updatedAt" = NOW()
       WHERE id = $2`,
      [tokens.refresh_token || tokens.access_token, barberId]
    );
    
    logger.info('Google Calendar connected successfully', { barberId, barberUserId });
    
    return { success: true };
  } catch (error) {
    logger.error('Google OAuth callback error:', error);
    return { success: false, error: 'Failed to connect Google Calendar' };
  }
}

/**
 * Get an authenticated OAuth2 client for a barber
 * @param barberId - The barber's record ID
 */
export async function getAuthenticatedClient(barberId: string) {
  const result = await pool.query(
    'SELECT google_refresh_token FROM barbers WHERE id = $1',
    [barberId]
  );
  
  if (result.rows.length === 0 || !result.rows[0].google_refresh_token) {
    throw new Error('Google Calendar not connected');
  }
  
  const oauth2Client = createOAuth2Client();
  oauth2Client.setCredentials({
    refresh_token: result.rows[0].google_refresh_token,
  });
  
  return oauth2Client;
}

/**
 * Check if a barber has Google Calendar connected
 * @param barberId - The barber's record ID
 */
export async function isCalendarConnected(barberId: string): Promise<boolean> {
  const result = await pool.query(
    'SELECT google_calendar_connected FROM barbers WHERE id = $1',
    [barberId]
  );
  
  return result.rows[0]?.google_calendar_connected || false;
}

/**
 * Disconnect Google Calendar for a barber
 * @param barberId - The barber's record ID
 */
export async function disconnectCalendar(barberId: string): Promise<void> {
  await pool.query(
    `UPDATE barbers 
     SET google_refresh_token = NULL,
         google_calendar_connected = false,
         "updatedAt" = NOW()
     WHERE id = $1`,
    [barberId]
  );
  
  logger.info('Google Calendar disconnected', { barberId });
}

/**
 * Get busy times from Google Calendar for a specific date range
 * @param barberId - The barber's record ID
 * @param startDate - Start of the date range
 * @param endDate - End of the date range
 * @returns Array of busy time slots
 */
export async function getBusyTimes(
  barberId: string,
  startDate: Date,
  endDate: Date
): Promise<Array<{ start: Date; end: Date }>> {
  try {
    const auth = await getAuthenticatedClient(barberId);
    const calendar = google.calendar({ version: 'v3', auth });
    
    const response = await calendar.freebusy.query({
      requestBody: {
        timeMin: startDate.toISOString(),
        timeMax: endDate.toISOString(),
        items: [{ id: 'primary' }],
      },
    });
    
    const busyTimes = response.data.calendars?.primary?.busy || [];
    
    return busyTimes.map((slot: { start?: string | null; end?: string | null }) => ({
      start: new Date(slot.start || ''),
      end: new Date(slot.end || ''),
    }));
  } catch (error) {
    logger.error('Failed to get busy times from Google Calendar:', error);
    return [];
  }
}

/**
 * Add a CampusCuts booking to Google Calendar
 * @param barberId - The barber's record ID
 * @param booking - The booking details
 */
export async function addBookingToCalendar(
  barberId: string,
  booking: {
    id: string;
    consumerName: string;
    serviceName: string;
    scheduledDate: Date;
    durationMinutes: number;
    location?: string;
  }
): Promise<string | null> {
  try {
    // Check if sync is enabled
    const barberResult = await pool.query(
      'SELECT google_calendar_sync_enabled FROM barbers WHERE id = $1',
      [barberId]
    );
    
    if (!barberResult.rows[0]?.google_calendar_sync_enabled) {
      return null;
    }
    
    const auth = await getAuthenticatedClient(barberId);
    const calendar = google.calendar({ version: 'v3', auth });
    
    const endDate = new Date(booking.scheduledDate);
    endDate.setMinutes(endDate.getMinutes() + booking.durationMinutes);
    
    const event = {
      summary: `CampusCut: ${booking.serviceName} - ${booking.consumerName}`,
      description: `CampusCuts Booking\nService: ${booking.serviceName}\nClient: ${booking.consumerName}\nBooking ID: ${booking.id}`,
      start: {
        dateTime: booking.scheduledDate.toISOString(),
        timeZone: 'America/Los_Angeles',
      },
      end: {
        dateTime: endDate.toISOString(),
        timeZone: 'America/Los_Angeles',
      },
      location: booking.location,
      reminders: {
        useDefault: false,
        overrides: [
          { method: 'popup', minutes: 30 },
          { method: 'popup', minutes: 10 },
        ],
      },
    };
    
    const response = await calendar.events.insert({
      calendarId: 'primary',
      requestBody: event,
    });
    
    logger.info('Booking added to Google Calendar', { 
      barberId, 
      bookingId: booking.id,
      googleEventId: response.data.id 
    });
    
    return response.data.id || null;
  } catch (error) {
    logger.error('Failed to add booking to Google Calendar:', error);
    return null;
  }
}

/**
 * Remove a booking from Google Calendar
 * @param barberId - The barber's record ID
 * @param googleEventId - The Google Calendar event ID
 */
export async function removeBookingFromCalendar(
  barberId: string,
  googleEventId: string
): Promise<boolean> {
  try {
    const auth = await getAuthenticatedClient(barberId);
    const calendar = google.calendar({ version: 'v3', auth });
    
    await calendar.events.delete({
      calendarId: 'primary',
      eventId: googleEventId,
    });
    
    logger.info('Booking removed from Google Calendar', { barberId, googleEventId });
    return true;
  } catch (error) {
    logger.error('Failed to remove booking from Google Calendar:', error);
    return false;
  }
}

export default {
  generateAuthUrl,
  handleOAuthCallback,
  isCalendarConnected,
  disconnectCalendar,
  getBusyTimes,
  addBookingToCalendar,
  removeBookingFromCalendar,
};

