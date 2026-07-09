-- CampusCuts Core Schema Migration
-- PostgreSQL 15+ required
-- Extensions: pgcrypto, pg_trgm

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ═══════════════════════════════════════════════════════════════
-- ENUMS
-- ═══════════════════════════════════════════════════════════════

CREATE TYPE "UserRole" AS ENUM ('CONSUMER', 'BARBER', 'ADMIN');

CREATE TYPE "LocationType" AS ENUM (
  'DORM',
  'APARTMENT',
  'OFF_CAMPUS',
  'LIBRARY',
  'COMMONS',
  'GYM',
  'PARKING_LOT',
  'GREEK_HOUSE',
  'OTHER'
);

CREATE TYPE "LocationCohort" AS ENUM (
  'FRESHMAN_HOUSING',
  'UPPERCLASS_HOUSING',
  'GRADUATE_HOUSING',
  'OFF_CAMPUS_POPULAR',
  'CAMPUS_CENTER',
  'ATHLETIC_FACILITY',
  'GREEK_ROW',
  'COMMUTER_LOT',
  'UNKNOWN'
);

CREATE TYPE "AvailabilityStatus" AS ENUM (
  'OPEN',
  'LOCKED',
  'BOOKED',
  'COMPLETED',
  'CANCELLED'
);

CREATE TYPE "BookingStatus" AS ENUM (
  'PENDING',
  'ACCEPTED',
  'PAID',
  'IN_PROGRESS',
  'COMPLETED',
  'DISPUTED',
  'CANCELLED',
  'REFUNDED'
);

CREATE TYPE "ServiceType" AS ENUM (
  'HAIRCUT',
  'FADE',
  'BEARD_TRIM',
  'FULL_SERVICE',
  'HOT_TOWEL_SHAVE',
  'COLOR',
  'STYLING',
  'LINEUP',
  'BUZZ_CUT',
  'SHAPE_UP',
  'PERM',
  'BRAIDS',
  'LOCS'
);

CREATE TYPE "DisputeStatus" AS ENUM (
  'OPEN',
  'UNDER_REVIEW',
  'RESOLVED',
  'ESCALATED',
  'CLOSED'
);

CREATE TYPE "AIModelType" AS ENUM (
  'LOCATION_NORMALIZATION',
  'FRAUD_DETECTION',
  'DISPUTE_RESOLUTION',
  'SENTIMENT_ANALYSIS',
  'QUALITY_ASSESSMENT',
  'DEMAND_PREDICTION'
);

