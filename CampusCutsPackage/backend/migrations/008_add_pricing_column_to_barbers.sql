-- Migration: Add pricing column to barbers table
-- This column stores barber-specific pricing for their services
-- Format: JSONB array of {name: string, price: number} objects
-- Example: [{"name": "Haircut", "price": 30}, {"name": "Fade", "price": 35}]

-- Add the pricing column if it doesn't exist
ALTER TABLE barbers ADD COLUMN IF NOT EXISTS pricing JSONB;

-- Add a comment explaining the column
COMMENT ON COLUMN barbers.pricing IS 'Barber custom pricing per service: [{name, price}]';

