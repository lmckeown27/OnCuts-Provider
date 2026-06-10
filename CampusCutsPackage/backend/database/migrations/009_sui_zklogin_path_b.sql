-- Sui + zkLogin + Stripe Checkout + Bridge
-- Adds optional Sui identity columns and checkout / settlement tracking.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS sui_address VARCHAR(66) UNIQUE,
  ADD COLUMN IF NOT EXISTS zk_login_salt TEXT;

CREATE INDEX IF NOT EXISTS idx_users_sui_address ON users(sui_address);

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS stripe_checkout_session_id VARCHAR(255),
  ADD COLUMN IF NOT EXISTS bridge_payout_id VARCHAR(255),
  ADD COLUMN IF NOT EXISTS on_chain_settlement_status VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_bookings_stripe_checkout_session_id ON bookings(stripe_checkout_session_id);

COMMENT ON COLUMN users.sui_address IS 'Sui address from zkLogin (barber/consumer)';
COMMENT ON COLUMN users.zk_login_salt IS 'Opaque salt material for zkLogin address derivation (server-side)';
COMMENT ON COLUMN bookings.bridge_payout_id IS 'Bridge API payout id after USDC delivery to Sui';
