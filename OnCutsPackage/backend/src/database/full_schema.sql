-- =====================================================
-- CAMPUSCUTS COMPLETE DATABASE SCHEMA
-- PostgreSQL 14+
-- Run this file to create all tables in the system
-- =====================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- =====================================================
-- 1. USERS TABLE
-- Core user accounts for all roles
-- =====================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    username VARCHAR(50) UNIQUE,
    campus_id UUID,
    role VARCHAR(20) NOT NULL CHECK (role IN ('student', 'barber')),
    user_type VARCHAR(20) CHECK (user_type IN ('student', 'barber', 'consumer', 'campus_manager', 'admin')),
    legacy_wallet_address VARCHAR(66) UNIQUE,
    stripe_account_id VARCHAR(255) UNIQUE,
    email_verified BOOLEAN DEFAULT FALSE,
    student_id_verified BOOLEAN DEFAULT FALSE,
    profile_picture_url TEXT,
    -- Custodial Wallet Balances (in USD cents)
    balance_available INTEGER DEFAULT 0 CHECK (balance_available >= 0),
    balance_pending INTEGER DEFAULT 0 CHECK (balance_pending >= 0),
    balance_locked INTEGER DEFAULT 0 CHECK (balance_locked >= 0),
    -- Location tracking
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    location_updated_at TIMESTAMP WITH TIME ZONE,
    location_permission VARCHAR(20) DEFAULT 'prompt' CHECK (location_permission IN ('granted', 'denied', 'prompt', 'unavailable')),
    -- Notification preferences
    notification_preferences JSONB DEFAULT '{
      "bookings": true,
      "messages": true,
      "payments": true,
      "reviews": true,
      "reminders": true,
      "system": true,
      "marketing": false,
      "quietHours": { "enabled": false, "start": "22:00", "end": "08:00" }
    }'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_legacy_wallet_address ON users(legacy_wallet_address);
CREATE INDEX IF NOT EXISTS idx_users_campus_id ON users(campus_id);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_location ON users(latitude, longitude) WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_location_permission ON users(location_permission);


-- =====================================================
-- 2. CAMPUSES TABLE
-- University/college information
-- =====================================================
CREATE TABLE IF NOT EXISTS campuses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    domain VARCHAR(255) UNIQUE NOT NULL,
    location GEOGRAPHY(POINT),
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(50) DEFAULT 'USA',
    timezone VARCHAR(50) DEFAULT 'America/New_York',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_campuses_domain ON campuses(domain);


-- =====================================================
-- 3. BARBERS TABLE
-- Barber profiles and settings
-- =====================================================
CREATE TABLE IF NOT EXISTS barbers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    bio TEXT,
    profile_image_url TEXT,
    pricing JSONB,
    specialties TEXT[] DEFAULT '{}',
    average_response_time INTEGER,
    total_earnings DECIMAL(10,2) DEFAULT 0,
    total_bookings INTEGER DEFAULT 0,
    average_rating DECIMAL(3,2) DEFAULT 0,
    years_experience INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    "weeklySchedule" JSONB DEFAULT '{
      "monday": { "enabled": true, "start": "09:00", "end": "17:00" },
      "tuesday": { "enabled": true, "start": "09:00", "end": "17:00" },
      "wednesday": { "enabled": true, "start": "09:00", "end": "17:00" },
      "thursday": { "enabled": true, "start": "09:00", "end": "17:00" },
      "friday": { "enabled": true, "start": "09:00", "end": "17:00" },
      "saturday": { "enabled": false, "start": "10:00", "end": "16:00" },
      "sunday": { "enabled": false, "start": "10:00", "end": "16:00" }
    }'::jsonb,
    -- Service location
    service_latitude DECIMAL(10, 8),
    service_longitude DECIMAL(11, 8),
    service_radius_km DECIMAL(5, 2) DEFAULT 10.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_barbers_user_id ON barbers(user_id);
