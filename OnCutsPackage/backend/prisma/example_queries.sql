-- CampusCuts Example Queries
-- Production-grade query patterns for common operations

-- ═══════════════════════════════════════════════════════════════
-- 1. BARBER DISCOVERY & RANKING
-- ═══════════════════════════════════════════════════════════════

-- Fetch ranked barbers for a campus (consumer discovery feed)
WITH ranked_barbers AS (
  SELECT 
    b.id,
    b.user_id,
    u.display_name,
    u.instagram_handle,
    u.avatar_url,
    b.specialties,
    b.current_min_price_usd_cents,
    b.current_max_price_usd_cents,
    b.avg_rating,
    b.total_reviews,
    b.bqs_score,
    br.rank_score,
    br.rank_position,
    br.breakdown as rank_breakdown,
    -- Availability density (for sorting)
    COUNT(a.id) FILTER (WHERE a.status = 'OPEN' AND a.start_time > NOW()) as open_slots
  FROM barbers b
  INNER JOIN users u ON b.user_id = u.id
  LEFT JOIN barber_rankings br ON b.id = br.barber_id
  LEFT JOIN availability a ON b.id = a.barber_id
  WHERE 
    b.campus_id = '00000000-0000-0000-0000-000000000001'
    AND b.is_active = true
    AND b.is_onboarded = true
    AND u.is_blocked = false
  GROUP BY b.id, u.id, br.rank_score, br.rank_position, br.breakdown
  ORDER BY br.rank_score DESC NULLS LAST, open_slots DESC
  LIMIT 20
)
SELECT * FROM ranked_barbers;

-- Get barber details with current pricing tier
SELECT 
  b.*,
  u.display_name,
  u.instagram_handle,
  bpm.multiplier as current_multiplier,
  bpm.reason as multiplier_reason,
  bqs.bqs_score,
  bqs.review_score_weighted,
  bqs.demand_score,
  bqs.price_justification_score,
  bqs.loyalty_score
FROM barbers b
INNER JOIN users u ON b.user_id = u.id
LEFT JOIN barber_pricing_multipliers bpm ON b.id = bpm.barber_id
  AND bpm.valid_from <= NOW() AND bpm.valid_until > NOW()
LEFT JOIN LATERAL (
  SELECT * FROM barber_quality_scores
  WHERE barber_id = b.id
  ORDER BY computed_at DESC
  LIMIT 1
) bqs ON true
WHERE b.id = '30000000-0000-0000-0000-000000000001';

-- ═══════════════════════════════════════════════════════════════
-- 2. LOCATION RESOLUTION (Fuzzy Matching)
-- ═══════════════════════════════════════════════════════════════

-- Resolve location alias to canonical location
-- Uses trigram similarity for fuzzy matching
CREATE OR REPLACE FUNCTION resolve_location(
  p_campus_id UUID,
  p_input_text VARCHAR
)
RETURNS TABLE (
  location_id UUID,
  canonical_name VARCHAR,
  match_type VARCHAR,
  similarity_score FLOAT
) AS $$
BEGIN
  RETURN QUERY
  -- First: Exact match on normalized name
  SELECT 
    l.id,
    l.name,
    'exact'::VARCHAR,
    1.0::FLOAT
  FROM locations l
  WHERE 
    l.campus_id = p_campus_id
    AND l.normalized_name = normalize_location_name(p_input_text)
  
  UNION ALL
  
  -- Second: Alias match
  SELECT DISTINCT
    l.id,
    l.name,
    'alias'::VARCHAR,
    0.95::FLOAT
  FROM locations l
  INNER JOIN location_aliases la ON l.id = la.location_id
  WHERE 
    l.campus_id = p_campus_id
    AND la.normalized_alias = normalize_location_name(p_input_text)
  
  UNION ALL
  
  -- Third: Fuzzy match using trigrams (similarity > 0.6)
  SELECT 
    l.id,
    l.name,
    'fuzzy'::VARCHAR,
    similarity(l.normalized_name, normalize_location_name(p_input_text))
  FROM locations l
  WHERE 
    l.campus_id = p_campus_id
    AND similarity(l.normalized_name, normalize_location_name(p_input_text)) > 0.6
  
  ORDER BY similarity_score DESC
  LIMIT 5;
END;
$$ LANGUAGE plpgsql;

-- Example usage
SELECT * FROM resolve_location(
  '00000000-0000-0000-0000-000000000001',
  'yak hall'
);

-- Search locations with autocomplete
SELECT 
  l.id,
  l.name,
  l.type,
  l.cohort,
  l.usage_count,
  l.is_verified,
  COALESCE(
    ARRAY_AGG(DISTINCT la.alias) FILTER (WHERE la.alias IS NOT NULL),
    '{}'
  ) as aliases,
  similarity(l.normalized_name, normalize_location_name($1)) as score
