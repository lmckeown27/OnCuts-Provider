-- CampusCuts Database Schema V2 - Production Custodial Wallet System
-- PostgreSQL 14+
-- Based on production-grade specification with escrow, batching, and reconciliation

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- for gen_random_uuid()

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- USERS (slightly modified from V1)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  role TEXT CHECK (role IN ('student','barber','admin')) NOT NULL,
  campus_id UUID,
  legacy_wallet_address TEXT UNIQUE,
  stripe_customer_id TEXT UNIQUE,     -- For deposits
  stripe_account_id TEXT UNIQUE,      -- For barber payouts (Stripe Connect)
  email_verified BOOLEAN DEFAULT false,
  student_id_verified BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  last_login TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_campus_id ON users(campus_id);

-- ============================================================================
-- CUSTODIAL WALLET TABLES
-- ============================================================================

-- BALANCES (internal ledger - separate from users for clarity)
CREATE TABLE balances (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id) UNIQUE NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  available_amount BIGINT DEFAULT 0 CHECK (available_amount >= 0), -- cents
  pending_amount BIGINT DEFAULT 0 CHECK (pending_amount >= 0),     -- cents
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_balances_user_id ON balances(user_id);

-- TRANSACTIONS (immutable ledger entries - replaces old ledger_entries)
CREATE TABLE transactions (
  id BIGSERIAL PRIMARY KEY,
  tx_ref TEXT UNIQUE NOT NULL, -- e.g., "TX-20251127-0001"
  user_id UUID REFERENCES users(id),
  type TEXT NOT NULL CHECK (type IN (
    'charge',              -- Consumer charged via Stripe
    'hold',                -- Funds held in escrow
    'release',             -- Escrow released to barber
    'payout',              -- Barber withdrawal to bank
    'refund',              -- Refund to consumer
    'fee',                 -- Platform fee collected
    'onchain_withdrawal',  -- Withdrawal to blockchain
    'tip',                 -- Tip payment
    'adjustment',          -- Admin adjustment
    'reversal'             -- Transaction reversal
  )),
  amount BIGINT NOT NULL,  -- cents (can be negative for debits)
  currency TEXT NOT NULL DEFAULT 'USD',
  status TEXT CHECK (status IN ('pending','completed','failed','reversed')) DEFAULT 'pending',
  related_booking_id UUID NULL,
  related_tx_id BIGINT NULL REFERENCES transactions(id), -- link to parent transaction
  stripe_payment_intent_id TEXT,
  stripe_payout_id TEXT,
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_transactions_user_id ON transactions(user_id);
CREATE INDEX idx_transactions_type ON transactions(type);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_booking_id ON transactions(related_booking_id);
CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);
CREATE UNIQUE INDEX idx_transactions_tx_ref ON transactions(tx_ref);

-- ESCROW_HOLDS (booking reservations - critical for payment flow)
CREATE TABLE escrow_holds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID UNIQUE NOT NULL,
  consumer_id UUID REFERENCES users(id) NOT NULL,
  barber_id UUID REFERENCES users(id) NOT NULL,
  amount BIGINT NOT NULL CHECK (amount > 0), -- cents
  currency TEXT NOT NULL DEFAULT 'USD',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL, -- Auto-refund after expiration
  onchain_tx_hash TEXT NULL,     -- If we anchor hold on-chain
  status TEXT CHECK (status IN ('held','released','refunded','expired')) DEFAULT 'held',
  released_at TIMESTAMP WITH TIME ZONE,
  refunded_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_escrow_booking_id ON escrow_holds(booking_id);
CREATE INDEX idx_escrow_consumer_id ON escrow_holds(consumer_id);
CREATE INDEX idx_escrow_barber_id ON escrow_holds(barber_id);
CREATE INDEX idx_escrow_status ON escrow_holds(status);
CREATE INDEX idx_escrow_expires_at ON escrow_holds(expires_at) WHERE status = 'held';

