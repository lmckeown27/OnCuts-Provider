-- ============================================================================
-- CAMPUSCUTS DYNAMIC PRICING ENGINE - DATABASE SCHEMA
-- ============================================================================
-- 
-- This schema supports market-aware dynamic pricing that combines:
-- - Individual barber performance scores (quality, reliability, demand)
-- - Market size normalization (MSI)
-- - Supply/demand adjustments (MDI)
-- 
-- Version: 1.0
-- Date: 2024-11-28
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PRICING CONFIGURATION (Singleton)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pricing_config (
    id SERIAL PRIMARY KEY,
    version INT NOT NULL DEFAULT 1,
    
    -- Score weights
    quality_weight DECIMAL(3,2) NOT NULL DEFAULT 0.70,
    reliability_weight DECIMAL(3,2) NOT NULL DEFAULT 0.20,
    demand_weight DECIMAL(3,2) NOT NULL DEFAULT 0.10,
    
    -- Quality sub-weights
    rating_weight DECIMAL(3,2) NOT NULL DEFAULT 0.80,
    repeat_rate_weight DECIMAL(3,2) NOT NULL DEFAULT 0.20,
    
    -- Reliability sub-weights
    on_time_weight DECIMAL(3,2) NOT NULL DEFAULT 0.70,
    no_show_weight DECIMAL(3,2) NOT NULL DEFAULT 0.30,
    
    -- Price multiplier bounds
    min_price_multiplier DECIMAL(4,2) NOT NULL DEFAULT 0.80,
    max_price_multiplier DECIMAL(4,2) NOT NULL DEFAULT 1.50,
    
    -- Market adjustments
    msi_influence DECIMAL(3,2) NOT NULL DEFAULT 0.30, -- How much MSI affects effective score
    mdi_min_adjustment DECIMAL(3,2) NOT NULL DEFAULT 0.90,
    mdi_max_adjustment DECIMAL(3,2) NOT NULL DEFAULT 1.10,
    
    -- Smoothing parameters
    msi_ema_alpha DECIMAL(3,2) NOT NULL DEFAULT 0.20,
    mdi_ema_alpha DECIMAL(3,2) NOT NULL DEFAULT 0.20,
    
    -- New barber policy
    new_barber_booking_threshold INT NOT NULL DEFAULT 5,
    new_barber_quality_boost DECIMAL(3,2) NOT NULL DEFAULT 0.20,
    
    -- Price shock protection
    max_daily_price_change_pct DECIMAL(4,2) NOT NULL DEFAULT 30.00,
    min_price_change_threshold_pct DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    
    -- Update frequency
    recompute_frequency_hours INT NOT NULL DEFAULT 24,
    
    -- Metadata
    updated_by VARCHAR(255),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT weights_sum_one CHECK (
        quality_weight + reliability_weight + demand_weight = 1.00
    ),
    CONSTRAINT quality_subweights_sum_one CHECK (
        rating_weight + repeat_rate_weight = 1.00
    )
);

-- Insert default configuration
INSERT INTO pricing_config (version) VALUES (1);

