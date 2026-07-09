-- Migration: Add Stripe webhook idempotency tracking
-- Purpose: Prevent duplicate processing of webhook events

-- Track processed Stripe webhook events
CREATE TABLE IF NOT EXISTS stripe_webhook_events (
  id SERIAL PRIMARY KEY,
  event_id VARCHAR(255) UNIQUE NOT NULL,
  event_type VARCHAR(100) NOT NULL,
  processed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  payload JSONB,
  processing_result VARCHAR(50) DEFAULT 'success'
);

-- Fast lookup by event_id
CREATE INDEX IF NOT EXISTS idx_stripe_webhook_events_event_id 
  ON stripe_webhook_events(event_id);

-- Query processed events by type and date
CREATE INDEX IF NOT EXISTS idx_stripe_webhook_events_type_date 
  ON stripe_webhook_events(event_type, processed_at DESC);

-- Add payments table if it doesn't exist (for audit trail)
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID REFERENCES bookings(id),
  consumer_id UUID REFERENCES users(id),
  barber_id UUID REFERENCES users(id),
  payment_intent_id VARCHAR(255) UNIQUE,
  amount_cents INTEGER NOT NULL,
  tip_amount_cents INTEGER DEFAULT 0,
  currency VARCHAR(3) DEFAULT 'USD',
  status VARCHAR(50) NOT NULL,
  failure_reason TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_booking_id ON payments(booking_id);
CREATE INDEX IF NOT EXISTS idx_payments_payment_intent ON payments(payment_intent_id);

-- Add paid_at and tip columns to bookings if not exists
ALTER TABLE bookings 
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS tip_amount_cents INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS payment_intent_id VARCHAR(255);

-- Comments
COMMENT ON TABLE stripe_webhook_events IS 'Tracks processed Stripe webhook events for idempotency';
COMMENT ON COLUMN stripe_webhook_events.event_id IS 'Stripe event ID (evt_xxx) - used for deduplication';
COMMENT ON COLUMN stripe_webhook_events.processing_result IS 'success or failed - for debugging';

