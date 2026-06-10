-- ============================================================================
-- CAMPUSCUTS STUDENT GRADING SYSTEM - DATABASE SCHEMA
-- ============================================================================
-- 
-- Two-sided marketplace requires grading both barbers AND students.
-- Students are scored even more strictly to ensure marketplace quality.
-- 
-- Student Score Components:
-- 1. Review Fairness (40% weight) - Are they fair or overly critical?
-- 2. Attendance Reliability (40% weight) - Do they show up?
-- 3. Platform Engagement (20% weight) - Are they active users?
-- 
-- Version: 1.0
-- Date: 2024-11-28
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. STUDENT METRICS (Aggregated Raw Data)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_metrics (
    id SERIAL PRIMARY KEY,
    student_id VARCHAR(255) NOT NULL,
    
    -- Time window for aggregation
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    period_date DATE NOT NULL,
    
    -- Booking metrics
    num_bookings INT NOT NULL DEFAULT 0,
    num_completed_bookings INT NOT NULL DEFAULT 0,
    num_canceled_bookings INT NOT NULL DEFAULT 0,
    num_no_shows INT NOT NULL DEFAULT 0,
    
    -- Attendance metrics
    attendance_rate DECIMAL(5,4) DEFAULT 0, -- 0-1
    no_show_rate DECIMAL(5,4) DEFAULT 0, -- 0-1
    cancellation_rate DECIMAL(5,4) DEFAULT 0, -- 0-1
    same_day_cancel_rate DECIMAL(5,4) DEFAULT 0, -- 0-1
    
    -- Review metrics (how they rate barbers)
    num_reviews_given INT DEFAULT 0,
    num_5_star_reviews INT DEFAULT 0,
    num_4_star_reviews INT DEFAULT 0,
    num_3_star_reviews INT DEFAULT 0,
    num_2_star_reviews INT DEFAULT 0,
    num_1_star_reviews INT DEFAULT 0,
    avg_rating_given DECIMAL(3,2), -- Average rating they give to barbers
    review_rate DECIMAL(5,4) DEFAULT 0, -- Fraction of bookings that get reviewed
    
    -- Engagement metrics
    num_unique_barbers INT DEFAULT 0, -- How many different barbers tried
    num_repeat_bookings INT DEFAULT 0, -- Bookings with same barber
    loyalty_rate DECIMAL(5,4) DEFAULT 0, -- 0-1
    avg_days_between_bookings DECIMAL(8,2),
    
    -- Financial metrics
    total_spent_cents INT DEFAULT 0,
    avg_tip_pct DECIMAL(5,2) DEFAULT 0,
    
    -- Complaint metrics
    num_complaints_filed INT DEFAULT 0,
    num_complaints_received INT DEFAULT 0, -- From barbers
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(student_id, period_date)
);

CREATE INDEX idx_student_metrics_student ON student_metrics(student_id);
CREATE INDEX idx_student_metrics_period ON student_metrics(period_date);

-- ----------------------------------------------------------------------------
-- 2. STUDENT SCORES (Computed Performance Scores)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_scores (
    id SERIAL PRIMARY KEY,
    student_id VARCHAR(255) NOT NULL,
    period_date DATE NOT NULL,
    
    -- Individual component scores (0-100)
    review_fairness_score DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    attendance_score DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    engagement_score DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    
    -- Weighted customer score (0-100)
    customer_score DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    
    -- Status flags
    is_new_student BOOLEAN DEFAULT false,
    total_lifetime_bookings INT DEFAULT 0,
    is_flagged BOOLEAN DEFAULT false, -- Flagged for poor behavior
    flag_reason TEXT,
    
    -- Score breakdown for transparency
    breakdown JSONB,
    
    -- Metadata
    computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(student_id, period_date),
    
    CONSTRAINT scores_range CHECK (
        review_fairness_score >= 0 AND review_fairness_score <= 100
        AND attendance_score >= 0 AND attendance_score <= 100
        AND engagement_score >= 0 AND engagement_score <= 100
        AND customer_score >= 0 AND customer_score <= 100
    )
);

CREATE INDEX idx_student_scores_student ON student_scores(student_id);
CREATE INDEX idx_student_scores_period ON student_scores(period_date);
CREATE INDEX idx_student_scores_flagged ON student_scores(is_flagged);
CREATE INDEX idx_student_scores_score ON student_scores(customer_score);

-- ----------------------------------------------------------------------------
-- 3. STUDENT GRADE LEVELS (Gamification)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_grade_levels (
    id SERIAL PRIMARY KEY,
    level_name VARCHAR(50) NOT NULL UNIQUE,
    min_score DECIMAL(5,2) NOT NULL,
    max_score DECIMAL(5,2) NOT NULL,
    badge_color VARCHAR(20),
    benefits TEXT[],
    restrictions TEXT[],
    sort_order INT NOT NULL,
    
    CONSTRAINT valid_score_range CHECK (min_score <= max_score)
);

