-- CampusCuts Database Schema
-- PostgreSQL 14+

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    campus_id INTEGER NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('student', 'barber')),
    legacy_wallet_address VARCHAR(66) UNIQUE,
    stripe_account_id VARCHAR(255) UNIQUE, -- Stripe Connect account ID for barbers
    email_verified BOOLEAN DEFAULT FALSE,
    student_id_verified BOOLEAN DEFAULT FALSE,
    -- Custodial Wallet Balances (in USD cents to avoid floating point issues)
    balance_available INTEGER DEFAULT 0 CHECK (balance_available >= 0), -- Funds available for use/withdrawal
    balance_pending INTEGER DEFAULT 0 CHECK (balance_pending >= 0), -- Funds held pending service completion
    balance_locked INTEGER DEFAULT 0 CHECK (balance_locked >= 0), -- Funds locked for disputes/holds
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_legacy_wallet_address ON users(legacy_wallet_address);
CREATE INDEX idx_users_campus_id ON users(campus_id);
CREATE INDEX idx_users_role ON users(role);

-- Campuses table
CREATE TABLE campuses (
    id SERIAL PRIMARY KEY,
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

CREATE INDEX idx_campuses_domain ON campuses(domain);

-- Barbers table (off-chain profile data)
CREATE TABLE barbers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    bio TEXT,
    profile_image_url TEXT,
    pricing JSONB, -- {"Haircut": 25, "Fade": 30, "Beard Trim": 15}
    average_response_time INTEGER, -- In minutes
    total_earnings DECIMAL(10,2) DEFAULT 0,
    total_bookings INTEGER DEFAULT 0,
    average_rating DECIMAL(3,2) DEFAULT 0,
    years_experience INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_barbers_user_id ON barbers(user_id);
CREATE INDEX idx_barbers_rating ON barbers(average_rating DESC);

-- Portfolio images
CREATE TABLE portfolio_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    barber_id UUID NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    caption TEXT,
    order_index INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_portfolio_barber_id ON portfolio_images(barber_id);

-- Barber availability templates
CREATE TABLE availability_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    barber_id UUID NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Sunday
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_availability_barber_id ON availability_templates(barber_id);

-- Booking metadata (off-chain details)
CREATE TABLE booking_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blockchain_booking_id BIGINT UNIQUE NOT NULL,
    barber_id UUID NOT NULL REFERENCES barbers(id),
    client_id UUID NOT NULL REFERENCES users(id),
    location_details TEXT, -- Specific dorm, room number, etc.
    special_requests TEXT,
    reminder_sent BOOLEAN DEFAULT FALSE,
    notification_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_booking_metadata_blockchain_id ON booking_metadata(blockchain_booking_id);
CREATE INDEX idx_booking_metadata_barber_id ON booking_metadata(barber_id);
CREATE INDEX idx_booking_metadata_client_id ON booking_metadata(client_id);

-- Chat messages
CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_id BIGINT NOT NULL,
    sender_id UUID NOT NULL REFERENCES users(id),
    receiver_id UUID NOT NULL REFERENCES users(id),
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_chat_booking_id ON chat_messages(booking_id);
CREATE INDEX idx_chat_sender_id ON chat_messages(sender_id);
CREATE INDEX idx_chat_receiver_id ON chat_messages(receiver_id);

-- Notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL, -- 'booking_confirmed', 'booking_cancelled', 'review_received', etc.
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    data JSONB, -- Additional data (booking_id, etc.)
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);

-- Payment transactions (off-chain Stripe data)
CREATE TABLE payment_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blockchain_payment_id BIGINT UNIQUE NOT NULL,
    booking_id BIGINT NOT NULL,
    stripe_payment_intent_id VARCHAR(255) UNIQUE NOT NULL,
    stripe_transfer_id VARCHAR(255),
    barber_id UUID NOT NULL REFERENCES barbers(id),
    client_id UUID NOT NULL REFERENCES users(id),
    amount DECIMAL(10,2) NOT NULL,
    platform_fee DECIMAL(10,2) NOT NULL,
    barber_payout DECIMAL(10,2) NOT NULL,
    tip_amount DECIMAL(10,2) DEFAULT 0,
    status VARCHAR(50) NOT NULL, -- 'pending', 'succeeded', 'refunded', 'failed'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payment_blockchain_id ON payment_transactions(blockchain_payment_id);
