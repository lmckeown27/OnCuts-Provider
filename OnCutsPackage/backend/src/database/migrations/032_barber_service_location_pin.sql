-- Public discovery pin metadata on barbers (device vs manual / web-only).
ALTER TABLE barbers
  ADD COLUMN IF NOT EXISTS service_location_label TEXT,
  ADD COLUMN IF NOT EXISTS service_location_source VARCHAR(32),
  ADD COLUMN IF NOT EXISTS service_location_web_only BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN barbers.service_location_label IS 'Human-readable label for the public discovery pin';
COMMENT ON COLUMN barbers.service_location_source IS 'device | manual | campus_default — how the public pin was set';
COMMENT ON COLUMN barbers.service_location_web_only IS 'When true, device GPS updates are ignored so a manual PlaceSearch pin sticks';
