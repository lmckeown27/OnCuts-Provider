-- Migration: Gas Wallet Management System
-- Purpose: Track platform gas wallets, top-up requests, and audit trail for Aptos gas funding

-- =============================================
-- 1. GAS WALLETS TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS gas_wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Wallet identification
  address TEXT UNIQUE NOT NULL,
  descriptive_name TEXT NOT NULL,
  campus_id UUID REFERENCES campuses(id) ON DELETE SET NULL,
  
  -- Cached balance for quick lookups
  current_balance_apt DECIMAL(20, 8) DEFAULT 0,
  last_checked_at TIMESTAMP WITH TIME ZONE,
  
  -- Configuration
  is_active BOOLEAN DEFAULT true,
  min_balance_threshold_apt DECIMAL(20, 8) DEFAULT 0.5,
  top_up_threshold_apt DECIMAL(20, 8) DEFAULT 0.1,
  safety_buffer_percentage DECIMAL(5, 2) DEFAULT 20.00,
  
  -- Audit
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE gas_wallets IS 'Platform Aptos gas wallets for funding on-chain transactions';
COMMENT ON COLUMN gas_wallets.current_balance_apt IS 'Cached balance in APT, updated by balance checker service';
COMMENT ON COLUMN gas_wallets.min_balance_threshold_apt IS 'Alert when balance falls below this';
COMMENT ON COLUMN gas_wallets.top_up_threshold_apt IS 'Auto-create top-up request when needed amount exceeds this';
COMMENT ON COLUMN gas_wallets.safety_buffer_percentage IS 'Add % buffer to gas estimates (e.g., 20 = 20%)';

-- =============================================
-- 2. GAS TOP-UP REQUESTS TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS gas_top_up_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Request details
  gas_wallet_id UUID REFERENCES gas_wallets(id) ON DELETE CASCADE NOT NULL,
  gas_wallet_address TEXT NOT NULL,
  requested_amount_apt DECIMAL(20, 8) NOT NULL,
  requested_amount_octas BIGINT NOT NULL, -- Amount in smallest Aptos unit
  
  -- Status tracking
  status TEXT CHECK (status IN ('pending', 'approved', 'completed', 'failed', 'cancelled')) NOT NULL DEFAULT 'pending',
  
  -- Admin action tracking
  admin_address_requested_from TEXT, -- Wallet address of admin who approved
  admin_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  approved_tx_hash TEXT, -- Transaction hash from admin wallet transfer
  
  -- Verification
  verified_amount_octas BIGINT, -- Actual amount received (verified on-chain)
  verification_status TEXT CHECK (verification_status IN ('pending', 'verified', 'amount_mismatch', 'tx_not_found', 'timeout')),
  verified_at TIMESTAMP WITH TIME ZONE,
  
  -- Metadata
  reason TEXT, -- Human-readable reason for top-up
  estimated_coverage_days DECIMAL(5, 2), -- How many days this top-up should cover
  idempotency_key TEXT UNIQUE, -- For idempotent requests
  
  -- Audit trail
  audit_metadata JSONB DEFAULT '{}',
  error_message TEXT,
  
  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  approved_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  failed_at TIMESTAMP WITH TIME ZONE,
  cancelled_at TIMESTAMP WITH TIME ZONE
);

