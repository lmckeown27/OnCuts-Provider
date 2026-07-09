-- Add phone_number column to barber_applications table
-- This column stores the applicant's phone number for contact purposes

ALTER TABLE barber_applications 
ADD COLUMN IF NOT EXISTS phone_number VARCHAR(50);

-- Also add to guest_barber_applications if table exists
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'guest_barber_applications') THEN
        ALTER TABLE guest_barber_applications 
        ADD COLUMN IF NOT EXISTS phone_number VARCHAR(50);
    END IF;
END $$;

-- Add index for potential future lookups
CREATE INDEX IF NOT EXISTS idx_barber_applications_phone ON barber_applications(phone_number) WHERE phone_number IS NOT NULL;

