-- 030_backfill_mobile_devices_bundle_id_for_barbers.sql
--
-- Migration 029 added `mobile_devices.bundle_id` so per-device APN topics can be set
-- correctly. Devices that registered **before** 029 still have `bundle_id IS NULL`. Until
-- those rows are reconciled they fall through to env-var-based topic resolution in
-- `pushNotification.service.ts`, which is the path that produces `DeviceTokenNotForTopic`
-- for the provider bundle (`Liam.Intera---Provider` — note: three hyphens, exact match
-- required).
--
-- This migration backfills `bundle_id` for legacy iOS rows whose owning user is an
-- **active barber** so the runtime can stop relying on the env-var fallback for them.
-- We intentionally leave non-barber NULL rows alone — they could legitimately be either
-- the consumer iOS app (`com.campuscuts.ios`) or any future bundle.
--
-- Safe to apply on a live DB:
--   * UPDATE only touches rows where the column is currently NULL.
--   * Only sets the column on iOS rows belonging to active barbers.
--   * Falls back to the bundle id you provide via the SET statement below; defaulted to
--     `Liam.Intera---Provider` because that is the only provider iOS bundle currently in
--     production. If you ever ship a second provider bundle, change the literal.
--   * Wrapped in a SAVEPOINT-style assertion that aborts if more rows would be touched than
--     the expected 1–500 ballpark, as a paranoia check against a bad join.

BEGIN;

-- Pre-check: how many rows would be backfilled?
DO $$
DECLARE
    candidate_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO candidate_count
      FROM mobile_devices md
      JOIN barbers b
        ON b."userId" = md.user_id AND b."isActive" = true
     WHERE md.platform = 'ios'
       AND md.is_active = true
       AND md.bundle_id IS NULL;

    RAISE NOTICE 'Backfill candidate count for provider iOS devices = %', candidate_count;

    IF candidate_count > 500 THEN
        RAISE EXCEPTION
            'Refusing to backfill % rows — that is suspiciously high. Inspect manually before re-running.',
            candidate_count;
    END IF;
END $$;

UPDATE mobile_devices md
   SET bundle_id = 'Liam.Intera---Provider',
       updated_at = NOW()
  FROM barbers b
 WHERE md.user_id = b."userId"
   AND b."isActive" = true
   AND md.platform = 'ios'
   AND md.is_active = true
   AND md.bundle_id IS NULL;

-- Sanity: every active barber's iOS row now has a non-null bundle id.
DO $$
DECLARE
    leftover BIGINT;
BEGIN
    SELECT COUNT(*) INTO leftover
      FROM mobile_devices md
      JOIN barbers b
        ON b."userId" = md.user_id AND b."isActive" = true
     WHERE md.platform = 'ios'
       AND md.is_active = true
       AND md.bundle_id IS NULL;

    IF leftover > 0 THEN
        RAISE WARNING
            'After backfill, % active-barber iOS rows still have NULL bundle_id.', leftover;
    END IF;
END $$;

COMMIT;
