import crypto from 'crypto';
import { logger } from '../utils/logger';

/**
 * zkLogin `poseidonHash` requires inputs in [0, r). A raw SHA-256 bigint can be ≥ r.
 * @see node_modules/@mysten/sui/dist/esm/zklogin/poseidon.js (BN254_FIELD_SIZE)
 */
const ZKLOGIN_SALT_FIELD_MODULUS = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

function getMasterSeed(): string {
  const s = process.env.MASTER_SEED?.trim() || process.env.SALT_SERVICE_SECRET?.trim();
  if (!s) {
    logger.error('MASTER_SEED (or SALT_SERVICE_SECRET fallback) is not configured');
    throw new Error('Salt service unavailable');
  }
  return s;
}

/**
 * Deterministic zkLogin salt per Google subject: SHA256(MASTER_SEED + google_sub), reduced mod BN254 field order.
 * Returned as a decimal string for @mysten/sui/zklogin (must be < r or poseidon throws).
 */
export function deriveZkLoginSaltFromGoogleSub(googleSub: string): string {
  if (!googleSub?.trim()) {
    throw new Error('Google subject (sub) required');
  }
  const seed = getMasterSeed();
  const hashHex = crypto.createHash('sha256').update(`${seed}${googleSub}`, 'utf8').digest('hex');
  const fromHash = BigInt(`0x${hashHex}`);
  const saltInField = fromHash % ZKLOGIN_SALT_FIELD_MODULUS;
  return saltInField.toString(10);
}

/**
 * Public salt API still accepts iss + sub; derivation uses `sub` only (Google identity).
 */
export function deriveZkLoginSalt(_issuer: string, subject: string): string {
  return deriveZkLoginSaltFromGoogleSub(subject);
}
