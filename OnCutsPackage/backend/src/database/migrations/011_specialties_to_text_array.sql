-- Migration: Change specialties from enum array to text array
-- This allows flexible service names without enum constraints

-- First, alter the column type from ServiceType[] to TEXT[]
ALTER TABLE barbers 
ALTER COLUMN specialties TYPE TEXT[] 
USING specialties::TEXT[];

-- No data migration needed - the values will convert automatically
-- e.g., BUZZ_CUT becomes 'BUZZ_CUT' as text

COMMENT ON COLUMN barbers.specialties IS 'Array of service/specialty names this barber offers';

