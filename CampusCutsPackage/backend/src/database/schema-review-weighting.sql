-- ============================================================================
-- CAMPUSCUTS REVIEW WEIGHTING SYSTEM
-- ============================================================================
-- 
-- Reviews from low-score students are weighted less (or not at all) to protect
-- barbers from unfair reviews by problem customers.
-- 
-- Review Weight Formula:
-- - VIP Students (95-100): 1.2x weight (trusted reviewers)
-- - Excellent Students (85-94): 1.0x weight (normal)
-- - Good Students (70-84): 0.8x weight (slightly reduced)
-- - Average Students (50-69): 0.5x weight (heavily reduced)
-- - Below Average (30-49): 0.2x weight (minimal impact)
-- - Poor Students (0-29): 0.0x weight (IGNORED completely)
-- 
-- Version: 1.0
-- Date: 2024-11-28
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ADD REVIEW WEIGHT TRACKING TO REVIEWS TABLE
-- ----------------------------------------------------------------------------

-- Add columns to existing reviews table
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS reviewer_score DECIMAL(5,2);
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS review_weight DECIMAL(3,2) DEFAULT 1.00;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS is_weighted BOOLEAN DEFAULT false;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS weight_reason TEXT;

-- Create index for weighted review queries
CREATE INDEX IF NOT EXISTS idx_reviews_weighted ON reviews(barber_id, is_weighted);
CREATE INDEX IF NOT EXISTS idx_reviews_weight ON reviews(review_weight);