COMMENT ON TABLE gas_top_up_requests IS 'Requests for admin to top up gas wallet with APT';
COMMENT ON COLUMN gas_top_up_requests.requested_amount_octas IS '1 APT = 100,000,000 octas';
COMMENT ON COLUMN gas_top_up_requests.idempotency_key IS 'Prevents duplicate requests from client retry';
COMMENT ON COLUMN gas_top_up_requests.verification_status IS 'On-chain verification result';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_gas_top_up_requests_status ON gas_top_up_requests(status);
CREATE INDEX IF NOT EXISTS idx_gas_top_up_requests_gas_wallet ON gas_top_up_requests(gas_wallet_id);
CREATE INDEX IF NOT EXISTS idx_gas_top_up_requests_idempotency ON gas_top_up_requests(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gas_top_up_requests_created_at ON gas_top_up_requests(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gas_top_up_requests_tx_hash ON gas_top_up_requests(approved_tx_hash) WHERE approved_tx_hash IS NOT NULL;

-- =============================================
-- 3. GAS WALLET AUDIT LOGS TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS gas_wallet_audit_logs (
  id BIGSERIAL PRIMARY KEY,
  
  -- Reference
  gas_wallet_id UUID REFERENCES gas_wallets(id) ON DELETE CASCADE NOT NULL,
  top_up_request_id UUID REFERENCES gas_top_up_requests(id) ON DELETE SET NULL,
  
  -- Event details
  event_type TEXT NOT NULL,
  -- Event types: 'balance_checked', 'top_up_requested', 'top_up_approved', 
  --              'top_up_completed', 'top_up_failed', 'manual_adjustment', 'alert_sent'
  
  -- Actor
  actor_type TEXT CHECK (actor_type IN ('system', 'admin', 'cron')),
  actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_wallet_address TEXT,
  
  -- Data
  data JSONB NOT NULL DEFAULT '{}',
  
  -- Timestamp
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE gas_wallet_audit_logs IS 'Immutable audit trail for all gas wallet events';
COMMENT ON COLUMN gas_wallet_audit_logs.event_type IS 'Type of event that occurred';
COMMENT ON COLUMN gas_wallet_audit_logs.actor_type IS 'Who or what triggered this event';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_gas_wallet_audit_logs_wallet ON gas_wallet_audit_logs(gas_wallet_id);
CREATE INDEX IF NOT EXISTS idx_gas_wallet_audit_logs_request ON gas_wallet_audit_logs(top_up_request_id) WHERE top_up_request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gas_wallet_audit_logs_event_type ON gas_wallet_audit_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_gas_wallet_audit_logs_created_at ON gas_wallet_audit_logs(created_at DESC);

-- =============================================
-- 4. GAS ESTIMATION CONFIG TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS gas_estimation_config (
  id SERIAL PRIMARY KEY,
  
  -- Estimation parameters
  default_avg_gas_apt_per_write DECIMAL(10, 8) NOT NULL DEFAULT 0.0003,
  estimation_horizon_hours INT NOT NULL DEFAULT 24,
  safety_buffer_percentage DECIMAL(5, 2) NOT NULL DEFAULT 20.00,
  
  -- Alert thresholds
  min_balance_alert_threshold_apt DECIMAL(20, 8) DEFAULT 0.5,
  critical_balance_threshold_apt DECIMAL(20, 8) DEFAULT 0.1,
  
  -- Top-up triggers
  auto_create_topup_threshold_apt DECIMAL(20, 8) DEFAULT 0.1,
  
  -- Verification settings
  tx_verification_timeout_minutes INT DEFAULT 10,
  min_confirmations INT DEFAULT 1,
  
  -- Active config (only one row should have is_active=true)
  is_active BOOLEAN DEFAULT true,
  
  -- Audit
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT only_one_active_config UNIQUE (is_active) WHERE is_active = true
);

COMMENT ON TABLE gas_estimation_config IS 'Configuration for gas estimation and top-up automation';

-- Insert default config
INSERT INTO gas_estimation_config (
  default_avg_gas_apt_per_write,
  estimation_horizon_hours,
  safety_buffer_percentage,
  min_balance_alert_threshold_apt,
  critical_balance_threshold_apt,
  auto_create_topup_threshold_apt,
  tx_verification_timeout_minutes,
  min_confirmations,
  is_active
) VALUES (
  0.0003,  -- ~0.03 cents per write at $10/APT
  24,      -- 24 hour lookahead
  20.00,   -- 20% safety buffer
  0.5,     -- Alert at 0.5 APT
  0.1,     -- Critical at 0.1 APT
  0.1,     -- Auto-create top-up when need > 0.1 APT
  10,      -- 10 minute verification timeout
  1,       -- Wait for 1 confirmation
  true     -- Active config
) ON CONFLICT DO NOTHING;

-- =============================================
-- 5. HELPER FUNCTIONS
-- =============================================

-- Function to update gas wallet balance
CREATE OR REPLACE FUNCTION update_gas_wallet_balance()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE gas_wallets
  SET updated_at = NOW()
  WHERE id = NEW.gas_wallet_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on gas_wallet_audit_logs to update parent
CREATE TRIGGER update_gas_wallet_on_audit_log
  AFTER INSERT ON gas_wallet_audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION update_gas_wallet_balance();

-- Function to update top-up request timestamp
CREATE OR REPLACE FUNCTION update_top_up_request_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  
  -- Auto-set completion timestamps based on status
  IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
    NEW.approved_at = NOW();
  ELSIF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    NEW.completed_at = NOW();
  ELSIF NEW.status = 'failed' AND OLD.status != 'failed' THEN
    NEW.failed_at = NOW();
  ELSIF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    NEW.cancelled_at = NOW();
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on gas_top_up_requests
CREATE TRIGGER update_top_up_request_on_update
  BEFORE UPDATE ON gas_top_up_requests
  FOR EACH ROW
  EXECUTE FUNCTION update_top_up_request_timestamp();

-- =============================================
-- 6. VIEWS FOR REPORTING
-- =============================================

-- View: Pending top-up requests
CREATE OR REPLACE VIEW pending_gas_top_ups AS
SELECT 
  r.id,
  r.gas_wallet_address,
  r.requested_amount_apt,
  r.status,
  r.reason,
  r.estimated_coverage_days,
  r.created_at,
  w.descriptive_name as wallet_name,
  w.current_balance_apt as current_balance,
  u.email as admin_email
FROM gas_top_up_requests r
JOIN gas_wallets w ON r.gas_wallet_id = w.id
LEFT JOIN users u ON r.admin_user_id = u.id
WHERE r.status IN ('pending', 'approved')
ORDER BY r.created_at DESC;

-- View: Gas wallet health summary
CREATE OR REPLACE VIEW gas_wallet_health AS
SELECT 
  w.id,
  w.address,
  w.descriptive_name,
  w.current_balance_apt,
  w.min_balance_threshold_apt,
  w.last_checked_at,
  CASE 
    WHEN w.current_balance_apt < w.min_balance_threshold_apt THEN 'critical'
    WHEN w.current_balance_apt < (w.min_balance_threshold_apt * 2) THEN 'low'
    ELSE 'healthy'
  END as health_status,
  (SELECT COUNT(*) FROM gas_top_up_requests r WHERE r.gas_wallet_id = w.id AND r.status = 'pending') as pending_top_ups,
  (SELECT SUM(requested_amount_apt) FROM gas_top_up_requests r WHERE r.gas_wallet_id = w.id AND r.status = 'completed') as total_topped_up_apt
FROM gas_wallets w
WHERE w.is_active = true;

-- View: Top-up request history with details
CREATE OR REPLACE VIEW top_up_request_history AS
SELECT 
  r.id,
  r.gas_wallet_address,
  r.requested_amount_apt,
  r.verified_amount_octas / 100000000.0 as verified_amount_apt,
  r.status,
  r.verification_status,
  r.approved_tx_hash,
  r.admin_address_requested_from,
  r.reason,
  r.created_at,
  r.completed_at,
  r.failed_at,
  EXTRACT(EPOCH FROM (r.completed_at - r.created_at)) / 60 as completion_time_minutes,
  w.descriptive_name as wallet_name,
  u.email as admin_email
FROM gas_top_up_requests r
JOIN gas_wallets w ON r.gas_wallet_id = w.id
LEFT JOIN users u ON r.admin_user_id = u.id
ORDER BY r.created_at DESC;

-- =============================================
-- SEED DATA
-- =============================================

-- Insert default platform gas wallet (if not exists)
INSERT INTO gas_wallets (
  address,
  descriptive_name,
  current_balance_apt,
  min_balance_threshold_apt,
  top_up_threshold_apt,
  safety_buffer_percentage,
  is_active
)
SELECT 
  '0x50c7bf0be7f5a56f8312ae8a49ec638d0d7b2bc68e061b867ed86d2af82a21aa',
  'Platform Main Gas Wallet (Devnet)',
  0.0,
  0.5,
  0.1,
  20.00,
  true
WHERE NOT EXISTS (
  SELECT 1 FROM gas_wallets 
  WHERE address = '0x50c7bf0be7f5a56f8312ae8a49ec638d0d7b2bc68e061b867ed86d2af82a21aa'
);

-- =============================================
-- GRANTS (adjust as needed for your user)
-- =============================================

-- Example: GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO campuscuts_app;
-- Example: GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO campuscuts_app;