FROM locations l
LEFT JOIN location_aliases la ON l.id = la.location_id
WHERE 
  l.campus_id = $2
  AND (
    l.normalized_name % normalize_location_name($1)  -- Trigram match
    OR l.normalized_name ILIKE '%' || $1 || '%'      -- Substring match
  )
GROUP BY l.id
ORDER BY 
  l.is_verified DESC,
  similarity(l.normalized_name, normalize_location_name($1)) DESC,
  l.usage_count DESC
LIMIT 10;

-- ═══════════════════════════════════════════════════════════════
-- 3. AVAILABILITY MANAGEMENT
-- ═══════════════════════════════════════════════════════════════

-- Lock an availability slot (prevents double-booking)
UPDATE availability
SET 
  status = 'LOCKED',
  locked_at = NOW(),
  locked_by = $1,  -- Consumer user ID
  lock_expires_at = NOW() + INTERVAL '10 minutes',
  updated_at = NOW()
WHERE 
  id = $2
  AND status = 'OPEN'
  AND (locked_at IS NULL OR lock_expires_at < NOW())
RETURNING *;

-- Get barber's upcoming availability with location details
SELECT 
  a.id,
  a.start_time,
  a.end_time,
  a.price_usd_cents,
  a.service_types,
  a.status,
  l.name as location_name,
  l.type as location_type,
  l.address
FROM availability a
INNER JOIN locations l ON a.location_id = l.id
WHERE 
  a.barber_id = $1
  AND a.start_time >= NOW()
  AND a.status IN ('OPEN', 'LOCKED', 'BOOKED')
ORDER BY a.start_time ASC;

-- Find available barbers for specific time window and location
SELECT 
  b.id,
  u.display_name,
  b.avg_rating,
  b.total_reviews,
  b.current_min_price_usd_cents,
  b.current_max_price_usd_cents,
  a.price_usd_cents,
  a.start_time,
  a.end_time
FROM barbers b
INNER JOIN users u ON b.user_id = u.id
INNER JOIN availability a ON b.id = a.barber_id
WHERE 
  b.campus_id = $1
  AND a.location_id = $2
  AND a.start_time >= $3  -- Desired start time
  AND a.end_time <= $4    -- Desired end time
  AND a.status = 'OPEN'
  AND b.is_active = true
  AND 'FADE' = ANY(a.service_types)  -- Filter by service type
ORDER BY b.bqs_score DESC NULLS LAST;

-- ═══════════════════════════════════════════════════════════════
-- 4. BOOKING LIFECYCLE
-- ═══════════════════════════════════════════════════════════════

-- Create booking (with atomic availability update)
WITH locked_availability AS (
  UPDATE availability
  SET 
    status = 'BOOKED',
    updated_at = NOW()
  WHERE 
    id = $1
    AND status = 'LOCKED'
    AND locked_by = $2
    AND lock_expires_at > NOW()
  RETURNING *
)
INSERT INTO bookings (
  availability_id, barber_id, consumer_id, service_type,
  price_usd_cents, platform_fee_usd_cents, barber_earnings_usd_cents,
  status
)
SELECT 
  id, 
  barber_id, 
  $2,  -- consumer_id
  $3,  -- service_type
  price_usd_cents,
  ROUND(price_usd_cents * 0.05),  -- 5% platform fee
  ROUND(price_usd_cents * 0.95),  -- 95% to barber
  'PENDING'
FROM locked_availability
RETURNING *;

-- Get booking details with all related information
SELECT 
  bk.id,
  bk.status,
  bk.service_type,
  bk.price_usd_cents,
  bk.aptos_tx_hash,
  bk.requested_at,
  bk.paid_at,
  bk.completed_at,
  -- Barber info
  bb.id as barber_id,
  bu.display_name as barber_name,
  bu.instagram_handle as barber_instagram,
  -- Consumer info
  cu.display_name as consumer_name,
  -- Availability info
  av.start_time,
  av.end_time,
  -- Location info
  loc.name as location_name,
  loc.address as location_address,
  -- Review (if exists)
  rev.rating,
  rev.comment as review_comment
FROM bookings bk
INNER JOIN availability av ON bk.availability_id = av.id
INNER JOIN barbers bb ON bk.barber_id = bb.id
INNER JOIN users bu ON bb.user_id = bu.id
INNER JOIN users cu ON bk.consumer_id = cu.id
INNER JOIN locations loc ON av.location_id = loc.id
LEFT JOIN reviews rev ON bk.id = rev.booking_id
WHERE bk.id = $1;