-- ----------------------------------------------------------------------------
-- 2. REVIEW WEIGHTING CONFIGURATION
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS review_weighting_config (
    id SERIAL PRIMARY KEY,
    version INT NOT NULL DEFAULT 1,
    
    -- Weight multipliers by student grade
    vip_customer_weight DECIMAL(3,2) NOT NULL DEFAULT 1.20,      -- 95-100: Trusted reviewers
    excellent_customer_weight DECIMAL(3,2) NOT NULL DEFAULT 1.00, -- 85-94: Normal weight
    good_customer_weight DECIMAL(3,2) NOT NULL DEFAULT 0.80,     -- 70-84: Slight reduction
    average_customer_weight DECIMAL(3,2) NOT NULL DEFAULT 0.50,  -- 50-69: Heavy reduction
    below_avg_customer_weight DECIMAL(3,2) NOT NULL DEFAULT 0.20, -- 30-49: Minimal impact
    poor_customer_weight DECIMAL(3,2) NOT NULL DEFAULT 0.00,     -- 0-29: IGNORED
    
    -- New/unscored customer default weight
    new_customer_default_weight DECIMAL(3,2) NOT NULL DEFAULT 0.70,
    
    -- Thresholds for additional penalties
    harsh_reviewer_penalty DECIMAL(3,2) NOT NULL DEFAULT 0.50, -- Extra penalty for harsh reviewers
    no_show_penalty_multiplier DECIMAL(3,2) NOT NULL DEFAULT 0.30, -- Reduce weight per no-show
    
    -- Minimum reviews needed for weight calculation
    min_reviews_for_full_weight INT NOT NULL DEFAULT 5,
    
    -- Enable/disable weighting system
    is_enabled BOOLEAN DEFAULT true,
    
    -- Metadata
    updated_by VARCHAR(255),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default configuration
INSERT INTO review_weighting_config (version) VALUES (1);

-- ----------------------------------------------------------------------------
-- 3. REVIEW WEIGHT AUDIT LOG
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS review_weight_audit (
    id SERIAL PRIMARY KEY,
    review_id INT NOT NULL,
    student_id VARCHAR(255) NOT NULL,
    barber_id VARCHAR(255) NOT NULL,
    
    -- Original review data
    original_rating INT NOT NULL,
    
    -- Student score at time of review
    student_score DECIMAL(5,2),
    student_grade_level VARCHAR(50),
    
    -- Weight calculation
    base_weight DECIMAL(3,2) NOT NULL,
    penalty_applied DECIMAL(3,2) DEFAULT 0.00,
    final_weight DECIMAL(3,2) NOT NULL,
    
    -- Impact on barber
    weighted_rating DECIMAL(4,2), -- rating × weight
    barber_avg_before DECIMAL(3,2),
    barber_avg_after DECIMAL(3,2),
    
    -- Reason for weight
    weight_reason TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_review_weight_audit_review ON review_weight_audit(review_id);
CREATE INDEX idx_review_weight_audit_student ON review_weight_audit(student_id);
CREATE INDEX idx_review_weight_audit_barber ON review_weight_audit(barber_id);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get review weight for a student score
CREATE OR REPLACE FUNCTION calculate_review_weight(p_student_score DECIMAL(5,2))
RETURNS DECIMAL(3,2) AS $$
DECLARE
    v_config RECORD;
    v_weight DECIMAL(3,2);
BEGIN
    -- Get configuration
    SELECT * INTO v_config FROM review_weighting_config ORDER BY version DESC LIMIT 1;
    
    -- If weighting is disabled, return 1.0
    IF NOT v_config.is_enabled THEN
        RETURN 1.00;
    END IF;
    
    -- If student has no score yet, use new customer default
    IF p_student_score IS NULL THEN
        RETURN v_config.new_customer_default_weight;
    END IF;
    
    -- Apply weight based on score tier
    IF p_student_score >= 95 THEN
        v_weight := v_config.vip_customer_weight;
    ELSIF p_student_score >= 85 THEN
        v_weight := v_config.excellent_customer_weight;
    ELSIF p_student_score >= 70 THEN
        v_weight := v_config.good_customer_weight;
    ELSIF p_student_score >= 50 THEN
        v_weight := v_config.average_customer_weight;
    ELSIF p_student_score >= 30 THEN
        v_weight := v_config.below_avg_customer_weight;
    ELSE
        -- Poor customers (0-29): reviews IGNORED
        v_weight := v_config.poor_customer_weight;
    END IF;
    
    RETURN v_weight;
END;
$$ LANGUAGE plpgsql;

-- Apply review weight to a review
CREATE OR REPLACE FUNCTION apply_review_weight(p_review_id INT)
RETURNS VOID AS $$
DECLARE
    v_review RECORD;
    v_student_score DECIMAL(5,2);
    v_weight DECIMAL(3,2);
    v_reason TEXT;
BEGIN
    -- Get review data
    SELECT r.*, u.id as student_id
    INTO v_review
    FROM reviews r
    JOIN users u ON r.student_id = u.id
    WHERE r.id = p_review_id;
    
    -- Get student's current score
    v_student_score := get_student_current_score(v_review.student_id);
    
    -- Calculate weight
    v_weight := calculate_review_weight(v_student_score);
    
    -- Generate reason
    IF v_student_score IS NULL THEN
        v_reason := 'New customer (default weight applied)';
    ELSIF v_student_score >= 95 THEN
        v_reason := 'VIP Customer (trusted reviewer)';
    ELSIF v_student_score >= 85 THEN
        v_reason := 'Excellent Customer (full weight)';
    ELSIF v_student_score >= 70 THEN
        v_reason := 'Good Customer (slight reduction)';
    ELSIF v_student_score >= 50 THEN
        v_reason := 'Average Customer (reduced weight)';
    ELSIF v_student_score >= 30 THEN
        v_reason := 'Below Average Customer (minimal weight)';
    ELSE
        v_reason := 'Poor Customer (review IGNORED due to low score)';
    END IF;
    
    -- Update review with weight
    UPDATE reviews
    SET 
        reviewer_score = v_student_score,
        review_weight = v_weight,
        is_weighted = true,
        weight_reason = v_reason
    WHERE id = p_review_id;
    
    -- Log audit entry
    INSERT INTO review_weight_audit (
        review_id, student_id, barber_id,
        original_rating, student_score, 
        base_weight, final_weight,
        weighted_rating, weight_reason
    ) VALUES (
        p_review_id,
        v_review.student_id,
        v_review.barber_id,
        v_review.rating,
        v_student_score,
        v_weight,
        v_weight,
        v_review.rating * v_weight,
        v_reason
    );
    
END;
$$ LANGUAGE plpgsql;

-- Calculate barber's weighted average rating
CREATE OR REPLACE FUNCTION get_barber_weighted_avg_rating(p_barber_id VARCHAR(255))
RETURNS DECIMAL(3,2) AS $$
DECLARE
    v_weighted_sum DECIMAL(10,2);
    v_total_weight DECIMAL(10,2);
    v_avg DECIMAL(3,2);
BEGIN
    -- Calculate weighted average
    SELECT 
        SUM(rating * COALESCE(review_weight, 1.0)),
        SUM(COALESCE(review_weight, 1.0))
    INTO v_weighted_sum, v_total_weight
    FROM reviews
    WHERE barber_id = p_barber_id;
    
    -- Avoid division by zero
    IF v_total_weight = 0 OR v_total_weight IS NULL THEN
        RETURN NULL;
    END IF;
    
    v_avg := v_weighted_sum / v_total_weight;
    
    RETURN ROUND(v_avg::numeric, 2);
END;
$$ LANGUAGE plpgsql;

-- Apply additional penalties for specific student behaviors
CREATE OR REPLACE FUNCTION apply_review_weight_penalties(
    p_review_id INT,
    p_student_id VARCHAR(255),
    p_base_weight DECIMAL(3,2)
)
RETURNS DECIMAL(3,2) AS $$
DECLARE
    v_config RECORD;
    v_student_metrics RECORD;
    v_final_weight DECIMAL(3,2);
    v_penalty DECIMAL(3,2) := 0.00;
BEGIN
    -- Get configuration
    SELECT * INTO v_config FROM review_weighting_config ORDER BY version DESC LIMIT 1;
    
    -- Get student's latest metrics
    SELECT * INTO v_student_metrics
    FROM student_metrics
    WHERE student_id = p_student_id
    ORDER BY period_date DESC
    LIMIT 1;
    
    IF v_student_metrics IS NULL THEN
        RETURN p_base_weight;
    END IF;
    
    -- Penalty for harsh reviewing pattern
    IF v_student_metrics.avg_rating_given IS NOT NULL 
       AND v_student_metrics.avg_rating_given < 3.5 THEN
        v_penalty := v_penalty + v_config.harsh_reviewer_penalty;
    END IF;
    
    -- Penalty for no-shows (each no-show reduces weight)
    IF v_student_metrics.no_show_rate > 0 THEN
        v_penalty := v_penalty + (v_student_metrics.no_show_rate * v_config.no_show_penalty_multiplier);
    END IF;
    
    -- Apply penalties
    v_final_weight := GREATEST(0.00, p_base_weight - v_penalty);
    
    RETURN v_final_weight;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-apply weight when review is created
CREATE OR REPLACE FUNCTION trigger_apply_review_weight()
RETURNS TRIGGER AS $$
BEGIN
    -- Apply weight after insert
    PERFORM apply_review_weight(NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Note: Enable this trigger after migration
-- CREATE TRIGGER auto_apply_review_weight
--     AFTER INSERT ON reviews
--     FOR EACH ROW
--     EXECUTE FUNCTION trigger_apply_review_weight();

-- ============================================================================
-- VIEWS FOR REPORTING
-- ============================================================================

-- View: Reviews with student scores and weights
CREATE OR REPLACE VIEW v_reviews_with_weights AS
SELECT 
    r.id as review_id,
    r.barber_id,
    b.user_id as barber_user_id,
    r.student_id,
    u.name as student_name,
    r.rating as original_rating,
    r.review_weight,
    (r.rating * COALESCE(r.review_weight, 1.0)) as weighted_rating,
    r.reviewer_score as student_score,
    get_student_grade_level(r.student_id) as student_grade_level,
    r.weight_reason,
    r.is_weighted,
    r.created_at
FROM reviews r
JOIN barbers b ON r.barber_id = b.id
JOIN users u ON r.student_id = u.id;

-- View: Barber rating comparison (original vs weighted)
CREATE OR REPLACE VIEW v_barber_rating_comparison AS
SELECT 
    b.id as barber_id,
    b.user_id,
    u.name as barber_name,
    COUNT(r.id) as total_reviews,
    ROUND(AVG(r.rating)::numeric, 2) as original_avg_rating,
    get_barber_weighted_avg_rating(b.id) as weighted_avg_rating,
    ROUND((get_barber_weighted_avg_rating(b.id) - AVG(r.rating))::numeric, 2) as rating_improvement
FROM barbers b
JOIN users u ON b.user_id = u.id
LEFT JOIN reviews r ON b.id = r.barber_id
GROUP BY b.id, b.user_id, u.name;

-- View: Impact of weighting per barber
CREATE OR REPLACE VIEW v_review_weighting_impact AS
SELECT 
    b.id as barber_id,
    u.name as barber_name,
    COUNT(r.id) FILTER (WHERE r.review_weight >= 1.0) as high_weight_reviews,
    COUNT(r.id) FILTER (WHERE r.review_weight < 1.0 AND r.review_weight > 0.0) as reduced_weight_reviews,
    COUNT(r.id) FILTER (WHERE r.review_weight = 0.0) as ignored_reviews,
    ROUND(AVG(r.review_weight)::numeric, 2) as avg_review_weight
FROM barbers b
JOIN users u ON b.user_id = u.id
LEFT JOIN reviews r ON b.id = r.barber_id
WHERE r.is_weighted = true
GROUP BY b.id, u.name;

-- ============================================================================
-- MIGRATION SCRIPT TO APPLY WEIGHTS TO EXISTING REVIEWS
-- ============================================================================

-- Function to backfill weights for existing reviews
CREATE OR REPLACE FUNCTION backfill_review_weights()
RETURNS void AS $$
DECLARE
    v_review RECORD;
    v_count INT := 0;
BEGIN
    -- Process all reviews that haven't been weighted yet
    FOR v_review IN 
        SELECT id FROM reviews WHERE is_weighted = false OR is_weighted IS NULL
    LOOP
        PERFORM apply_review_weight(v_review.id);
        v_count := v_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Applied weights to % reviews', v_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