-- Audit log for config changes
CREATE TABLE IF NOT EXISTS pricing_config_audit (
    id SERIAL PRIMARY KEY,
    config_id INT NOT NULL REFERENCES pricing_config(id),
    version INT NOT NULL,
    changes JSONB NOT NULL,
    changed_by VARCHAR(255) NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- 2. CAMPUS MARKET METRICS
-- ----------------------------------------------------------------------------
-- Extend existing campuses table with pricing metrics
ALTER TABLE campuses ADD COLUMN IF NOT EXISTS student_count INT DEFAULT 0;
ALTER TABLE campuses ADD COLUMN IF NOT EXISTS region VARCHAR(100);

CREATE TABLE IF NOT EXISTS campus_market_metrics (
    id SERIAL PRIMARY KEY,
    campus_id INT NOT NULL REFERENCES campuses(id) ON DELETE CASCADE,
    
    -- Market Size Index (0-1, normalized)
    msi DECIMAL(5,4) NOT NULL DEFAULT 0.5000,
    msi_raw DECIMAL(10,2), -- Raw calculation before smoothing
    
    -- Market Demand Index (0-1, normalized)
    mdi DECIMAL(5,4) NOT NULL DEFAULT 0.5000,
    mdi_raw DECIMAL(10,2), -- Raw calculation before smoothing
    
    -- Base price multiplier for this campus
    base_price_multiplier DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    
    -- Supporting metrics
    active_barbers_count INT NOT NULL DEFAULT 0,
    total_bookings_30d INT NOT NULL DEFAULT 0,
    avg_bookings_per_barber DECIMAL(8,2) DEFAULT 0,
    
    -- Historical bounds for normalization
    historical_min_demand DECIMAL(10,2) DEFAULT 0,
    historical_max_demand DECIMAL(10,2) DEFAULT 100,
    
    -- Computed period
    computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(campus_id, period_start)
);

CREATE INDEX idx_campus_market_metrics_campus ON campus_market_metrics(campus_id);
CREATE INDEX idx_campus_market_metrics_period ON campus_market_metrics(period_start, period_end);

-- ----------------------------------------------------------------------------
-- 3. SERVICES & PRICING
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS services (
    id SERIAL PRIMARY KEY,
    slug VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    
    -- Base price in cents (default across all markets)
    default_base_price_cents INT NOT NULL,
    
    -- Computed price bounds (can be overridden per market)
    default_min_price_cents INT NOT NULL,
    default_max_price_cents INT NOT NULL,
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT price_bounds_valid CHECK (
        default_min_price_cents <= default_base_price_cents 
        AND default_base_price_cents <= default_max_price_cents
    )
);

-- Seed default services
INSERT INTO services (slug, name, default_base_price_cents, default_min_price_cents, default_max_price_cents) VALUES
('haircut', 'Haircut', 2500, 2000, 3750),
('haircut_fade', 'Haircut & Fade', 3500, 2800, 5250),
('beard_trim', 'Beard Trim', 1500, 1200, 2250),
('full_service', 'Full Service (Cut + Fade + Beard)', 5000, 4000, 7500)
ON CONFLICT (slug) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 4. BARBER METRICS (Aggregated Raw Data)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS barber_metrics (
    id SERIAL PRIMARY KEY,
    barber_id VARCHAR(255) NOT NULL,
    
    -- Time window for aggregation
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    period_date DATE NOT NULL, -- Simpler period identifier (YYYY-MM-DD)
    
    -- Raw aggregated metrics
    num_bookings INT NOT NULL DEFAULT 0,
    num_completed_bookings INT NOT NULL DEFAULT 0,
    num_canceled_bookings INT NOT NULL DEFAULT 0,
    num_no_shows INT NOT NULL DEFAULT 0,
    
    -- Quality metrics
    avg_rating DECIMAL(3,2), -- 1.00 to 5.00
    total_ratings INT DEFAULT 0,
    
    -- Repeat customer metrics
    num_repeat_customers INT DEFAULT 0,
    num_unique_customers INT DEFAULT 0,
    repeat_rate DECIMAL(5,4) DEFAULT 0, -- 0-1
    
    -- Reliability metrics
    num_on_time INT DEFAULT 0,
    on_time_pct DECIMAL(5,4) DEFAULT 0, -- 0-1
    no_show_pct DECIMAL(5,4) DEFAULT 0, -- 0-1
    canceled_pct DECIMAL(5,4) DEFAULT 0, -- 0-1
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(barber_id, period_date)
);

CREATE INDEX idx_barber_metrics_barber ON barber_metrics(barber_id);
CREATE INDEX idx_barber_metrics_period ON barber_metrics(period_date);

-- ----------------------------------------------------------------------------
-- 5. BARBER SCORES (Computed Performance Scores)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS barber_scores (
    id SERIAL PRIMARY KEY,
    barber_id VARCHAR(255) NOT NULL,
    period_date DATE NOT NULL,
    
    -- Individual component scores (0-100)
    quality_score DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    reliability_score DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    demand_score DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    
    -- Weighted performance score (0-100)
    performance_score DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    
    -- Market-adjusted score
    effective_score DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    
    -- Supporting data
    campus_id INT,
    msi DECIMAL(5,4), -- MSI at time of computation
    mdi DECIMAL(5,4), -- MDI at time of computation
    is_new_barber BOOLEAN DEFAULT false,
    total_lifetime_bookings INT DEFAULT 0,
    
    -- Score breakdown for transparency
    breakdown JSONB,
    
    -- Metadata
    computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(barber_id, period_date),
    
    CONSTRAINT scores_range CHECK (
        quality_score >= 0 AND quality_score <= 100
        AND reliability_score >= 0 AND reliability_score <= 100
        AND demand_score >= 0 AND demand_score <= 100
        AND performance_score >= 0 AND performance_score <= 100
        AND effective_score >= 0 AND effective_score <= 100
    )
);

CREATE INDEX idx_barber_scores_barber ON barber_scores(barber_id);
CREATE INDEX idx_barber_scores_period ON barber_scores(period_date);
CREATE INDEX idx_barber_scores_campus ON barber_scores(campus_id);

-- ----------------------------------------------------------------------------
-- 6. BARBER PRICES (Final Computed Prices)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS barber_prices (
    id SERIAL PRIMARY KEY,
    barber_id VARCHAR(255) NOT NULL,
    service_id INT NOT NULL REFERENCES services(id),
    period_date DATE NOT NULL,
    
    -- Price components (all in cents)
    base_price_cents INT NOT NULL,
    min_price_cents INT NOT NULL,
    max_price_cents INT NOT NULL,
    final_price_cents INT NOT NULL,
    
    -- Previous price for change tracking
    previous_price_cents INT,
    price_change_pct DECIMAL(6,2),
    
    -- Price was capped due to shock protection
    is_shock_capped BOOLEAN DEFAULT false,
    
    -- Detailed breakdown for UI transparency
    breakdown JSONB NOT NULL,
    -- Example breakdown structure:
    -- {
    --   "performanceScore": 85.5,
    --   "effectiveScore": 87.2,
    --   "msi": 0.75,
    --   "mdi": 0.60,
    --   "basePrice": 2500,
    --   "priceMultiplier": 1.41,
    --   "marketAdjustment": 1.02,
    --   "computedPrice": 3600,
    --   "finalPrice": 3600,
    --   "minPrice": 2000,
    --   "maxPrice": 3750,
    --   "cappedReason": null
    -- }
    
    -- Metadata
    computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(barber_id, service_id, period_date),
    
    CONSTRAINT price_in_bounds CHECK (
        final_price_cents >= min_price_cents 
        AND final_price_cents <= max_price_cents
    )
);

CREATE INDEX idx_barber_prices_barber ON barber_prices(barber_id);
CREATE INDEX idx_barber_prices_service ON barber_prices(service_id);
CREATE INDEX idx_barber_prices_period ON barber_prices(period_date);
CREATE INDEX idx_barber_prices_shock ON barber_prices(is_shock_capped);

-- ----------------------------------------------------------------------------
-- 7. PRICE RECOMPUTE LOG (Job Tracking)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS price_recompute_log (
    id SERIAL PRIMARY KEY,
    
    -- Job metadata
    job_type VARCHAR(50) NOT NULL, -- 'scheduled', 'manual', 'on-demand'
    trigger_source VARCHAR(100), -- 'cron', 'admin-ui', 'api', etc.
    triggered_by VARCHAR(255), -- User ID or 'system'
    
    -- Scope
    campus_ids INT[],
    barber_ids VARCHAR(255)[],
    is_full_recompute BOOLEAN DEFAULT false,
    
    -- Results
    status VARCHAR(50) NOT NULL, -- 'running', 'completed', 'failed', 'partial'
    barbers_processed INT DEFAULT 0,
    prices_updated INT DEFAULT 0,
    errors_count INT DEFAULT 0,
    
    -- Performance
    duration_ms INT,
    
    -- Details
    summary JSONB,
    error_details TEXT,
    
    -- Timestamps
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_price_recompute_log_status ON price_recompute_log(status);
CREATE INDEX idx_price_recompute_log_started ON price_recompute_log(started_at);

-- ----------------------------------------------------------------------------
-- 8. PRICE ANOMALIES (Monitoring & Alerts)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS price_anomalies (
    id SERIAL PRIMARY KEY,
    barber_id VARCHAR(255) NOT NULL,
    service_id INT NOT NULL REFERENCES services(id),
    period_date DATE NOT NULL,
    
    -- Anomaly type
    anomaly_type VARCHAR(100) NOT NULL, 
    -- Types: 'large_increase', 'large_decrease', 'shock_cap_hit', 
    --        'score_spike', 'low_data_quality'
    
    severity VARCHAR(20) NOT NULL, -- 'low', 'medium', 'high', 'critical'
    
    -- Details
    old_price_cents INT,
    new_price_cents INT,
    price_change_pct DECIMAL(6,2),
    
    description TEXT NOT NULL,
    context JSONB,
    
    -- Resolution
    status VARCHAR(50) DEFAULT 'open', -- 'open', 'reviewed', 'resolved', 'ignored'
    reviewed_by VARCHAR(255),
    reviewed_at TIMESTAMP,
    resolution_notes TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_price_anomalies_barber ON price_anomalies(barber_id);
CREATE INDEX idx_price_anomalies_status ON price_anomalies(status);
CREATE INDEX idx_price_anomalies_severity ON price_anomalies(severity);
CREATE INDEX idx_price_anomalies_created ON price_anomalies(created_at);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to get current pricing config
CREATE OR REPLACE FUNCTION get_current_pricing_config()
RETURNS pricing_config AS $$
BEGIN
    RETURN (SELECT * FROM pricing_config ORDER BY version DESC LIMIT 1);
END;
$$ LANGUAGE plpgsql;

-- Function to get barber's latest price for a service
CREATE OR REPLACE FUNCTION get_barber_current_price(
    p_barber_id VARCHAR(255),
    p_service_id INT
)
RETURNS INT AS $$
BEGIN
    RETURN (
        SELECT final_price_cents 
        FROM barber_prices 
        WHERE barber_id = p_barber_id 
        AND service_id = p_service_id 
        ORDER BY period_date DESC 
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql;

-- Function to check if barber is "new" (below threshold)
CREATE OR REPLACE FUNCTION is_new_barber(
    p_barber_id VARCHAR(255)
)
RETURNS BOOLEAN AS $$
DECLARE
    v_threshold INT;
    v_booking_count INT;
BEGIN
    -- Get threshold from config
    SELECT new_barber_booking_threshold INTO v_threshold 
    FROM pricing_config 
    ORDER BY version DESC 
    LIMIT 1;
    
    -- Count completed bookings
    SELECT COUNT(*) INTO v_booking_count
    FROM bookings
    WHERE barber_id = p_barber_id
    AND status = 'completed';
    
    RETURN v_booking_count < v_threshold;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS FOR REPORTING
-- ============================================================================

-- View: Latest barber scores with prices
CREATE OR REPLACE VIEW v_barber_pricing_current AS
SELECT 
    b.id as barber_id,
    b.user_id,
    b.campus_id,
    c.name as campus_name,
    bs.period_date,
    bs.performance_score,
    bs.effective_score,
    bs.quality_score,
    bs.reliability_score,
    bs.demand_score,
    bs.is_new_barber,
    bs.total_lifetime_bookings,
    json_agg(
        json_build_object(
            'service_id', bp.service_id,
            'service_name', s.name,
            'final_price_cents', bp.final_price_cents,
            'final_price_usd', bp.final_price_cents / 100.0,
            'base_price_cents', bp.base_price_cents,
            'price_change_pct', bp.price_change_pct,
            'is_shock_capped', bp.is_shock_capped
        )
    ) as prices
FROM barbers b
LEFT JOIN campuses c ON b.campus_id = c.id
LEFT JOIN LATERAL (
    SELECT * FROM barber_scores 
    WHERE barber_id = b.id 
    ORDER BY period_date DESC 
    LIMIT 1
) bs ON true
LEFT JOIN LATERAL (
    SELECT * FROM barber_prices 
    WHERE barber_id = b.id 
    ORDER BY period_date DESC
) bp ON true
LEFT JOIN services s ON bp.service_id = s.id
WHERE b.is_active = true
GROUP BY b.id, b.user_id, b.campus_id, c.name, bs.period_date, bs.performance_score, 
         bs.effective_score, bs.quality_score, bs.reliability_score, bs.demand_score, 
         bs.is_new_barber, bs.total_lifetime_bookings;

-- View: Campus market health
CREATE OR REPLACE VIEW v_campus_market_health AS
SELECT 
    c.id as campus_id,
    c.name as campus_name,
    c.city,
    c.state,
    cmm.msi,
    cmm.mdi,
    cmm.base_price_multiplier,
    cmm.active_barbers_count,
    cmm.total_bookings_30d,
    cmm.avg_bookings_per_barber,
    cmm.period_start,
    cmm.period_end,
    COUNT(DISTINCT b.id) FILTER (WHERE b.is_active = true) as active_barbers,
    AVG(bs.performance_score) as avg_performance_score,
    MIN(bs.performance_score) as min_performance_score,
    MAX(bs.performance_score) as max_performance_score
FROM campuses c
LEFT JOIN campus_market_metrics cmm ON c.id = cmm.campus_id 
    AND cmm.period_start = (
        SELECT MAX(period_start) 
        FROM campus_market_metrics 
        WHERE campus_id = c.id
    )
LEFT JOIN barbers b ON c.id = b.campus_id
LEFT JOIN LATERAL (
    SELECT * FROM barber_scores 
    WHERE barber_id = b.id 
    ORDER BY period_date DESC 
    LIMIT 1
) bs ON true
WHERE c.is_active = true
GROUP BY c.id, c.name, c.city, c.state, cmm.msi, cmm.mdi, cmm.base_price_multiplier, 
         cmm.active_barbers_count, cmm.total_bookings_30d, cmm.avg_bookings_per_barber, 
         cmm.period_start, cmm.period_end;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger to update updated_at on campus_market_metrics
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_campus_market_metrics_updated_at
    BEFORE UPDATE ON campus_market_metrics
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_services_updated_at
    BEFORE UPDATE ON services
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- GRANTS (Optional - adjust based on your role structure)
-- ============================================================================
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_role;
-- GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO api_role;
-- GRANT ALL ON ALL TABLES IN SCHEMA public TO admin_role;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

