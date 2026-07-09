-- Migration: Fix conversations.scheduled_time to use TIMESTAMPTZ
-- The scheduled_time column was using TIMESTAMP (without timezone) which caused
-- 8-hour timezone discrepancies when formatting times for emails.
-- This migration converts it to TIMESTAMPTZ, assuming existing values are in UTC.

-- Step 1: Add a new column with correct type
ALTER TABLE conversations 
ADD COLUMN IF NOT EXISTS scheduled_time_tz TIMESTAMPTZ;

-- Step 2: Copy existing data (treating old values as UTC)
UPDATE conversations 
SET scheduled_time_tz = scheduled_time AT TIME ZONE 'UTC'
WHERE scheduled_time IS NOT NULL AND scheduled_time_tz IS NULL;

-- Step 3: Drop old column and rename new one
-- Note: Only do this after verifying data was copied correctly
-- ALTER TABLE conversations DROP COLUMN scheduled_time;
-- ALTER TABLE conversations RENAME COLUMN scheduled_time_tz TO scheduled_time;

-- For now, just add the new column and let the application use bookings.requestedAt as source of truth

