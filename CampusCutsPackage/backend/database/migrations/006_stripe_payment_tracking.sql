-- Stripe Payment Tracking Tables
-- Migration: 006_stripe_payment_tracking
-- Purpose: Track Stripe payments, refunds, and barber payouts

-- ============================================
-- Payment Transactions Table
-- ============================================
CREATE TABLE IF NOT EXISTS payment_transactions (
  id SERIAL PRIMARY KEY,
  booking_id INTEGER REFERENCES bookings(id) ON DELETE CASCADE,
  student_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  barber_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  payment_intent_id VARCHAR(255) UNIQUE NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'USD',
  status VARCHAR(50) NOT NULL, -- 'succeeded', 'failed', 'refunded', 'canceled'
  payment_method VARCHAR(50), -- 'card', 'bank_transfer', etc.
  failure_reason TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_payment_transactions_booking_id ON payment_transactions(booking_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_student_id ON payment_transactions(student_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_barber_id ON payment_transactions(barber_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_payment_intent_id ON payment_transactions(payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON payment_transactions(status);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_created_at ON payment_transactions(created_at DESC);

-- ============================================
-- Barber Payouts Table
-- ============================================
CREATE TABLE IF NOT EXISTS barber_payouts (
  id SERIAL PRIMARY KEY,
  barber_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  booking_id INTEGER REFERENCES bookings(id) ON DELETE SET NULL,
  transfer_id VARCHAR(255) UNIQUE NOT NULL, -- Stripe transfer ID
  amount DECIMAL(10, 2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'USD',
  status VARCHAR(50) NOT NULL, -- 'pending', 'completed', 'failed'
  failure_reason TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_barber_payouts_barber_id ON barber_payouts(barber_id);
CREATE INDEX IF NOT EXISTS idx_barber_payouts_booking_id ON barber_payouts(booking_id);
CREATE INDEX IF NOT EXISTS idx_barber_payouts_transfer_id ON barber_payouts(transfer_id);
CREATE INDEX IF NOT EXISTS idx_barber_payouts_status ON barber_payouts(status);
CREATE INDEX IF NOT EXISTS idx_barber_payouts_created_at ON barber_payouts(created_at DESC);

-- ============================================
-- Add payment columns to bookings table
-- ============================================
ALTER TABLE bookings 
ADD COLUMN IF NOT EXISTS payment_intent_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS payment_status VARCHAR(50) DEFAULT 'pending'; -- 'pending', 'paid', 'failed', 'refunded', 'canceled'

-- Add index for payment_intent_id lookups
CREATE INDEX IF NOT EXISTS idx_bookings_payment_intent_id ON bookings(payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_bookings_payment_status ON bookings(payment_status);

-- ============================================
-- Add Stripe Connect columns to users table
-- ============================================
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS stripe_account_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS stripe_connect_onboarded BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS stripe_charges_enabled BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS stripe_payouts_enabled BOOLEAN DEFAULT FALSE;

-- Add index for Stripe account lookups
CREATE INDEX IF NOT EXISTS idx_users_stripe_account_id ON users(stripe_account_id);
CREATE INDEX IF NOT EXISTS idx_users_stripe_connect_onboarded ON users(stripe_connect_onboarded);

-- ============================================
-- Add triggers for updated_at timestamps
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers
DROP TRIGGER IF EXISTS update_payment_transactions_updated_at ON payment_transactions;
CREATE TRIGGER update_payment_transactions_updated_at
  BEFORE UPDATE ON payment_transactions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_barber_payouts_updated_at ON barber_payouts;
CREATE TRIGGER update_barber_payouts_updated_at
  BEFORE UPDATE ON barber_payouts
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON TABLE payment_transactions IS 'Records all Stripe payment transactions (payments, refunds, etc.)';
COMMENT ON TABLE barber_payouts IS 'Records all payouts to barbers via Stripe Connect';
COMMENT ON COLUMN bookings.payment_intent_id IS 'Stripe Payment Intent ID for this booking';
COMMENT ON COLUMN bookings.payment_status IS 'Payment status: pending, paid, failed, refunded, canceled';
COMMENT ON COLUMN users.stripe_account_id IS 'Stripe Connect account ID for barbers';
COMMENT ON COLUMN users.stripe_connect_onboarded IS 'Whether barber completed Stripe Connect onboarding';

