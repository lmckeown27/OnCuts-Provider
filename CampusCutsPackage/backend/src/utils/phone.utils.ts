import { ApiError } from '../middleware/errorHandler';

/** Stable synthetic email for `pending_registrations` / `users.email` when signing up with phone only. */
export function syntheticEmailFromPhoneE164(e164: string): string {
  const digits = e164.replace(/\D/g, '');
  return `${digits}@phone.signup.campuscuts.com`;
}

/** Normalizes to E.164: leading +, or US 10-digit → +1. */
export function normalizePhoneToE164(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) {
    throw new ApiError(400, 'Phone number is required');
  }
  const digitsOnly = trimmed.replace(/\D/g, '');
  if (digitsOnly.length < 10) {
    throw new ApiError(400, 'Enter a valid phone number');
  }
  if (trimmed.startsWith('+')) {
    const rest = trimmed.slice(1).replace(/\D/g, '');
    if (rest.length < 10 || rest.length > 15) {
      throw new ApiError(400, 'Enter a valid phone number');
    }
    return `+${rest}`;
  }
  if (digitsOnly.length === 10) {
    return `+1${digitsOnly}`;
  }
  if (digitsOnly.length === 11 && digitsOnly.startsWith('1')) {
    return `+${digitsOnly}`;
  }
  throw new ApiError(400, 'Include country code (e.g. +1 for US) or use 10 digits for US numbers');
}

/** Resolves the internal registration key from `email` or `phone` (E.164) body fields. */
export function resolveRegistrationEmailFromBody(body: { email?: unknown; phone?: unknown }): string {
  const rawPhone = body.phone != null ? String(body.phone).trim() : '';
  const rawEmail = body.email != null ? String(body.email).trim() : '';
  if (rawPhone && rawEmail) {
    throw new ApiError(400, 'Provide only email or phone');
  }
  if (rawPhone) {
    return syntheticEmailFromPhoneE164(normalizePhoneToE164(rawPhone));
  }
  if (rawEmail) {
    return rawEmail.toLowerCase();
  }
  throw new ApiError(400, 'Email or phone is required');
}

export function isSyntheticPhoneEmail(email: string): boolean {
  return email.toLowerCase().endsWith('@phone.signup.campuscuts.com');
}

/** Reconstructs E.164 from synthetic `digits@phone.signup.campuscuts.com`. */
export function phoneE164FromSyntheticEmail(email: string): string | null {
  if (!isSyntheticPhoneEmail(email)) return null;
  const local = email.split('@')[0];
  if (!/^\d+$/.test(local)) return null;
  return `+${local}`;
}
