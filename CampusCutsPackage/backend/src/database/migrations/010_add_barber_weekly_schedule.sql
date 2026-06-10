-- Migration: Add weekly schedule to barbers table
-- This stores the barber's recurring weekly availability hours

-- Add weeklySchedule column as JSONB
ALTER TABLE barbers 
ADD COLUMN IF NOT EXISTS "weeklySchedule" JSONB DEFAULT '{
  "monday": { "enabled": true, "start": "09:00", "end": "17:00" },
  "tuesday": { "enabled": true, "start": "09:00", "end": "17:00" },
  "wednesday": { "enabled": true, "start": "09:00", "end": "17:00" },
  "thursday": { "enabled": true, "start": "09:00", "end": "17:00" },
  "friday": { "enabled": true, "start": "09:00", "end": "17:00" },
  "saturday": { "enabled": false, "start": "10:00", "end": "16:00" },
  "sunday": { "enabled": false, "start": "10:00", "end": "16:00" }
}'::jsonb;

-- Add index for faster querying by schedule
CREATE INDEX IF NOT EXISTS idx_barbers_weekly_schedule ON barbers USING GIN ("weeklySchedule");

COMMENT ON COLUMN barbers."weeklySchedule" IS 'Recurring weekly availability schedule for the barber';