CREATE INDEX IF NOT EXISTS idx_barbers_rating ON barbers(average_rating DESC);
CREATE INDEX IF NOT EXISTS idx_barbers_weekly_schedule ON barbers USING GIN ("weeklySchedule");
CREATE INDEX IF NOT EXISTS idx_barbers_service_location ON barbers(service_latitude, service_longitude) WHERE service_latitude IS NOT NULL AND service_longitude IS NOT NULL;


-- =====================================================
-- 4. BARBER APPLICATIONS TABLE
-- Applications from consumers to become barbers
-- =====================================================
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'barber_application_status') THEN
        CREATE TYPE barber_application_status AS ENUM ('pending', 'under_review', 'interview_scheduled', 'approved', 'rejected');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS barber_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    campus_id UUID REFERENCES campuses(id) ON DELETE SET NULL,
    years_experience VARCHAR(20) NOT NULL,
    has_license BOOLEAN DEFAULT FALSE,
    license_number VARCHAR(100),
    specialties TEXT[] NOT NULL DEFAULT '{}',
    has_own_tools BOOLEAN DEFAULT FALSE,
    needs_tools BOOLEAN DEFAULT FALSE,
    tools_needed TEXT,
    available_hours VARCHAR(20) NOT NULL,
    why_be_barber TEXT NOT NULL,
    portfolio_description TEXT,
    social_media VARCHAR(255),
    additional_notes TEXT,
    status barber_application_status DEFAULT 'pending',
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    review_notes TEXT,
    interview_scheduled_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_barber_applications_user_id ON barber_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_barber_applications_campus_id ON barber_applications(campus_id);
