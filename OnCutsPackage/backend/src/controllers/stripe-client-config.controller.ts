import { Request, Response } from 'express';

function trimEnv(name: string): string | undefined {
  const v = process.env[name]?.trim();
  return v || undefined;
}

/**
 * Shared by `GET /api/v1/stripe/client-config` and the `bookings-simple` alias (for hosts where the
 * dedicated `/api/v1/stripe` mount is missing on an older build).
 */
/** First characters of the server publishable key so mobile can verify it matches the app bundle key (avoids opaque PaymentIntent HTTP 404). */
export function stripePublishableKeyPrefixForClientVerification(): string | undefined {
  const pk =
    trimEnv('STRIPE_PUBLISHABLE_KEY') ||
    trimEnv('VITE_STRIPE_PUBLISHABLE_KEY') ||
    '';
  if (!pk.startsWith('pk_')) return undefined;
  return pk.slice(0, 20);
}

export function sendStripeClientConfig(_req: Request, res: Response): void {
  const pk =
    trimEnv('STRIPE_PUBLISHABLE_KEY') ||
    trimEnv('VITE_STRIPE_PUBLISHABLE_KEY') ||
    '';
  if (!pk.startsWith('pk_')) {
    res.status(503).json({
      success: false,
      error:
        'Set STRIPE_PUBLISHABLE_KEY (or VITE_STRIPE_PUBLISHABLE_KEY) on the server to the same publishable key as your Stripe Dashboard for this deployment’s mode (live vs test).',
    });
    return;
  }
  res.json({ success: true, publishableKey: pk });
}