-- Get barber's pending booking requests
SELECT 
  bk.id,
  bk.requested_at,
  cu.display_name as consumer_name,
  cu.avatar_url as consumer_avatar,
  av.start_time,
  av.end_time,
  loc.name as location_name,
  bk.price_usd_cents,
  bk.service_type,
  -- Consumer reliability score (if we have it)
  COUNT(cbk.id) FILTER (WHERE cbk.status = 'COMPLETED') as consumer_completed_bookings,
  COUNT(cbk.id) FILTER (WHERE cbk.status = 'CANCELLED') as consumer_cancelled_bookings
FROM bookings bk
INNER JOIN availability av ON bk.availability_id = av.id
INNER JOIN users cu ON bk.consumer_id = cu.id
INNER JOIN locations loc ON av.location_id = loc.id
LEFT JOIN bookings cbk ON cu.id = cbk.consumer_id AND cbk.created_at < bk.created_at
WHERE 
  bk.barber_id = $1
  AND bk.status = 'PENDING'
GROUP BY bk.id, cu.id, av.id, loc.id
ORDER BY bk.requested_at ASC;

-- ═══════════════════════════════════════════════════════════════
-- 5. REPUTATION & BQS COMPUTATION
-- ═══════════════════════════════════════════════════════════════

-- Compute current BQS components for a barber
WITH barber_stats AS (
  SELECT 
    b.id as barber_id,
    -- Review Score Weighted: avg_rating * log(1 + total_reviews)
    CASE 
      WHEN b.total_reviews > 0 THEN b.avg_rating * LN(1 + b.total_reviews) * 10
      ELSE 0
    END as review_score_weighted,
    -- Demand Score: % of slots filled in last 30 days
    COALESCE(
      100.0 * COUNT(a.id) FILTER (WHERE a.status IN ('BOOKED', 'COMPLETED')) / NULLIF(COUNT(a.id), 0),
      0
    ) as demand_score,
    -- Price Justification: % of bookings at current pricing tier
    COALESCE(
      100.0 * COUNT(bk.id) FILTER (WHERE bk.status = 'COMPLETED' AND bk.created_at > NOW() - INTERVAL '30 days') / 
              NULLIF(COUNT(bk.id) FILTER (WHERE bk.created_at > NOW() - INTERVAL '30 days'), 0),
      0
    ) as price_justification_score,
    -- Loyalty Score: % of repeat customers
    COALESCE(
      100.0 * COUNT(DISTINCT bk.consumer_id) FILTER (
        WHERE bk.consumer_id IN (
          SELECT consumer_id FROM bookings 
          WHERE barber_id = b.id AND status = 'COMPLETED'
          GROUP BY consumer_id HAVING COUNT(*) > 1
        )
      ) / NULLIF(COUNT(DISTINCT bk.consumer_id), 0),
      0
    ) as loyalty_score
  FROM barbers b
  LEFT JOIN availability a ON b.id = a.barber_id 
    AND a.created_at > NOW() - INTERVAL '30 days'
  LEFT JOIN bookings bk ON b.id = bk.barber_id
  WHERE b.id = $1
  GROUP BY b.id, b.avg_rating, b.total_reviews
)
SELECT 
  barber_id,
  review_score_weighted,
  demand_score,
  price_justification_score,
  loyalty_score,
  -- BQS = 0.45*R + 0.25*D + 0.15*P + 0.15*L
  compute_barber_bqs(
    review_score_weighted,
    demand_score,
    price_justification_score,
    loyalty_score
  ) as bqs_score,
  determine_pricing_multiplier(
    compute_barber_bqs(
      review_score_weighted,
      demand_score,
      price_justification_score,
      loyalty_score
    )
  ) as suggested_multiplier
FROM barber_stats;

-- Update barber reputation from blockchain data (idempotent)
UPDATE barbers b
SET 
  total_bookings = stats.total,
  completed_bookings = stats.completed,
  cancelled_bookings = stats.cancelled,
  avg_rating = stats.avg_rating,
  total_reviews = stats.review_count,
  updated_at = NOW()
FROM (
  SELECT 
    bk.barber_id,
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE bk.status = 'COMPLETED') as completed,
    COUNT(*) FILTER (WHERE bk.status = 'CANCELLED') as cancelled,
    COALESCE(AVG(rev.rating), 0) as avg_rating,
    COUNT(rev.id) as review_count
  FROM bookings bk
  LEFT JOIN reviews rev ON bk.id = rev.booking_id
  WHERE bk.barber_id = $1
  GROUP BY bk.barber_id
) stats
WHERE b.id = stats.barber_id;

-- ═══════════════════════════════════════════════════════════════
-- 6. MARKET INTELLIGENCE QUERIES
-- ═══════════════════════════════════════════════════════════════

