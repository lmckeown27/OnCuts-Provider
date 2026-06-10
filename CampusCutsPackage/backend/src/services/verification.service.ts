/**
 * Verification Service - Database-backed Verification Code Management
 * 
 * Manages pending user registrations and email verification codes.
 * Uses PostgreSQL for persistence (survives server restarts).
 * Codes expire after 1 hour.
 * 
 * @module verification.service
 */

import { logger } from '../utils/logger';
import { pool } from '../database/connection';

/**
 * Pending Registration Data
 */
export interface PendingRegistration {
  email: string;
  password: string;
  firstName: string;
  lastName: string;
  campusId: string | null;
  role: 'student' | 'barber';
  verificationCode: string;
  expiresAt: Date;
  createdAt: Date;
}

// Legacy alias for backwards compatibility
export type { PendingRegistration as PendingRegistrationData };

/**
 * Verification Code Expiration Time (1 hour)
 */
const VERIFICATION_CODE_EXPIRY_MS = 60 * 60 * 1000; // 1 hour

/**
 * Generate Random 6-Digit Verification Code
 * 
 * @returns 6-digit numeric string
 */
export function generateVerificationCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * Initialize pending_registrations table if it doesn't exist
 */
async function ensureTableExists(): Promise<void> {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS pending_registrations (
        email VARCHAR(255) PRIMARY KEY,
        password_hash TEXT NOT NULL,
        first_name VARCHAR(255) NOT NULL,
        last_name VARCHAR(255) NOT NULL,
        campus_id UUID,
        role VARCHAR(50) NOT NULL,
        verification_code VARCHAR(6) NOT NULL,
        expires_at TIMESTAMP NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
  } catch (error) {
    logger.error('Failed to create pending_registrations table:', error);
  }
}

/**
 * Run after PostgreSQL is connected (see index.ts). Avoids module-load races with the DB pool.
 */
export async function initVerificationSchema(): Promise<void> {
  await ensureTableExists();
}

/**
 * Create Pending Registration
 * 
 * Stores user registration data with email verification code.
 * Overwrites existing pending registration for the same email.
 * 
 * @param registrationData - User registration data
 * @returns Email verification code
 */
export async function createPendingRegistration(
  registrationData: Omit<PendingRegistration, 'verificationCode' | 'expiresAt' | 'createdAt'>
): Promise<string> {
  const verificationCode = generateVerificationCode();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + VERIFICATION_CODE_EXPIRY_MS);
  
  const emailKey = registrationData.email.toLowerCase();
  
  try {
    // Upsert - insert or update if exists
    await pool.query(`
      INSERT INTO pending_registrations (email, password_hash, first_name, last_name, campus_id, role, verification_code, expires_at, created_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      ON CONFLICT (email) DO UPDATE SET
        password_hash = $2,
        first_name = $3,
        last_name = $4,
        campus_id = $5,
        role = $6,
        verification_code = $7,
        expires_at = $8,
        created_at = $9
    `, [
      emailKey,
      registrationData.password,
      registrationData.firstName,
      registrationData.lastName,
      registrationData.campusId,
      registrationData.role,
      verificationCode,
      expiresAt,
      now
    ]);
    
    logger.info(`Created pending registration for ${emailKey}, expires at ${expiresAt.toISOString()}`);
  } catch (error) {
    logger.error(`Failed to create pending registration for ${emailKey}:`, error);
    throw error;
  }
  
  return verificationCode;
}

/**
 * Verify Email Code and Complete Registration
 * 
 * Validates email verification code and returns registration data if valid.
 * Removes the pending registration after success.
 * 
 * @param email - User's email address
 * @param code - 6-digit verification code
 * @returns PendingRegistration if valid, null if invalid/expired
 */
