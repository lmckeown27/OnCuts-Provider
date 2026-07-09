-- Capitalistic Marketplace Engine Schema
-- Migration: 004
-- Description: Implements BQS, dynamic pricing, market calibration, and ranking

-- ============================================================
-- MARKETS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS markets (
  market_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT,
  base_price NUMERIC(10, 2) NOT NULL,
  average_price NUMERIC(10, 2) NOT NULL,
  premium_price_ceiling NUMERIC(10, 2) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- MARKET FACTORS TABLE (Market-specific calibration)
-- ============================================================
CREATE TABLE IF NOT EXISTS market_factors (
  market_id UUID PRIMARY KEY REFERENCES markets(market_id) ON DELETE CASCADE,
  demand_normalization_factor NUMERIC(5, 2) DEFAULT 1.0,
  review_weight_adjustment NUMERIC(5, 2) DEFAULT 1.0,
  competition_intensity_score NUMERIC(5, 2) DEFAULT 1.0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- BARBERS TABLE (Extended with BQS fields)
-- ============================================================
-- Check if barbers table exists, if not create it
CREATE TABLE IF NOT EXISTS barbers (
  barber_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  market_id UUID REFERENCES markets(market_id),
  base_price NUMERIC(10, 2),
  current_price NUMERIC(10, 2),
  min_allowed_price NUMERIC(10, 2),
  max_allowed_price NUMERIC(10, 2),
  
  -- BQS Components
  bqs NUMERIC(5, 2) DEFAULT 0,
  bqs_last_updated TIMESTAMP,
  review_score_weighted NUMERIC(5, 2) DEFAULT 0,
  demand_score NUMERIC(5, 2) DEFAULT 0,
  price_justification_score NUMERIC(5, 2) DEFAULT 0,
  loyalty_score NUMERIC(5, 2) DEFAULT 0,
  
  -- Stats for BQS calculation
  review_count INT DEFAULT 0,
  avg_rating NUMERIC(3, 2) DEFAULT 0,
  total_bookings INT DEFAULT 0,
  completed_bookings INT DEFAULT 0,
  repeat_customers INT DEFAULT 0,
  total_customers INT DEFAULT 0,
  slots_available_weekly INT DEFAULT 0,
  slots_booked_weekly INT DEFAULT 0,
  
  -- Pricing multiplier (earned via BQS)
  pricing_multiplier NUMERIC(5, 2) DEFAULT 1.0,
  
  -- Status
  is_active BOOLEAN DEFAULT true,
  is_verified BOOLEAN DEFAULT false,
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Add market_id column if it doesn't exist (for existing barbers table)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name='barbers' AND column_name='market_id') THEN
    ALTER TABLE barbers ADD COLUMN market_id UUID REFERENCES markets(market_id);
  END IF;
END $$;

-- Add BQS columns if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name='barbers' AND column_name='bqs') THEN
    ALTER TABLE barbers 
      ADD COLUMN bqs NUMERIC(5, 2) DEFAULT 0,
      ADD COLUMN bqs_last_updated TIMESTAMP,
      ADD COLUMN review_score_weighted NUMERIC(5, 2) DEFAULT 0,
      ADD COLUMN demand_score NUMERIC(5, 2) DEFAULT 0,
      ADD COLUMN price_justification_score NUMERIC(5, 2) DEFAULT 0,
      ADD COLUMN loyalty_score NUMERIC(5, 2) DEFAULT 0,
      ADD COLUMN pricing_multiplier NUMERIC(5, 2) DEFAULT 1.0,
      ADD COLUMN min_allowed_price NUMERIC(10, 2),
      ADD COLUMN max_allowed_price NUMERIC(10, 2),
      ADD COLUMN slots_available_weekly INT DEFAULT 0,
      ADD COLUMN slots_booked_weekly INT DEFAULT 0,
      ADD COLUMN repeat_customers INT DEFAULT 0,
      ADD COLUMN total_customers INT DEFAULT 0;
  END IF;
END $$;

-- ============================================================
-- REVIEWS TABLE (if not exists)
-- ============================================================
CREATE TABLE IF NOT EXISTS reviews (
  review_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barber_id UUID REFERENCES barbers(barber_id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  booking_id UUID,
  rating INT CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  timestamp TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- BOOKINGS TABLE EXTENSIONS
-- ============================================================
-- Add fields needed for BQS calculations
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name='bookings' AND column_name='price_charged') THEN
    ALTER TABLE bookings 
      ADD COLUMN price_charged NUMERIC(10, 2),
      ADD COLUMN completed BOOLEAN DEFAULT false,
      ADD COLUMN is_repeat_customer BOOLEAN DEFAULT false;
  END IF;
END $$;

-- ============================================================
-- BARBER RANK HISTORY (for tracking)
-- ============================================================
CREATE TABLE IF NOT EXISTS barber_rank_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barber_id UUID REFERENCES barbers(barber_id) ON DELETE CASCADE,
  bqs NUMERIC(5, 2),
  rank_score NUMERIC(5, 2),
  market_rank INT,
  timestamp TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- SURGE PRICING EVENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS surge_events (
  event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  market_id UUID REFERENCES markets(market_id),
  time_block TIMESTAMP,
  active_users_requesting INT,
  active_barbers_available INT,
  demand_supply_ratio NUMERIC(5, 2),
  surge_multiplier NUMERIC(5, 2),
  is_active BOOLEAN DEFAULT true,
  started_at TIMESTAMP DEFAULT NOW(),
  ended_at TIMESTAMP
);

-- ============================================================
-- CRON HISTORY (job execution tracking)
-- ============================================================
CREATE TABLE IF NOT EXISTS cron_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_name TEXT NOT NULL,
  executed_at TIMESTAMP DEFAULT NOW(),
  status TEXT CHECK (status IN ('success', 'failed', 'running')),
  duration_ms INT,
  error_message TEXT,
  records_processed INT
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_barbers_market ON barbers(market_id);
CREATE INDEX IF NOT EXISTS idx_barbers_bqs ON barbers(bqs DESC);
CREATE INDEX IF NOT EXISTS idx_barbers_active ON barbers(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_reviews_barber ON reviews(barber_id);
CREATE INDEX IF NOT EXISTS idx_bookings_barber ON bookings(barber_id);
CREATE INDEX IF NOT EXISTS idx_bookings_completed ON bookings(completed) WHERE completed = true;
CREATE INDEX IF NOT EXISTS idx_surge_events_market_time ON surge_events(market_id, time_block);
CREATE INDEX IF NOT EXISTS idx_cron_history_job ON cron_history(job_name, executed_at DESC);

-- ============================================================
-- SEED DATA: Markets
-- ============================================================
INSERT INTO markets (market_id, name, city, state, base_price, average_price, premium_price_ceiling) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Cal Poly SLO', 'San Luis Obispo', 'CA', 20.00, 30.00, 50.00),
  ('22222222-2222-2222-2222-222222222222', 'UCSB', 'Santa Barbara', 'CA', 22.00, 32.00, 55.00),
  ('33333333-3333-3333-3333-333333333333', 'UCLA', 'Los Angeles', 'CA', 25.00, 40.00, 75.00),
  ('44444444-4444-4444-4444-444444444444', 'USC', 'Los Angeles', 'CA', 25.00, 40.00, 75.00),
  ('55555555-5555-5555-5555-555555555555', 'UC Berkeley', 'Berkeley', 'CA', 25.00, 38.00, 70.00)
ON CONFLICT (market_id) DO NOTHING;

-- ============================================================
-- SEED DATA: Market Factors
-- ============================================================
INSERT INTO market_factors (market_id, demand_normalization_factor, review_weight_adjustment, competition_intensity_score) VALUES
  -- Small market (SLO)
  ('11111111-1111-1111-1111-111111111111', 0.8, 1.2, 0.7),
  -- Medium market (UCSB)
  ('22222222-2222-2222-2222-222222222222', 1.0, 1.0, 1.0),
  -- Large markets (LA - UCLA, USC)
  ('33333333-3333-3333-3333-333333333333', 1.3, 0.9, 1.5),
  ('44444444-4444-4444-4444-444444444444', 1.3, 0.9, 1.5),
  -- Large market (Berkeley)
  ('55555555-5555-5555-5555-555555555555', 1.2, 0.95, 1.3)
ON CONFLICT (market_id) DO NOTHING;

