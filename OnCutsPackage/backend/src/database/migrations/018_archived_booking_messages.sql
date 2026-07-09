-- Migration: Archive booking messages for admin viewing
-- This table stores messages that are deleted when bookings are completed/paid
-- Allows admins to view historical conversations

CREATE TABLE IF NOT EXISTS archived_booking_messages (
    id SERIAL PRIMARY KEY,
    booking_id UUID NOT NULL,
    original_message_id INTEGER,
    original_conversation_id INTEGER,
    sender_id UUID NOT NULL,
    sender_first_name VARCHAR(100),
    sender_last_name VARCHAR(100),
    sender_avatar TEXT,
    sender_role VARCHAR(50),
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text',
    created_at TIMESTAMP NOT NULL,
    archived_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_archived_messages_booking ON archived_booking_messages(booking_id);
CREATE INDEX IF NOT EXISTS idx_archived_messages_created ON archived_booking_messages(created_at);