-- ═══════════════════════════════════════════════════════════════
-- CORE TABLES
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE "campuses" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "slug" VARCHAR(50) UNIQUE NOT NULL,
  "name" VARCHAR(200) NOT NULL,
  "city" VARCHAR(100) NOT NULL,
  "state" VARCHAR(2) NOT NULL,
  "country" VARCHAR(2) NOT NULL DEFAULT 'US',
  "timezone" VARCHAR(50) NOT NULL,
  
  -- Market configuration
  "base_price_usd_cents" INTEGER NOT NULL DEFAULT 2200,
  "average_price_usd_cents" INTEGER NOT NULL DEFAULT 3500,
  "premium_ceiling_usd_cents" INTEGER NOT NULL DEFAULT 4500,
  "platform_fee_percent" DECIMAL(5,2) NOT NULL DEFAULT 5.00,
  
  -- Status
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  
  -- Timestamps
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "users" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "wallet_address" VARCHAR(66) UNIQUE NOT NULL,
  "role" "UserRole" NOT NULL,
  "campus_id" UUID NOT NULL REFERENCES "campuses"("id") ON DELETE RESTRICT,
  
  -- Profile
  "display_name" VARCHAR(100),
  "avatar_url" TEXT,
  "instagram_handle" VARCHAR(50),
  
  -- Status flags
  "is_verified" BOOLEAN NOT NULL DEFAULT false,
  "is_blocked" BOOLEAN NOT NULL DEFAULT false,
  "is_banned" BOOLEAN NOT NULL DEFAULT false,
  
  -- Timestamps
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "last_active_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "barbers" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "user_id" UUID UNIQUE NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "campus_id" UUID NOT NULL REFERENCES "campuses"("id") ON DELETE RESTRICT,
  
  -- Profile
  "bio" TEXT,
  "specialties" "ServiceType"[] NOT NULL DEFAULT '{}',
  
  -- Pricing
  "current_min_price_usd_cents" INTEGER NOT NULL,
  "current_max_price_usd_cents" INTEGER NOT NULL,
  
  -- Cached reputation (NEVER manually edited)
  "total_bookings" INTEGER NOT NULL DEFAULT 0,
  "completed_bookings" INTEGER NOT NULL DEFAULT 0,
  "cancelled_bookings" INTEGER NOT NULL DEFAULT 0,
  "avg_rating" DECIMAL(3,2),
  "total_reviews" INTEGER NOT NULL DEFAULT 0,
  "reliability_score" DECIMAL(5,2),
  
  -- Dynamic pricing
  "bqs_score" DECIMAL(5,2),
  "pricing_multiplier" DECIMAL(4,2) NOT NULL DEFAULT 1.00,
  
  -- Status
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "is_onboarded" BOOLEAN NOT NULL DEFAULT false,
  
  -- Timestamps
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT "barber_pricing_valid" CHECK (
    "current_min_price_usd_cents" <= "current_max_price_usd_cents"
  ),
  CONSTRAINT "bqs_score_range" CHECK (
    "bqs_score" IS NULL OR ("bqs_score" >= 0 AND "bqs_score" <= 100)
  ),
  CONSTRAINT "multiplier_range" CHECK (
    "pricing_multiplier" >= 1.00 AND "pricing_multiplier" <= 1.50
  )
);

CREATE TABLE "locations" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "campus_id" UUID NOT NULL REFERENCES "campuses"("id") ON DELETE RESTRICT,
  
  -- Identity
  "name" VARCHAR(200) NOT NULL,
  "normalized_name" VARCHAR(200) NOT NULL,
  
  -- Classification
  "type" "LocationType" NOT NULL,
  "cohort" "LocationCohort" NOT NULL DEFAULT 'UNKNOWN',
  
  -- Metadata
  "usage_count" INTEGER NOT NULL DEFAULT 1,
  "confidence" DECIMAL(4,2) NOT NULL DEFAULT 0.50,
  "is_verified" BOOLEAN NOT NULL DEFAULT false,
  
  -- Optional enrichment
  "address" TEXT,
  "building_code" VARCHAR(20),
  "notes" TEXT,
  
  -- Attribution
  "created_by_user_id" UUID REFERENCES "users"("id") ON DELETE SET NULL,
  
  -- Timestamps
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT "confidence_range" CHECK (
    "confidence" >= 0.00 AND "confidence" <= 1.00
  ),
  UNIQUE ("campus_id", "normalized_name")
);

CREATE TABLE "location_aliases" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "location_id" UUID NOT NULL REFERENCES "locations"("id") ON DELETE CASCADE,
  
  "alias" VARCHAR(200) NOT NULL,
  "normalized_alias" VARCHAR(200) NOT NULL,
  
  "is_ai_generated" BOOLEAN NOT NULL DEFAULT false,
  "usage_count" INTEGER NOT NULL DEFAULT 0,
  
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  UNIQUE ("location_id", "normalized_alias")
);

