import { Response, NextFunction } from 'express';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest } from '../middleware/auth';
import { logger } from '../utils/logger';

const SUI_ADDR = /^0x[0-9a-fA-F]{64}$/;

/**
 * Barber Sui (or legacy hex) payout address for Checkout metadata.
 * GET /api/barber/payout/status
 */
export async function getBarberPayoutStatus(req: AuthRequest, res: Response, next: NextFunction) {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      throw new ApiError(401, 'Not authenticated');
    }

    const result = await pool.query(
      `SELECT
         NULLIF(TRIM(sui_address), '') AS sui,
         NULLIF(TRIM("walletAddress"), '') AS legacy
       FROM users
       WHERE id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'User not found');
    }

    const row = result.rows[0];
    const payoutAddress = (row.sui as string | null) || (row.legacy as string | null) || null;
    const valid = Boolean(payoutAddress && SUI_ADDR.test(payoutAddress));

    res.json({
      success: true,
      data: {
        payout_ready: valid,
        /** Canonical payout id when valid; otherwise null */
        sui_address: valid ? payoutAddress : null,
        /** Raw DB value if present but not valid 0x+64 hex (user should replace) */
        invalid_stored_address: Boolean(payoutAddress && !valid),
        stored_address_preview: !valid && payoutAddress ? `${payoutAddress.slice(0, 10)}…` : null,
      },
    });
  } catch (e) {
    logger.error('getBarberPayoutStatus failed', e);
    next(e);
  }
}

const PLATFORM_FEE_RATE = 0.15;

function num(v: unknown): number {
  if (v === null || v === undefined) return 0;
  const n = typeof v === 'string' ? parseFloat(v) : Number(v);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Earnings snapshot for Payout Settings UI (ledger + booking-based estimate).
 * GET /api/barber/payout/summary
 */
export async function getBarberPayoutSummary(req: AuthRequest, res: Response, next: NextFunction) {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      throw new ApiError(401, 'Not authenticated');
    }

    const barberResult = await pool.query(
      `SELECT id FROM barbers WHERE "userId" = $1 AND "isActive" = true LIMIT 1`,
      [userId]
    );

    if (barberResult.rows.length === 0) {
      return res.json({
        success: true,
        data: {
          has_barber_profile: false,
          ledger_total_dollars: 0,
          ledger_pending_dollars: 0,
          ledger_paid_out_dollars: 0,
          booking_estimated_barber_cents: 0,
          paid_bookings_count: 0,
          recent_30d_barber_cents: 0,
          display_total_dollars: 0,
        },
      });
    }

    const barberId = barberResult.rows[0].id as string;

    let ledgerTotal = 0;
    let ledgerPending = 0;
    let ledgerPaidOut = 0;

    try {
      const ledgerRow = await pool.query(
        `SELECT 
          COALESCE(SUM(barber_payout), 0) AS total,
          COALESCE(SUM(CASE WHEN status = 'pending' THEN barber_payout ELSE 0 END), 0) AS pending,
          COALESCE(SUM(CASE WHEN status = 'succeeded' THEN barber_payout ELSE 0 END), 0) AS paid_out
         FROM payment_transactions
         WHERE barber_id = $1`,
        [barberId]
      );
      const lr = ledgerRow.rows[0] || {};
      ledgerTotal = num(lr.total);
      ledgerPending = num(lr.pending);
      ledgerPaidOut = num(lr.paid_out);
    } catch (ledgerErr: unknown) {
      const pe = ledgerErr as { code?: string; message?: string };
      // 42501 = insufficient_privilege; 42P01 = undefined_table
      if (pe.code === '42501' || pe.code === '42P01') {
        logger.warn(
          'getBarberPayoutSummary: skipping payment_transactions ledger (missing table or GRANT); using booking estimate only',
          { code: pe.code, barberId }
        );
      } else {
        throw ledgerErr;
      }
    }

    const [bookingRow, recentRow] = await Promise.all([
      pool.query(
        `SELECT 
          COALESCE(SUM(
            (b."priceUsdCents" - ROUND(b."priceUsdCents" * ${PLATFORM_FEE_RATE})::bigint)
            + COALESCE(b."tipAmountCents", 0)::bigint
          ), 0)::bigint AS est_cents,
          COUNT(*)::int AS cnt
         FROM bookings b
         WHERE b."barberId" = $1 AND UPPER(b.status::text) = 'PAID'`,
        [barberId]
      ),
      pool.query(
        `SELECT COALESCE(SUM(
            (b."priceUsdCents" - ROUND(b."priceUsdCents" * ${PLATFORM_FEE_RATE})::bigint)
            + COALESCE(b."tipAmountCents", 0)::bigint
          ), 0)::bigint AS est_cents
         FROM bookings b
         WHERE b."barberId" = $1
           AND UPPER(b.status::text) = 'PAID'
           AND (
             (b."paidAt" IS NOT NULL AND b."paidAt" >= NOW() - INTERVAL '30 days')
             OR (b."paidAt" IS NULL AND b."updatedAt" >= NOW() - INTERVAL '30 days')
           )`,
        [barberId]
      ),
    ]);

    const br = bookingRow.rows[0] || {};
    const bookingEstCents = num(br.est_cents);
    const paidCount = Math.round(num((br as { cnt?: unknown }).cnt));

    const rr = recentRow.rows[0] || {};
    const recent30Cents = num(rr.est_cents);

    const displayTotal =
      ledgerTotal > 0 ? ledgerTotal : Math.round(bookingEstCents) / 100;

    res.json({
      success: true,
      data: {
        has_barber_profile: true,
        ledger_total_dollars: ledgerTotal,
        ledger_pending_dollars: ledgerPending,
        ledger_paid_out_dollars: ledgerPaidOut,
        booking_estimated_barber_cents: Math.round(bookingEstCents),
        paid_bookings_count: paidCount,
        recent_30d_barber_cents: Math.round(recent30Cents),
        display_total_dollars: displayTotal,
      },
    });
  } catch (e) {
    logger.error('getBarberPayoutSummary failed', e);
    next(e);
  }
}
