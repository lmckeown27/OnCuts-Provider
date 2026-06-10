-- Migration: Create pending_payouts table for tracking failed/pending barber payouts
-- This ensures no barber payouts are lost if Stripe Connect fails

-- Create pending_payouts table
CREATE TABLE IF NOT EXISTS pending_payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    barber_id UUID NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
    amount_cents INTEGER NOT NULL,
    tip_cents INTEGER DEFAULT 0,
    payment_intent_id VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    stripe_transfer_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(booking_id)
);

-- Add indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_pending_payouts_status ON pending_payouts(status);
CREATE INDEX IF NOT EXISTS idx_pending_payouts_barber ON pending_payouts(barber_id);
CREATE INDEX IF NOT EXISTS idx_pending_payouts_created ON pending_payouts(created_at);

-- Add missing columns to payments table for payout tracking
ALTER TABLE payments ADD COLUMN IF NOT EXISTS stripe_transfer_id VARCHAR(255);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS platform_fee_cents INTEGER;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS barber_earnings_cents INTEGER;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS transfer_status VARCHAR(20) DEFAULT 'pending';
ALTER TABLE payments ADD COLUMN IF NOT EXISTS transferred_at TIMESTAMP WITH TIME ZONE;

-- Add index for transfer lookups
CREATE INDEX IF NOT EXISTS idx_payments_transfer_id ON payments(stripe_transfer_id);
CREATE INDEX IF NOT EXISTS idx_payments_transfer_status ON payments(transfer_status);

