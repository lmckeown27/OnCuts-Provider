-- Migration: Add location tracking to users table
-- This enables matching consumers with nearby barbers

-- Add location columns to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS latitude DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS longitude DECIMAL(11, 8),
ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS location_permission VARCHAR(20) DEFAULT 'prompt' 
  CHECK (location_permission IN ('granted', 'denied', 'prompt', 'unavailable'));

-- Add index for location-based queries
CREATE INDEX IF NOT EXISTS idx_users_location ON users(latitude, longitude) 
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Add index for permission status queries
CREATE INDEX IF NOT EXISTS idx_users_location_permission ON users(location_permission);

-- Add service location to barbers (optional - for barbers who work from a specific location)
ALTER TABLE barbers
ADD COLUMN IF NOT EXISTS service_latitude DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS service_longitude DECIMAL(11, 8),
ADD COLUMN IF NOT EXISTS service_radius_km DECIMAL(5, 2) DEFAULT 10.0;

-- Create index for barber service locations
CREATE INDEX IF NOT EXISTS idx_barbers_service_location ON barbers(service_latitude, service_longitude)
WHERE service_latitude IS NOT NULL AND service_longitude IS NOT NULL;

-- Comment on columns
COMMENT ON COLUMN users.latitude IS 'User current latitude from device geolocation';
COMMENT ON COLUMN users.longitude IS 'User current longitude from device geolocation';
COMMENT ON COLUMN users.location_updated_at IS 'When location was last updated';
COMMENT ON COLUMN users.location_permission IS 'Browser geolocation permission status';
COMMENT ON COLUMN barbers.service_latitude IS 'Optional: specific location where barber provides services';
COMMENT ON COLUMN barbers.service_longitude IS 'Optional: specific location where barber provides services';
COMMENT ON COLUMN barbers.service_radius_km IS 'How far barber is willing to travel to provide services';

