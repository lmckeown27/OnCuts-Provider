-- Rename Aptos-era column; application prefers sui_address, then legacy_wallet_address.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'aptos_address'
  ) THEN
    ALTER TABLE users RENAME COLUMN aptos_address TO legacy_wallet_address;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE c.relkind = 'i' AND c.relname = 'idx_users_aptos_address' AND n.nspname = 'public') THEN
    ALTER INDEX idx_users_aptos_address RENAME TO idx_users_legacy_wallet_address;
  END IF;
END $$;

COMMENT ON COLUMN users.legacy_wallet_address IS 'Pre-Sui / custodial-era hex id; prefer sui_address for settlement';
