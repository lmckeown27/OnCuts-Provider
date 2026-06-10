-- Migration: Add Stripe Connect status columns to users table
-- Purpose: Track whether barber's Stripe account is fully verified and can receive payouts
-- This allows filtering out "Restricted" barbers from consumer view

-- Add stripe_payouts_enabled column (tracks if barber can receive payouts)
ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_payouts_enabled BOOLEAN DEFAULT FALSE;

-- Add stripe_charges_enabled column (tracks if barber can accept charges)
ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_charges_enabled BOOLEAN DEFAULT FALSE;

-- Create index for efficient filtering of verified barbers
CREATE INDEX IF NOT EXISTS idx_users_stripe_payouts_enabled 
  ON users(stripe_payouts_enabled) 
  WHERE stripe_payouts_enabled = true;

-- NOTE: Do NOT auto-backfill as true - this would show restricted accounts to consumers
-- Instead, run the sync script after migration to check each account with Stripe API:
--   cd backend && npm run sync-stripe-status
-- 
-- This will query Stripe for each barber and set the correct status

COMMENT ON COLUMN users.stripe_payouts_enabled IS 'Whether barber Stripe Connect account can receive payouts (false = restricted)';
COMMENT ON COLUMN users.stripe_charges_enabled IS 'Whether barber Stripe Connect account can accept charges';

