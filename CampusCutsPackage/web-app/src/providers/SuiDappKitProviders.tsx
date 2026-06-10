/**
 * Sui Wallet Standard + RPC (unused in main app tree; kept if you re-enable wallet connect).
 */
import { SuiClientProvider, WalletProvider } from '@mysten/dapp-kit';
import '@mysten/dapp-kit/dist/index.css';
import type { ReactNode } from 'react';
import { SUI_RPC_URL } from '../config/constants';

const networks = {
  /** Single network from env (testnet/mainnet fullnode URL) */
  default: { url: SUI_RPC_URL },
};

export function SuiDappKitProviders({ children }: { children: ReactNode }) {
  return (
    <SuiClientProvider networks={networks} defaultNetwork="default">
      <WalletProvider autoConnect={false} storageKey="campuscuts-sui-wallet-kit">
        {children}
      </WalletProvider>
    </SuiClientProvider>
  );
}