export async function verifyCode(email: string, code: string): Promise<PendingRegistration | null> {
  const emailKey = email.toLowerCase();
  
  try {
    const result = await pool.query(`
      SELECT email, password_hash, first_name, last_name, campus_id, role, verification_code, expires_at, created_at
      FROM pending_registrations
      WHERE email = $1
    `, [emailKey]);
    
    if (result.rows.length === 0) {
      logger.warn(`No pending registration found for ${emailKey}`);
      return null;
    }
    
    const row = result.rows[0];
    const expiresAt = new Date(row.expires_at);
    
    // Check if expired
    if (new Date() > expiresAt) {
      await pool.query('DELETE FROM pending_registrations WHERE email = $1', [emailKey]);
      logger.warn(`Verification code expired for ${emailKey}`);
      return null;
    }
    
    // Check if code matches
    if (row.verification_code !== code) {
      logger.warn(`Invalid verification code for ${emailKey}`);
      return null;
    }
    
    // Valid! Remove from pending
    await pool.query('DELETE FROM pending_registrations WHERE email = $1', [emailKey]);
    logger.info(`Email verified for ${emailKey}, registration complete`);
    
    return {
      email: row.email,
      password: row.password_hash,
      firstName: row.first_name,
      lastName: row.last_name,
      campusId: row.campus_id,
      role: row.role,
      verificationCode: row.verification_code,
      expiresAt: expiresAt,
      createdAt: new Date(row.created_at)
    };
  } catch (error) {
    logger.error(`Error verifying code for ${emailKey}:`, error);
    return null;
  }
}

/**
 * Check if Email Has Pending Registration
 * 
 * @param email - User's email address
 * @returns true if pending registration exists and not expired
 */
export async function hasPendingRegistration(email: string): Promise<boolean> {
  const emailKey = email.toLowerCase();
  
  try {
    const result = await pool.query(`
      SELECT 1 FROM pending_registrations
      WHERE email = $1 AND expires_at > NOW()
    `, [emailKey]);
    
    return result.rows.length > 0;
  } catch (error) {
    logger.error(`Error checking pending registration for ${emailKey}:`, error);
    return false;
  }
}

/**
 * Get Pending Registration (without verification)
 * 
 * Returns pending registration data without verifying code.
 * Useful for checking status or resending code.
 * 
 * @param email - User's email address
 * @returns PendingRegistration if exists and not expired, null otherwise
 */
export async function getPendingRegistration(email: string): Promise<PendingRegistration | null> {
  const emailKey = email.toLowerCase();
  
  try {
    const result = await pool.query(`
      SELECT email, password_hash, first_name, last_name, campus_id, role, verification_code, expires_at, created_at
      FROM pending_registrations
      WHERE email = $1 AND expires_at > NOW()
    `, [emailKey]);
    
    if (result.rows.length === 0) {
      return null;
    }
    
    const row = result.rows[0];
    return {
      email: row.email,
      password: row.password_hash,
      firstName: row.first_name,
      lastName: row.last_name,
      campusId: row.campus_id,
      role: row.role,
      verificationCode: row.verification_code,
      expiresAt: new Date(row.expires_at),
      createdAt: new Date(row.created_at)
    };
  } catch (error) {
    logger.error(`Error getting pending registration for ${emailKey}:`, error);
    return null;
  }
}

/**
 * Cancel Pending Registration
 * 
 * Removes a pending registration from storage.
 * 
 * @param email - User's email address
 * @returns true if removed, false if didn't exist
 */
export async function cancelPendingRegistration(email: string): Promise<boolean> {
  const emailKey = email.toLowerCase();
  
  try {
    const result = await pool.query(
      'DELETE FROM pending_registrations WHERE email = $1',
      [emailKey]
    );
    
    const existed = (result.rowCount ?? 0) > 0;
    if (existed) {
      logger.info(`Cancelled pending registration for ${emailKey}`);
    }
    
    return existed;
  } catch (error) {
    logger.error(`Error cancelling pending registration for ${emailKey}:`, error);
    return false;
  }
}

/**
 * Cleanup Expired Registrations
 * 
 * Removes all expired pending registrations from database.
 */
export async function cleanupExpiredRegistrations(): Promise<void> {
  try {
    const result = await pool.query(
      'DELETE FROM pending_registrations WHERE expires_at < NOW()'
    );
    
    const removed = result.rowCount ?? 0;
    if (removed > 0) {
      logger.info(`Cleaned up ${removed} expired pending registrations`);
    }
  } catch (error) {
    logger.error('Error cleaning up expired registrations:', error);
  }
}

// Auto-cleanup every hour
setInterval(cleanupExpiredRegistrations, 60 * 60 * 1000);

logger.info('Verification service initialized (database-backed)');
