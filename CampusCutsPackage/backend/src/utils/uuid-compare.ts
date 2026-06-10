/**
 * Compare user/database UUIDs from mixed sources (JWT, node-pg) without
 * false negatives from casing or trivial whitespace differences.
 */
export function sameUuid(a: unknown, b: unknown): boolean {
  const norm = (v: unknown) =>
    (typeof v === 'string' ? v : String(v ?? '')).trim().toLowerCase();
  const sa = norm(a);
  const sb = norm(b);
  return sa.length > 0 && sa === sb;
}
