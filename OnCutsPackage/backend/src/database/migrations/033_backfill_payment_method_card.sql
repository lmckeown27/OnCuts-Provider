-- Backfill paymentMethod for settled Stripe / card bookings that predate webhook writes.
-- Cash stays explicit (`paymentMethod = 'cash'`); null on settled rows was treated as card in admin SQL.

UPDATE bookings
SET "paymentMethod" = 'card',
    "updatedAt" = NOW()
WHERE "paymentMethod" IS NULL
  AND (
    "paidAt" IS NOT NULL
    OR ("totalPaidCents" IS NOT NULL AND "totalPaidCents" > 0)
  );

COMMENT ON COLUMN bookings."paymentMethod" IS 'Payment method used: card or cash. Settled Stripe bookings default to card.';
