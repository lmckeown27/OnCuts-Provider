-- Per-consumer "hide from my list" for past bookings (does not delete the booking row).

CREATE TABLE IF NOT EXISTS consumer_hidden_bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consumer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (consumer_id, booking_id)
);

CREATE INDEX IF NOT EXISTS idx_consumer_hidden_bookings_consumer
  ON consumer_hidden_bookings(consumer_id);
