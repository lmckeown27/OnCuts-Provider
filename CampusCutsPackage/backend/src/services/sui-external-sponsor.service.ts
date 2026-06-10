import axios, { AxiosError } from 'axios';
import { logger } from '../utils/logger';

/**
 * Optional HTTP gas station (e.g. Shinami): treasury builds + signs intent;
 * sponsor service returns a second signature for the same transaction bytes.
 *
 * POST JSON body (configurable):
 *   { "transactionBlockB64": "<base64>" }
 *
 * Expected JSON response (one of):
 *   { "sponsorSignature": "<base64>" }
 *   { "signature": "<base64>" }  // alias
 *
 * Set SUI_SPONSOR_API_URL (+ SUI_SPONSOR_API_KEY) to enable. If unset, the
 * relayer signs gas with GAS_SPONSOR_SECRET locally.
 */
export function isExternalGasSponsorConfigured(): boolean {
  return Boolean(process.env.SUI_SPONSOR_API_URL?.trim());
}

export async function fetchExternalSponsorSignature(transactionBytes: Uint8Array): Promise<string> {
  const url = process.env.SUI_SPONSOR_API_URL?.trim();
  if (!url) {
    throw new Error('SUI_SPONSOR_API_URL is not configured');
  }
  const key = process.env.SUI_SPONSOR_API_KEY?.trim();
  const transactionBlockB64 = Buffer.from(transactionBytes).toString('base64');

  try {
    const res = await axios.post<{
      sponsorSignature?: string;
      signature?: string;
    }>(
      url,
      { transactionBlockB64 },
      {
        timeout: 60_000,
        headers: {
          'Content-Type': 'application/json',
          ...(key ? { Authorization: `Bearer ${key}` } : {}),
        },
      }
    );
    const sig = res.data?.sponsorSignature || res.data?.signature;
    if (!sig || typeof sig !== 'string') {
      throw new Error('Sponsor API response missing sponsorSignature / signature');
    }
    return sig;
  } catch (e) {
    const ax = e as AxiosError;
    logger.error('External gas sponsor request failed', {
      status: ax.response?.status,
      data: ax.response?.data,
      message: ax.message,
    });
    throw e;
  }
}
