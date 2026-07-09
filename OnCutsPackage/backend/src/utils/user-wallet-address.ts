/**
 * Resolve user on-chain identity: `sui_address` (zkLogin), then Prisma `"walletAddress"` (hex id).
 *
 * DBs that only have `legacy_wallet_address` (snake_case) should add/copy into `"walletAddress"` or adjust SQL.
 */

export const USER_PRIMARY_WALLET_SQL_U =
  'COALESCE(NULLIF(TRIM(u.sui_address), \'\'), NULLIF(TRIM(u."walletAddress"), \'\'))';

export const USER_PRIMARY_WALLET_SQL =
  'COALESCE(NULLIF(TRIM(sui_address), \'\'), NULLIF(TRIM("walletAddress"), \'\'))';

export function primaryWalletFromUserRow(row: {
  sui_address?: string | null;
  legacy_wallet_address?: string | null;
  walletAddress?: string | null;
}): string | undefined {
  const s = row.sui_address?.trim();
  if (s) return s;
  const w = row.walletAddress?.trim();
  if (w) return w;
  const l = row.legacy_wallet_address?.trim();
  if (l) return l;
  return undefined;
}
