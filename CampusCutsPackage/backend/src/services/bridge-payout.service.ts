import axios, { AxiosError } from 'axios';
import { logger } from '../utils/logger';

/** 80% barber USDC, 20% platform treasury on Sui (after Stripe settles). */
const BARBER_SHARE = 0.8;

export interface BridgePayoutParams {
  amountTotalCents: number;
  barberSuiAddress: string;
  bookingId: string;
  stripeCheckoutSessionId: string;
}

/**
 * POST /v1/payouts — request body varies by Bridge provider; adjust to live API docs.
 */
export async function requestBridgePayoutToSui(
  params: BridgePayoutParams
): Promise<{ bridgePayoutId: string; raw: unknown }> {
  const apiKey = process.env.BRIDGE_API_KEY;
  const baseUrl = process.env.BRIDGE_API_BASE_URL || 'https://api.bridge.example';
  const treasury = process.env.SUI_TREASURY_ADDRESS;

  if (!apiKey) {
    logger.warn('BRIDGE_API_KEY missing — logging payout intent only (dev mode)');
    const barberCents = Math.floor(params.amountTotalCents * BARBER_SHARE);
    const treasuryCents = params.amountTotalCents - barberCents;
    logger.info('Bridge payout (dry-run)', {
      bookingId: params.bookingId,
      sessionId: params.stripeCheckoutSessionId,
      barberSui: params.barberSuiAddress,
      treasury,
      barberUsdcCents: barberCents,
      treasuryUsdcCents: treasuryCents,
    });
    return {
      bridgePayoutId: `dry-run-${params.stripeCheckoutSessionId}`,
      raw: { mode: 'dry_run' },
    };
  }

  if (!treasury) {
    throw new Error('SUI_TREASURY_ADDRESS is required for Bridge payouts');
  }

  const barberUsdcCents = Math.floor(params.amountTotalCents * BARBER_SHARE);
  const treasuryUsdcCents = params.amountTotalCents - barberUsdcCents;

  const body = {
    chain: 'sui',
    currency: 'USDC',
    reference: params.bookingId,
    stripe_checkout_session_id: params.stripeCheckoutSessionId,
    recipients: [
      { address: params.barberSuiAddress, amount_cents: barberUsdcCents, role: 'barber' },
      { address: treasury, amount_cents: treasuryUsdcCents, role: 'platform' },
    ],
  };

  try {
    const res = await axios.post(`${baseUrl.replace(/\/$/, '')}/v1/payouts`, body, {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      timeout: 30_000,
    });

    const id =
      (res.data && (res.data.id || res.data.payout_id || res.data.payoutId)) ||
      `bridge-${params.stripeCheckoutSessionId}`;

    return { bridgePayoutId: String(id), raw: res.data };
  } catch (err) {
    const ax = err as AxiosError;
    logger.error('Bridge /v1/payouts failed', {
      status: ax.response?.status,
      data: ax.response?.data,
      message: ax.message,
    });
    throw err;
  }
}
