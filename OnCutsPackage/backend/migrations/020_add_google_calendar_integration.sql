-- Migration: Add Google Calendar integration columns to barbers table
-- Purpose: Store Google OAuth refresh token for calendar sync

-- Add Google Calendar integration columns
ALTER TABLE barbers 
ADD COLUMN IF NOT EXISTS google_refresh_token TEXT,
ADD COLUMN IF NOT EXISTS google_calendar_connected BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS google_calendar_connected_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS google_calendar_sync_enabled BOOLEAN DEFAULT TRUE;

-- Comment for documentation
COMMENT ON COLUMN barbers.google_refresh_token IS 'Google OAuth2 refresh token for calendar access';
COMMENT ON COLUMN barbers.google_calendar_connected IS 'Whether Google Calendar is currently connected';
COMMENT ON COLUMN barbers.google_calendar_connected_at IS 'When the Google Calendar was last connected';
COMMENT ON COLUMN barbers.google_calendar_sync_enabled IS 'Whether to sync bookings to Google Calendar';

