-- Migration: 011_booking_centric_conversations.sql
-- Purpose: Make conversations booking/service-centric for CampusCuts
-- This caches booking details in the conversation for performance and persistence

-- Add cached booking context columns to conversations table
ALTER TABLE conversations 
ADD COLUMN IF NOT EXISTS service_name VARCHAR(100),
ADD COLUMN IF NOT EXISTS service_price DECIMAL(10, 2),
ADD COLUMN IF NOT EXISTS scheduled_time TIMESTAMP,
ADD COLUMN IF NOT EXISTS location VARCHAR(255),
ADD COLUMN IF NOT EXISTS location_details TEXT,
ADD COLUMN IF NOT EXISTS booking_status VARCHAR(50) DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS barber_name VARCHAR(100),
ADD COLUMN IF NOT EXISTS consumer_name VARCHAR(100),
ADD COLUMN IF NOT EXISTS barber_profile_picture TEXT,
ADD COLUMN IF NOT EXISTS consumer_profile_picture TEXT,
ADD COLUMN IF NOT EXISTS notes TEXT;

-- Add index for booking status queries
CREATE INDEX IF NOT EXISTS idx_conversations_booking_status ON conversations(booking_status);

-- Comment explaining the denormalization
COMMENT ON COLUMN conversations.service_name IS 'Cached service name for display without JOIN';
COMMENT ON COLUMN conversations.service_price IS 'Cached service price at time of booking';
COMMENT ON COLUMN conversations.scheduled_time IS 'Cached scheduled time for quick access';
COMMENT ON COLUMN conversations.location IS 'Cached service location';
COMMENT ON COLUMN conversations.booking_status IS 'Cached booking status (pending, confirmed, completed, cancelled)';
COMMENT ON COLUMN conversations.barber_name IS 'Cached barber display name';
COMMENT ON COLUMN conversations.consumer_name IS 'Cached consumer name';

