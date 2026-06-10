-- CampusCuts Reputation & Intelligence Layer Migration
-- Depends on: 001_init_core_schema.sql

-- ═══════════════════════════════════════════════════════════════
-- REPUTATION & RANKING TABLES
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE "reputation_snapshots" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "barber_id" UUID NOT NULL REFERENCES "barbers"("id") ON DELETE CASCADE,
  
  -- Snapshot data (derived from blockchain)
  "total_bookings" INTEGER NOT NULL,
  "completed_bookings" INTEGER NOT NULL,
  "cancelled_bookings" INTEGER NOT NULL,
  "avg_rating" DECIMAL(3,2) NOT NULL,
  "total_reviews" INTEGER NOT NULL,
  "repeat_customer_rate" DECIMAL(5,2) NOT NULL,
  
  -- Metadata
  "snapshot_date" DATE NOT NULL,
  "computed_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  UNIQUE ("barber_id", "snapshot_date"),
  CONSTRAINT "snapshot_rating_range" CHECK ("avg_rating" >= 1.00 AND "avg_rating" <= 5.00)
);

CREATE TABLE "barber_rankings" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "barber_id" UUID NOT NULL REFERENCES "barbers"("id") ON DELETE CASCADE,
  "campus_id" UUID NOT NULL REFERENCES "campuses"("id") ON DELETE CASCADE,
  
  -- Ranking
  "rank_score" DECIMAL(7,2) NOT NULL,
  "breakdown" JSONB NOT NULL,
  "rank_position" INTEGER NOT NULL,
  "total_barbers" INTEGER NOT NULL,
  
  -- Validity
  "computed_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "valid_until" TIMESTAMPTZ NOT NULL,
  
  UNIQUE ("barber_id", "campus_id", "computed_at"),
  CONSTRAINT "rank_position_valid" CHECK ("rank_position" > 0 AND "rank_position" <= "total_barbers")
);

CREATE TABLE "barber_quality_scores" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "barber_id" UUID NOT NULL REFERENCES "barbers"("id") ON DELETE CASCADE,
  
  -- BQS components
  "review_score_weighted" DECIMAL(5,2) NOT NULL,
  "demand_score" DECIMAL(5,2) NOT NULL,
  "price_justification_score" DECIMAL(5,2) NOT NULL,
  "loyalty_score" DECIMAL(5,2) NOT NULL,
  
  -- Final BQS (0-100)
  "bqs_score" DECIMAL(5,2) NOT NULL,
  
  -- Metadata
  "computed_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "data_window" VARCHAR(50) NOT NULL,
  
  CONSTRAINT "bqs_components_valid" CHECK (
    "review_score_weighted" >= 0 AND "review_score_weighted" <= 100 AND
    "demand_score" >= 0 AND "demand_score" <= 100 AND
    "price_justification_score" >= 0 AND "price_justification_score" <= 100 AND
    "loyalty_score" >= 0 AND "loyalty_score" <= 100 AND
    "bqs_score" >= 0 AND "bqs_score" <= 100
  )
);

CREATE TABLE "barber_pricing_multipliers" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "barber_id" UUID NOT NULL REFERENCES "barbers"("id") ON DELETE CASCADE,
  
  -- Multiplier (1.0 to 1.5)
  "multiplier" DECIMAL(4,2) NOT NULL,
  "bqs_score" DECIMAL(5,2) NOT NULL,
  "reason" VARCHAR(200) NOT NULL,
  
  -- Validity period
  "valid_from" TIMESTAMPTZ NOT NULL,
  "valid_until" TIMESTAMPTZ NOT NULL,
  
  CONSTRAINT "multiplier_valid" CHECK ("multiplier" >= 1.00 AND "multiplier" <= 1.50),
  CONSTRAINT "validity_period_valid" CHECK ("valid_from" < "valid_until")
);

