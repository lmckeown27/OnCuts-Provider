-- ═══════════════════════════════════════════════════════════════════════
-- CAMPUSCUTS POSTGRESQL CACHE LAYER - IMPROVED SCHEMA
-- ═══════════════════════════════════════════════════════════════════════
--
-- ARCHITECTURE: Hybrid (Blockchain + PostgreSQL Cache)
-- - Source of Truth: Aptos blockchain
-- - Cache Layer: PostgreSQL (synced hourly)
-- - Purpose: Fast queries, complex analytics, admin dashboards
--
-- Adapted from: CampusKinect PostgreSQL architecture
-- Version: 2.0
-- Last Updated: December 11, 2025
--
-- ═══════════════════════════════════════════════════════════════════════

-- Drop existing tables (clean slate)
DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS bookings CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS universities CASCADE;
DROP TABLE IF EXISTS sync_status CASCADE;

-- ═══════════════════════════════════════════════════════════════════════
-- CORE TABLES
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
-- Universities (Campus Entities)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE universities (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  domain VARCHAR(255) UNIQUE NOT NULL,
  city VARCHAR(100),
  state VARCHAR(100),
  country VARCHAR(100) DEFAULT 'US',
  
  -- Geographic data for location-based features
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  
  -- Metadata
  student_count INTEGER DEFAULT 0,
  active_barbers INTEGER DEFAULT 0,
  total_bookings INTEGER DEFAULT 0,
  
  -- Status
  is_active BOOLEAN DEFAULT TRUE,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes (adapted from CampusKinect)
CREATE INDEX idx_universities_domain ON universities(domain);
CREATE INDEX idx_universities_is_active ON universities(is_active);

-- Comments for documentation
COMMENT ON TABLE universities IS 'University/campus entities. Auto-created from email domains.';
COMMENT ON COLUMN universities.domain IS 'Email domain (e.g., calpoly.edu) - unique identifier';

-- ───────────────────────────────────────────────────────────────────────
-- Users (Cached from Blockchain)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  
  -- Blockchain identity (PRIMARY KEY in blockchain)
  legacy_wallet_address VARCHAR(66) UNIQUE NOT NULL,
  
  -- User profile
  email VARCHAR(255),
  full_name VARCHAR(255),
  display_name VARCHAR(200),
  profile_picture_cid VARCHAR(255),  -- IPFS CID
  
  -- University assignment (multi-tenancy)
  university_id INTEGER REFERENCES universities(id) ON DELETE SET NULL,
  
  -- Role (1=student, 2=barber)
  role INTEGER NOT NULL DEFAULT 1 CHECK (role IN (1, 2)),
  
  -- Balances (in cents, synced from blockchain)
  balance BIGINT NOT NULL DEFAULT 0,
  locked_balance BIGINT NOT NULL DEFAULT 0,
  
  -- Barber-specific fields
  specialties TEXT[] DEFAULT '{}',
  service_types TEXT[] DEFAULT '{}',
  base_price INTEGER DEFAULT 0,
  bio TEXT,
  years_experience INTEGER DEFAULT 0,
  
  -- Metrics (calculated from bookings/reviews)
  total_bookings INTEGER DEFAULT 0,
  completed_bookings INTEGER DEFAULT 0,
  completion_rate DECIMAL(5,2) DEFAULT 0.00,
  average_rating DECIMAL(3,2) DEFAULT 0.00,
  total_reviews INTEGER DEFAULT 0,
  
  -- Status flags
  is_verified BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  banned_at TIMESTAMP,
  ban_reason TEXT,
  
  -- Blockchain sync tracking
  blockchain_created_at BIGINT,  -- Timestamp from blockchain
  synced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Timestamps
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes (comprehensive coverage from CampusKinect)
CREATE INDEX idx_users_legacy_wallet_address ON users(legacy_wallet_address);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_university_id ON users(university_id);
CREATE INDEX idx_users_is_active ON users(is_active);
CREATE INDEX idx_users_banned_at ON users(banned_at) WHERE banned_at IS NOT NULL;

-- Composite indexes for common queries
CREATE INDEX idx_users_university_role ON users(university_id, role);
CREATE INDEX idx_users_role_rating ON users(role, average_rating DESC) WHERE role = 2;  -- Barber rankings

-- Comments
COMMENT ON TABLE users IS 'User accounts; on-chain ids: sui_address and optional legacy_wallet_address.';
COMMENT ON COLUMN users.legacy_wallet_address IS 'Pre-Sui custodial hex id; prefer sui_address when set';
COMMENT ON COLUMN users.balance IS 'Available balance in cents (synced from blockchain)';
COMMENT ON COLUMN users.locked_balance IS 'Funds locked in escrow (synced from blockchain)';

-- ───────────────────────────────────────────────────────────────────────
-- Bookings (Cached from Blockchain)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE bookings (
  id SERIAL PRIMARY KEY,
  
  -- Blockchain identity
  blockchain_id BIGINT UNIQUE NOT NULL,
  
  -- Participants
  student_address VARCHAR(66) NOT NULL,
  barber_address VARCHAR(66) NOT NULL,
  
  -- Financial details (in cents)
  amount BIGINT NOT NULL,
  platform_fee BIGINT NOT NULL DEFAULT 0,
  barber_payout BIGINT,  -- Calculated: amount - platform_fee
  
  -- Scheduling
  scheduled_time TIMESTAMP NOT NULL,
  duration_minutes INTEGER DEFAULT 60,
  
  -- Service details
  service_type VARCHAR(100),
  service_description TEXT,
  location VARCHAR(255),
  
  -- Status tracking
  -- 0=pending, 1=confirmed, 2=completed, 3=cancelled, 4=disputed
  status INTEGER NOT NULL DEFAULT 0 CHECK (status IN (0, 1, 2, 3, 4)),
  
  -- Status change timestamps
  confirmed_at TIMESTAMP,
  completed_at TIMESTAMP,
  cancelled_at TIMESTAMP,
  disputed_at TIMESTAMP,
  
  -- Cancellation/dispute details
  cancellation_reason TEXT,
  dispute_reason TEXT,
  dispute_resolved_at TIMESTAMP,
  dispute_resolution VARCHAR(20),  -- 'refund', 'release', 'partial'
  
  -- Blockchain sync tracking
  blockchain_created_at BIGINT,
  synced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Timestamps
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes (comprehensive from CampusKinect)
CREATE INDEX idx_bookings_blockchain_id ON bookings(blockchain_id);
CREATE INDEX idx_bookings_student ON bookings(student_address);
CREATE INDEX idx_bookings_barber ON bookings(barber_address);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_scheduled_time ON bookings(scheduled_time);
CREATE INDEX idx_bookings_created_at ON bookings(created_at DESC);

-- Composite indexes for common queries
CREATE INDEX idx_bookings_student_status ON bookings(student_address, status);
CREATE INDEX idx_bookings_barber_status ON bookings(barber_address, status);
CREATE INDEX idx_bookings_barber_completed ON bookings(barber_address, completed_at DESC) 
  WHERE status = 2;  -- Barber earnings history

-- Campus filtering (multi-tenancy like CampusKinect)
CREATE INDEX idx_bookings_campus_filter ON bookings(student_address) 
  WHERE student_address LIKE '0x1%' 
     OR student_address LIKE '0x2%' 
     OR student_address LIKE '0x3%';

-- Comments
COMMENT ON TABLE bookings IS 'Booking records cached from Aptos blockchain. Synced hourly.';
COMMENT ON COLUMN bookings.blockchain_id IS 'Unique booking ID from smart contract';
COMMENT ON COLUMN bookings.status IS '0=pending, 1=confirmed, 2=completed, 3=cancelled, 4=disputed';

-- ───────────────────────────────────────────────────────────────────────
-- Reviews (Cached from Blockchain)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE reviews (
  id SERIAL PRIMARY KEY,
  
  -- Blockchain identity
  blockchain_id BIGINT UNIQUE NOT NULL,
  
  -- Relationships
  booking_id BIGINT NOT NULL,  -- References booking blockchain_id
  reviewer_address VARCHAR(66) NOT NULL,
  barber_address VARCHAR(66) NOT NULL,
  
  -- Review content
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment_cid VARCHAR(255),  -- IPFS CID for comment text
  comment_text TEXT,  -- Fetched from IPFS, cached here
  
  -- Response (barber can respond)
  barber_response_cid VARCHAR(255),
  barber_response_text TEXT,
  responded_at TIMESTAMP,
  
  -- Review credibility (student reputation impacts review weight)
  reviewer_credibility_score INTEGER DEFAULT 100,
  review_weight DECIMAL(3,2) DEFAULT 1.00,  -- 0.2 to 1.2 (based on student score)
  
  -- Moderation
  is_flagged BOOLEAN DEFAULT FALSE,
  flag_reason VARCHAR(100),
  flagged_at TIMESTAMP,
  is_verified BOOLEAN DEFAULT TRUE,
  
  -- Blockchain sync tracking
  blockchain_created_at BIGINT,
  synced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Timestamps
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_reviews_blockchain_id ON reviews(blockchain_id);
CREATE INDEX idx_reviews_booking_id ON reviews(booking_id);
CREATE INDEX idx_reviews_reviewer ON reviews(reviewer_address);
CREATE INDEX idx_reviews_barber ON reviews(barber_address);
CREATE INDEX idx_reviews_rating ON reviews(rating);
CREATE INDEX idx_reviews_created_at ON reviews(created_at DESC);
CREATE INDEX idx_reviews_is_flagged ON reviews(is_flagged) WHERE is_flagged = true;

-- Composite indexes for barber profile queries
CREATE INDEX idx_reviews_barber_rating ON reviews(barber_address, rating, created_at DESC);

-- Comments
COMMENT ON TABLE reviews IS 'Review/rating data cached from Aptos blockchain and IPFS. Synced hourly.';
COMMENT ON COLUMN reviews.comment_cid IS 'IPFS content identifier for review comment';
COMMENT ON COLUMN reviews.review_weight IS 'Weight applied based on reviewer credibility (0.2-1.2)';

-- ═══════════════════════════════════════════════════════════════════════
-- SYNC TRACKING
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE sync_status (
  id SERIAL PRIMARY KEY,
  table_name VARCHAR(50) UNIQUE NOT NULL,
  last_sync_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_blockchain_version BIGINT,  -- Last blockchain transaction version synced
  records_synced INTEGER DEFAULT 0,
  records_updated INTEGER DEFAULT 0,
  records_failed INTEGER DEFAULT 0,
  sync_duration_ms INTEGER DEFAULT 0,
  last_error TEXT,
  error_count INTEGER DEFAULT 0,
  next_sync_at TIMESTAMP,
  is_syncing BOOLEAN DEFAULT FALSE
);

-- Initialize sync status for each table
INSERT INTO sync_status (table_name, next_sync_at) VALUES 
    ('users', CURRENT_TIMESTAMP + INTERVAL '1 hour'),
    ('bookings', CURRENT_TIMESTAMP + INTERVAL '1 hour'),
    ('reviews', CURRENT_TIMESTAMP + INTERVAL '1 hour');

-- Comments
COMMENT ON TABLE sync_status IS 'Tracks blockchain→PostgreSQL sync health for each table';

-- ═══════════════════════════════════════════════════════════════════════
-- MATERIALIZED VIEWS (Performance Optimization from CampusKinect)
-- ═══════════════════════════════════════════════════════════════════════

-- Barber Statistics (Refreshed hourly with sync)
CREATE MATERIALIZED VIEW barber_stats AS
SELECT 
    u.legacy_wallet_address as barber_address,
    u.full_name,
    u.university_id,
    COUNT(DISTINCT b.id) as total_bookings,
    COUNT(DISTINCT CASE WHEN b.status = 2 THEN b.id END) as completed_bookings,
    COUNT(DISTINCT CASE WHEN b.status = 3 THEN b.id END) as cancelled_bookings,
    ROUND(
      COUNT(DISTINCT CASE WHEN b.status = 2 THEN b.id END)::DECIMAL / 
      NULLIF(COUNT(DISTINCT b.id), 0) * 100, 
      2
    ) as completion_rate,
    AVG(CASE WHEN r.rating IS NOT NULL THEN r.rating END) as avg_rating,
    COUNT(DISTINCT r.id) as total_reviews,
    SUM(CASE WHEN b.status = 2 THEN b.amount - b.platform_fee ELSE 0 END) as total_earnings_cents,
    MAX(b.completed_at) as last_booking_completed,
    MIN(b.created_at) as first_booking_date
FROM users u
LEFT JOIN bookings b ON u.legacy_wallet_address = b.barber_address
LEFT JOIN reviews r ON u.legacy_wallet_address = r.barber_address
WHERE u.role = 2
GROUP BY u.legacy_wallet_address, u.full_name, u.university_id;

-- Index on materialized view
CREATE INDEX idx_barber_stats_address ON barber_stats(barber_address);
CREATE INDEX idx_barber_stats_university ON barber_stats(university_id);
CREATE INDEX idx_barber_stats_rating ON barber_stats(avg_rating DESC NULLS LAST);

COMMENT ON MATERIALIZED VIEW barber_stats IS 'Aggregated barber statistics. Refreshed hourly with blockchain sync.';

-- Campus Statistics (Refreshed hourly)
CREATE MATERIALIZED VIEW campus_stats AS
SELECT 
    CASE 
      WHEN b.student_address LIKE '0x1%' THEN 'campus-1'
      WHEN b.student_address LIKE '0x2%' THEN 'campus-2'
      WHEN b.student_address LIKE '0x3%' THEN 'campus-3'
      ELSE 'unknown'
    END as campus_id,
    COUNT(DISTINCT b.id) as total_bookings,
    COUNT(DISTINCT CASE WHEN b.status = 2 THEN b.id END) as completed_bookings,
    COUNT(DISTINCT b.student_address) as unique_students,
    COUNT(DISTINCT b.barber_address) as unique_barbers,
    SUM(CASE WHEN b.status = 2 THEN b.amount ELSE 0 END) as total_volume_cents,
    SUM(CASE WHEN b.status = 2 THEN b.platform_fee ELSE 0 END) as platform_fees_cents,
    AVG(CASE WHEN b.status = 2 THEN b.amount END) as avg_booking_amount_cents,
    MAX(b.completed_at) as last_booking_completed,
    MIN(b.created_at) as first_booking_date
FROM bookings b
GROUP BY campus_id;

CREATE INDEX idx_campus_stats_campus_id ON campus_stats(campus_id);

COMMENT ON MATERIALIZED VIEW campus_stats IS 'Aggregated campus statistics. Refreshed hourly with blockchain sync.';

-- ═══════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════

-- Function to refresh all materialized views (called after sync)
CREATE OR REPLACE FUNCTION refresh_all_stats() RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY barber_stats;
  REFRESH MATERIALIZED VIEW CONCURRENTLY campus_stats;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_all_stats() IS 'Refreshes all materialized views. Call after blockchain sync.';

-- Function to get campus ID from student address (multi-tenancy helper)
CREATE OR REPLACE FUNCTION get_campus_id(student_addr VARCHAR) RETURNS VARCHAR AS $$
BEGIN
  RETURN CASE 
    WHEN student_addr LIKE '0x1%' THEN 'campus-1'
    WHEN student_addr LIKE '0x2%' THEN 'campus-2'
    WHEN student_addr LIKE '0x3%' THEN 'campus-3'
    ELSE 'unknown'
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to update user statistics (called by triggers)
CREATE OR REPLACE FUNCTION update_user_stats() RETURNS TRIGGER AS $$
BEGIN
  -- Update barber stats when booking completes
  IF (TG_OP = 'UPDATE' AND NEW.status = 2 AND OLD.status != 2) THEN
    UPDATE users SET
      total_bookings = total_bookings + 1,
      completed_bookings = completed_bookings + 1,
      completion_rate = (completed_bookings::DECIMAL / NULLIF(total_bookings, 0) * 100),
      updated_at = CURRENT_TIMESTAMP
    WHERE legacy_wallet_address = NEW.barber_address AND role = 2;
  END IF;
  
  -- Update barber stats when review is added
  IF (TG_TABLE_NAME = 'reviews' AND TG_OP = 'INSERT') THEN
    UPDATE users SET
      total_reviews = total_reviews + 1,
      average_rating = (
        SELECT AVG(rating) FROM reviews WHERE barber_address = NEW.barber_address
      ),
      updated_at = CURRENT_TIMESTAMP
    WHERE legacy_wallet_address = NEW.barber_address AND role = 2;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers to maintain user stats
CREATE TRIGGER trg_update_barber_stats_booking
AFTER UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION update_user_stats();

CREATE TRIGGER trg_update_barber_stats_review
AFTER INSERT ON reviews
FOR EACH ROW
EXECUTE FUNCTION update_user_stats();

-- ═══════════════════════════════════════════════════════════════════════
-- SEED DEFAULT UNIVERSITIES
-- ═══════════════════════════════════════════════════════════════════════

INSERT INTO universities (name, domain, city, state, student_count, created_at) VALUES
('California Polytechnic State University', 'calpoly.edu', 'San Luis Obispo', 'CA', 21000, NOW()),
('University of California, Santa Barbara', 'ucsb.edu', 'Santa Barbara', 'CA', 26000, NOW()),
('University of California, Los Angeles', 'ucla.edu', 'Los Angeles', 'CA', 45000, NOW());

-- ═══════════════════════════════════════════════════════════════════════
-- PERFORMANCE MONITORING VIEWS
-- ═══════════════════════════════════════════════════════════════════════

-- View for monitoring slow queries
CREATE OR REPLACE VIEW slow_queries AS
SELECT 
  query,
  calls,
  total_time,
  mean_time,
  max_time,
  stddev_time
FROM pg_stat_statements
WHERE mean_time > 100  -- Queries averaging >100ms
ORDER BY mean_time DESC
LIMIT 50;

COMMENT ON VIEW slow_queries IS 'Monitors queries averaging >100ms. Requires pg_stat_statements extension.';

-- View for monitoring table sizes
CREATE OR REPLACE VIEW table_sizes AS
SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

COMMENT ON VIEW table_sizes IS 'Monitors table and index sizes for capacity planning';

-- ═══════════════════════════════════════════════════════════════════════
-- VACUUM AND ANALYZE
-- ═══════════════════════════════════════════════════════════════════════

-- Analyze all tables for query planner
ANALYZE users;
ANALYZE bookings;
ANALYZE reviews;
ANALYZE sync_status;

-- ═══════════════════════════════════════════════════════════════════════
-- SUMMARY
-- ═══════════════════════════════════════════════════════════════════════

SELECT 
  '✅ CAMPUSCUTS POSTGRESQL CACHE INITIALIZED!' as status,
  (SELECT COUNT(*) FROM universities) as universities,
  'Ready for blockchain sync' as next_step;

-- Show table information
SELECT 
  table_name,
  pg_size_pretty(pg_total_relation_size(table_schema||'.'||table_name)) as size
FROM information_schema.tables
WHERE table_schema = 'public' 
  AND table_type = 'BASE TABLE'
ORDER BY pg_total_relation_size(table_schema||'.'||table_name) DESC;

