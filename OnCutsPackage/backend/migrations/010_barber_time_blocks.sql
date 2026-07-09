-- Migration: Add barber_time_blocks table for one-time date-specific blocks
-- These are different from availability_templates which define recurring weekly schedule
-- Time blocks are for specific dates (e.g., "block Friday Feb 14, 2pm-4pm")

CREATE TABLE IF NOT EXISTS barber_time_blocks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    barber_id UUID NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
    block_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    reason TEXT, -- Optional reason for the block (e.g., "Doctor appointment")
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure end_time is after start_time
    CONSTRAINT valid_time_range CHECK (end_time > start_time)
);

-- Index for efficient lookups by barber and date
CREATE INDEX IF NOT EXISTS idx_time_blocks_barber_date ON barber_time_blocks(barber_id, block_date);

-- Index for cleanup queries (deleting old blocks)
CREATE INDEX IF NOT EXISTS idx_time_blocks_date ON barber_time_blocks(block_date);

-- Add comment for documentation
COMMENT ON TABLE barber_time_blocks IS 'One-time date-specific availability blocks for barbers. Unlike availability_templates which define recurring weekly schedule, these blocks are for specific dates only.';

