-- Fix: "permission denied for table payment_transactions" on GET /api/v1/barber/payout/summary
--
-- Run as a superuser (e.g. postgres), after identifying your app role from DATABASE_URL:
--   \du
--   SELECT current_user;
--
-- Replace app_role below with that role name (often matches the DB user in Railway/EC2 .env).

-- GRANT SELECT ON TABLE payment_transactions TO app_role;
-- GRANT INSERT, UPDATE, DELETE ON TABLE payment_transactions TO app_role;  -- if webhooks write this table

-- Example (uncomment and rename):
-- GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.payment_transactions TO campuscuts;

-- Optional: default privileges for future tables created by migrations run as superuser:
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO campuscuts;
