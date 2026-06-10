-- CampusCuts Seed Data
-- Example campus: Cal Poly SLO
-- Production-grade sample data for development and testing

-- ═══════════════════════════════════════════════════════════════
-- 1. CAMPUS
-- ═══════════════════════════════════════════════════════════════

INSERT INTO "campuses" (
  "id",
  "slug",
  "name",
  "city",
  "state",
  "timezone",
  "base_price_usd_cents",
  "average_price_usd_cents",
  "premium_ceiling_usd_cents",
  "platform_fee_percent"
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  'calpoly-slo',
  'California Polytechnic State University',
  'San Luis Obispo',
  'CA',
  'America/Los_Angeles',
  2200,  -- $22
  3500,  -- $35
  4500,  -- $45
  5.00
);

-- Market factors for Cal Poly (medium-sized market)
INSERT INTO "market_factors" ("campus_id", "demand_normalization_factor", "review_weight_adjustment", "competition_intensity_score", "surge_threshold")
VALUES ('00000000-0000-0000-0000-000000000001', 1.00, 1.10, 0.75, 2.00);

-- ═══════════════════════════════════════════════════════════════
-- 2. LOCATIONS (Crowd-Sourced)
-- ═══════════════════════════════════════════════════════════════

-- Canonical locations (AI-normalized)
INSERT INTO "locations" ("id", "campus_id", "name", "normalized_name", "type", "cohort", "usage_count", "confidence", "is_verified") VALUES
('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Yakʔitʸutʸu Hall', 'yak it yu t yu hall', 'DORM', 'FRESHMAN_HOUSING', 45, 0.95, true),
('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Cerro Vista Apartments', 'cerro vista apartments', 'APARTMENT', 'UPPERCLASS_HOUSING', 78, 0.98, true),
('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Kennedy Library', 'kennedy library', 'LIBRARY', 'CAMPUS_CENTER', 23, 0.90, true),
('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'Recreation Center', 'recreation center', 'GYM', 'ATHLETIC_FACILITY', 12, 0.85, true),
('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'Poly Canyon Village', 'poly canyon village', 'APARTMENT', 'UPPERCLASS_HOUSING', 62, 0.97, true),
('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001', 'Mustang Station Apartments', 'mustang station apartments', 'OFF_CAMPUS', 'OFF_CAMPUS_POPULAR', 34, 0.88, true),
('10000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000001', 'Campus Market', 'campus market', 'COMMONS', 'CAMPUS_CENTER', 8, 0.75, false),
('10000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000001', 'Mott Athletic Center', 'mott athletic center', 'GYM', 'ATHLETIC_FACILITY', 5, 0.70, false);

-- Location aliases (user-submitted variations)
INSERT INTO "location_aliases" ("location_id", "alias", "normalized_alias", "is_ai_generated", "usage_count") VALUES
('10000000-0000-0000-0000-000000000001', 'Yak', 'yak', false, 23),
('10000000-0000-0000-0000-000000000001', 'Yak Hall', 'yak hall', true, 15),
('10000000-0000-0000-0000-000000000002', 'CV', 'cv', false, 41),
('10000000-0000-0000-0000-000000000002', 'Cerro Vista', 'cerro vista', true, 37),
('10000000-0000-0000-0000-000000000003', 'Kennedy Lib', 'kennedy lib', false, 12),
('10000000-0000-0000-0000-000000000005', 'PCV', 'pcv', false, 58),
('10000000-0000-0000-0000-000000000005', 'Poly Canyon', 'poly canyon', true, 4),
('10000000-0000-0000-0000-000000000006', 'Mustang', 'mustang', false, 19);

-- ═══════════════════════════════════════════════════════════════
-- 3. USERS (Wallet-First Identity)
-- ═══════════════════════════════════════════════════════════════

-- Consumers
INSERT INTO "users" ("id", "wallet_address", "role", "campus_id", "display_name", "is_verified") VALUES
('20000000-0000-0000-0000-000000000001', '0x1a2b3c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567890', 'CONSUMER', '00000000-0000-0000-0000-000000000001', 'Alex Thompson', true),
('20000000-0000-0000-0000-000000000002', '0x2b3c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567890ab', 'CONSUMER', '00000000-0000-0000-0000-000000000001', 'Jordan Lee', true),
('20000000-0000-0000-0000-000000000003', '0x3c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567890abcd', 'CONSUMER', '00000000-0000-0000-0000-000000000001', 'Sam Rivera', false);

-- Barbers
INSERT INTO "users" ("id", "wallet_address", "role", "campus_id", "display_name", "instagram_handle", "is_verified") VALUES
('20000000-0000-0000-0000-000000000101', '0xb1000000000000000000000000000000000000000000000000000000000001', 'BARBER', '00000000-0000-0000-0000-000000000001', 'Marcus Johnson', 'marcuscuts_slo', true),
('20000000-0000-0000-0000-000000000102', '0xb2000000000000000000000000000000000000000000000000000000000002', 'BARBER', '00000000-0000-0000-0000-000000000001', 'David Kim', 'davidkim_fades', true),
('20000000-0000-0000-0000-000000000103', '0xb3000000000000000000000000000000000000000000000000000000000003', 'BARBER', '00000000-0000-0000-0000-000000000001', 'Carlos Martinez', 'carlosthebarber', true),
('20000000-0000-0000-0000-000000000104', '0xb4000000000000000000000000000000000000000000000000000000000004', 'BARBER', '00000000-0000-0000-0000-000000000001', 'Tyler Brooks', NULL, false);

-- Admin
INSERT INTO "users" ("id", "wallet_address", "role", "campus_id", "display_name", "is_verified") VALUES
('20000000-0000-0000-0000-000000000201', '0xa1000000000000000000000000000000000000000000000000000000000001', 'ADMIN', '00000000-0000-0000-0000-000000000001', 'Admin User', true);

-- ═══════════════════════════════════════════════════════════════
-- 4. BARBERS (Profiles)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO "barbers" (
  "id", "user_id", "campus_id", "bio", "specialties",
  "current_min_price_usd_cents", "current_max_price_usd_cents",
  "total_bookings", "completed_bookings", "cancelled_bookings",
  "avg_rating", "total_reviews", "reliability_score",
  "bqs_score", "pricing_multiplier", "is_active", "is_onboarded"
) VALUES
(
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000001',
  'Professional barber with 8 years experience. Specializing in modern fades and classic cuts.',
  ARRAY['FADE', 'HAIRCUT', 'LINEUP']::ServiceType[],
  2200, 6075,  -- $22 to $60.75 (1.35x multiplier)
  127, 119, 3,
  4.8, 98,
  95.5,
  88.5, 1.35, true, true
),
(
  '30000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000102',
  '00000000-0000-0000-0000-000000000001',
  'Creative stylist focused on precision cuts and customer satisfaction.',
  ARRAY['HAIRCUT', 'FADE', 'BEARD_TRIM', 'FULL_SERVICE']::ServiceType[],
  2200, 5625,  -- $22 to $56.25 (1.25x multiplier)
  89, 84, 2,
  4.7, 71,
  92.3,
  83.2, 1.25, true, true
),
(
  '30000000-0000-0000-0000-000000000003',
  '20000000-0000-0000-0000-000000000103',
  '00000000-0000-0000-0000-000000000001',
  'Experienced in all hair types. Bilingual (English/Spanish).',
  ARRAY['HAIRCUT', 'BEARD_TRIM', 'FADE', 'COLOR']::ServiceType[],
  2200, 4950,  -- $22 to $49.50 (1.10x multiplier)
  56, 52, 1,
  4.6, 48,
  88.7,
  72.1, 1.10, true, true
),
(
  '30000000-0000-0000-0000-000000000004',
  '20000000-0000-0000-0000-000000000104',
  '00000000-0000-0000-0000-000000000001',
  'New to campus, eager to build clientele!',
  ARRAY['HAIRCUT', 'FADE']::ServiceType[],
  2200, 4500,  -- $22 to $45 (1.0x multiplier - new barber)
  8, 7, 0,
  4.9, 5,
  NULL,
  NULL, 1.00, true, true
);

-- ═══════════════════════════════════════════════════════════════
-- 5. AVAILABILITY (Sample Slots)
-- ═══════════════════════════════════════════════════════════════

-- Marcus Johnson (high-demand barber) - Friday slots
INSERT INTO "availability" (
  "barber_id", "location_id", "start_time", "end_time", 
  "price_usd_cents", "service_types", "status"
) VALUES
('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 
 NOW() + INTERVAL '2 days' + INTERVAL '14 hours', NOW() + INTERVAL '2 days' + INTERVAL '14.5 hours',
 5400, ARRAY['FADE']::ServiceType[], 'OPEN'),
('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002',
 NOW() + INTERVAL '2 days' + INTERVAL '15 hours', NOW() + INTERVAL '2 days' + INTERVAL '15.5 hours',
 5400, ARRAY['FADE']::ServiceType[], 'OPEN'),
('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002',
 NOW() + INTERVAL '2 days' + INTERVAL '16 hours', NOW() + INTERVAL '2 days' + INTERVAL '16.5 hours',
 5400, ARRAY['FADE']::ServiceType[], 'BOOKED');

-- David Kim - Saturday slots
INSERT INTO "availability" (
  "barber_id", "location_id", "start_time", "end_time",
  "price_usd_cents", "service_types", "status"
) VALUES
('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000005',
 NOW() + INTERVAL '3 days' + INTERVAL '10 hours', NOW() + INTERVAL '3 days' + INTERVAL '10.5 hours',
 4500, ARRAY['HAIRCUT', 'FADE']::ServiceType[], 'OPEN'),
('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000005',
 NOW() + INTERVAL '3 days' + INTERVAL '11 hours', NOW() + INTERVAL '3 days' + INTERVAL '11.5 hours',
 4500, ARRAY['HAIRCUT', 'FADE']::ServiceType[], 'OPEN');

-- Tyler Brooks (new barber) - Multiple slots available
INSERT INTO "availability" (
  "barber_id", "location_id", "start_time", "end_time",
  "price_usd_cents", "service_types", "status"
) VALUES
('30000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001',
 NOW() + INTERVAL '1 day' + INTERVAL '13 hours', NOW() + INTERVAL '1 day' + INTERVAL '13.5 hours',
 3200, ARRAY['HAIRCUT']::ServiceType[], 'OPEN'),
('30000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001',
 NOW() + INTERVAL '1 day' + INTERVAL '14 hours', NOW() + INTERVAL '1 day' + INTERVAL '14.5 hours',
 3200, ARRAY['HAIRCUT']::ServiceType[], 'OPEN'),
('30000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001',
 NOW() + INTERVAL '1 day' + INTERVAL '15 hours', NOW() + INTERVAL '1 day' + INTERVAL '15.5 hours',
 3200, ARRAY['HAIRCUT']::ServiceType[], 'OPEN');

-- ═══════════════════════════════════════════════════════════════
-- 6. SAMPLE BOOKINGS (Historical)
-- ═══════════════════════════════════════════════════════════════

-- Create past availability slot for completed booking
INSERT INTO "availability" (
  "id", "barber_id", "location_id", "start_time", "end_time",
  "price_usd_cents", "service_types", "status"
) VALUES (
  '40000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  NOW() - INTERVAL '7 days' + INTERVAL '14 hours',
  NOW() - INTERVAL '7 days' + INTERVAL '14.5 hours',
  5400, ARRAY['FADE']::ServiceType[], 'COMPLETED'
);

-- Completed booking with review
INSERT INTO "bookings" (
  "id", "availability_id", "barber_id", "consumer_id", "service_type",
  "price_usd_cents", "platform_fee_usd_cents", "barber_earnings_usd_cents",
  "aptos_tx_hash", "status",
  "requested_at", "accepted_at", "paid_at", "completed_at"
) VALUES (
  '50000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'FADE',
  5400, 270, 5130,
  '0xf1000000000000000000000000000000000000000000000000000000000001',
  'COMPLETED',
  NOW() - INTERVAL '8 days',
  NOW() - INTERVAL '7 days' + INTERVAL '1 hour',
  NOW() - INTERVAL '7 days' + INTERVAL '2 hours',
  NOW() - INTERVAL '7 days' + INTERVAL '14.75 hours'
);

-- Review for the booking
INSERT INTO "reviews" (
  "booking_id", "barber_id", "consumer_id", "rating", "comment",
  "sentiment_score", "aptos_tx_hash"
) VALUES (
  '50000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  5,
  'Excellent fade! Marcus is a true professional. Will definitely book again.',
  0.92,
  '0xf2000000000000000000000000000000000000000000000000000000000002'
);

-- ═══════════════════════════════════════════════════════════════
-- 7. QUALITY SCORES & RANKINGS (Historical Snapshots)
-- ═══════════════════════════════════════════════════════════════

-- BQS scores for top barbers
INSERT INTO "barber_quality_scores" (
  "barber_id", "review_score_weighted", "demand_score", 
  "price_justification_score", "loyalty_score", "bqs_score",
  "data_window"
) VALUES
('30000000-0000-0000-0000-000000000001', 92.5, 88.3, 85.0, 88.2, 88.5, 'last_30_days'),
('30000000-0000-0000-0000-000000000002', 85.2, 82.5, 80.0, 84.8, 83.2, 'last_30_days'),
('30000000-0000-0000-0000-000000000003', 78.5, 68.7, 72.0, 69.5, 72.1, 'last_30_days');

-- Current pricing multipliers
INSERT INTO "barber_pricing_multipliers" (
  "barber_id", "multiplier", "bqs_score", "reason",
  "valid_from", "valid_until"
) VALUES
('30000000-0000-0000-0000-000000000001', 1.35, 88.5, 'BQS 80-90: Premium tier', NOW() - INTERVAL '1 day', NOW() + INTERVAL '6 days'),
('30000000-0000-0000-0000-000000000002', 1.25, 83.2, 'BQS 80-90: Premium tier', NOW() - INTERVAL '1 day', NOW() + INTERVAL '6 days'),
('30000000-0000-0000-0000-000000000003', 1.10, 72.1, 'BQS 60-80: Mid tier', NOW() - INTERVAL '1 day', NOW() + INTERVAL '6 days'),
('30000000-0000-0000-0000-000000000004', 1.00, NULL, 'New barber: Base pricing', NOW() - INTERVAL '1 day', NOW() + INTERVAL '6 days');

-- Campus rankings (computed today)
INSERT INTO "barber_rankings" (
  "barber_id", "campus_id", "rank_score", "breakdown",
  "rank_position", "total_barbers", "valid_until"
) VALUES
('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 
 91.25, '{"bqs": 88.5, "availability": 0.85, "proximity": 1.0}'::jsonb, 1, 4, NOW() + INTERVAL '1 hour'),
('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
 86.40, '{"bqs": 83.2, "availability": 0.90, "proximity": 1.0}'::jsonb, 2, 4, NOW() + INTERVAL '1 hour'),
('30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
 74.85, '{"bqs": 72.1, "availability": 0.75, "proximity": 1.0}'::jsonb, 3, 4, NOW() + INTERVAL '1 hour'),
('30000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001',
 68.00, '{"bqs": 50.0, "availability": 0.95, "proximity": 1.0}'::jsonb, 4, 4, NOW() + INTERVAL '1 hour');

-- ═══════════════════════════════════════════════════════════════
-- 8. AI ANNOTATIONS (Examples)
-- ═══════════════════════════════════════════════════════════════

-- Location normalization annotation
INSERT INTO "ai_annotations" (
  "entity_type", "entity_id", "model_type", "model_name",
  "output", "confidence"
) VALUES (
  'location', '10000000-0000-0000-0000-000000000001',
  'LOCATION_NORMALIZATION', 'gpt-4-turbo',
  '{"canonical_name": "Yakʔitʸutʸu Hall", "aliases": ["Yak", "Yak Hall"], "category": "DORM", "cohort": "FRESHMAN_HOUSING"}'::jsonb,
  0.95
);

-- Review sentiment analysis
INSERT INTO "ai_annotations" (
  "entity_type", "entity_id", "model_type", "model_name",
  "output", "confidence"
) VALUES (
  'review', (SELECT "id" FROM "reviews" ORDER BY "created_at" DESC LIMIT 1),
  'SENTIMENT_ANALYSIS', 'gpt-4-turbo',
  '{"sentiment": "positive", "score": 0.92, "keywords": ["excellent", "professional", "definitely"], "concerns": []}'::jsonb,
  0.92
);

-- ═══════════════════════════════════════════════════════════════
-- 9. MARKET STATS (Recent Activity)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO "market_stats" ("campus_id", "stat_type", "value", "timestamp") VALUES
('00000000-0000-0000-0000-000000000001', 'active_barbers', 4, NOW() - INTERVAL '1 hour'),
('00000000-0000-0000-0000-000000000001', 'demand_supply_ratio', 1.35, NOW() - INTERVAL '1 hour'),
('00000000-0000-0000-0000-000000000001', 'avg_price_usd_cents', 4275, NOW() - INTERVAL '1 hour'),
('00000000-0000-0000-0000-000000000001', 'bookings_last_24h', 12, NOW() - INTERVAL '1 hour');

COMMENT ON TABLE campuses IS 'Campus entities with market configuration';
COMMENT ON TABLE locations IS 'Crowd-sourced, AI-normalized service locations';
COMMENT ON TABLE barbers IS 'Barber profiles with cached blockchain reputation';
COMMENT ON TABLE bookings IS 'Booking records anchored to blockchain transactions';
COMMENT ON TABLE reviews IS 'Reviews with AI sentiment analysis (non-authoritative)';
COMMENT ON TABLE barber_rankings IS 'Capitalistic marketplace rankings (recomputed regularly)';
COMMENT ON TABLE ai_annotations IS 'AI-generated annotations (advisory only, not authoritative)';

