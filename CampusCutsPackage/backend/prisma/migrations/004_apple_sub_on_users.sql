-- Sign in with Apple: stable `sub` claim for repeat sign-ins when the identity JWT omits `email`.
ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_sub VARCHAR(255) NULL;

CREATE UNIQUE INDEX IF NOT EXISTS users_apple_sub_uidx ON users(apple_sub) WHERE apple_sub IS NOT NULL;