CREATE TABLE "market_factors" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "campus_id" UUID UNIQUE NOT NULL REFERENCES "campuses"("id") ON DELETE CASCADE,
  
  -- Calibration factors
  "demand_normalization_factor" DECIMAL(4,2) NOT NULL DEFAULT 1.00,
  "review_weight_adjustment" DECIMAL(4,2) NOT NULL DEFAULT 1.00,
  "competition_intensity_score" DECIMAL(4,2) NOT NULL DEFAULT 1.00,
  "surge_threshold" DECIMAL(4,2) NOT NULL DEFAULT 2.00,
  
  -- Timestamps
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT "market_factors_positive" CHECK (
    "demand_normalization_factor" > 0 AND
    "review_weight_adjustment" > 0 AND
    "competition_intensity_score" > 0 AND
    "surge_threshold" > 0
  )
);

-- ═══════════════════════════════════════════════════════════════
-- AI & INTELLIGENCE TABLES
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE "ai_annotations" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Polymorphic reference
  "entity_type" VARCHAR(50) NOT NULL,
  "entity_id" UUID NOT NULL,
  
  -- AI metadata
  "model_type" "AIModelType" NOT NULL,
  "model_name" VARCHAR(100) NOT NULL,
  
  -- Output
  "output" JSONB NOT NULL,
  "confidence" DECIMAL(4,2),
  
  -- Timestamp
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT "confidence_valid" CHECK (
    "confidence" IS NULL OR ("confidence" >= 0.00 AND "confidence" <= 1.00)
  )
);

CREATE TABLE "ai_events_log" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  "event_type" VARCHAR(100) NOT NULL,
  "entity_type" VARCHAR(50) NOT NULL,
  "entity_id" UUID NOT NULL,
  
  "payload" JSONB NOT NULL,
  "processing_status" VARCHAR(50) NOT NULL,
  
  "error" TEXT,
  
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "processed_at" TIMESTAMPTZ
);

CREATE TABLE "fraud_flags" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  
  "flag_type" VARCHAR(100) NOT NULL,
  "risk_score" DECIMAL(4,2) NOT NULL,
  "evidence" JSONB NOT NULL,
  
  "status" VARCHAR(50) NOT NULL,
  "reviewed_by" UUID,
  
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "reviewed_at" TIMESTAMPTZ,
  
  CONSTRAINT "risk_score_valid" CHECK ("risk_score" >= 0.00 AND "risk_score" <= 1.00)
);

CREATE TABLE "market_stats" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "campus_id" UUID NOT NULL,
  
  "stat_type" VARCHAR(100) NOT NULL,
  "value" DECIMAL(10,2) NOT NULL,
  "metadata" JSONB,
  
  "timestamp" TIMESTAMPTZ NOT NULL,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- ADMIN & MODERATION TABLES
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE "admin_notes" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "admin_id" UUID NOT NULL,
  
  "note" TEXT NOT NULL,
  "is_internal" BOOLEAN NOT NULL DEFAULT true,
  
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "cron_history" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  "job_name" VARCHAR(100) NOT NULL,
  "status" VARCHAR(50) NOT NULL,
  
  "duration" INTEGER,
  "records_processed" INTEGER,
  "error" TEXT,
  "metadata" JSONB,
  
  "executed_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- INDEXES
-- ═══════════════════════════════════════════════════════════════

-- Reputation Snapshots
CREATE INDEX "idx_reputation_snapshots_barber_date" ON "reputation_snapshots"("barber_id", "snapshot_date" DESC);

-- Barber Rankings
CREATE INDEX "idx_barber_rankings_campus_score" ON "barber_rankings"("campus_id", "rank_score" DESC);
CREATE INDEX "idx_barber_rankings_valid_until" ON "barber_rankings"("valid_until");

-- Barber Quality Scores
CREATE INDEX "idx_barber_quality_scores_barber_computed" ON "barber_quality_scores"("barber_id", "computed_at" DESC);

-- Barber Pricing Multipliers
CREATE INDEX "idx_barber_pricing_multipliers_validity" ON "barber_pricing_multipliers"("barber_id", "valid_from", "valid_until");

