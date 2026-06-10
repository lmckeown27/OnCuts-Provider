-- Intera / CampusCuts: OAuth provider label (idempotent with 004_apple_sub_on_users.sql).
ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(32) NULL;

UPDATE users SET auth_provider = 'apple' WHERE apple_sub IS NOT NULL AND (auth_provider IS NULL OR auth_provider = '');
