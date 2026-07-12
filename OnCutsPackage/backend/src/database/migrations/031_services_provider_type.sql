-- 031_services_provider_type.sql
-- Tag campus service catalog rows with the operator profession they belong to
-- (`barber` / `beauty`), matching `barbers.provider_type`.

ALTER TABLE services
  ADD COLUMN IF NOT EXISTS provider_type VARCHAR(32) NOT NULL DEFAULT 'barber';

CREATE INDEX IF NOT EXISTS idx_services_provider_type
  ON services (provider_type);

COMMENT ON COLUMN services.provider_type IS
  'Operator profession this service belongs to (e.g. barber, beauty).';
