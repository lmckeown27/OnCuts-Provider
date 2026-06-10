-- Migration 008: Payment Escrows System (Fixed for UUID)
-- Unified escrow table supporting both off-chain (Stripe) and on-chain (Circle + Blockchain) payments

-- Drop existing objects if migration was partially run
DROP VIEW IF EXISTS escrow_details CASCADE;
DROP TRIGGER IF EXISTS trigger_update_escrows_updated_at ON escrows;
DROP FUNCTION IF EXISTS update_escrows_updated_at();
DROP TABLE IF EXISTS escrows CASCADE;

-- Create escrows table with UUID for booking_id
CREATE TABLE escrows (
  id SERIAL PRIMARY KEY,
  booking_id UUID NOT NULL,  -- Changed from INTEGER to UUID
  amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  type VARCHAR(20) NOT NULL DEFAULT 'offchain',
  
  -- Off-chain fields (Stripe)
  stripe_payment_intent_id VARCHAR(255),
  stripe_transfer_id VARCHAR(255),
  stripe_refund_id VARCHAR(255),
  
  -- On-chain fields (future use)
  blockchain_tx_hash VARCHAR(255),
  blockchain_escrow_id VARCHAR(255),
  usdc_amount DECIMAL(20, 6),
  
  -- Timestamps
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  released_at TIMESTAMP,
  refunded_at TIMESTAMP,
  
  -- Constraints
  CONSTRAINT escrow_status_check CHECK (status IN ('pending', 'held', 'released', 'refunded', 'failed')),
  CONSTRAINT escrow_type_check CHECK (type IN ('offchain', 'onchain')),
  CONSTRAINT escrow_stripe_or_blockchain CHECK (
    (type = 'offchain' AND stripe_payment_intent_id IS NOT NULL) OR
    (type = 'onchain' AND blockchain_tx_hash IS NOT NULL) OR
    (status = 'pending')
  )
);

-- Check if bookings table exists and has compatible ID type
DO $$
BEGIN
  -- Try to add foreign key constraint if bookings table exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'bookings') THEN
    -- Check if bookings.id is uuid type
    IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'bookings' 
      AND column_name = 'id' 
      AND udt_name = 'uuid'
    ) THEN
      ALTER TABLE escrows ADD CONSTRAINT escrows_booking_id_fkey 
        FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE;
      RAISE NOTICE 'Foreign key constraint added to bookings table';
    ELSE
      RAISE NOTICE 'Warning: bookings.id is not UUID type, skipping foreign key constraint';
    END IF;
  ELSE
    RAISE NOTICE 'Warning: bookings table does not exist, skipping foreign key constraint';
  END IF;
END $$;

-- Indexes for performance
CREATE INDEX idx_escrows_booking_id ON escrows(booking_id);
CREATE INDEX idx_escrows_status ON escrows(status);
CREATE INDEX idx_escrows_type ON escrows(type);
CREATE INDEX idx_escrows_stripe_payment_intent ON escrows(stripe_payment_intent_id) WHERE stripe_payment_intent_id IS NOT NULL;
CREATE INDEX idx_escrows_blockchain_tx ON escrows(blockchain_tx_hash) WHERE blockchain_tx_hash IS NOT NULL;
CREATE INDEX idx_escrows_created_at ON escrows(created_at DESC);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_escrows_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  
  -- Auto-set released_at when status changes to released
  IF NEW.status = 'released' AND OLD.status != 'released' THEN
    NEW.released_at = NOW();
  END IF;
  
  -- Auto-set refunded_at when status changes to refunded
  IF NEW.status = 'refunded' AND OLD.status != 'refunded' THEN
    NEW.refunded_at = NOW();
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_escrows_updated_at
  BEFORE UPDATE ON escrows
  FOR EACH ROW
  EXECUTE FUNCTION update_escrows_updated_at();

-- View for easy querying of escrow details
CREATE OR REPLACE VIEW escrow_details AS
SELECT 
  e.id AS escrow_id,
  e.booking_id,
  e.amount,
  e.status AS escrow_status,
  e.type AS escrow_type,
  e.stripe_payment_intent_id,
  e.stripe_transfer_id,
  e.blockchain_tx_hash,
  e.created_at AS escrow_created_at,
  e.released_at AS escrow_released_at,
  e.refunded_at AS escrow_refunded_at
FROM escrows e;

-- Grant permissions (adjust based on your database user)
-- GRANT SELECT, INSERT, UPDATE ON escrows TO campuscuts_user;
-- GRANT SELECT ON escrow_details TO campuscuts_user;
-- GRANT USAGE, SELECT ON SEQUENCE escrows_id_seq TO campuscuts_user;

-- Add comment
COMMENT ON TABLE escrows IS 'Payment escrows supporting both off-chain (Stripe) and on-chain (blockchain) modes';

-- Migration complete
SELECT 'Migration 008: Payment Escrows System (UUID Fixed) - Complete' AS status;

