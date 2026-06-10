/**
 * Sui helpers. Balance reads go through SuiClient; zkLogin owns addresses.
 */

import type { SuiClient } from '@mysten/sui/client';

export async function getSuiBalanceMist(
  client: SuiClient,
  address: string
): Promise<bigint> {
  const bal = await client.getBalance({ owner: address });
  return BigInt(bal.totalBalance);
}

export function suiExplorerTxUrl(digest: string, network: 'testnet' | 'mainnet' | 'devnet' = 'testnet'): string {
  return `https://suiexplorer.com/txblock/${digest}?network=${network}`;
}
