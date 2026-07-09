/**
 * Polymarket-style wallet picker: grid of Wallet Standard (browser extension) wallets
 * for Sui, then fill payout address from the connected account.
 */
import { useCallback, useEffect, useState } from 'react';
import { useConnectWallet, useCurrentAccount, useWallets } from '@mysten/dapp-kit';
import { normalizeSuiAddress, isValidSuiAddress } from '@mysten/sui/utils';
import type { WalletWithRequiredFeatures } from '@mysten/wallet-standard';
import { X, Wallet } from 'lucide-react';
import toast from 'react-hot-toast';
import Button from './Button';

const SUI_SIGN_FEATURES = ['sui:signTransaction', 'sui:signTransactionBlock'] as const;

function walletSupportsSuiConnect(wallet: WalletWithRequiredFeatures) {
  if (!SUI_SIGN_FEATURES.some((f) => f in wallet.features)) {
    return false;
  }
  // Slush is optional infra; barbers should use official Sui Wallet / Suiet — hide from picker.
  if (wallet.name?.toLowerCase().includes('slush')) {
    return false;
  }
  return true;
}

const SUI_WALLET_CHROME =
  'https://chromewebstore.google.com/detail/sui-wallet/opcgpfmipidbgpenhmajoajpbobppdil';

type Props = {
  onAddressChosen: (normalizedAddress: string) => void;
  disabled?: boolean;
};

export default function PayoutBrowserWalletConnect({ onAddressChosen, disabled }: Props) {
  const [open, setOpen] = useState(false);
  const [connectingName, setConnectingName] = useState<string | null>(null);
  const wallets = useWallets().filter(walletSupportsSuiConnect);
  const { mutate: connectWallet } = useConnectWallet();
  const account = useCurrentAccount();

  const close = useCallback(() => {
    if (connectingName) return;
    setOpen(false);
  }, [connectingName]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, close]);

  const handleUseConnected = () => {
    if (!account?.address) return;
    const n = normalizeSuiAddress(account.address);
    if (!isValidSuiAddress(n)) return;
    onAddressChosen(n);
  };

  const handlePickWallet = (wallet: WalletWithRequiredFeatures) => {
    setConnectingName(wallet.name);
    connectWallet(
      { wallet },
      {
        onSuccess: () => {
          setConnectingName(null);
          setOpen(false);
          toast.success(`Connected to ${wallet.name}`);
        },
        onError: (err) => {
          setConnectingName(null);
          toast.error(err?.message || 'Could not connect wallet');
        },
      }
    );
  };

  return (
    <div className="rounded-xl border border-gray-200 bg-slate-50/80 p-4 mb-5">
      <p className="text-sm font-medium text-gray-900 mb-1">Optional: browser extension</p>
      <p className="text-xs text-gray-600 mb-3">
        If you use Sui Wallet, Suiet, or similar (Wallet Standard), you can connect to fill the field. You can
        always paste an address instead—no extension required.
      </p>
      <div className="flex flex-col sm:flex-row sm:flex-wrap sm:items-center gap-3">
        <button
          type="button"
          disabled={disabled}
          onClick={() => setOpen(true)}
          className="inline-flex items-center justify-center rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 disabled:opacity-50"
        >
          Connect wallet
        </button>
        {account?.address && (
          <>
            <span
              className="text-xs font-mono text-gray-700 truncate max-w-full sm:max-w-[220px]"
              title={account.address}
            >
              {normalizeSuiAddress(account.address)}
            </span>
            <Button
              type="button"
              variant="secondary"
              size="sm"
              disabled={disabled}
              onClick={handleUseConnected}
            >
              Fill payout address
            </Button>
          </>
        )}
      </div>
      <p className="text-[11px] text-gray-500 mt-2">
        After filling, tap <strong>Save payout address</strong> below to store it on your account.
      </p>

      {open && (
        <div
          className="fixed inset-0 z-[200] flex items-center justify-center p-4 bg-black/50 transition-opacity duration-200"
          role="presentation"
          onClick={close}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="payout-wallet-picker-title"
            className="relative w-full max-w-md rounded-3xl border border-gray-200 bg-white p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              type="button"
              aria-label="Close"
              disabled={!!connectingName}
              onClick={close}
              className="absolute right-4 top-4 rounded-lg p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-800 disabled:opacity-40"
            >
              <X className="h-5 w-5" />
            </button>
            <h2 id="payout-wallet-picker-title" className="pr-10 text-xl font-semibold text-gray-900">
              Connect a wallet
            </h2>
            <p className="mt-1 text-sm text-gray-600">
              Optional: connect a browser extension. You can also paste a Sui address in Payout Settings without
              installing anything.
            </p>

            <div className="my-5 flex w-full items-center gap-4">
              <div className="h-px flex-1 bg-gray-200" />
              <span className="text-xs font-medium text-gray-500">Sui extensions</span>
              <div className="h-px flex-1 bg-gray-200" />
            </div>

            {wallets.length > 0 ? (
              <ul className="grid grid-cols-4 gap-3">
                {wallets.map((w, idx) => (
                    <li key={`${w.name}-${idx}`}>
                      <button
                        type="button"
                        disabled={disabled || !!connectingName}
                        onClick={() => handlePickWallet(w)}
                        className="flex h-14 w-full flex-col items-center justify-center rounded-xl border border-gray-200 bg-white p-2 transition hover:border-primary-300 hover:bg-primary-50/50 active:scale-[0.97] disabled:cursor-not-allowed disabled:opacity-50"
                        title={w.name}
                      >
                        {typeof w.icon === 'string' ? (
                          <img src={w.icon} alt="" className="h-8 w-8 rounded-lg object-contain" />
                        ) : (
                          <Wallet className="h-8 w-8 text-primary-600" aria-hidden />
                        )}
                        <span className="sr-only">{w.name}</span>
                      </button>
                    </li>
                ))}
              </ul>
            ) : (
              <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
                <p className="font-medium">No browser wallet detected</p>
                <p className="mt-1 text-xs text-amber-800">
                  Close this window and <strong>paste your Sui address</strong> in the field below, or install the
                  official{' '}
                  <a
                    href={SUI_WALLET_CHROME}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-semibold underline hover:text-amber-950"
                  >
                    Sui Wallet extension
                  </a>{' '}
                  if you prefer connecting instead.
                </p>
              </div>
            )}

            {connectingName && (
              <p className="mt-4 text-center text-sm text-gray-600">
                Confirm connection in <span className="font-medium">{connectingName}</span>…
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
