-- Per-stage flags so we send at most one push per milestone (24h / 12h / 3h / 1h before appointment).
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_push_24h_sent BOOLEAN DEFAULT FALSE;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_push_12h_sent BOOLEAN DEFAULT FALSE;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_push_3h_sent BOOLEAN DEFAULT FALSE;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_push_1h_sent BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN bookings.reminder_push_24h_sent IS 'Consumer push reminder sent for ~24h-before window';
COMMENT ON COLUMN bookings.reminder_push_12h_sent IS 'Consumer push reminder sent for ~12h-before window';
COMMENT ON COLUMN bookings.reminder_push_3h_sent IS 'Consumer push reminder sent for ~3h-before window';
COMMENT ON COLUMN bookings.reminder_push_1h_sent IS 'Consumer push reminder sent for ~1h-before window (separate from reminder_sent email)';
