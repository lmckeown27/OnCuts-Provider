import { useEffect, useState } from 'react';
import { SuiClient } from '@mysten/sui/client';
import { DollarSign } from 'lucide-react';
import { SUI_RPC_URL, SUI_USDC_COIN_TYPE } from '../config/constants';

function formatUsdc6(baseUnits: bigint): string {
  const neg = baseUnits < 0n;
  const v = neg ? -baseUnits : baseUnits;
  const whole = v / 1000000n;
  const frac = (v % 1000000n).toString().padStart(6, '0');
  const s = `${whole}.${frac}`;
  return neg ? `-${s}` : s;
}

type Props = {
  suiAddress: string | null | undefined;
  className?: string;
};

/**
 * Reads USDC balance for the barber’s zkLogin / invisible wallet via Sui RPC (read-only).
 */
export default function InvisibleUsdcBalance({ suiAddress, className }: Props) {
  const [display, setDisplay] = useState<string>('—');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!suiAddress?.trim() || !SUI_USDC_COIN_TYPE) {
      setDisplay(SUI_USDC_COIN_TYPE ? '—' : 'Set VITE_SUI_USDC_COIN_TYPE');
      return;
    }

    let cancelled = false;
    setLoading(true);

    void (async () => {
      try {
        const client = new SuiClient({ url: SUI_RPC_URL });
        let cursor: string | null | undefined;
        let total = 0n;
        do {
          const page = await client.getCoins({
            owner: suiAddress.trim(),
            coinType: SUI_USDC_COIN_TYPE,
            cursor: cursor ?? undefined,
          });
          for (const c of page.data) {
            total += BigInt(c.balance);
          }
          cursor = page.hasNextPage ? page.nextCursor ?? null : null;
        } while (cursor && !cancelled);

        if (!cancelled) {
          setDisplay(formatUsdc6(total));
        }
      } catch {
        if (!cancelled) setDisplay('Error');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [suiAddress]);

  if (!suiAddress?.trim()) {
    return null;
  }

  const explorerBase =
    SUI_RPC_URL.includes('mainnet') || import.meta.env.VITE_SUI_EXPLORER_BASE_URL
      ? import.meta.env.VITE_SUI_EXPLORER_BASE_URL || 'https://suiscan.xyz/mainnet'
      : import.meta.env.VITE_SUI_EXPLORER_BASE_URL || 'https://suiscan.xyz/testnet';

  return (
    <div
      className={
        className ||
        'flex items-center justify-between rounded-xl border border-primary-200 bg-primary-50/60 px-4 py-3 text-sm'
      }
    >
      <div className="flex items-center gap-2 text-gray-800">
        <DollarSign className="h-5 w-5 text-primary-600 shrink-0" />
        <div>
          <p className="font-semibold text-gray-900">Invisible account (USDC)</p>
          <p className="text-xs text-gray-600">
            Balance on Sui for your zkLogin address{loading ? ' (loading…)' : ''}.
          </p>
        </div>
      </div>
      <div className="text-right">
        <p className="text-lg font-bold text-primary-800 tabular-nums">{display}</p>
        <a
          href={`${explorerBase.replace(/\/$/, '')}/address/${encodeURIComponent(suiAddress.trim())}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-primary-700 underline hover:text-primary-900"
        >
          View on explorer
        </a>
      </div>
    </div>
  );
}
