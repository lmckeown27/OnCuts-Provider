-- MoonPay sell/off-ramp: track in-app bank cash-out after treasury tops up barber wallet (gross-up for fees).

CREATE TABLE IF NOT EXISTS moonpay_offramp_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  transaction_id BIGINT REFERENCES transactions(id) ON DELETE SET NULL,
  net_amount_cents INTEGER NOT NULL CHECK (net_amount_cents > 0),
  gross_usdc_base_units NUMERIC(30, 0) NOT NULL CHECK (gross_usdc_base_units > 0),
  sui_wallet_address TEXT NOT NULL,
  external_customer_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'funded'
    CHECK (status IN ('pending_funding', 'funded', 'moonpay_completed', 'failed')),
  sui_fund_digest TEXT,
  moonpay_transaction_id TEXT,
  moonpay_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_moonpay_offramp_user_id ON moonpay_offramp_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_moonpay_offramp_status ON moonpay_offramp_sessions(status);
CREATE INDEX IF NOT EXISTS idx_moonpay_offramp_external_customer ON moonpay_offramp_sessions(external_customer_id);

COMMENT ON TABLE moonpay_offramp_sessions IS 'Barber MoonPay off-ramp: net ledger debit, gross USDC sent on Sui for fee buffer';
