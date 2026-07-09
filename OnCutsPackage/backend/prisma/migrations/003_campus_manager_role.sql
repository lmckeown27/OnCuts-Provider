-- Campus Manager Role Migration
-- Adds Campus Manager functionality as a role overlay on Barber entity

-- Add Campus Manager fields to barbers table
ALTER TABLE "barbers"
ADD COLUMN "is_campus_manager" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "campus_manager_since" TIMESTAMPTZ;

-- Create partial unique index: Only one Campus Manager per campus
-- This allows multiple false values but only one true value per campus
CREATE UNIQUE INDEX "idx_unique_campus_manager" ON "barbers"("campus_id")
WHERE "is_campus_manager" = true;

-- Create index for Campus Manager queries
CREATE INDEX "idx_barbers_campus_manager" ON "barbers"("campus_id", "is_campus_manager")
WHERE "is_campus_manager" = true;

-- Function to safely promote a barber to Campus Manager
CREATE OR REPLACE FUNCTION promote_to_campus_manager(
  p_barber_id UUID,
  p_campus_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  v_current_manager_id UUID;
BEGIN
  -- Check if there's already a Campus Manager for this campus
  SELECT id INTO v_current_manager_id
  FROM barbers
  WHERE campus_id = p_campus_id AND is_campus_manager = true;
  
  -- If there's a different Campus Manager, fail
  IF v_current_manager_id IS NOT NULL AND v_current_manager_id != p_barber_id THEN
    RAISE EXCEPTION 'Campus already has a Campus Manager (barber_id: %)', v_current_manager_id;
  END IF;
  
  -- Promote the barber
  UPDATE barbers
  SET 
    is_campus_manager = true,
    campus_manager_since = NOW(),
    updated_at = NOW()
  WHERE 
    id = p_barber_id
    AND campus_id = p_campus_id
    AND is_active = true
    AND is_onboarded = true;
  
  RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to safely revoke Campus Manager role
CREATE OR REPLACE FUNCTION revoke_campus_manager(
  p_barber_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE barbers
  SET 
    is_campus_manager = false,
    campus_manager_since = NULL,
    updated_at = NOW()
  WHERE id = p_barber_id;
  
  RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Add comments
COMMENT ON COLUMN barbers.is_campus_manager IS 'Campus Manager role flag. Only one barber per campus can be Campus Manager.';
COMMENT ON COLUMN barbers.campus_manager_since IS 'Timestamp when barber was promoted to Campus Manager role.';
COMMENT ON INDEX idx_unique_campus_manager IS 'Ensures only one Campus Manager per campus (partial unique index).';
COMMENT ON FUNCTION promote_to_campus_manager IS 'Safely promotes a barber to Campus Manager role with validation.';
COMMENT ON FUNCTION revoke_campus_manager IS 'Removes Campus Manager role from a barber.';