CREATE INDEX idx_payment_stripe_intent ON payment_transactions(stripe_payment_intent_id);
CREATE INDEX idx_payment_barber_id ON payment_transactions(barber_id);

-- Ledger Entries (Custodial Wallet Internal Ledger)
-- This is the core of the custodial wallet system - tracks ALL balance changes
CREATE TABLE ledger_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL, -- In USD cents (can be positive or negative)
    type VARCHAR(50) NOT NULL CHECK (type IN (
        'DEPOSIT',              -- User adds funds via Stripe/card
        'WITHDRAWAL',           -- User withdraws to bank
        'BOOKING_PAYMENT',      -- Customer pays for booking
        'BOOKING_REFUND',       -- Booking cancelled, refund issued
        'SERVICE_COMPLETION',   -- Funds released from pending to available
        'TIP',                  -- Tip given/received
        'PLATFORM_FEE',         -- Platform commission deducted
        'PROMOTIONAL_CREDIT',   -- Platform issues credit/promo
        'DISPUTE_HOLD',         -- Funds locked due to dispute
        'DISPUTE_RELEASE',      -- Dispute resolved, funds released
        'ADJUSTMENT'            -- Manual adjustment by platform
    )),
    balance_type VARCHAR(20) NOT NULL CHECK (balance_type IN ('available', 'pending', 'locked')),
    balance_after INTEGER NOT NULL, -- Snapshot of balance after this transaction
    reference_type VARCHAR(50), -- 'booking', 'payout', 'stripe_charge', etc.
    reference_id VARCHAR(255), -- ID of related entity (booking_id, payout_id, etc.)
    metadata JSONB, -- Additional data (stripe details, booking info, etc.)
    description TEXT, -- Human-readable description
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id) -- For admin-initiated transactions
);

CREATE INDEX idx_ledger_user_id ON ledger_entries(user_id);
CREATE INDEX idx_ledger_type ON ledger_entries(type);
CREATE INDEX idx_ledger_created_at ON ledger_entries(created_at DESC);
CREATE INDEX idx_ledger_reference ON ledger_entries(reference_type, reference_id);

-- Withdrawal Requests (for barber payouts)
CREATE TABLE withdrawal_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL CHECK (amount > 0), -- In USD cents
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    stripe_payout_id VARCHAR(255) UNIQUE, -- Stripe Connect payout ID
    stripe_destination_id VARCHAR(255), -- Connected account ID
    failure_reason TEXT,
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX idx_withdrawal_user_id ON withdrawal_requests(user_id);
CREATE INDEX idx_withdrawal_status ON withdrawal_requests(status);
CREATE INDEX idx_withdrawal_requested_at ON withdrawal_requests(requested_at DESC);

-- Review metadata (full text stored off-chain)
CREATE TABLE review_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blockchain_review_id BIGINT UNIQUE NOT NULL,
    booking_id BIGINT NOT NULL,
    review_text TEXT NOT NULL,
    images JSONB, -- Array of image URLs
    helpful_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_review_metadata_blockchain_id ON review_metadata(blockchain_review_id);
CREATE INDEX idx_review_metadata_booking_id ON review_metadata(booking_id);

-- Student ID verification requests
CREATE TABLE verification_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    student_id_image_url TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMP,
    rejection_reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_verification_user_id ON verification_requests(user_id);
CREATE INDEX idx_verification_status ON verification_requests(status);

-- Analytics events
CREATE TABLE analytics_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    event_type VARCHAR(100) NOT NULL, -- 'page_view', 'barber_view', 'booking_created', etc.
    event_data JSONB,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_analytics_user_id ON analytics_events(user_id);
CREATE INDEX idx_analytics_event_type ON analytics_events(event_type);
CREATE INDEX idx_analytics_timestamp ON analytics_events(timestamp DESC);

-- Referral tracking
CREATE TABLE referrals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referrer_id UUID NOT NULL REFERENCES users(id),
    referred_id UUID NOT NULL REFERENCES users(id),
    reward_amount DECIMAL(10,2) DEFAULT 0,
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'completed', 'expired'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX idx_referrals_referrer_id ON referrals(referrer_id);
CREATE INDEX idx_referrals_referred_id ON referrals(referred_id);