-- ONCHAIN_RECORDS (audit proofs - hash-based anchoring)
CREATE TABLE onchain_records (
  id BIGSERIAL PRIMARY KEY,
  record_type TEXT NOT NULL CHECK (record_type IN (
    'booking_hash',      -- Booking completion proof
    'payment_hash',      -- Payment proof
    'review_hash',       -- Review proof
    'withdrawal',        -- Withdrawal transaction
    'batch_anchor'       -- Batch of events (merkle root)
  )),
  subject_id UUID,       -- e.g., booking_id or user_id
  chain TEXT NOT NULL CHECK (chain IN ('aptos','solana','ethereum','base','arbitrum')),
  tx_hash TEXT NOT NULL,
  block_number BIGINT,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT now(),
  raw_receipt JSONB,     -- Full transaction receipt
  proof_data JSONB       -- Merkle proof or hash data
);

CREATE INDEX idx_onchain_type ON onchain_records(record_type);
CREATE INDEX idx_onchain_subject ON onchain_records(subject_id);
CREATE INDEX idx_onchain_chain ON onchain_records(chain);
CREATE INDEX idx_onchain_timestamp ON onchain_records(timestamp DESC);

-- PLATFORM_FEES (fee pool accounting)
CREATE TABLE platform_fees (
  id BIGSERIAL PRIMARY KEY,
  amount BIGINT NOT NULL CHECK (amount >= 0), -- cents
  currency TEXT NOT NULL DEFAULT 'USD',
  source_tx_id BIGINT REFERENCES transactions(id) NOT NULL,
  collected_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  withdrawn BOOLEAN DEFAULT false,
  withdrawal_tx_hash TEXT NULL,
  withdrawal_date TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_platform_fees_withdrawn ON platform_fees(withdrawn);
CREATE INDEX idx_platform_fees_collected_at ON platform_fees(collected_at DESC);

-- AUDIT_LOGS (immutable audit trail)
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  actor_user_id UUID REFERENCES users(id) NULL, -- NULL for system actions
  action TEXT NOT NULL,
  object_type TEXT,
  object_id TEXT,
  details JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_audit_actor ON audit_logs(actor_user_id);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_created_at ON audit_logs(created_at DESC);

-- ============================================================================
-- WITHDRAWAL BATCHING TABLES
-- ============================================================================

-- WITHDRAWAL_QUEUE (for batching on-chain withdrawals)
CREATE TABLE withdrawal_queue (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id) NOT NULL,
  transaction_id BIGINT REFERENCES transactions(id) UNIQUE NOT NULL,
  amount BIGINT NOT NULL CHECK (amount > 0), -- cents
  destination_type TEXT CHECK (destination_type IN ('bank','onchain')) NOT NULL,
  destination_address TEXT, -- blockchain address or bank account id
  chain TEXT CHECK (chain IN ('aptos','solana','ethereum','base')),
  status TEXT CHECK (status IN ('queued','batched','processing','completed','failed')) DEFAULT 'queued',
  batch_id UUID NULL,
  queued_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  processed_at TIMESTAMP WITH TIME ZONE,
  failure_reason TEXT
);

CREATE INDEX idx_withdrawal_queue_status ON withdrawal_queue(status);
CREATE INDEX idx_withdrawal_queue_queued_at ON withdrawal_queue(queued_at);
CREATE INDEX idx_withdrawal_queue_batch_id ON withdrawal_queue(batch_id);

-- WITHDRAWAL_BATCHES (groups of withdrawals processed together)
CREATE TABLE withdrawal_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chain TEXT NOT NULL,
  total_amount BIGINT NOT NULL,
  withdrawal_count INTEGER NOT NULL,
  tx_hash TEXT UNIQUE,
  status TEXT CHECK (status IN ('pending','submitted','confirmed','failed')) DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  submitted_at TIMESTAMP WITH TIME ZONE,
  confirmed_at TIMESTAMP WITH TIME ZONE,
  gas_used BIGINT,
  failure_reason TEXT
);

CREATE INDEX idx_withdrawal_batches_status ON withdrawal_batches(status);
CREATE INDEX idx_withdrawal_batches_chain ON withdrawal_batches(chain);

-- ============================================================================
-- RECONCILIATION TABLES
-- ============================================================================

