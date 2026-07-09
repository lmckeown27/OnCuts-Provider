-- Admin dashboard treasury snapshot (GET /api/admin/treasury).
-- Creates the VIEW expected by older docs / ad-hoc queries if it was never applied from schema-v2.sql.

CREATE OR REPLACE VIEW platform_treasury AS
SELECT
  (SELECT COALESCE(SUM(available_amount + pending_amount), 0)::bigint FROM balances)
    AS total_user_balances_cents,
  (SELECT COALESCE(SUM(amount), 0)::bigint FROM escrow_holds WHERE status = 'held')
    AS total_escrow_cents,
  (SELECT COALESCE(SUM(amount), 0)::bigint FROM platform_fees WHERE NOT COALESCE(withdrawn, false))
    AS total_fees_cents;
