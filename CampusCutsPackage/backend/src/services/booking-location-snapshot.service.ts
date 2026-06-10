/**
 * Copies location fields from the linked conversation onto the booking row.
 * Required because conversations are deleted after payment while the app still
 * lists booking history with location via GET /bookings-simple.
 */

export async function snapshotBookingLocationFromConversation(
  bookingId: string,
  client: { query: (text: string, values?: unknown[]) => Promise<unknown> }
): Promise<void> {
  await client.query(
    `UPDATE bookings b
     SET "serviceLocation" = COALESCE(NULLIF(TRIM(b."serviceLocation"), ''), c.location),
         "serviceLocationDetails" = COALESCE(
           NULLIF(TRIM(b."serviceLocationDetails"), ''),
           c.location_details
         )
     FROM conversations c
     WHERE c.booking_id = b.id AND b.id = $1`,
    [bookingId]
  );
}