-- Seed grade levels (stricter than barber grading)
INSERT INTO student_grade_levels (level_name, min_score, max_score, badge_color, benefits, restrictions, sort_order) VALUES
('VIP Customer', 95.00, 100.00, 'platinum', 
    ARRAY['Priority scheduling', '10% loyalty discount', 'Skip waitlists', 'Exclusive perks'],
    ARRAY[]::TEXT[],
    1),
('Excellent Customer', 85.00, 94.99, 'gold',
    ARRAY['Priority support', '5% loyalty discount', 'Enhanced visibility'],
    ARRAY[]::TEXT[],
    2),
('Good Customer', 70.00, 84.99, 'silver',
    ARRAY['Standard support', 'Full platform access'],
    ARRAY[]::TEXT[],
    3),
('Average Customer', 50.00, 69.99, 'bronze',
    ARRAY['Standard access'],
    ARRAY[]::TEXT[],
    4),
('Below Average', 30.00, 49.99, 'gray',
    ARRAY[]::TEXT[],
    ARRAY['Request-book only', 'Extended response time', 'Some barbers may decline']::TEXT[],
    5),
('Poor Customer', 0.00, 29.99, 'red',
    ARRAY[]::TEXT[],
    ARRAY['Request-book only', 'Most barbers may decline', 'Account review required', 'Higher deposit required']::TEXT[],
    6)