-- Get real-time demand/supply ratio for surge pricing
SELECT 
  c.id as campus_id,
  c.name as campus_name,
  COUNT(DISTINCT a.barber_id) FILTER (
    WHERE a.status = 'OPEN' AND a.start_time BETWEEN NOW() AND NOW() + INTERVAL '4 hours'
  ) as available_barbers,
  COUNT(DISTINCT bk.consumer_id) FILTER (
    WHERE bk.status = 'PENDING' AND bk.requested_at > NOW() - INTERVAL '15 minutes'
  ) as active_consumers_requesting,
  CASE 
    WHEN COUNT(DISTINCT a.barber_id) FILTER (WHERE a.status = 'OPEN') = 0 THEN NULL
    ELSE COUNT(DISTINCT bk.consumer_id)::DECIMAL / 
         NULLIF(COUNT(DISTINCT a.barber_id) FILTER (WHERE a.status = 'OPEN'), 0)
  END as demand_supply_ratio,
  mf.surge_threshold
FROM campuses c
LEFT JOIN availability a ON c.id = a.barber_id
LEFT JOIN bookings bk ON c.id = (SELECT campus_id FROM barbers WHERE id = bk.barber_id)
LEFT JOIN market_factors mf ON c.id = mf.campus_id
WHERE c.id = $1
GROUP BY c.id, c.name, mf.surge_threshold;

-- Campus performance dashboard
SELECT 
  c.name as campus_name,
  COUNT(DISTINCT b.id) as total_barbers,
  COUNT(DISTINCT b.id) FILTER (WHERE b.is_active) as active_barbers,
  AVG(b.avg_rating) FILTER (WHERE b.total_reviews > 0) as avg_barber_rating,
  COUNT(bk.id) FILTER (WHERE bk.created_at > NOW() - INTERVAL '7 days') as bookings_last_7_days,
  COUNT(bk.id) FILTER (WHERE bk.status = 'COMPLETED' AND bk.completed_at > NOW() - INTERVAL '7 days') as completed_last_7_days,
  AVG(bk.price_usd_cents) FILTER (WHERE bk.created_at > NOW() - INTERVAL '7 days') as avg_booking_price,
  SUM(bk.platform_fee_usd_cents) FILTER (WHERE bk.status = 'COMPLETED' AND bk.completed_at > NOW() - INTERVAL '7 days') as platform_revenue_7d
FROM campuses c
LEFT JOIN barbers b ON c.id = b.campus_id
LEFT JOIN bookings bk ON b.id = bk.barber_id
WHERE c.id = $1
GROUP BY c.id, c.name;

-- ═══════════════════════════════════════════════════════════════
-- 7. ADMIN & MODERATION QUERIES
-- ═══════════════════════════════════════════════════════════════

-- Flag users with suspicious patterns (fraud detection)
SELECT 
  u.id,
  u.wallet_address,
  u.display_name,
  u.role,
  COUNT(DISTINCT bk.id) as total_bookings,
  COUNT(DISTINCT bk.id) FILTER (WHERE bk.status = 'CANCELLED' AND bk.cancelled_by = u.id) as user_cancelled_count,
  COUNT(DISTINCT bk.id) FILTER (WHERE bk.status = 'DISPUTED') as dispute_count,
  COUNT(DISTINCT rev.id) FILTER (WHERE rev.rating = 5 AND rev.created_at > NOW() - INTERVAL '24 hours') as five_star_24h,
  -- Suspicious indicators
  CASE 
    WHEN COUNT(DISTINCT bk.id) FILTER (WHERE bk.status = 'CANCELLED' AND bk.cancelled_by = u.id) > 3 THEN 'high_cancellation'
    WHEN COUNT(DISTINCT bk.id) FILTER (WHERE bk.status = 'DISPUTED') > 1 THEN 'multiple_disputes'
    WHEN COUNT(DISTINCT rev.id) FILTER (WHERE rev.rating = 5 AND rev.created_at > NOW() - INTERVAL '24 hours') > 5 THEN 'review_spam'
    ELSE NULL
  END as fraud_indicator
FROM users u
LEFT JOIN bookings bk ON u.id = CASE 
  WHEN u.role = 'CONSUMER' THEN bk.consumer_id
  WHEN u.role = 'BARBER' THEN (SELECT user_id FROM barbers WHERE id = bk.barber_id)
  END
LEFT JOIN reviews rev ON u.id = rev.consumer_id
WHERE u.campus_id = $1
GROUP BY u.id
HAVING 
  COUNT(DISTINCT bk.id) FILTER (WHERE bk.status = 'CANCELLED' AND bk.cancelled_by = u.id) > 3
  OR COUNT(DISTINCT bk.id) FILTER (WHERE bk.status = 'DISPUTED') > 1
  OR COUNT(DISTINCT rev.id) FILTER (WHERE rev.rating = 5 AND rev.created_at > NOW() - INTERVAL '24 hours') > 5;

