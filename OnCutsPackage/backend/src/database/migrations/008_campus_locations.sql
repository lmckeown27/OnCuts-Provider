-- Migration: Campus Location Ingestion System
-- Description: Crowd-sourced, AI-enriched campus location registry
-- Version: 008
-- Date: 2025-12-16

-- =====================================================
-- CAMPUS LOCATIONS TABLE
-- =====================================================
-- Purpose: Central registry of all campus service locations
-- Scoping: Each location is tied to a specific university_id
-- Confidence: Increases with usage and AI verification
-- Verification: Automated promotion based on usage + confidence

CREATE TABLE IF NOT EXISTS campus_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- University scoping
  university_id UUID NOT NULL,
  
  -- Location identity
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL, -- Lowercased, stripped, dedupe key
  
  -- Classification
  category VARCHAR(32) NOT NULL DEFAULT 'OTHER' CHECK (category IN (
    'ON_CAMPUS',      -- Campus buildings, facilities
    'OFF_CAMPUS',     -- Off-campus housing/locations
    'DORM',           -- On-campus dormitory
    'APARTMENT',      -- Off-campus apartment complex
    'COMMON_AREA',    -- Shared spaces (library, quad, etc.)
    'OTHER'           -- Uncategorized
  )),
  
  -- Student cohort association (for ranking/filtering)
  cohort VARCHAR(32) NOT NULL DEFAULT 'UNKNOWN' CHECK (cohort IN (
    'FIRST_YEAR',     -- Freshman housing/areas
    'UPPER_CLASS',    -- Upperclassman housing
    'GRAD',           -- Graduate student housing
    'MIXED',          -- Multi-cohort location
    'UNKNOWN'         -- Not yet classified
  )),
  
  -- Usage & quality metrics
  usage_count INTEGER NOT NULL DEFAULT 1,
  confidence NUMERIC(3, 2) NOT NULL DEFAULT 0.30 CHECK (confidence >= 0 AND confidence <= 1.0),
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  
  -- Audit trail
  created_by_user_id UUID,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  
  -- Ensure unique normalized names per university
  CONSTRAINT unique_normalized_name_per_university UNIQUE (university_id, normalized_name)
);

-- Indexes for performance
CREATE INDEX idx_campus_locations_university ON campus_locations(university_id);
CREATE INDEX idx_campus_locations_normalized ON campus_locations(normalized_name);
CREATE INDEX idx_campus_locations_verified ON campus_locations(university_id, is_verified, confidence DESC);
CREATE INDEX idx_campus_locations_category ON campus_locations(university_id, category);
CREATE INDEX idx_campus_locations_usage ON campus_locations(university_id, usage_count DESC);

-- =====================================================
-- CAMPUS LOCATION ALIASES TABLE
-- =====================================================
-- Purpose: Alternative names for the same location
-- Example: "Yak Yit Dorm" → "Yakʔitʸuʸu Hall"
-- Source: AI enrichment + user submissions

CREATE TABLE IF NOT EXISTS campus_location_aliases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Parent location
  campus_location_id UUID NOT NULL REFERENCES campus_locations(id) ON DELETE CASCADE,
  
  -- Alias identity
  alias TEXT NOT NULL,
  normalized_alias TEXT NOT NULL, -- Lowercased, stripped
  
  -- Audit
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  
  -- Ensure unique aliases per location
  CONSTRAINT unique_normalized_alias_per_location UNIQUE (campus_location_id, normalized_alias)
);

-- Indexes for fuzzy matching
CREATE INDEX idx_campus_location_aliases_normalized ON campus_location_aliases(normalized_alias);
CREATE INDEX idx_campus_location_aliases_location ON campus_location_aliases(campus_location_id);

-- =====================================================
-- LOCATION ENRICHMENT LOG
-- =====================================================
-- Purpose: Track AI enrichment attempts and results
-- Auditability: Know when AI modified confidence/category

CREATE TABLE IF NOT EXISTS location_enrichment_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Target location
  campus_location_id UUID NOT NULL REFERENCES campus_locations(id) ON DELETE CASCADE,
  
  -- AI output
  ai_suggested_name TEXT,
  ai_suggested_category VARCHAR(32),
  ai_suggested_cohort VARCHAR(32),
  ai_suggested_aliases TEXT[], -- Array of suggested aliases
  ai_confidence_adjustment NUMERIC(3, 2),
  
  -- Application status
  applied BOOLEAN NOT NULL DEFAULT FALSE,
  applied_at TIMESTAMP,
  rejected_reason TEXT, -- Why AI suggestion was not applied
  
  -- Audit
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_location_enrichment_log_location ON location_enrichment_log(campus_location_id);
CREATE INDEX idx_location_enrichment_log_created ON location_enrichment_log(created_at DESC);

-- =====================================================
-- LOCATION MERGE LOG
-- =====================================================
-- Purpose: Track when locations are merged (duplicate resolution)
-- Auditability: Know which locations were consolidated

CREATE TABLE IF NOT EXISTS location_merge_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Merge details
  source_location_id UUID NOT NULL, -- The location that was merged (deleted)
  target_location_id UUID NOT NULL REFERENCES campus_locations(id), -- The location it merged into
  
  -- Context
  merged_by_user_id UUID, -- Admin who performed merge, NULL if automatic
  merge_reason TEXT, -- "duplicate", "AI suggestion", "admin override"
  
  -- Audit
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_location_merge_log_source ON location_merge_log(source_location_id);
CREATE INDEX idx_location_merge_log_target ON location_merge_log(target_location_id);

-- =====================================================
-- TRIGGER: Auto-update updated_at
-- =====================================================

CREATE OR REPLACE FUNCTION update_campus_location_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER campus_location_updated_at
BEFORE UPDATE ON campus_locations
FOR EACH ROW
EXECUTE FUNCTION update_campus_location_updated_at();

-- =====================================================
-- COMMENTS
-- =====================================================

COMMENT ON TABLE campus_locations IS 'Crowd-sourced registry of campus service locations with AI enrichment';
COMMENT ON COLUMN campus_locations.normalized_name IS 'Deduplication key: lowercased, stripped, no punctuation';
COMMENT ON COLUMN campus_locations.confidence IS 'Quality score: starts at 0.3, increases with usage and AI verification';
COMMENT ON COLUMN campus_locations.is_verified IS 'Promoted to verified when: usage_count >= 5 AND confidence >= 0.8 AND cohort != UNKNOWN';
COMMENT ON COLUMN campus_locations.cohort IS 'Student demographic most associated with this location';

COMMENT ON TABLE campus_location_aliases IS 'Alternative names for campus locations (e.g., nicknames, abbreviations)';
COMMENT ON TABLE location_enrichment_log IS 'Audit log of AI enrichment attempts and outcomes';
COMMENT ON TABLE location_merge_log IS 'Audit log of location deduplication merges';

