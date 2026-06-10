-- OAuth-created accounts (e.g. Sign in with Apple) use a random password hash until the user sets one.
ALTER TABLE users ADD COLUMN IF NOT EXISTS has_platform_password BOOLEAN NOT NULL DEFAULT TRUE;

-- Existing Apple-linked accounts: allow first-time password setup in the app.
UPDATE users SET has_platform_password = FALSE WHERE apple_sub IS NOT NULL;
