/**
 * Migration 007: Circle Wallet Integration
 * 
 * Adds Circle wallet tracking and transaction history
 * 
 * Changes:
 * 1. Add Circle wallet fields to users table
 * 2. Create circle_transactions table for USDC transfer tracking
 * 3. Add indexes for performance
 * 4. Add constraints for data integrity
 */

-- Add Circle wallet fields to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS circle_wallet_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS circle_wallet_address VARCHAR(255),
ADD COLUMN IF NOT EXISTS circle_wallet_blockchain VARCHAR(50) DEFAULT 'MATIC-AMOY';

-- Create index for faster wallet lookups
CREATE INDEX IF NOT EXISTS idx_users_circle_wallet_id ON users(circle_wallet_id);
CREATE INDEX IF NOT EXISTS idx_users_circle_wallet_address ON users(circle_wallet_address);

-- Add comments
COMMENT ON COLUMN users.circle_wallet_id IS 'Circle developer-controlled wallet ID';
COMMENT ON COLUMN users.circle_wallet_address IS 'Blockchain address of Circle wallet';
COMMENT ON COLUMN users.circle_wallet_blockchain IS 'Blockchain network (e.g., MATIC-AMOY, ETH-SEPOLIA)';

-- Create circle_transactions table for tracking USDC transfers
CREATE TABLE IF NOT EXISTS circle_transactions (
  id SERIAL PRIMARY KEY,
  transfer_id VARCHAR(255) UNIQUE NOT NULL,
  from_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  to_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  amount DECIMAL(20, 6) NOT NULL CHECK (amount > 0),
  currency VARCHAR(10) DEFAULT 'USDC' NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
  booking_id INTEGER REFERENCES bookings(id) ON DELETE SET NULL,
  error_message TEXT,
  created_at TIMESTAMP DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);

-- Add indexes for common queries
CREATE INDEX IF NOT EXISTS idx_circle_tx_from_user ON circle_transactions(from_user_id);
CREATE INDEX IF NOT EXISTS idx_circle_tx_to_user ON circle_transactions(to_user_id);
CREATE INDEX IF NOT EXISTS idx_circle_tx_booking ON circle_transactions(booking_id);
CREATE INDEX IF NOT EXISTS idx_circle_tx_status ON circle_transactions(status);
CREATE INDEX IF NOT EXISTS idx_circle_tx_created ON circle_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_circle_tx_transfer_id ON circle_transactions(transfer_id);

-- Add comments
COMMENT ON TABLE circle_transactions IS 'Track all USDC transfers via Circle API';
COMMENT ON COLUMN circle_transactions.transfer_id IS 'Circle API transfer/transaction ID';
COMMENT ON COLUMN circle_transactions.from_user_id IS 'User sending USDC (NULL for platform)';
COMMENT ON COLUMN circle_transactions.to_user_id IS 'User receiving USDC (NULL for external)';
COMMENT ON COLUMN circle_transactions.amount IS 'Amount in USDC (6 decimals)';
COMMENT ON COLUMN circle_transactions.status IS 'Transfer status: PENDING, INITIATED, QUEUED, SENT, CONFIRMED, COMPLETE, FAILED, CANCELLED';
COMMENT ON COLUMN circle_transactions.booking_id IS 'Associated booking (if payment-related)';
COMMENT ON COLUMN circle_transactions.completed_at IS 'When transfer reached final state';

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_circle_transactions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_circle_transactions_updated_at ON circle_transactions;
CREATE TRIGGER trigger_circle_transactions_updated_at
  BEFORE UPDATE ON circle_transactions
  FOR EACH ROW
  EXECUTE FUNCTION update_circle_transactions_updated_at();

-- Create view for transaction history with user details
CREATE OR REPLACE VIEW circle_transaction_history AS
SELECT 
  ct.id,
  ct.transfer_id,
  ct.amount,
  ct.currency,
  ct.status,
  ct.booking_id,
  ct.created_at,
  ct.completed_at,
  fu.id AS from_user_id,
  fu.email AS from_user_email,
  fu.first_name AS from_user_first_name,
  fu.last_name AS from_user_last_name,
  tu.id AS to_user_id,
  tu.email AS to_user_email,
  tu.first_name AS to_user_first_name,
  tu.last_name AS to_user_last_name,
  EXTRACT(EPOCH FROM (ct.completed_at - ct.created_at)) AS duration_seconds
FROM circle_transactions ct
LEFT JOIN users fu ON ct.from_user_id = fu.id
LEFT JOIN users tu ON ct.to_user_id = tu.id
ORDER BY ct.created_at DESC;

COMMENT ON VIEW circle_transaction_history IS 'Transaction history with user details for reporting';

-- Grant permissions (adjust as needed for your setup)
GRANT SELECT, INSERT, UPDATE ON circle_transactions TO campuscuts_user;
GRANT USAGE, SELECT ON SEQUENCE circle_transactions_id_seq TO campuscuts_user;
GRANT SELECT ON circle_transaction_history TO campuscuts_user;

-- Migration complete
SELECT 'Migration 007: Circle Wallet Integration - Complete' AS status;