CREATE TABLE "availability" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "barber_id" UUID NOT NULL REFERENCES "barbers"("id") ON DELETE CASCADE,
  "location_id" UUID NOT NULL REFERENCES "locations"("id") ON DELETE RESTRICT,
  
  -- Time slot
  "start_time" TIMESTAMPTZ NOT NULL,
  "end_time" TIMESTAMPTZ NOT NULL,
  
  -- Pricing
  "price_usd_cents" INTEGER NOT NULL,
  "service_types" "ServiceType"[] NOT NULL DEFAULT '{}',
  
  -- State
  "status" "AvailabilityStatus" NOT NULL DEFAULT 'OPEN',
  
  -- Lock mechanism
  "locked_at" TIMESTAMPTZ,
  "locked_by" UUID,
  "lock_expires_at" TIMESTAMPTZ,
  
  -- Timestamps
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT "time_slot_valid" CHECK ("start_time" < "end_time"),
  CONSTRAINT "lock_valid" CHECK (
    ("locked_at" IS NULL AND "locked_by" IS NULL AND "lock_expires_at" IS NULL) OR
    ("locked_at" IS NOT NULL AND "locked_by" IS NOT NULL AND "lock_expires_at" IS NOT NULL)
  )
);

CREATE TABLE "bookings" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "availability_id" UUID UNIQUE NOT NULL REFERENCES "availability"("id") ON DELETE RESTRICT,
  "barber_id" UUID NOT NULL REFERENCES "barbers"("id") ON DELETE RESTRICT,
  "consumer_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE RESTRICT,
  
  -- Service
  "service_type" "ServiceType" NOT NULL,
  "price_usd_cents" INTEGER NOT NULL,
  "platform_fee_usd_cents" INTEGER NOT NULL,
  "barber_earnings_usd_cents" INTEGER NOT NULL,
  
  -- Blockchain
  "aptos_tx_hash" VARCHAR(66),
  "aptos_event_index" BIGINT,
  
  -- Status
  "status" "BookingStatus" NOT NULL DEFAULT 'PENDING',
  
  -- Timeline
  "requested_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "accepted_at" TIMESTAMPTZ,
  "paid_at" TIMESTAMPTZ,
  "started_at" TIMESTAMPTZ,
  "completed_at" TIMESTAMPTZ,
  "cancelled_at" TIMESTAMPTZ,
  
  -- Cancellation
  "cancelled_by" UUID,
  "cancellation_reason" TEXT,
  
  -- Timestamps
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT "booking_amounts_valid" CHECK (
    "price_usd_cents" = "platform_fee_usd_cents" + "barber_earnings_usd_cents"
  )
);

CREATE TABLE "reviews" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "booking_id" UUID UNIQUE NOT NULL REFERENCES "bookings"("id") ON DELETE RESTRICT,
  "barber_id" UUID NOT NULL REFERENCES "barbers"("id") ON DELETE RESTRICT,
  "consumer_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE RESTRICT,
  
  -- Content
  "rating" SMALLINT NOT NULL,
  "comment" TEXT,
  
  -- AI analysis
  "sentiment_score" DECIMAL(4,2),
  
  -- Blockchain
  "aptos_tx_hash" VARCHAR(66),
  
  -- Timestamps
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT "rating_range" CHECK ("rating" >= 1 AND "rating" <= 5),
  CONSTRAINT "sentiment_range" CHECK (
    "sentiment_score" IS NULL OR 
    ("sentiment_score" >= -1.00 AND "sentiment_score" <= 1.00)
  )
);

CREATE TABLE "disputes" (
  "id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  "booking_id" UUID UNIQUE NOT NULL REFERENCES "bookings"("id") ON DELETE RESTRICT,
  
  -- Dispute
  "opened_by" UUID NOT NULL,
  "reason" TEXT NOT NULL,
  "evidence" JSONB,
  
  -- Status
  "status" "DisputeStatus" NOT NULL DEFAULT 'OPEN',
  
  -- Resolution
  "resolved_by" UUID,
  "resolution" TEXT,
  "refund_amount_usd_cents" INTEGER,
  
  -- Timestamps
  "opened_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "resolved_at" TIMESTAMPTZ
);

