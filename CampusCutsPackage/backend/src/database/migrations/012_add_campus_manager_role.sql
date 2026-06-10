-- Add CAMPUS_MANAGER to UserRole enum
-- Campus Managers have all barber + consumer functionality plus management capabilities

-- Add the new role value to the enum
ALTER TYPE "UserRole" ADD VALUE IF NOT EXISTS 'CAMPUS_MANAGER';

-- Note: Users with role CAMPUS_MANAGER should also have a barber profile
-- The isCampusManager flag on barbers table remains for backward compatibility
-- but the role field on users table is now the source of truth

COMMENT ON TYPE "UserRole" IS 'User roles: CONSUMER (students booking haircuts), BARBER (providing services), CAMPUS_MANAGER (manages barbers for a campus), ADMIN (platform admin)';

