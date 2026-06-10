-- Persist Sui transaction digest per Stripe payment (explorer + idempotency).
-- The app uses the unified `payments` row created on checkout.session.completed.

ALTER TABLE payments ADD COLUMN IF NOT EXISTS path_b_sui_tx_digest VARCHAR(128);

CREATE INDEX IF NOT EXISTS idx_payments_path_b_sui_tx_digest
  ON payments (path_b_sui_tx_digest)
  WHERE path_b_sui_tx_digest IS NOT NULL;

COMMENT ON COLUMN payments.path_b_sui_tx_digest IS 'Sui tx digest after USDC settlement (Stripe → on-chain)';