-- AI Annotations
CREATE INDEX "idx_ai_annotations_entity" ON "ai_annotations"("entity_type", "entity_id");
CREATE INDEX "idx_ai_annotations_model" ON "ai_annotations"("model_type", "created_at" DESC);

-- AI Events Log
CREATE INDEX "idx_ai_events_log_status" ON "ai_events_log"("processing_status", "created_at" DESC);
CREATE INDEX "idx_ai_events_log_type" ON "ai_events_log"("event_type");

-- Fraud Flags
CREATE INDEX "idx_fraud_flags_user_status" ON "fraud_flags"("user_id", "status");
CREATE INDEX "idx_fraud_flags_risk" ON "fraud_flags"("risk_score" DESC);

-- Market Stats
CREATE INDEX "idx_market_stats_campus_type_time" ON "market_stats"("campus_id", "stat_type", "timestamp" DESC);

-- Admin Notes
CREATE INDEX "idx_admin_notes_user" ON "admin_notes"("user_id");

-- Cron History
CREATE INDEX "idx_cron_history_job_time" ON "cron_history"("job_name", "executed_at" DESC);
CREATE INDEX "idx_cron_history_status" ON "cron_history"("status");

-- ═══════════════════════════════════════════════════════════════
-- TRIGGERS
-- ═══════════════════════════════════════════════════════════════

CREATE TRIGGER market_factors_update BEFORE UPDATE ON "market_factors"
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- ═══════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

-- Function to clean up expired availability locks
CREATE OR REPLACE FUNCTION cleanup_expired_locks()
RETURNS INTEGER AS $$
DECLARE
  affected_count INTEGER;
BEGIN
  UPDATE "availability"
  SET 
    "status" = 'OPEN',
    "locked_at" = NULL,
    "locked_by" = NULL,
    "lock_expires_at" = NULL,
    "updated_at" = NOW()
  WHERE 
    "status" = 'LOCKED' AND
    "lock_expires_at" < NOW();
  
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  RETURN affected_count;
END;
$$ LANGUAGE plpgsql;

-- Function to compute barber BQS score
CREATE OR REPLACE FUNCTION compute_barber_bqs(
  p_barber_id UUID,
  p_review_score DECIMAL,
  p_demand_score DECIMAL,
  p_price_justification DECIMAL,
  p_loyalty_score DECIMAL
)
RETURNS DECIMAL AS $$
DECLARE
  v_bqs DECIMAL;
BEGIN
  -- BQS = 0.45*R + 0.25*D + 0.15*P + 0.15*L
  v_bqs := (0.45 * p_review_score) + 
           (0.25 * p_demand_score) + 
           (0.15 * p_price_justification) + 
           (0.15 * p_loyalty_score);
  
  -- Clamp to 0-100
  v_bqs := LEAST(GREATEST(v_bqs, 0), 100);
  
  RETURN v_bqs;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to determine pricing multiplier from BQS
CREATE OR REPLACE FUNCTION determine_pricing_multiplier(p_bqs_score DECIMAL)
RETURNS DECIMAL AS $$
BEGIN
  IF p_bqs_score IS NULL OR p_bqs_score < 60 THEN
    RETURN 1.00;
  ELSIF p_bqs_score >= 60 AND p_bqs_score < 80 THEN
    RETURN 1.10;
  ELSIF p_bqs_score >= 80 AND p_bqs_score < 90 THEN
    RETURN 1.25;
  ELSE
    RETURN 1.50;
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to normalize text for location matching
CREATE OR REPLACE FUNCTION normalize_location_name(p_name TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN LOWER(
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(p_name, '[^\w\s]', '', 'g'),
        '\s+', ' ', 'g'
      ),
      '^\s+|\s+$', '', 'g'
    )
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION compute_barber_bqs IS 'Computes Barber Quality Score using capitalistic marketplace formula';
COMMENT ON FUNCTION determine_pricing_multiplier IS 'Determines dynamic pricing multiplier based on BQS tier';
COMMENT ON FUNCTION normalize_location_name IS 'Normalizes location names for fuzzy matching and deduplication';