-- ═══════════════════════════════════════════════════════════════
-- INDEXES (Performance-Critical)
-- ═══════════════════════════════════════════════════════════════

-- Campuses
CREATE INDEX "idx_campuses_slug" ON "campuses"("slug");
CREATE INDEX "idx_campuses_city_state" ON "campuses"("city", "state");
CREATE INDEX "idx_campuses_active" ON "campuses"("is_active");

-- Users
CREATE INDEX "idx_users_wallet" ON "users"("wallet_address");
CREATE INDEX "idx_users_campus_role" ON "users"("campus_id", "role");
CREATE INDEX "idx_users_verified" ON "users"("is_verified");
CREATE INDEX "idx_users_blocked" ON "users"("is_blocked");

-- Barbers
CREATE INDEX "idx_barbers_user" ON "barbers"("user_id");
CREATE INDEX "idx_barbers_campus_active" ON "barbers"("campus_id", "is_active");
CREATE INDEX "idx_barbers_bqs" ON "barbers"("bqs_score" DESC NULLS LAST);
CREATE INDEX "idx_barbers_rating" ON "barbers"("avg_rating" DESC NULLS LAST);

-- Locations
CREATE INDEX "idx_locations_campus_verified" ON "locations"("campus_id", "is_verified");
CREATE INDEX "idx_locations_campus_type" ON "locations"("campus_id", "type");
CREATE INDEX "idx_locations_usage" ON "locations"("usage_count" DESC);
CREATE INDEX "idx_locations_confidence" ON "locations"("confidence" DESC);
CREATE INDEX "idx_locations_normalized_trgm" ON "locations" USING gin("normalized_name" gin_trgm_ops);

-- Location Aliases
CREATE INDEX "idx_location_aliases_normalized" ON "location_aliases"("normalized_alias");
CREATE INDEX "idx_location_aliases_normalized_trgm" ON "location_aliases" USING gin("normalized_alias" gin_trgm_ops);

-- Availability
CREATE INDEX "idx_availability_barber_status" ON "availability"("barber_id", "status");
CREATE INDEX "idx_availability_time" ON "availability"("start_time", "end_time");
CREATE INDEX "idx_availability_status" ON "availability"("status");
CREATE INDEX "idx_availability_lock" ON "availability"("locked_by", "lock_expires_at") WHERE "locked_by" IS NOT NULL;

-- Bookings
CREATE INDEX "idx_bookings_barber_status" ON "bookings"("barber_id", "status");
CREATE INDEX "idx_bookings_consumer_status" ON "bookings"("consumer_id", "status");
CREATE INDEX "idx_bookings_tx_hash" ON "bookings"("aptos_tx_hash") WHERE "aptos_tx_hash" IS NOT NULL;
CREATE INDEX "idx_bookings_status" ON "bookings"("status");
CREATE INDEX "idx_bookings_requested_at" ON "bookings"("requested_at" DESC);

-- Reviews
CREATE INDEX "idx_reviews_barber_rating" ON "reviews"("barber_id", "rating");
CREATE INDEX "idx_reviews_consumer" ON "reviews"("consumer_id");
CREATE INDEX "idx_reviews_created" ON "reviews"("created_at" DESC);

-- Disputes
CREATE INDEX "idx_disputes_status" ON "disputes"("status");
CREATE INDEX "idx_disputes_opened" ON "disputes"("opened_at" DESC);

-- ═══════════════════════════════════════════════════════════════
-- TRIGGERS (Auto-update timestamps)
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER campuses_update BEFORE UPDATE ON "campuses"
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER users_update BEFORE UPDATE ON "users"
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER barbers_update BEFORE UPDATE ON "barbers"
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER locations_update BEFORE UPDATE ON "locations"
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER availability_update BEFORE UPDATE ON "availability"
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER bookings_update BEFORE UPDATE ON "bookings"
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER reviews_update BEFORE UPDATE ON "reviews"
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();

