-- 029_mobile_devices_bundle_id.sql
--
-- The CampusCuts backend supports two iOS clients that share this `mobile_devices` table:
--
--   * Consumer iOS app — bundle id `com.campuscuts.ios`
--   * Provider iOS app — bundle id `Liam.Intera---Provider`
--
-- APNs requires the `apns-topic` header to match the receiving app's bundle id exactly. Before
-- this column existed, `pushNotification.service.ts` set the topic to a single env var
-- (`APN_BUNDLE_ID`) for every iOS device — meaning whichever bundle wasn't picked silently lost
-- every push (APN rejects the others as `TopicDisallowed` / `BadTopic`).
--
-- The fix: record the registering app's bundle id at `POST /notifications/register-device`
-- time and use it as the per-device APN topic at send time. The env var stays as a fallback
-- for legacy rows where `bundle_id IS NULL`.
--
-- Safe to apply on a live database: additive, no defaults required, no constraint changes.

ALTER TABLE mobile_devices
    ADD COLUMN IF NOT EXISTS bundle_id VARCHAR(255);

COMMENT ON COLUMN mobile_devices.bundle_id IS
    'iOS bundle identifier (or Android package name) of the app that registered this token. Used as the APN apns-topic so consumer and provider iOS apps route correctly. NULL on legacy rows; pushNotification.service.ts falls back to process.env.APN_BUNDLE_ID.';
