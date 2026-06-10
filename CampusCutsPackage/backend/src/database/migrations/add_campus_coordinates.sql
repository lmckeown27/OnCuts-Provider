-- Add latitude and longitude columns to campuses table
-- Run with: sudo -u postgres psql -d campuscuts -f add_campus_coordinates.sql

-- Add columns
ALTER TABLE campuses ADD COLUMN IF NOT EXISTS latitude DECIMAL(10, 6);
ALTER TABLE campuses ADD COLUMN IF NOT EXISTS longitude DECIMAL(10, 6);

-- Add index for geographic queries
CREATE INDEX IF NOT EXISTS idx_campuses_coordinates ON campuses(latitude, longitude);

-- Update existing campuses with coordinates
UPDATE campuses SET latitude = 35.3050, longitude = -120.6625 WHERE slug = 'cal-poly' OR name ILIKE '%cal poly%san luis%';

-- Verify
SELECT name, city, state, latitude, longitude FROM campuses WHERE latitude IS NOT NULL;

