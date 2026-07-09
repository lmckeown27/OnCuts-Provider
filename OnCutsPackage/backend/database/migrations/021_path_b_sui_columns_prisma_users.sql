-- Sui / zkLogin on Prisma-managed `users` (camelCase "walletAddress" already holds legacy hex).
-- Adds zkLogin / Sui columns if missing (snake_case is fine alongside camelCase columns).

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS sui_address VARCHAR(66),
  ADD COLUMN IF NOT EXISTS zk_login_salt TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS users_sui_address_key ON users (sui_address) WHERE sui_address IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_sui_address ON users (sui_address);

COMMENT ON COLUMN users.sui_address IS 'Sui payout / zkLogin address';
COMMENT ON COLUMN users.zk_login_salt IS 'Opaque salt for zkLogin derivation';