CREATE INDEX IF NOT EXISTS idx_barber_applications_status ON barber_applications(status);
CREATE INDEX IF NOT EXISTS idx_barber_applications_created_at ON barber_applications(created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_barber_applications_unique_pending ON barber_applications(user_id) WHERE status IN ('pending', 'under_review', 'interview_scheduled');


-- =====================================================
-- 5. BOOKINGS TABLE
-- Service bookings between consumers and barbers
-- =====================================================
CREATE TABLE IF NOT EXISTS bookings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID NOT NULL REFERENCES users(id),
    barber_id UUID NOT NULL REFERENCES users(id),
    service_name VARCHAR(255) NOT NULL,
    scheduled_time TIMESTAMP NOT NULL,
    location TEXT NOT NULL,
    location_details TEXT,
    notes TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bookings_student ON bookings(student_id);
CREATE INDEX IF NOT EXISTS idx_bookings_barber ON bookings(barber_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_scheduled ON bookings(scheduled_time);


-- =====================================================
-- 6. CONVERSATIONS TABLE
-- Real-time messaging conversations (booking-centric)
-- =====================================================
CREATE TABLE IF NOT EXISTS conversations (
    id SERIAL PRIMARY KEY,
    user1_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    booking_id UUID REFERENCES bookings(id),
    -- Cached booking context for performance
    service_name VARCHAR(100),
    service_price DECIMAL(10, 2),
    scheduled_time TIMESTAMP,
    location VARCHAR(255),
    location_details TEXT,
    booking_status VARCHAR(50) DEFAULT 'pending',
    barber_name VARCHAR(100),
    consumer_name VARCHAR(100),
    barber_profile_picture TEXT,
    consumer_profile_picture TEXT,
    notes TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_message_at TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user1_id, user2_id, booking_id)
);

CREATE INDEX IF NOT EXISTS idx_conversations_user1 ON conversations(user1_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user2 ON conversations(user2_id);
CREATE INDEX IF NOT EXISTS idx_conversations_booking ON conversations(booking_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_message ON conversations(last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_booking_status ON conversations(booking_status);


-- =====================================================
-- 7. MESSAGES TABLE
-- Individual messages within conversations
-- =====================================================
CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text',
    media_url TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_unread ON messages(is_read) WHERE is_read = false;


-- =====================================================
-- 8. CHAT MESSAGES TABLE (Legacy)
-- Original chat system - kept for backwards compatibility
-- =====================================================
CREATE TABLE IF NOT EXISTS chat_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_id BIGINT NOT NULL,
    sender_id UUID NOT NULL REFERENCES users(id),
    receiver_id UUID NOT NULL REFERENCES users(id),
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_chat_booking_id ON chat_messages(booking_id);
CREATE INDEX IF NOT EXISTS idx_chat_sender_id ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_receiver_id ON chat_messages(receiver_id);


-- =====================================================
-- 9. NOTIFICATIONS TABLE
-- In-app notifications for users
-- =====================================================
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    data JSONB,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);


-- =====================================================
-- 10. MOBILE DEVICES TABLE
-- Device tokens for push notifications
-- =====================================================
CREATE TABLE IF NOT EXISTS mobile_devices (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL UNIQUE,
    platform VARCHAR(20) NOT NULL CHECK (platform IN ('ios', 'android')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_mobile_devices_user ON mobile_devices(user_id);
CREATE INDEX IF NOT EXISTS idx_mobile_devices_active ON mobile_devices(is_active) WHERE is_active = true;


-- =====================================================
-- 11. NOTIFICATION LOGS TABLE
-- Audit trail for sent notifications
-- =====================================================
CREATE TABLE IF NOT EXISTS notification_logs (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    type VARCHAR(50) NOT NULL,
    results JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notification_logs_user ON notification_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_logs_type ON notification_logs(type);
CREATE INDEX IF NOT EXISTS idx_notification_logs_created ON notification_logs(created_at DESC);


-- =====================================================
-- 12. PAYMENT TRANSACTIONS TABLE
-- Stripe payment records
-- =====================================================
CREATE TABLE IF NOT EXISTS payment_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blockchain_payment_id BIGINT UNIQUE,
    booking_id UUID REFERENCES bookings(id),
    stripe_payment_intent_id VARCHAR(255) UNIQUE NOT NULL,
    stripe_transfer_id VARCHAR(255),
    barber_id UUID NOT NULL REFERENCES barbers(id),
    client_id UUID NOT NULL REFERENCES users(id),
    amount DECIMAL(10,2) NOT NULL,
    platform_fee DECIMAL(10,2) NOT NULL,
    barber_payout DECIMAL(10,2) NOT NULL,
    tip_amount DECIMAL(10,2) DEFAULT 0,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_payment_blockchain_id ON payment_transactions(blockchain_payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_stripe_intent ON payment_transactions(stripe_payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_payment_barber_id ON payment_transactions(barber_id);


-- =====================================================
-- 13. LEDGER ENTRIES TABLE
-- Custodial wallet internal ledger
-- =====================================================
CREATE TABLE IF NOT EXISTS ledger_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL,
    type VARCHAR(50) NOT NULL CHECK (type IN (
        'DEPOSIT', 'WITHDRAWAL', 'BOOKING_PAYMENT', 'BOOKING_REFUND',
        'SERVICE_COMPLETION', 'TIP', 'PLATFORM_FEE', 'PROMOTIONAL_CREDIT',
        'DISPUTE_HOLD', 'DISPUTE_RELEASE', 'ADJUSTMENT'
    )),
    balance_type VARCHAR(20) NOT NULL CHECK (balance_type IN ('available', 'pending', 'locked')),
    balance_after INTEGER NOT NULL,
    reference_type VARCHAR(50),
    reference_id VARCHAR(255),
    metadata JSONB,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_ledger_user_id ON ledger_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_ledger_type ON ledger_entries(type);
CREATE INDEX IF NOT EXISTS idx_ledger_created_at ON ledger_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_reference ON ledger_entries(reference_type, reference_id);


-- =====================================================
-- 14. WITHDRAWAL REQUESTS TABLE
-- Barber payout requests
-- =====================================================
CREATE TABLE IF NOT EXISTS withdrawal_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL CHECK (amount > 0),
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    stripe_payout_id VARCHAR(255) UNIQUE,
    stripe_destination_id VARCHAR(255),
    failure_reason TEXT,
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_withdrawal_user_id ON withdrawal_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_status ON withdrawal_requests(status);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requested_at ON withdrawal_requests(requested_at DESC);


-- =====================================================
-- 15. PORTFOLIO IMAGES TABLE
-- Barber portfolio/work samples
-- =====================================================
CREATE TABLE IF NOT EXISTS portfolio_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    barber_id UUID NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    caption TEXT,
    order_index INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_portfolio_barber_id ON portfolio_images(barber_id);


-- =====================================================
-- 16. AVAILABILITY TEMPLATES TABLE
-- Recurring barber availability slots
-- =====================================================
CREATE TABLE IF NOT EXISTS availability_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    barber_id UUID NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_availability_barber_id ON availability_templates(barber_id);


-- =====================================================
-- 17. BOOKING METADATA TABLE
-- Additional booking details
-- =====================================================
CREATE TABLE IF NOT EXISTS booking_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blockchain_booking_id BIGINT UNIQUE,
    barber_id UUID NOT NULL REFERENCES barbers(id),
    client_id UUID NOT NULL REFERENCES users(id),
    location_details TEXT,
    special_requests TEXT,
    reminder_sent BOOLEAN DEFAULT FALSE,
    notification_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_booking_metadata_blockchain_id ON booking_metadata(blockchain_booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_metadata_barber_id ON booking_metadata(barber_id);
CREATE INDEX IF NOT EXISTS idx_booking_metadata_client_id ON booking_metadata(client_id);


-- =====================================================
-- 18. REVIEW METADATA TABLE
-- Service reviews and ratings
-- =====================================================
CREATE TABLE IF NOT EXISTS review_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blockchain_review_id BIGINT UNIQUE,
    booking_id UUID REFERENCES bookings(id),
    review_text TEXT NOT NULL,
    images JSONB,
    helpful_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_review_metadata_blockchain_id ON review_metadata(blockchain_review_id);
CREATE INDEX IF NOT EXISTS idx_review_metadata_booking_id ON review_metadata(booking_id);


-- =====================================================
-- 19. VERIFICATION REQUESTS TABLE
-- Student ID verification
-- =====================================================
CREATE TABLE IF NOT EXISTS verification_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    student_id_image_url TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMP,
    rejection_reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_verification_user_id ON verification_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_verification_status ON verification_requests(status);


-- =====================================================
-- 20. ANALYTICS EVENTS TABLE
-- User activity tracking
-- =====================================================
CREATE TABLE IF NOT EXISTS analytics_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    event_type VARCHAR(100) NOT NULL,
    event_data JSONB,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_analytics_user_id ON analytics_events(user_id);
CREATE INDEX IF NOT EXISTS idx_analytics_event_type ON analytics_events(event_type);
CREATE INDEX IF NOT EXISTS idx_analytics_timestamp ON analytics_events(timestamp DESC);


-- =====================================================
-- 21. REFERRALS TABLE
-- Referral program tracking
-- =====================================================
CREATE TABLE IF NOT EXISTS referrals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referrer_id UUID NOT NULL REFERENCES users(id),
    referred_id UUID NOT NULL REFERENCES users(id),
    reward_amount DECIMAL(10,2) DEFAULT 0,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer_id ON referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referred_id ON referrals(referred_id);


-- =====================================================
-- 22. APTOS TRANSACTIONS TABLE
-- Blockchain transaction monitoring
-- =====================================================
CREATE TABLE IF NOT EXISTS aptos_transactions (
    id BIGSERIAL PRIMARY KEY,
    version TEXT NOT NULL,
    tx_hash TEXT UNIQUE NOT NULL,
    tx_type TEXT NOT NULL CHECK (tx_type IN ('deposit', 'withdrawal', 'batch_withdrawal', 'onchain_proof', 'unknown')),
    sender TEXT NOT NULL,
    recipient TEXT,
    amount_octas BIGINT,
    amount_usd DECIMAL(10, 2),
    gas_used BIGINT NOT NULL,
    success BOOLEAN NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    description TEXT,
    metadata JSONB DEFAULT '{}',
    platform_address TEXT NOT NULL,
    raw_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_aptos_tx_hash ON aptos_transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_aptos_platform_address ON aptos_transactions(platform_address);
CREATE INDEX IF NOT EXISTS idx_aptos_timestamp ON aptos_transactions(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_aptos_tx_type ON aptos_transactions(tx_type);


-- =====================================================
-- 23. STRIPE EVENTS TABLE
-- Stripe webhook event logging
-- =====================================================
CREATE TABLE IF NOT EXISTS stripe_events (
    id BIGSERIAL PRIMARY KEY,
    event_id TEXT UNIQUE NOT NULL,
    event_type TEXT NOT NULL,
    payment_intent_id TEXT,
    customer_id TEXT,
    amount_cents BIGINT,
    amount_usd DECIMAL(10, 2),
    status TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    description TEXT,
    metadata JSONB DEFAULT '{}',
    student_email TEXT,
    barber_email TEXT,
    booking_id TEXT,
    raw_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stripe_event_id ON stripe_events(event_id);
CREATE INDEX IF NOT EXISTS idx_stripe_event_type ON stripe_events(event_type);
CREATE INDEX IF NOT EXISTS idx_stripe_timestamp ON stripe_events(timestamp DESC);


-- =====================================================
-- 24. GAS WALLETS TABLE
-- Platform Aptos gas wallets
-- =====================================================
CREATE TABLE IF NOT EXISTS gas_wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    address TEXT UNIQUE NOT NULL,
    descriptive_name TEXT NOT NULL,
    campus_id UUID REFERENCES campuses(id) ON DELETE SET NULL,
    current_balance_apt DECIMAL(20, 8) DEFAULT 0,
    last_checked_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    min_balance_threshold_apt DECIMAL(20, 8) DEFAULT 0.5,
    top_up_threshold_apt DECIMAL(20, 8) DEFAULT 0.1,
    safety_buffer_percentage DECIMAL(5, 2) DEFAULT 20.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- =====================================================
-- 25. GAS TOP-UP REQUESTS TABLE
-- Admin gas wallet top-up requests
-- =====================================================
CREATE TABLE IF NOT EXISTS gas_top_up_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gas_wallet_id UUID REFERENCES gas_wallets(id) ON DELETE CASCADE NOT NULL,
    gas_wallet_address TEXT NOT NULL,
    requested_amount_apt DECIMAL(20, 8) NOT NULL,
    requested_amount_octas BIGINT NOT NULL,
    status TEXT CHECK (status IN ('pending', 'approved', 'completed', 'failed', 'cancelled')) NOT NULL DEFAULT 'pending',
    admin_address_requested_from TEXT,
    admin_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_tx_hash TEXT,
    verified_amount_octas BIGINT,
    verification_status TEXT CHECK (verification_status IN ('pending', 'verified', 'amount_mismatch', 'tx_not_found', 'timeout')),
    verified_at TIMESTAMP WITH TIME ZONE,
    reason TEXT,
    estimated_coverage_days DECIMAL(5, 2),
    idempotency_key TEXT UNIQUE,
    audit_metadata JSONB DEFAULT '{}',
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    approved_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_gas_top_up_requests_status ON gas_top_up_requests(status);
CREATE INDEX IF NOT EXISTS idx_gas_top_up_requests_gas_wallet ON gas_top_up_requests(gas_wallet_id);


-- =====================================================
-- 26. GAS WALLET AUDIT LOGS TABLE
-- Immutable audit trail for gas wallet events
-- =====================================================
CREATE TABLE IF NOT EXISTS gas_wallet_audit_logs (
    id BIGSERIAL PRIMARY KEY,
    gas_wallet_id UUID REFERENCES gas_wallets(id) ON DELETE CASCADE NOT NULL,
    top_up_request_id UUID REFERENCES gas_top_up_requests(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    actor_type TEXT CHECK (actor_type IN ('system', 'admin', 'cron')),
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    actor_wallet_address TEXT,
    data JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gas_wallet_audit_logs_wallet ON gas_wallet_audit_logs(gas_wallet_id);
CREATE INDEX IF NOT EXISTS idx_gas_wallet_audit_logs_event_type ON gas_wallet_audit_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_gas_wallet_audit_logs_created_at ON gas_wallet_audit_logs(created_at DESC);


-- =====================================================
-- 27. GAS ESTIMATION CONFIG TABLE
-- Configuration for gas estimation
-- =====================================================
CREATE TABLE IF NOT EXISTS gas_estimation_config (
    id SERIAL PRIMARY KEY,
    default_avg_gas_apt_per_write DECIMAL(10, 8) NOT NULL DEFAULT 0.0003,
    estimation_horizon_hours INT NOT NULL DEFAULT 24,
    safety_buffer_percentage DECIMAL(5, 2) NOT NULL DEFAULT 20.00,
    min_balance_alert_threshold_apt DECIMAL(20, 8) DEFAULT 0.5,
    critical_balance_threshold_apt DECIMAL(20, 8) DEFAULT 0.1,
    auto_create_topup_threshold_apt DECIMAL(20, 8) DEFAULT 0.1,
    tx_verification_timeout_minutes INT DEFAULT 10,
    min_confirmations INT DEFAULT 1,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- =====================================================
-- 28. CAMPUS LOCATIONS TABLE
-- Crowd-sourced campus locations
-- =====================================================
CREATE TABLE IF NOT EXISTS campus_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    category VARCHAR(32) NOT NULL DEFAULT 'OTHER' CHECK (category IN (
        'ON_CAMPUS', 'OFF_CAMPUS', 'DORM', 'APARTMENT', 'COMMON_AREA', 'OTHER'
    )),
    cohort VARCHAR(32) NOT NULL DEFAULT 'UNKNOWN' CHECK (cohort IN (
        'FIRST_YEAR', 'UPPER_CLASS', 'GRAD', 'MIXED', 'UNKNOWN'
    )),
    usage_count INTEGER NOT NULL DEFAULT 1,
    confidence NUMERIC(3, 2) NOT NULL DEFAULT 0.30 CHECK (confidence >= 0 AND confidence <= 1.0),
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_by_user_id UUID,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_normalized_name_per_university UNIQUE (university_id, normalized_name)
);

CREATE INDEX IF NOT EXISTS idx_campus_locations_university ON campus_locations(university_id);
CREATE INDEX IF NOT EXISTS idx_campus_locations_normalized ON campus_locations(normalized_name);
CREATE INDEX IF NOT EXISTS idx_campus_locations_verified ON campus_locations(university_id, is_verified, confidence DESC);


-- =====================================================
-- 29. CAMPUS LOCATION ALIASES TABLE
-- Alternative names for locations
-- =====================================================
CREATE TABLE IF NOT EXISTS campus_location_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campus_location_id UUID NOT NULL REFERENCES campus_locations(id) ON DELETE CASCADE,
    alias TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_normalized_alias_per_location UNIQUE (campus_location_id, normalized_alias)
);

CREATE INDEX IF NOT EXISTS idx_campus_location_aliases_normalized ON campus_location_aliases(normalized_alias);


-- =====================================================
-- 30. LOCATION ENRICHMENT LOG TABLE
-- AI enrichment audit trail
-- =====================================================
CREATE TABLE IF NOT EXISTS location_enrichment_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campus_location_id UUID NOT NULL REFERENCES campus_locations(id) ON DELETE CASCADE,
    ai_suggested_name TEXT,
    ai_suggested_category VARCHAR(32),
    ai_suggested_cohort VARCHAR(32),
    ai_suggested_aliases TEXT[],
    ai_confidence_adjustment NUMERIC(3, 2),
    applied BOOLEAN NOT NULL DEFAULT FALSE,
    applied_at TIMESTAMP,
    rejected_reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_location_enrichment_log_location ON location_enrichment_log(campus_location_id);


-- =====================================================
-- 31. LOCATION MERGE LOG TABLE
-- Duplicate resolution audit trail
-- =====================================================
CREATE TABLE IF NOT EXISTS location_merge_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_location_id UUID NOT NULL,
    target_location_id UUID NOT NULL REFERENCES campus_locations(id),
    merged_by_user_id UUID,
    merge_reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_location_merge_log_target ON location_merge_log(target_location_id);


-- =====================================================
-- TRIGGERS & FUNCTIONS
-- =====================================================

-- Update timestamp function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply triggers to tables
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_barbers_updated_at ON barbers;
CREATE TRIGGER update_barbers_updated_at BEFORE UPDATE ON barbers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_booking_metadata_updated_at ON booking_metadata;
CREATE TRIGGER update_booking_metadata_updated_at BEFORE UPDATE ON booking_metadata
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_payment_transactions_updated_at ON payment_transactions;
CREATE TRIGGER update_payment_transactions_updated_at BEFORE UPDATE ON payment_transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_conversations_updated_at ON conversations;
CREATE TRIGGER update_conversations_updated_at BEFORE UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Campus location trigger
CREATE OR REPLACE FUNCTION update_campus_location_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS campus_location_updated_at ON campus_locations;
CREATE TRIGGER campus_location_updated_at
BEFORE UPDATE ON campus_locations
FOR EACH ROW EXECUTE FUNCTION update_campus_location_updated_at();


-- =====================================================
-- VIEWS (For Admin Dashboard)
-- =====================================================

-- Combined transaction feed
CREATE OR REPLACE VIEW admin_transaction_feed AS
    SELECT 'aptos' AS platform, tx_hash AS transaction_id, tx_type AS transaction_type,
           sender AS from_address, recipient AS to_address, amount_usd, description,
           timestamp, success AS status_success, metadata
    FROM aptos_transactions
    UNION ALL
    SELECT 'stripe' AS platform, event_id AS transaction_id, event_type AS transaction_type,
           student_email AS from_address, barber_email AS to_address, amount_usd, description,
           timestamp, (status IN ('succeeded', 'paid', 'created')) AS status_success, metadata
    FROM stripe_events
    ORDER BY timestamp DESC;

-- Gas wallet health
CREATE OR REPLACE VIEW gas_wallet_health AS
SELECT 
    w.id, w.address, w.descriptive_name, w.current_balance_apt, 
    w.min_balance_threshold_apt, w.last_checked_at,
    CASE 
        WHEN w.current_balance_apt < w.min_balance_threshold_apt THEN 'critical'
        WHEN w.current_balance_apt < (w.min_balance_threshold_apt * 2) THEN 'low'
        ELSE 'healthy'
    END as health_status
FROM gas_wallets w WHERE w.is_active = true;

-- Daily transaction stats
CREATE OR REPLACE VIEW daily_transaction_stats AS
SELECT 
    DATE(timestamp) AS date,
    platform,
    COUNT(*) AS transaction_count,
    SUM(amount_usd) AS total_volume_usd
FROM admin_transaction_feed
WHERE timestamp >= NOW() - INTERVAL '30 days'
GROUP BY DATE(timestamp), platform
ORDER BY date DESC, platform;


-- =====================================================
-- SEED DATA
-- =====================================================

-- Seed campuses
INSERT INTO campuses (name, domain, city, state) VALUES
('Cal Poly San Luis Obispo', 'calpoly.edu', 'San Luis Obispo', 'CA'),
('Harvard University', 'harvard.edu', 'Cambridge', 'MA'),
('Stanford University', 'stanford.edu', 'Stanford', 'CA'),
('MIT', 'mit.edu', 'Cambridge', 'MA'),
('UC Berkeley', 'berkeley.edu', 'Berkeley', 'CA'),
('UCLA', 'ucla.edu', 'Los Angeles', 'CA'),
('USC', 'usc.edu', 'Los Angeles', 'CA'),
('Yale University', 'yale.edu', 'New Haven', 'CT'),
('Princeton University', 'princeton.edu', 'Princeton', 'NJ'),
('Columbia University', 'columbia.edu', 'New York', 'NY')
ON CONFLICT (domain) DO NOTHING;

-- Seed gas estimation config
INSERT INTO gas_estimation_config (
    default_avg_gas_apt_per_write, estimation_horizon_hours, safety_buffer_percentage,
    min_balance_alert_threshold_apt, critical_balance_threshold_apt,
    auto_create_topup_threshold_apt, tx_verification_timeout_minutes, min_confirmations, is_active
) VALUES (0.0003, 24, 20.00, 0.5, 0.1, 0.1, 10, 1, true)
ON CONFLICT DO NOTHING;


-- =====================================================
-- SCHEMA COMPLETE
-- Total: 31 Tables, 5 Views, 7 Triggers, 3 Functions
-- =====================================================

