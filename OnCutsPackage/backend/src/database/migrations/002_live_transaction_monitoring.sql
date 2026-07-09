-- Migration: Live Transaction Monitoring Tables
-- Purpose: Store Aptos blockchain and Stripe payment events for admin dashboard monitoring

-- =============================================
-- 1. APTOS BLOCKCHAIN TRANSACTIONS TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS aptos_transactions (
  id BIGSERIAL PRIMARY KEY,
  
  -- Transaction identifiers
  version TEXT NOT NULL,
  tx_hash TEXT UNIQUE NOT NULL,
  
  -- Transaction type and participants
  tx_type TEXT NOT NULL CHECK (tx_type IN ('deposit', 'withdrawal', 'batch_withdrawal', 'onchain_proof', 'unknown')),
  sender TEXT NOT NULL,
  recipient TEXT,
  
  -- Amounts
  amount_octas BIGINT,
  amount_usd DECIMAL(10, 2),
  
  -- Gas and status
  gas_used BIGINT NOT NULL,
  success BOOLEAN NOT NULL,
  
  -- Timing
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
  
  -- Description and metadata
  description TEXT,
  metadata JSONB DEFAULT '{}',
  
  -- Platform tracking
  platform_address TEXT NOT NULL,
  
  -- Raw data for debugging
  raw_data JSONB,
  
  -- Audit
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_aptos_tx_hash ON aptos_transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_aptos_platform_address ON aptos_transactions(platform_address);
CREATE INDEX IF NOT EXISTS idx_aptos_timestamp ON aptos_transactions(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_aptos_tx_type ON aptos_transactions(tx_type);
CREATE INDEX IF NOT EXISTS idx_aptos_sender ON aptos_transactions(sender);
CREATE INDEX IF NOT EXISTS idx_aptos_recipient ON aptos_transactions(recipient) WHERE recipient IS NOT NULL;

-- =============================================
-- 2. STRIPE PAYMENT EVENTS TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS stripe_events (
  id BIGSERIAL PRIMARY KEY,
  
  -- Event identifiers
  event_id TEXT UNIQUE NOT NULL,
  event_type TEXT NOT NULL,
  
  -- Payment identifiers
  payment_intent_id TEXT,
  customer_id TEXT,
  
  -- Amounts
  amount_cents BIGINT,
  amount_usd DECIMAL(10, 2),
  
  -- Status
  status TEXT NOT NULL,
  
  -- Timing
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
  
  -- Description and metadata
  description TEXT,
  metadata JSONB DEFAULT '{}',
  
  -- User tracking (for admin display)
  student_email TEXT,
  barber_email TEXT,
  booking_id TEXT,
  
  -- Raw data for debugging
  raw_data JSONB,
  
  -- Audit
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_stripe_event_id ON stripe_events(event_id);
CREATE INDEX IF NOT EXISTS idx_stripe_event_type ON stripe_events(event_type);
CREATE INDEX IF NOT EXISTS idx_stripe_payment_intent ON stripe_events(payment_intent_id) WHERE payment_intent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stripe_customer ON stripe_events(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stripe_timestamp ON stripe_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_stripe_booking_id ON stripe_events(booking_id) WHERE booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stripe_student_email ON stripe_events(student_email) WHERE student_email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stripe_barber_email ON stripe_events(barber_email) WHERE barber_email IS NOT NULL;

-- =============================================
-- 3. COMBINED TRANSACTION FEED VIEW
-- =============================================

-- This view combines both Aptos and Stripe transactions for unified admin dashboard
CREATE OR REPLACE VIEW admin_transaction_feed AS
  -- Aptos transactions
  SELECT 
    'aptos' AS platform,
    tx_hash AS transaction_id,
    tx_type AS transaction_type,
    sender AS from_address,
    recipient AS to_address,
    amount_usd,
    description,
    timestamp,
    success AS status_success,
    metadata
  FROM aptos_transactions
  
  UNION ALL
  
  -- Stripe events
  SELECT 
    'stripe' AS platform,
    event_id AS transaction_id,
    event_type AS transaction_type,
    student_email AS from_address,
    barber_email AS to_address,
    amount_usd,
    description,
    timestamp,
    (status IN ('succeeded', 'paid', 'created')) AS status_success,
    metadata
  FROM stripe_events
  
  ORDER BY timestamp DESC;

-- =============================================
-- 4. STATS HELPER VIEWS
-- =============================================

-- Daily transaction stats
CREATE OR REPLACE VIEW daily_transaction_stats AS
SELECT 
  DATE(timestamp) AS date,
  platform,
  COUNT(*) AS transaction_count,
  SUM(amount_usd) AS total_volume_usd
FROM admin_transaction_feed
WHERE timestamp >= NOW() - INTERVAL '30 days'
GROUP BY DATE(timestamp), platform
ORDER BY date DESC, platform;

-- Real-time platform stats (last 24 hours)
CREATE OR REPLACE VIEW realtime_platform_stats AS
SELECT 
  platform,
  COUNT(*) AS transaction_count,
  SUM(amount_usd) FILTER (WHERE status_success = true) AS successful_volume_usd,
  COUNT(*) FILTER (WHERE status_success = true) AS successful_count,
  COUNT(*) FILTER (WHERE status_success = false) AS failed_count
FROM admin_transaction_feed
WHERE timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY platform;

-- =============================================
-- COMMENTS
-- =============================================

COMMENT ON TABLE aptos_transactions IS 'Stores all Aptos blockchain transactions for the platform wallet';
COMMENT ON TABLE stripe_events IS 'Stores all Stripe webhook events for payment monitoring';
COMMENT ON VIEW admin_transaction_feed IS 'Unified view of all platform transactions (Aptos + Stripe) for admin dashboard';
COMMENT ON VIEW daily_transaction_stats IS 'Daily aggregated transaction statistics';
COMMENT ON VIEW realtime_platform_stats IS 'Real-time platform statistics (last 24 hours)';

