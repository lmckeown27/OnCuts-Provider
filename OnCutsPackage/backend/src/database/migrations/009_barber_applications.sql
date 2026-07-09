-- Barber Applications Table
-- Stores applications from consumers wanting to become barbers

-- Create application status enum
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'barber_application_status') THEN
        CREATE TYPE barber_application_status AS ENUM ('pending', 'under_review', 'interview_scheduled', 'approved', 'rejected');
    END IF;
END $$;

-- Create barber applications table
CREATE TABLE IF NOT EXISTS barber_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    campus_id UUID REFERENCES campuses(id) ON DELETE SET NULL,
    
    -- Application data
    years_experience VARCHAR(20) NOT NULL,
    has_license BOOLEAN DEFAULT FALSE,
    license_number VARCHAR(100),
    specialties TEXT[] NOT NULL DEFAULT '{}',
    has_own_tools BOOLEAN DEFAULT FALSE,
    available_hours VARCHAR(20) NOT NULL,
    why_be_barber TEXT NOT NULL,
    portfolio_description TEXT,
    social_media VARCHAR(255),
    additional_notes TEXT,
    
    -- Status tracking
    status barber_application_status DEFAULT 'pending',
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    review_notes TEXT,
    interview_scheduled_at TIMESTAMP WITH TIME ZONE,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_barber_applications_user_id ON barber_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_barber_applications_campus_id ON barber_applications(campus_id);
CREATE INDEX IF NOT EXISTS idx_barber_applications_status ON barber_applications(status);
CREATE INDEX IF NOT EXISTS idx_barber_applications_created_at ON barber_applications(created_at DESC);

-- Prevent duplicate pending applications from the same user
CREATE UNIQUE INDEX IF NOT EXISTS idx_barber_applications_unique_pending 
    ON barber_applications(user_id) 
    WHERE status IN ('pending', 'under_review', 'interview_scheduled');

-- Add comment
COMMENT ON TABLE barber_applications IS 'Stores applications from consumers who want to become barbers on the platform';

