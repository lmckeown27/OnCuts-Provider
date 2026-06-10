-- Migration: Add review columns to bookings table
-- This allows reviews to be stored directly in the bookings table for simplicity

-- Add review columns to bookings table
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "reviewRating" SMALLINT;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "reviewComment" TEXT;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "reviewedAt" TIMESTAMPTZ;

-- Add check constraint for rating range
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'booking_review_rating_range'
    ) THEN
        ALTER TABLE bookings ADD CONSTRAINT booking_review_rating_range 
        CHECK ("reviewRating" IS NULL OR ("reviewRating" >= 1 AND "reviewRating" <= 5));
    END IF;
END $$;

-- Create index for finding reviewed bookings
CREATE INDEX IF NOT EXISTS idx_bookings_review_rating ON bookings("reviewRating") WHERE "reviewRating" IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bookings_barber_review ON bookings("barberId", "reviewRating") WHERE "reviewRating" IS NOT NULL;

-- Also ensure barbers table has the rating columns with correct names
ALTER TABLE barbers ADD COLUMN IF NOT EXISTS "avgRating" DECIMAL(3,2);
ALTER TABLE barbers ADD COLUMN IF NOT EXISTS "totalReviews" INTEGER DEFAULT 0;

COMMENT ON COLUMN bookings."reviewRating" IS 'Consumer rating (1-5 stars) for this booking';
COMMENT ON COLUMN bookings."reviewComment" IS 'Consumer review comment text';
COMMENT ON COLUMN bookings."reviewedAt" IS 'Timestamp when the review was submitted';