ON CONFLICT (level_name) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 4. STUDENT RESTRICTIONS (For poor behavior)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_restrictions (
    id SERIAL PRIMARY KEY,
    student_id VARCHAR(255) NOT NULL,
    
    restriction_type VARCHAR(50) NOT NULL,
    -- Types: 'requires_deposit', 'barber_approval_required',
    --        'booking_cooldown', 'account_suspended'
    
    reason TEXT NOT NULL,
    severity VARCHAR(20) NOT NULL, -- 'low', 'medium', 'high', 'critical'
    
    -- Restriction details
    is_active BOOLEAN DEFAULT true,
    starts_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP, -- NULL = permanent until manually removed
    
    -- Triggering data
    triggered_by_score DECIMAL(5,2),
    triggered_by_metric VARCHAR(100),
    
    -- Resolution
    resolved_at TIMESTAMP,
    resolved_by VARCHAR(255),
    resolution_notes TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_student_restrictions_student ON student_restrictions(student_id);
CREATE INDEX idx_student_restrictions_active ON student_restrictions(is_active);
CREATE INDEX idx_student_restrictions_type ON student_restrictions(restriction_type);

-- ----------------------------------------------------------------------------
-- 5. BARBER STUDENT BLOCKS (Barbers can block problem students)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS barber_student_blocks (
    id SERIAL PRIMARY KEY,
    barber_id VARCHAR(255) NOT NULL,
    student_id VARCHAR(255) NOT NULL,
    
    reason TEXT NOT NULL,
    block_type VARCHAR(50) DEFAULT 'permanent',
    -- Types: 'temporary', 'permanent', 'auto' (system-recommended)
    
    -- Details
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    
    -- Metadata
    triggered_by_incident VARCHAR(255), -- booking_id or incident_id
    notes TEXT,
    
    UNIQUE(barber_id, student_id)
);

CREATE INDEX idx_barber_student_blocks_barber ON barber_student_blocks(barber_id);
CREATE INDEX idx_barber_student_blocks_student ON barber_student_blocks(student_id);
CREATE INDEX idx_barber_student_blocks_active ON barber_student_blocks(is_active);

-- ----------------------------------------------------------------------------
-- 6. STUDENT GRADING CONFIG (Separate from barber pricing config)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_grading_config (
    id SERIAL PRIMARY KEY,
    version INT NOT NULL DEFAULT 1,
    
    -- Score weights (total = 1.0)
    review_fairness_weight DECIMAL(3,2) NOT NULL DEFAULT 0.40,
    attendance_weight DECIMAL(3,2) NOT NULL DEFAULT 0.40,
    engagement_weight DECIMAL(3,2) NOT NULL DEFAULT 0.20,
    
    -- Review fairness sub-weights
    avg_rating_weight DECIMAL(3,2) NOT NULL DEFAULT 0.60,
    review_rate_weight DECIMAL(3,2) NOT NULL DEFAULT 0.40,
    
    -- Attendance sub-weights
    show_up_weight DECIMAL(3,2) NOT NULL DEFAULT 0.70,
    no_cancel_weight DECIMAL(3,2) NOT NULL DEFAULT 0.30,
    
    -- Thresholds for penalties
    harsh_reviewer_threshold DECIMAL(3,2) DEFAULT 3.50, -- Avg rating < 3.5 = harsh
    excessive_no_show_threshold DECIMAL(5,4) DEFAULT 0.15, -- >15% no-shows
    excessive_cancel_threshold DECIMAL(5,4) DEFAULT 0.25, -- >25% cancellations
    
    -- New student policy
    new_student_booking_threshold INT NOT NULL DEFAULT 3,
    
    -- Auto-flag thresholds
    auto_flag_score_threshold DECIMAL(5,2) DEFAULT 30.00,
    auto_restrict_score_threshold DECIMAL(5,2) DEFAULT 20.00,
    
    -- Metadata
    updated_by VARCHAR(255),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT weights_sum_one CHECK (
        review_fairness_weight + attendance_weight + engagement_weight = 1.00
    )
);

-- Insert default configuration
INSERT INTO student_grading_config (version) VALUES (1);

-- ----------------------------------------------------------------------------
-- 7. STUDENT GRADING AUDIT LOG
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_grading_audit (
    id SERIAL PRIMARY KEY,
    student_id VARCHAR(255) NOT NULL,
    
    action VARCHAR(100) NOT NULL,
    -- Actions: 'score_calculated', 'flagged', 'restricted', 'unrestricted', 
    --          'blocked_by_barber', 'score_improved'
    
    old_score DECIMAL(5,2),
    new_score DECIMAL(5,2),
    
    details JSONB,
    triggered_by VARCHAR(255), -- 'system', 'admin', 'barber'
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_student_grading_audit_student ON student_grading_audit(student_id);
CREATE INDEX idx_student_grading_audit_action ON student_grading_audit(action);
CREATE INDEX idx_student_grading_audit_created ON student_grading_audit(created_at);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get student's current score
CREATE OR REPLACE FUNCTION get_student_current_score(p_student_id VARCHAR(255))
RETURNS DECIMAL(5,2) AS $$
BEGIN
    RETURN (
        SELECT customer_score 
        FROM student_scores 
        WHERE student_id = p_student_id 
        ORDER BY period_date DESC 
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql;

-- Get student's grade level
CREATE OR REPLACE FUNCTION get_student_grade_level(p_student_id VARCHAR(255))
RETURNS VARCHAR(50) AS $$
DECLARE
    v_score DECIMAL(5,2);
BEGIN
    v_score := get_student_current_score(p_student_id);
    
    IF v_score IS NULL THEN
        RETURN 'New Customer';
    END IF;
    
    RETURN (
        SELECT level_name
        FROM student_grade_levels
        WHERE v_score >= min_score AND v_score <= max_score
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql;

-- Check if student has active restrictions
CREATE OR REPLACE FUNCTION student_has_active_restrictions(p_student_id VARCHAR(255))
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM student_restrictions
        WHERE student_id = p_student_id
        AND is_active = true
        AND (expires_at IS NULL OR expires_at > NOW())
    );
END;
$$ LANGUAGE plpgsql;

-- Check if student is blocked by barber
CREATE OR REPLACE FUNCTION is_student_blocked_by_barber(
    p_student_id VARCHAR(255),
    p_barber_id VARCHAR(255)
)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM barber_student_blocks
        WHERE student_id = p_student_id
        AND barber_id = p_barber_id
        AND is_active = true
        AND (expires_at IS NULL OR expires_at > NOW())
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS FOR REPORTING
-- ============================================================================

-- View: Current student scores with grade levels
CREATE OR REPLACE VIEW v_student_scores_current AS
SELECT 
    u.id as student_id,
    u.name as student_name,
    u.email as student_email,
    u.campus_id,
    c.name as campus_name,
    ss.period_date,
    ss.customer_score,
    ss.review_fairness_score,
    ss.attendance_score,
    ss.engagement_score,
    ss.is_new_student,
    ss.total_lifetime_bookings,
    ss.is_flagged,
    ss.flag_reason,
    get_student_grade_level(u.id) as grade_level,
    student_has_active_restrictions(u.id) as has_restrictions
FROM users u
LEFT JOIN campuses c ON u.campus_id = c.id
LEFT JOIN LATERAL (
    SELECT * FROM student_scores 
    WHERE student_id = u.id 
    ORDER BY period_date DESC 
    LIMIT 1
) ss ON true
WHERE u.role = 'student';

-- View: Student behavior summary
CREATE OR REPLACE VIEW v_student_behavior_summary AS
SELECT 
    student_id,
    SUM(num_bookings) as total_bookings,
    SUM(num_completed_bookings) as completed_bookings,
    SUM(num_no_shows) as total_no_shows,
    SUM(num_canceled_bookings) as total_cancellations,
    AVG(attendance_rate) as avg_attendance_rate,
    AVG(avg_rating_given) as avg_rating_given,
    COUNT(DISTINCT period_date) as periods_tracked
FROM student_metrics
GROUP BY student_id;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-update timestamp
CREATE TRIGGER update_student_restrictions_updated_at
    BEFORE UPDATE ON student_restrictions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

