-- Intera / CampusCuts: user-chosen password flag (idempotent with 005_has_platform_password.sql if already applied).
ALTER TABLE users ADD COLUMN IF NOT EXISTS has_platform_password BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE users SET has_platform_password = FALSE WHERE apple_sub IS NOT NULL;
