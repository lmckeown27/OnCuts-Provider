-- Persist service location on booking so history APIs work after the conversation row is removed on payment.

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS "serviceLocation" TEXT,
  ADD COLUMN IF NOT EXISTS "serviceLocationDetails" TEXT;