-- RECONCILIATION_REPORTS (daily reconciliation results)
CREATE TABLE reconciliation_reports (
  id BIGSERIAL PRIMARY KEY,
  report_date DATE UNIQUE NOT NULL,
  report_type TEXT CHECK (report_type IN ('stripe','bank','onchain','full')) NOT NULL,
  status TEXT CHECK (status IN ('pending','completed','discrepancies','failed')) DEFAULT 'pending',
  total_platform_balance_cents BIGINT,
  total_user_balances_cents BIGINT,
  total_escrow_cents BIGINT,
  discrepancy_cents BIGINT,
  discrepancies JSONB, -- Array of discrepancy details
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_reconciliation_date ON reconciliation_reports(report_date DESC);
CREATE INDEX idx_reconciliation_status ON reconciliation_reports(status);

-- ============================================================================
-- SUPPORTING TABLES (from V1, kept for compatibility)
-- ============================================================================

-- CAMPUSES
CREATE TABLE campuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  domain TEXT UNIQUE NOT NULL,
  location GEOGRAPHY(POINT),
  address TEXT,
  city TEXT,
  state TEXT,
  country TEXT DEFAULT 'USA',
  timezone TEXT DEFAULT 'America/New_York',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_campuses_domain ON campuses(domain);

-- BOOKINGS (simplified - payment logic now in escrow_holds)
CREATE TABLE bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consumer_id UUID REFERENCES users(id) NOT NULL,
  barber_id UUID REFERENCES users(id) NOT NULL,
  service_id UUID,
  price_cents BIGINT NOT NULL,
  tip_cents BIGINT DEFAULT 0,
  requested_slot TIMESTAMP WITH TIME ZONE NOT NULL,
  status TEXT CHECK (status IN ('pending','confirmed','completed','cancelled','disputed')) DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE,
  cancelled_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_bookings_consumer ON bookings(consumer_id);
CREATE INDEX idx_bookings_barber ON bookings(barber_id);
CREATE INDEX idx_bookings_status ON bookings(status);

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Auto-update updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_balances_updated_at BEFORE UPDATE ON balances
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Generate sequential transaction references
CREATE SEQUENCE tx_ref_seq;

CREATE OR REPLACE FUNCTION generate_tx_ref()
RETURNS TEXT AS $$
DECLARE
  seq_val BIGINT;
  date_str TEXT;
BEGIN
  seq_val := nextval('tx_ref_seq');
  date_str := to_char(current_date, 'YYYYMMDD');
  RETURN 'TX-' || date_str || '-' || lpad(seq_val::TEXT, 6, '0');
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- Platform treasury view (scalar subqueries — valid without a dummy FROM row)
CREATE OR REPLACE VIEW platform_treasury AS
SELECT
  (SELECT COALESCE(SUM(available_amount + pending_amount), 0)::bigint FROM balances)
    AS total_user_balances_cents,
  (SELECT COALESCE(SUM(amount), 0)::bigint FROM escrow_holds WHERE status = 'held')
    AS total_escrow_cents,
  (SELECT COALESCE(SUM(amount), 0)::bigint FROM platform_fees WHERE NOT COALESCE(withdrawn, false))
    AS total_fees_cents;

-- User balance summary view
CREATE VIEW user_balance_summary AS
SELECT
  u.id,
  u.email,
  u.role,
  COALESCE(b.available_amount, 0) as available_cents,
  COALESCE(b.pending_amount, 0) as pending_cents,
  COALESCE(b.available_amount, 0) + COALESCE(b.pending_amount, 0) as total_balance_cents,
  (SELECT COUNT(*) FROM escrow_holds WHERE barber_id = u.id AND status = 'held') as active_escrows
FROM users u
LEFT JOIN balances b ON u.id = b.user_id;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE balances IS 'User balances in custodial wallet - amounts in cents';
COMMENT ON TABLE transactions IS 'Immutable transaction ledger - all balance changes';
COMMENT ON TABLE escrow_holds IS 'Booking payment holds - released on completion or refunded';
COMMENT ON TABLE onchain_records IS 'On-chain proof anchors - hash-based for gas efficiency';
COMMENT ON TABLE platform_fees IS 'Platform fee pool - 5% of completed bookings';
COMMENT ON TABLE withdrawal_queue IS 'Queued withdrawals for batching';
COMMENT ON TABLE withdrawal_batches IS 'Batched on-chain withdrawals for gas efficiency';
COMMENT ON TABLE reconciliation_reports IS 'Daily reconciliation results';

