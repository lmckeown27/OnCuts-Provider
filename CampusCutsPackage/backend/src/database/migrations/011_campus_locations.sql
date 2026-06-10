-- Migration: Campus Locations System
-- Description: Creates a table for campus-specific locations that barbers can use
-- Date: 2026-01-18

-- Campus locations table: stores locations available at each campus
CREATE TABLE IF NOT EXISTS campus_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campus_id UUID NOT NULL REFERENCES campuses(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  address TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(campus_id, name)
);

-- Barber locations: junction table linking barbers to their available locations
CREATE TABLE IF NOT EXISTS barber_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barber_id UUID NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
  location_id UUID NOT NULL REFERENCES campus_locations(id) ON DELETE CASCADE,
  is_primary BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(barber_id, location_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_campus_locations_campus ON campus_locations(campus_id);
CREATE INDEX IF NOT EXISTS idx_campus_locations_active ON campus_locations(campus_id, is_active);
CREATE INDEX IF NOT EXISTS idx_barber_locations_barber ON barber_locations(barber_id);
CREATE INDEX IF NOT EXISTS idx_barber_locations_location ON barber_locations(location_id);

-- Comments
COMMENT ON TABLE campus_locations IS 'Stores predefined locations for each campus where services can be performed';
COMMENT ON TABLE barber_locations IS 'Links barbers to the locations where they are available to work';
COMMENT ON COLUMN campus_locations.created_by IS 'The campus manager or admin who created this location';
COMMENT ON COLUMN barber_locations.is_primary IS 'Indicates if this is the barber''s primary/default location';

