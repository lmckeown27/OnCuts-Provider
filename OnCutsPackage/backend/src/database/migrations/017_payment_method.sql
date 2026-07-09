-- Migration: Add payment_method column to bookings table
-- This allows tracking whether payments were made via card or cash

-- Add payment_method column
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS "paymentMethod" VARCHAR(20) DEFAULT NULL;

-- Add comment for documentation
COMMENT ON COLUMN bookings."paymentMethod" IS 'Payment method used: card or cash';

-- Create index for potential filtering/reporting
CREATE INDEX IF NOT EXISTS idx_bookings_payment_method ON bookings("paymentMethod");

