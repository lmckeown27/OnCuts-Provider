import { pool } from '../database/connection';
import type { JwtPayload } from '../middleware/auth';

/**
 * Role embedded in JWT must match `requireRole` hierarchy (student | barber | campus_manager | admin).
 * Users with `users.role = CONSUMER` but an active `barbers` row are treated as `barber` for API access.
 */
export async function resolveAccessTokenRole(
  userId: string,
  dbRole: string
): Promise<JwtPayload['role']> {
  const r = (dbRole || '').toUpperCase();
  if (r === 'ADMIN') return 'admin';
  if (r === 'CAMPUS_MANAGER') return 'campus_manager';
  if (r === 'BARBER') return 'barber';

  const barberCheck = await pool.query(
    'SELECT 1 FROM barbers WHERE "userId" = $1 AND "isActive" = true LIMIT 1',
    [userId]
  );
  if (barberCheck.rows.length > 0) {
    return 'barber';
  }

  return 'student';
}