-- Update timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply triggers
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_barbers_updated_at BEFORE UPDATE ON barbers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_booking_metadata_updated_at BEFORE UPDATE ON booking_metadata
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_payment_transactions_updated_at BEFORE UPDATE ON payment_transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Conversations table (for real-time chat)
CREATE TABLE conversations (
    id SERIAL PRIMARY KEY,
    user1_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    booking_id BIGINT, -- Optional: conversation tied to a specific booking
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_message_at TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user1_id, user2_id, booking_id)
);

CREATE INDEX idx_conversations_user1 ON conversations(user1_id);
CREATE INDEX idx_conversations_user2 ON conversations(user2_id);
CREATE INDEX idx_conversations_booking ON conversations(booking_id);
CREATE INDEX idx_conversations_last_message ON conversations(last_message_at DESC);

-- Messages table
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text', -- 'text', 'image', 'system'
    media_url TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_created ON messages(created_at DESC);
CREATE INDEX idx_messages_unread ON messages(is_read) WHERE is_read = false;

-- Mobile devices (for push notifications)
CREATE TABLE mobile_devices (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL,
    platform VARCHAR(20) NOT NULL CHECK (platform IN ('ios', 'android')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(device_token)
);

CREATE INDEX idx_mobile_devices_user ON mobile_devices(user_id);
CREATE INDEX idx_mobile_devices_active ON mobile_devices(is_active) WHERE is_active = true;

-- Notification logs (for analytics and debugging)
CREATE TABLE notification_logs (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    type VARCHAR(50) NOT NULL, -- 'booking_confirmation', 'message', 'reminder', etc.
    results JSONB, -- Store delivery results
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_notification_logs_user ON notification_logs(user_id);
CREATE INDEX idx_notification_logs_type ON notification_logs(type);
CREATE INDEX idx_notification_logs_created ON notification_logs(created_at DESC);

-- Bookings table (for booking-centric messaging reference)
CREATE TABLE IF NOT EXISTS bookings (
    id SERIAL PRIMARY KEY,
    student_id UUID NOT NULL REFERENCES users(id),
    barber_id UUID NOT NULL REFERENCES users(id),
    service_name VARCHAR(255) NOT NULL,
    scheduled_time TIMESTAMP NOT NULL,
    location TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'confirmed', 'completed', 'cancelled'
    price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bookings_student ON bookings(student_id);
CREATE INDEX IF NOT EXISTS idx_bookings_barber ON bookings(barber_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_scheduled ON bookings(scheduled_time);

-- Update notification_preferences column in users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS notification_preferences JSONB DEFAULT '{
  "bookings": true,
  "messages": true,
  "payments": true,
  "reviews": true,
  "reminders": true,
  "system": true,
  "marketing": false,
  "quietHours": {
    "enabled": false,
    "start": "22:00",
    "end": "08:00"
  }
}'::jsonb;

-- Add username column to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(50) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS user_type VARCHAR(20) CHECK (user_type IN ('student', 'barber'));

-- Update existing schema to use user_type
UPDATE users SET user_type = role WHERE user_type IS NULL;

-- Seed initial campus data
INSERT INTO campuses (name, domain, city, state) VALUES
('Harvard University', 'harvard.edu', 'Cambridge', 'MA'),
('Stanford University', 'stanford.edu', 'Stanford', 'CA'),
('MIT', 'mit.edu', 'Cambridge', 'MA'),
('UC Berkeley', 'berkeley.edu', 'Berkeley', 'CA'),
('Yale University', 'yale.edu', 'New Haven', 'CT'),
('Princeton University', 'princeton.edu', 'Princeton', 'NJ'),
('Columbia University', 'columbia.edu', 'New York', 'NY'),
('University of Pennsylvania', 'upenn.edu', 'Philadelphia', 'PA'),
('Duke University', 'duke.edu', 'Durham', 'NC'),
('Northwestern University', 'northwestern.edu', 'Evanston', 'IL')
ON CONFLICT (domain) DO NOTHING;

