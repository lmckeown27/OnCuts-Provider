-- CampusCuts PostgreSQL Cache Layer
-- 
-- IMPORTANT: This is a CACHE, not the source of truth!
-- Source of truth: Aptos blockchain
-- This database is synced hourly from blockchain
--
-- Why PostgreSQL?
-- - Fast complex queries (analytics, pricing, admin dashboards)
-- - 50-70% cheaper than blockchain indexer services
-- - 90% cache hit rate = lower gas costs

-- Enable PostGIS extension for geospatial queries
CREATE EXTENSION IF NOT EXISTS postgis;

-- Users table (cached from blockchain)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    legacy_wallet_address VARCHAR(66) UNIQUE NOT NULL,
    email VARCHAR(255),
    full_name VARCHAR(255),
    role INTEGER NOT NULL DEFAULT 1, -- 1=student, 2=barber
    balance BIGINT NOT NULL DEFAULT 0,
    locked_balance BIGINT NOT NULL DEFAULT 0,
    profile_picture_cid VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_legacy_wallet_address ON users(legacy_wallet_address);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);

-- Bookings table (cached from blockchain)
CREATE TABLE IF NOT EXISTS bookings (
    id SERIAL PRIMARY KEY,
    blockchain_id BIGINT UNIQUE NOT NULL, -- ID from blockchain
    student_address VARCHAR(66) NOT NULL,
    barber_address VARCHAR(66) NOT NULL,
    amount BIGINT NOT NULL,
    platform_fee BIGINT NOT NULL DEFAULT 0,
    scheduled_time TIMESTAMP NOT NULL,
    status INTEGER NOT NULL DEFAULT 0, -- 0=pending, 1=confirmed, 2=completed, 3=cancelled
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP,
    cancelled_at TIMESTAMP,
    synced_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bookings_blockchain_id ON bookings(blockchain_id);
CREATE INDEX idx_bookings_student ON bookings(student_address);
CREATE INDEX idx_bookings_barber ON bookings(barber_address);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_scheduled_time ON bookings(scheduled_time);

-- Reviews table (cached from blockchain)
CREATE TABLE IF NOT EXISTS reviews (
    id SERIAL PRIMARY KEY,
    blockchain_id BIGINT UNIQUE NOT NULL,
    booking_id BIGINT NOT NULL,
    reviewer_address VARCHAR(66) NOT NULL,
    barber_address VARCHAR(66) NOT NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment_cid VARCHAR(255), -- IPFS CID for comment
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reviews_blockchain_id ON reviews(blockchain_id);
CREATE INDEX idx_reviews_booking_id ON reviews(booking_id);
CREATE INDEX idx_reviews_barber ON reviews(barber_address);
CREATE INDEX idx_reviews_rating ON reviews(rating);

-- Sync status table (tracks last sync time)
CREATE TABLE IF NOT EXISTS sync_status (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(50) UNIQUE NOT NULL,
    last_sync_time TIMESTAMP NOT NULL DEFAULT NOW(),
    last_blockchain_height BIGINT,
    records_synced INTEGER DEFAULT 0,
    sync_duration_ms INTEGER DEFAULT 0
);

INSERT INTO sync_status (table_name) VALUES 
    ('users'),
    ('bookings'),
    ('reviews')
ON CONFLICT (table_name) DO NOTHING;

-- Add comments for documentation
COMMENT ON TABLE users IS 'Cached user data from Aptos blockchain. Synced hourly.';
COMMENT ON TABLE bookings IS 'Cached booking data from Aptos blockchain. Synced hourly.';
COMMENT ON TABLE reviews IS 'Cached review data from Aptos blockchain. Synced hourly.';
COMMENT ON TABLE sync_status IS 'Tracks blockchain sync status for each table.';

-- Create a view for barber statistics (commonly queried)
CREATE OR REPLACE VIEW barber_stats AS
SELECT 
    b.barber_address,
    u.full_name,
    COUNT(DISTINCT bk.id) as total_bookings,
    COUNT(DISTINCT CASE WHEN bk.status = 2 THEN bk.id END) as completed_bookings,
    AVG(CASE WHEN r.rating IS NOT NULL THEN r.rating END) as avg_rating,
    COUNT(DISTINCT r.id) as total_reviews,
    SUM(CASE WHEN bk.status = 2 THEN bk.amount ELSE 0 END) as total_earnings
FROM users u
LEFT JOIN bookings bk ON u.legacy_wallet_address = bk.barber_address
LEFT JOIN reviews r ON u.legacy_wallet_address = r.barber_address
WHERE u.role = 2
GROUP BY b.barber_address, u.full_name;

COMMENT ON VIEW barber_stats IS 'Aggregated barber statistics for fast queries. Updated hourly via sync.';

