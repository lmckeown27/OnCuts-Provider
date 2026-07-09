/**
 * Phone-first signup: SMS code before password (no row in pending_registrations until password is set).
 */
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { generateVerificationCode } from './verification.service';

const OTP_EXPIRY_MS = 60 * 60 * 1000; // 1 hour

export interface PhoneSignupPendingRow {
  phoneE164: string;
  firstName: string;
  lastName: string;
  role: string;
  campusId: string | null;
  verificationCode: string;
  expiresAt: Date;
}

async function ensureTable(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS phone_signup_pending (
      phone_e164 VARCHAR(20) PRIMARY KEY,
      first_name VARCHAR(255) NOT NULL,
      last_name VARCHAR(255) NOT NULL,
      role VARCHAR(50) NOT NULL,
      campus_id UUID,
      verification_code VARCHAR(6) NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
    )
  `);
}

export async function initPhoneSignupSchema(): Promise<void> {
  await ensureTable();
}

export async function upsertPhoneSignupOtp(params: {
  phoneE164: string;
  firstName: string;
  lastName: string;
  role: string;
  campusId: string | null;
}): Promise<string> {
  await ensureTable();
  const code = generateVerificationCode();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + OTP_EXPIRY_MS);

  await pool.query(
    `
    INSERT INTO phone_signup_pending (phone_e164, first_name, last_name, role, campus_id, verification_code, expires_at, created_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    ON CONFLICT (phone_e164) DO UPDATE SET
      first_name = EXCLUDED.first_name,
      last_name = EXCLUDED.last_name,
      role = EXCLUDED.role,
      campus_id = EXCLUDED.campus_id,
      verification_code = EXCLUDED.verification_code,
      expires_at = EXCLUDED.expires_at,
      created_at = EXCLUDED.created_at
    `,
    [
      params.phoneE164,
      params.firstName,
      params.lastName,
      params.role,
      params.campusId,
      code,
      expiresAt,
      now,
    ]
  );

  logger.info(`Phone signup OTP created for ${params.phoneE164}`);
  return code;
}

/**
 * Validates code and returns profile row (does not delete — caller issues ticket or fails).
 */
export async function verifyPhoneSignupOtp(
  phoneE164: string,
  code: string
): Promise<PhoneSignupPendingRow | null> {
  await ensureTable();
  const result = await pool.query(
    `
    SELECT phone_e164, first_name, last_name, role, campus_id, verification_code, expires_at
    FROM phone_signup_pending
    WHERE phone_e164 = $1
    `,
    [phoneE164]
  );

  if (result.rows.length === 0) {
    return null;
  }

  const row = result.rows[0];
  if (new Date() > new Date(row.expires_at)) {
    await pool.query('DELETE FROM phone_signup_pending WHERE phone_e164 = $1', [phoneE164]);
    return null;
  }

  if (row.verification_code !== code) {
    return null;
  }

  await pool.query('DELETE FROM phone_signup_pending WHERE phone_e164 = $1', [phoneE164]);

  return {
    phoneE164: row.phone_e164,
    firstName: row.first_name,
    lastName: row.last_name,
    role: row.role,
    campusId: row.campus_id,
    verificationCode: row.verification_code,
    expiresAt: row.expires_at,
  };
}
