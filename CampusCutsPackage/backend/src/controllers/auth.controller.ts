/**
 * Authentication Controller
 * 
 * Handles user authentication operations including registration, login, and token management.
 * 
 * ## JWT Authentication Flow:
 * 
 * ### 1. User Registration:
 * ```
 * POST /api/v1/auth/register
 * Body: { email, password, firstName, lastName, campusId, role }
 * 
 * Process:
 * - Validates campus email domain
 * - Hashes password with bcrypt (10 rounds)
 * - On-chain identity via zkLogin / Sui, optional legacy_wallet_address
 * - Stores user in database
 * - Generates JWT token
 * - Returns user data + token
 * ```
 * 
 * ### 2. User Login:
 * ```
 * POST /api/v1/auth/login
 * Body: { email, password }
 * 
 * Process:
 * - Finds user by email
 * - Verifies password with bcrypt.compare()
 * - Generates JWT token with user data
 * - Updates last_login timestamp
 * - Returns user data + token
 * ```
 * 
 * ### 3. Authenticated Request:
 * ```
 * GET /api/v1/bookings
 * Headers: { Authorization: "Bearer <token>" }
 * 
 * Process:
 * - auth.middleware.ts extracts and verifies token
 * - Token payload decoded to req.user
 * - Route handler accesses req.user for user info
 * ```
 * 
 * ## JWT Token Structure:
 * 
 * ### Header:
 * ```json
 * {
 *   "alg": "HS256",  // HMAC with SHA-256
 *   "typ": "JWT"     // Token type
 * }
 * ```
 * 
 * ### Payload (JwtPayload):
 * ```json
 * {
 *   "userId": "123e4567-e89b-12d3-a456-426614174000",
 *   "email": "student@university.edu",
 *   "role": "student",
 *   "campusId": 1,
 *   "iat": 1704067200,  // Issued at (Unix timestamp)
 *   "exp": 1704672000   // Expiration (Unix timestamp)
 * }
 * ```
 * 
 * ### Signature:
 * ```
 * HMACSHA256(
 *   base64UrlEncode(header) + "." + base64UrlEncode(payload),
 *   JWT_SECRET
 * )
 * ```
 * 
 * ## Environment Variables Required:
 * - JWT_SECRET: Secret key for signing tokens (required, 32+ chars)
 * - JWT_EXPIRES_IN: Token expiration time (default: "7d")
 * - JWT_REFRESH_SECRET: Separate secret for refresh tokens (optional)
 * - JWT_REFRESH_EXPIRES_IN: Refresh token expiration (default: "30d")
 * 
 * ## Security Features:
 * 1. **Password Hashing**: bcrypt with 10 salt rounds
 * 2. **Token Signing**: HMAC-SHA256 signature verification
 * 3. **Token Expiration**: Automatic expiration (configurable)
 * 4. **Domain Validation**: Email must match campus domain
 * 5. **Account Status**: Checks is_active flag on login
 * 6. **Credential Obfuscation**: Same error for wrong email/password
 * 
 * @module auth.controller
 */

import { Request, Response, NextFunction } from 'express';
import bcrypt from 'bcrypt';
import { randomBytes } from 'crypto';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import appleSigninAuth from 'apple-signin-auth';
import { v4 as uuidv4 } from 'uuid';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest, JwtPayload } from '../middleware/auth';
import { logger } from '../utils/logger';
import {
  generateAccessToken,
  generateRefreshToken,
  generateEmailVerificationToken,
  generatePasswordResetToken,
  verifyToken,
} from '../utils/jwt.utils';
import { resolveAccessTokenRole } from '../utils/access-token-role';
import {
  sendVerificationEmail,
  sendPasswordResetEmail,
  sendWelcomeEmail,
  isAutoVerifyEnabled
} from '../services/email.service';
import {
  createPendingRegistration,
  verifyCode,
  getPendingRegistration
} from '../services/verification.service';
import { sendVerificationSms } from '../services/sms.service';
import {
  normalizePhoneToE164,
  resolveRegistrationEmailFromBody,
  phoneE164FromSyntheticEmail,
} from '../utils/phone.utils';
// Note: educationalDomainService removed - campus is now determined by user selection, not email domain

const googleOAuthClient = new OAuth2Client();

/** Optional `firstName` / `lastName` from the native client (Apple only sends full name on first authorization). */
function trimAppleProfileField(v: unknown, maxLen: number): string | null {
  if (v == null) return null;
  const s = String(v).trim();
  if (!s) return null;
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

function applePlaceholderFirstNameFromEmail(email: string): string {
  const local = (email.split('@')[0] ?? 'user').trim().slice(0, 100);
  return local.length > 0 ? local : 'User';
}

function isApplePrivateRelayEmail(email: string): boolean {
  return email.trim().toLowerCase().endsWith('@privaterelay.appleid.com');
}

function trimOptionalEmailField(v: unknown): string | undefined {
  if (v == null) return undefined;
  const s = String(v).trim().toLowerCase();
  if (!s || !s.includes('@')) return undefined;
  return s;
}

/** Client-supplemental email when the Apple JWT omits `email` (e.g. repeat sign-in); use Keychain replay from first auth. */
function clientSupplementalEmailFromBody(body: Record<string, unknown>): string | undefined {
  const keys = ['email', 'userEmail', 'appleEmail', 'contactEmail'] as const;
  for (const k of keys) {
    const e = trimOptionalEmailField(body[k]);
    if (e) return e;
  }
  return undefined;
}

function parseAppleNameFieldsFromBody(body: Record<string, unknown>): { first: string | null; last: string | null } {
  let first =
    trimAppleProfileField(body.firstName, 100) ??
    trimAppleProfileField(body.givenName, 100);
  let last =
    trimAppleProfileField(body.lastName, 100) ??
    trimAppleProfileField(body.familyName, 100);
  const full = body.fullName;
  if (full && typeof full === 'object') {
    const o = full as Record<string, unknown>;
    if (!first) {
      first =
        trimAppleProfileField(o.givenName, 100) ??
        trimAppleProfileField(o.given_name, 100);
    }
    if (!last) {
      last =
        trimAppleProfileField(o.familyName, 100) ??
        trimAppleProfileField(o.family_name, 100);
    }
  }
  return { first, last };
}

/**
 * Register New User - Step 1: Create Pending Registration
 * 
 * Creates a pending user registration and sends verification email.
 * User account is NOT created until email is verified.
 * 
 * ## Two-Step Registration Flow:
 * 1. POST /auth/register → Creates pending registration, sends verification email
 * 2. POST /auth/verify-email → Verifies code, creates user account, issues JWT
 * 
 * ## Request:
 * ```json
 * POST /api/v1/auth/register
 * {
 *   "email": "student@university.edu",
 *   "password": "SecurePassword123!",
 *   "firstName": "John",
 *   "lastName": "Doe",
 *   "campusId": 1,
 *   "role": "student"
 * }
 * ```
 * 
 * ## Response:
 * ```json
 * {
 *   "success": true,
 *   "message": "Verification email sent. Please check your inbox.",
 *   "data": {
 *     "email": "student@university.edu",
 *     "expiresIn": 600
 *   }
 * }
 * ```
 * 
 * ## AUTO_VERIFY_EMAILS Mode (Development):
 * If AUTO_VERIFY_EMAILS=true, the verification code is logged instead of emailed.
 * 
 * @param req - Express request with registration data
 * @param res - Express response
 * @param next - Express next function
 */
export const register = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { password, firstName, lastName, role, campusId: requestedCampusId } = req.body;

    if (!password || !firstName || !lastName || !role) {
      throw new ApiError(400, 'All fields are required');
    }

    let email: string;
    let phoneE164: string | null = null;
    try {
      email = resolveRegistrationEmailFromBody(req.body);
      const rawPhone = req.body.phone != null ? String(req.body.phone).trim() : '';
      if (rawPhone) {
        phoneE164 = normalizePhoneToE164(rawPhone);
      }
    } catch (e: unknown) {
      if (e instanceof ApiError) throw e;
      throw new ApiError(400, 'Invalid email or phone');
    }

    if (!phoneE164) {
      const emailDomain = email.split('@')[1];
      if (!emailDomain) {
        throw new ApiError(400, 'Please provide a valid email address');
      }
    }

    // Campus assignment: Use user-provided campusId if valid, otherwise leave as null
    // Consumers don't need to be tied to a university - they can browse barbers at any campus
    let campusId: string | null = null;
    
    if (requestedCampusId) {
      // Check if it's a valid UUID format
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      const isUuid = uuidRegex.test(requestedCampusId);
      
      let validCampus;
      if (isUuid) {
        // Look up by UUID
        validCampus = await pool.query(
          'SELECT id, name FROM campuses WHERE id = $1 AND is_active = TRUE',
          [requestedCampusId]
        );
      } else {
        // Look up by slug (convert slug to name pattern, e.g., "cal-poly" -> "%cal%poly%")
        // Or try exact name match first
        const slugPattern = requestedCampusId.replace(/-/g, '%');
        validCampus = await pool.query(
          `SELECT id, name FROM campuses 
           WHERE is_active = TRUE 
           AND (LOWER(name) LIKE $1 OR LOWER(REPLACE(name, ' ', '-')) = $2)
           ORDER BY name LIMIT 1`,
          [`%${slugPattern}%`, requestedCampusId.toLowerCase()]
        );
      }
      
      if (validCampus.rows.length > 0) {
        campusId = validCampus.rows[0].id;
        logger.info(`User selected campus: ${validCampus.rows[0].name} (ID: ${campusId})`);
      } else {
        logger.warn(`Invalid or inactive campusId provided: ${requestedCampusId}, proceeding without campus`);
      }
    }
    
    // No fallback campus - consumers can register without a campus affiliation
    if (!campusId) {
      logger.info('User registering without campus affiliation');
    }

    // Check if user already exists in database
    const existingUser = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
    
    if (existingUser.rows.length > 0) {
      throw new ApiError(400, 'User with this email already exists');
    }

    // If a pending registration exists, `createPendingRegistration` upserts a new code and expiry
    // (same as resend-verification) so users can request another email without waiting.

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // Create pending registration with email verification code
    const verificationCode = await createPendingRegistration({
      email,
      password: passwordHash,
      firstName,
      lastName,
      campusId,
      role
    });

    try {
      if (phoneE164) {
        await sendVerificationSms(phoneE164, verificationCode);
        logger.info(`Verification SMS sent to ${phoneE164} (registration email key: ${email})`);

        if (isAutoVerifyEnabled()) {
          return res.status(200).json({
            success: true,
            message: 'Registration pending SMS verification (AUTO-VERIFY MODE)',
            data: {
              email,
              phone: phoneE164,
              expiresIn: 600,
              verificationCode,
            },
          });
        }

        return res.status(200).json({
          success: true,
          message: 'Verification code sent to your phone.',
          data: {
            email,
            phone: phoneE164,
            expiresIn: 600,
          },
        });
      }

      await sendVerificationEmail(email, verificationCode);

      logger.info(`Verification email sent to ${email}`);

      if (isAutoVerifyEnabled()) {
        return res.status(200).json({
          success: true,
          message: 'Registration pending email verification (AUTO-VERIFY MODE)',
          data: {
            email,
            expiresIn: 600,
            verificationCode,
          },
        });
      }

      res.status(200).json({
        success: true,
        message: 'Verification email sent. Please check your inbox.',
        data: {
          email,
          expiresIn: 600,
        },
      });
    } catch (sendError: unknown) {
      logger.error('Failed to send verification:', sendError);
      throw new ApiError(500, 'Failed to send verification. Please try again later.');
    }
  } catch (error) {
    next(error);
  }
};

/**
 * Verify Email - Complete Registration
 * 
 * Verifies the 6-digit email code and creates the user account.
 * Creates the user row and issues JWT (no custodial chain wallet mint).
 * 
 * ## Request:
 * ```json
 * POST /api/v1/auth/verify-email
 * {
 *   "email": "student@university.edu",
 *   "code": "123456"
 * }
 * ```
 * 
 * ## Response:
 * ```json
 * {
 *   "success": true,
 *   "message": "Email verified successfully. Welcome to CampusCuts!",
 *   "data": {
 *     "user": {
 *       "id": "123e4567-e89b-12d3-a456-426614174000",
 *       "email": "student@university.edu",
 *       "firstName": "John",
 *       "lastName": "Doe",
 *       "role": "student",
 *       "campusId": 1
 *     },
 *     "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
 *     "suiAddress": null
 *   }
 * }
 * ```
 * 
 * @param req - Express request with email and verification code
 * @param res - Express response
 * @param next - Express next function
 */
export const verifyEmailRegistration = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { code } = req.body;

    if (!code) {
      throw new ApiError(400, 'Verification code is required');
    }

    let email: string;
    try {
      email = resolveRegistrationEmailFromBody(req.body);
    } catch {
      throw new ApiError(400, 'Email or phone and verification code are required');
    }

    // Verify email code
    const pendingReg = await verifyCode(email, code);

    if (!pendingReg) {
      throw new ApiError(400, 'Invalid or expired verification code');
    }

    // Check again if user was created in the meantime
    const existingUser = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
    
    if (existingUser.rows.length > 0) {
      throw new ApiError(400, 'User already exists. Please log in.');
    }

    // Check if this email has an approved guest barber application
    const approvedGuestApp = await pool.query(
      `SELECT id, campus_id, specialties FROM guest_barber_applications 
       WHERE email = $1 AND status = 'approved' AND linked_user_id IS NULL
       ORDER BY created_at DESC LIMIT 1`,
      [email.toLowerCase()]
    );

    const hasApprovedApplication = approvedGuestApp.rows.length > 0;

    // Map frontend role to database enum (student -> CONSUMER, barber -> BARBER)
    // If user has an approved guest application, make them a BARBER
    let dbRole: string;
    if (hasApprovedApplication) {
      dbRole = 'BARBER';
      logger.info(`User ${email} has an approved guest application - auto-promoting to BARBER`);
    } else {
      const roleMap: { [key: string]: string } = {
        'student': 'CONSUMER',
        'barber': 'BARBER',
        'admin': 'ADMIN'
      };
      dbRole = roleMap[pendingReg.role.toLowerCase()] || 'CONSUMER';
    }

    // Use campus from approved application if available, otherwise use the one from registration
    const campusId = hasApprovedApplication 
      ? approvedGuestApp.rows[0].campus_id 
      : pendingReg.campusId;

    // Barbers and consumers may register without a campus (e.g. Intera Provider uses device location instead of manual campus pick).
    if (!campusId) {
      logger.info(`User ${email} registering as ${dbRole} without campus affiliation`);
    }

    // Create user in database (off-chain for v1 - no blockchain wallets)
    // Note: Column names use camelCase in the database schema
    // id uses gen_random_uuid() since the column has no default
    const result = await pool.query(
      `INSERT INTO users (id, email, password_hash, first_name, last_name, "campusId", role, email_verified, "updatedAt")
       VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6::"UserRole", TRUE, NOW())
       RETURNING id, email, first_name, last_name, "campusId", role, "createdAt"`,
      [
        pendingReg.email,
        pendingReg.password,
        pendingReg.firstName,
        pendingReg.lastName,
        campusId,
        dbRole
      ]
    );

    const user = result.rows[0];

    // If user had an approved guest application, create their barber profile
    if (hasApprovedApplication) {
      const guestApp = approvedGuestApp.rows[0];
      const specialties = guestApp.specialties || [];
      
      // Generate pricing from specialties
      const SERVICE_BASE_PRICES: Record<string, number> = {
        'Buzz Cut': 23, 'Line Up': 23, 'Beard Trim': 23, 'Haircut': 28, 'Taper': 28,
        'Hot Shave': 28, 'Kids Cut': 28, 'Fade': 35, 'Haircut & Fade': 35, 'Mullet': 35,
        'Design/Art': 38, 'Afro Textures': 38, "Women's Cut": 40, 'Color Treatment': 45, 'Perm': 45,
      };
      const pricing = specialties.map((specialty: string) => ({
        name: specialty,
        price: SERVICE_BASE_PRICES[specialty] || 25,
      }));

      // Create barber profile
      await pool.query(
        `INSERT INTO barbers (
           id, "userId", "campusId", specialties, pricing, "isActive", "weeklySchedule",
           "currentMinPriceUsdCents", "currentMaxPriceUsdCents",
           "totalBookings", "completedBookings", "cancelledBookings", "totalReviews",
           "pricingMultiplier", "isCampusManager", "isOnboarded",
           "createdAt", "updatedAt"
         )
         VALUES (
           gen_random_uuid(), $1, $2, $3, $4, true, '{}',
           0, 0,
           0, 0, 0, 0,
           1.00, false, false,
           NOW(), NOW()
         )
         ON CONFLICT ("userId") DO UPDATE SET 
           specialties = EXCLUDED.specialties,
           pricing = EXCLUDED.pricing,
           "isActive" = true,
           "campusId" = EXCLUDED."campusId",
           "updatedAt" = NOW()`,
        [user.id, guestApp.campus_id, specialties, JSON.stringify(pricing)]
      );

      // Link the guest application to the new user
      await pool.query(
        'UPDATE guest_barber_applications SET linked_user_id = $1 WHERE id = $2',
        [user.id, guestApp.id]
      );

      logger.info(`Created barber profile for user ${user.id} from approved guest application ${guestApp.id}`);
    }

    const accessRole = await resolveAccessTokenRole(user.id, user.role);

    // Generate JWT tokens (role must match requireRole hierarchy, not raw DB enum)
    const token = generateAccessToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    const refreshToken = generateRefreshToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    // Send welcome email (non-blocking)
    sendWelcomeEmail(user.email, user.first_name).catch(err => {
      logger.error('Failed to send welcome email:', err);
    });

    logger.info(`New user registered and verified: ${user.email} (${user.role}, jwtRole=${accessRole})`);

    res.status(201).json({
      success: true,
      message: hasApprovedApplication 
        ? 'Email verified successfully. Welcome to CampusCuts! Your barber application has been linked to your account.'
        : 'Email verified successfully. Welcome to CampusCuts!',
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.first_name,
          lastName: user.last_name,
          role: user.role,
          campusId: user.campusId,
          emailVerified: true
        },
        accessToken: token,
        refreshToken
      }
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Resend Verification Code
 * 
 * Resends verification email with a new code to a pending registration.
 * 
 * ## Request:
 * ```json
 * POST /api/v1/auth/resend-verification
 * {
 *   "email": "student@university.edu"
 * }
 * ```
 * 
 * ## Response:
 * ```json
 * {
 *   "success": true,
 *   "message": "Verification email resent. Please check your inbox.",
 *   "data": {
 *     "email": "student@university.edu",
 *     "expiresIn": 600
 *   }
 * }
 * ```
 * 
 * @param req - Express request with email
 * @param res - Express response
 * @param next - Express next function
 */
export const resendVerificationCode = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    let email: string;
    try {
      email = resolveRegistrationEmailFromBody(req.body);
    } catch {
      throw new ApiError(400, 'Email or phone is required');
    }

    // Check if there's a pending registration
    const pendingReg = await getPendingRegistration(email);

    if (!pendingReg) {
      throw new ApiError(400, 'No pending registration found for this email. Please register first.');
    }

    // Check if user already exists
    const existingUser = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
    
    if (existingUser.rows.length > 0) {
      throw new ApiError(400, 'User already exists. Please log in.');
    }

    // Create new verification code (overwrites previous)
    const verificationCode = await createPendingRegistration({
      email: pendingReg.email,
      password: pendingReg.password,
      firstName: pendingReg.firstName,
      lastName: pendingReg.lastName,
      campusId: pendingReg.campusId,
      role: pendingReg.role
    });

    const smsPhone = phoneE164FromSyntheticEmail(pendingReg.email);

    try {
      if (smsPhone) {
        await sendVerificationSms(smsPhone, verificationCode);
        logger.info(`Verification SMS resent to ${smsPhone}`);
        if (isAutoVerifyEnabled()) {
          return res.status(200).json({
            success: true,
            message: 'Verification code resent (AUTO-VERIFY MODE)',
            data: {
              email,
              phone: smsPhone,
              expiresIn: 600,
              verificationCode,
            },
          });
        }
        return res.status(200).json({
          success: true,
          message: 'Verification code resent to your phone.',
          data: {
            email,
            phone: smsPhone,
            expiresIn: 600,
          },
        });
      }

      await sendVerificationEmail(email, verificationCode);

      logger.info(`Verification code resent to ${email}`);

      if (isAutoVerifyEnabled()) {
        return res.status(200).json({
          success: true,
          message: 'Verification email resent (AUTO-VERIFY MODE)',
          data: {
            email,
            expiresIn: 600,
            verificationCode,
          },
        });
      }

      res.status(200).json({
        success: true,
        message: 'Verification email resent. Please check your inbox.',
        data: {
          email,
          expiresIn: 600,
        },
      });
    } catch (sendError: unknown) {
      logger.error('Failed to resend verification:', sendError);
      throw new ApiError(500, 'Failed to resend verification. Please try again later.');
    }
  } catch (error) {
    next(error);
  }
};

/**
 * Login user
 */
export const login = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { email, password } = req.body;

    // Find user
    const result = await pool.query(
      `SELECT id, email, password_hash, first_name, last_name, "campusId", role, "isBlocked", "isBanned", email_verified, "avatarUrl", sui_address
       FROM users WHERE email = $1`,
      [email]
    );

    if (result.rows.length === 0) {
      throw new ApiError(401, 'Account not found', 'ACCOUNT_NOT_FOUND');
    }

    const user = result.rows[0];

    if (user.isBlocked || user.isBanned) {
      throw new ApiError(403, 'Account is deactivated');
    }

    // Verify password
    const isPasswordValid = await bcrypt.compare(password, user.password_hash);

    if (!isPasswordValid) {
      throw new ApiError(401, 'Invalid password', 'INVALID_PASSWORD');
    }

    // Update last login
    await pool.query('UPDATE users SET "lastActiveAt" = CURRENT_TIMESTAMP WHERE id = $1', [user.id]);

    // Check if user has an ACTIVE barber profile (demoted barbers have isActive = false)
    const barberCheck = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1 AND "isActive" = true',
      [user.id]
    );
    const hasBarberProfile = barberCheck.rows.length > 0;

    const accessRole = await resolveAccessTokenRole(user.id, user.role);

    const token = generateAccessToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    const refreshToken = generateRefreshToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    logger.info(`User logged in: ${user.email} (jwtRole=${accessRole}, dbRole=${user.role})`);

    res.json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.first_name,
          lastName: user.last_name,
          role: user.role,
          campusId: user.campusId,
          emailVerified: user.email_verified,
          profile_picture_url: user.avatarUrl,
          hasBarberProfile,
          suiAddress: user.sui_address ?? null,
        },
        accessToken: token,
        refreshToken,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * GET /api/v1/auth/check-email?email=… — whether a user row exists (sign-in handshake).
 */
export const checkEmailExists = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const raw = typeof req.query.email === 'string' ? req.query.email.trim() : '';
    if (!raw) {
      throw new ApiError(400, 'email query parameter required');
    }
    const normalized = raw.toLowerCase();
    const result = await pool.query(
      'SELECT 1 FROM users WHERE LOWER(TRIM(email)) = $1 LIMIT 1',
      [normalized]
    );
    res.json({
      success: true,
      data: { exists: result.rows.length > 0 },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * POST /api/v1/auth/google — Intera (and other clients): exchange Google `id_token` for CampusCuts JWTs.
 * Set GOOGLE_OAUTH_IOS_CLIENT_ID and/or GOOGLE_OAUTH_WEB_CLIENT_ID to match token audiences.
 */
export const googleIdTokenLogin = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const rawBody = req.body as { idToken?: string; id_token?: string };
    const idToken = (rawBody.idToken ?? rawBody.id_token)?.trim();
    if (!idToken) {
      throw new ApiError(400, 'idToken required');
    }

    const audiences = [
      process.env.GOOGLE_OAUTH_IOS_CLIENT_ID,
      process.env.GOOGLE_OAUTH_WEB_CLIENT_ID,
      process.env.VITE_GOOGLE_OAUTH_CLIENT_ID,
    ]
      .map((s) => s?.trim())
      .filter((s): s is string => Boolean(s));

    if (audiences.length === 0) {
      logger.error('Google sign-in: set GOOGLE_OAUTH_IOS_CLIENT_ID and/or GOOGLE_OAUTH_WEB_CLIENT_ID');
      throw new ApiError(
        500,
        'Google sign-in is not configured on the server (set GOOGLE_OAUTH_IOS_CLIENT_ID and/or GOOGLE_OAUTH_WEB_CLIENT_ID)'
      );
    }

    let ticket;
    try {
      ticket = await googleOAuthClient.verifyIdToken({
        idToken,
        audience: audiences.length === 1 ? audiences[0] : audiences,
      });
    } catch {
      throw new ApiError(401, 'Invalid or expired Google token');
    }

    const gPayload = ticket.getPayload();
    if (!gPayload?.sub) {
      throw new ApiError(400, 'Invalid Google token payload');
    }

    const emailRaw = gPayload.email?.trim().toLowerCase();
    if (!emailRaw) {
      throw new ApiError(401, 'Google account has no email');
    }
    if (gPayload.email_verified === false) {
      throw new ApiError(401, 'Google email not verified');
    }

    const result = await pool.query(
      `SELECT id, email, first_name, last_name, "campusId", role, "isBlocked", "isBanned", email_verified, "avatarUrl", sui_address
       FROM users WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))`,
      [emailRaw]
    );

    if (result.rows.length === 0) {
      throw new ApiError(401, 'Account not found', 'ACCOUNT_NOT_FOUND');
    }

    const user = result.rows[0];

    if (user.isBlocked || user.isBanned) {
      throw new ApiError(403, 'Account is deactivated');
    }

    await pool.query('UPDATE users SET "lastActiveAt" = CURRENT_TIMESTAMP WHERE id = $1', [user.id]);

    const barberCheck = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1 AND "isActive" = true',
      [user.id]
    );
    const hasBarberProfile = barberCheck.rows.length > 0;

    const accessRole = await resolveAccessTokenRole(user.id, user.role);

    const token = generateAccessToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    const refreshToken = generateRefreshToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    logger.info(`User logged in (Google): ${user.email} (jwtRole=${accessRole}, dbRole=${user.role})`);

    res.json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.first_name,
          lastName: user.last_name,
          role: user.role,
          campusId: user.campusId,
          emailVerified: user.email_verified,
          profile_picture_url: user.avatarUrl,
          hasBarberProfile,
          suiAddress: user.sui_address ?? null,
        },
        accessToken: token,
        refreshToken,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * POST /api/v1/auth/apple — Exchange Apple `identityToken` (JWT) for CampusCuts JWTs (App Store Guideline 4.8).
 * Set `APPLE_CLIENT_ID` to the **iOS bundle identifier** (e.g. `Liam.Intera`) — same as the Sign in with Apple Services ID audience for native apps.
 * Requires `apple_sub` on `users` (see `004_apple_sub_on_users.sql`) so returning users can sign in when the JWT omits `email`.
 */
export const appleIdTokenLogin = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const rawBody = req.body as Record<string, unknown>;
    const idToken = String(
      rawBody.identityToken ?? rawBody.id_token ?? rawBody.idToken ?? ''
    ).trim();
    if (!idToken) {
      throw new ApiError(400, 'identityToken required');
    }

    const { first: firstParsed, last: lastParsed } = parseAppleNameFieldsFromBody(rawBody);
    const firstNameClient = firstParsed;
    const lastNameClient = lastParsed;

    const appleAudience = process.env.APPLE_CLIENT_ID?.trim();
    if (!appleAudience) {
      logger.error('Apple sign-in: set APPLE_CLIENT_ID to the iOS app bundle identifier (e.g. Liam.Intera)');
      throw new ApiError(
        500,
        'Apple sign-in is not configured on the server (set APPLE_CLIENT_ID to your iOS bundle ID)'
      );
    }

    let appleSub: string;
    let emailFromToken: string | undefined;
    try {
      const payload = await appleSigninAuth.verifyIdToken(idToken, {
        audience: appleAudience,
        ignoreExpiration: false,
      });
      appleSub = String(payload.sub || '').trim();
      const rawEmail = typeof (payload as { email?: unknown }).email === 'string'
        ? (payload as { email: string }).email.trim().toLowerCase()
        : undefined;
      emailFromToken = rawEmail && rawEmail.length > 0 ? rawEmail : undefined;
      if (!appleSub) {
        throw new ApiError(401, 'Invalid Apple credential');
      }
    } catch (e) {
      if (e instanceof ApiError) throw e;
      throw new ApiError(401, 'Invalid or expired Apple credential');
    }

    const clientEmail = clientSupplementalEmailFromBody(rawBody);
    /** Prefer client body when the JWT only has Hide My Email (Create Account preflow sends real `@icloud.com`). */
    let effectiveEmail: string | undefined;
    if (
      emailFromToken &&
      clientEmail &&
      isApplePrivateRelayEmail(emailFromToken) &&
      !isApplePrivateRelayEmail(clientEmail)
    ) {
      effectiveEmail = clientEmail;
    } else {
      effectiveEmail = emailFromToken ?? clientEmail;
    }

    let result = await pool.query(
      `SELECT id, email, first_name, last_name, "campusId", role, "isBlocked", "isBanned", email_verified, "avatarUrl", sui_address, apple_sub, has_platform_password
       FROM users WHERE apple_sub = $1 LIMIT 1`,
      [appleSub]
    );

    if (result.rows.length === 0 && effectiveEmail) {
      result = await pool.query(
        `SELECT id, email, first_name, last_name, "campusId", role, "isBlocked", "isBanned", email_verified, "avatarUrl", sui_address, apple_sub, has_platform_password
         FROM users WHERE LOWER(TRIM(email)) = LOWER(TRIM($1)) LIMIT 1`,
        [effectiveEmail]
      );
    }

    let user: (typeof result.rows)[0];

    if (result.rows.length === 0) {
      if (!effectiveEmail) {
        throw new ApiError(
          400,
          'Apple did not include an email in the identity token. Send the saved relay or personal email in the JSON body (`email`, `userEmail`, `appleEmail`, or `contactEmail`) from the user’s first sign-in (Keychain), or use “Share My Email” and sign in again.'
        );
      }
      const randomHash = await bcrypt.hash(randomBytes(48).toString('hex'), 10);
      const relay = isApplePrivateRelayEmail(effectiveEmail);
      const firstNameFinal =
        firstNameClient ?? (relay ? 'Apple' : applePlaceholderFirstNameFromEmail(effectiveEmail));
      const lastNameFinal = lastNameClient ?? (relay ? 'User' : 'Customer');
      try {
        const ins = await pool.query(
          `INSERT INTO users (id, email, password_hash, first_name, last_name, "campusId", role, email_verified, "updatedAt", apple_sub, has_platform_password, auth_provider)
           VALUES (gen_random_uuid(), $1, $2, $3, $4, NULL, 'CONSUMER'::"UserRole", TRUE, NOW(), $5, FALSE, 'apple')
           RETURNING id, email, first_name, last_name, "campusId", role, "isBlocked", "isBanned", email_verified, "avatarUrl", sui_address, apple_sub, has_platform_password`,
          [effectiveEmail, randomHash, firstNameFinal, lastNameFinal, appleSub]
        );
        user = ins.rows[0];
        logger.info(`New user created via Sign in with Apple: ${user.email}`);
        sendWelcomeEmail(user.email, user.first_name).catch((err) => {
          logger.error('Failed to send welcome email (Apple sign-up):', err);
        });
      } catch (insertErr: unknown) {
        const pg = insertErr as { code?: string };
        if (pg?.code === '23505') {
          const again = await pool.query(
            `SELECT id, email, first_name, last_name, "campusId", role, "isBlocked", "isBanned", email_verified, "avatarUrl", sui_address, apple_sub, has_platform_password
             FROM users WHERE apple_sub = $1 OR LOWER(TRIM(email)) = LOWER(TRIM($2)) LIMIT 1`,
            [appleSub, effectiveEmail]
          );
          if (again.rows.length === 0) {
            throw insertErr;
          }
          user = again.rows[0];
          if (!user.apple_sub) {
            await pool.query('UPDATE users SET apple_sub = $1 WHERE id = $2', [appleSub, user.id]);
          }
        } else {
          throw insertErr;
        }
      }
    } else {
      user = result.rows[0];
    }

    if (user.isBlocked || user.isBanned) {
      throw new ApiError(403, 'Account is deactivated');
    }

    if (!user.apple_sub) {
      await pool.query('UPDATE users SET apple_sub = $1 WHERE id = $2', [appleSub, user.id]);
    }

    if (
      clientEmail &&
      !isApplePrivateRelayEmail(clientEmail) &&
      isApplePrivateRelayEmail(user.email) &&
      clientEmail.toLowerCase().trim() !== String(user.email).toLowerCase().trim()
    ) {
      try {
        const upgraded = await pool.query(
          `UPDATE users SET email = $1, "updatedAt" = NOW()
           WHERE id = $2
             AND LOWER(TRIM(email)) LIKE '%@privaterelay.appleid.com'
             AND NOT EXISTS (
               SELECT 1 FROM users u2
               WHERE u2.id <> $2::uuid AND LOWER(TRIM(u2.email)) = LOWER(TRIM($1::text))
             )
           RETURNING id, email, first_name, last_name, "campusId", role, "isBlocked", "isBanned", email_verified, "avatarUrl", sui_address, apple_sub, has_platform_password`,
          [clientEmail, user.id]
        );
        if (upgraded.rows.length > 0) {
          user = upgraded.rows[0];
          logger.info(`Apple sign-in: upgraded relay email to client-supplied address for user ${user.id}`);
        }
      } catch (e) {
        logger.warn('Apple sign-in: could not upgrade relay email to client address', e);
      }
    }

    if (firstNameClient || lastNameClient) {
      await pool.query(
        `UPDATE users SET
          first_name = COALESCE(NULLIF(TRIM($2::text), ''), first_name),
          last_name = COALESCE(NULLIF(TRIM($3::text), ''), last_name)
         WHERE id = $1`,
        [user.id, firstNameClient ?? null, lastNameClient ?? null]
      );
      const refreshed = await pool.query(
        `SELECT id, email, first_name, last_name, "campusId", role, "isBlocked", "isBanned", email_verified, "avatarUrl", sui_address, apple_sub, has_platform_password
         FROM users WHERE id = $1 LIMIT 1`,
        [user.id]
      );
      user = refreshed.rows[0];
    }

    await pool.query('UPDATE users SET "lastActiveAt" = CURRENT_TIMESTAMP WHERE id = $1', [user.id]);

    const barberCheck = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1 AND "isActive" = true',
      [user.id]
    );
    const hasBarberProfile = barberCheck.rows.length > 0;

    const accessRole = await resolveAccessTokenRole(user.id, user.role);

    const token = generateAccessToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    const refreshToken = generateRefreshToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    logger.info(`User logged in via Apple: ${user.email} sub=${appleSub} (jwtRole=${accessRole}, dbRole=${user.role})`);

    res.json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.first_name,
          lastName: user.last_name,
          role: user.role,
          campusId: user.campusId,
          emailVerified: user.email_verified,
          profile_picture_url: user.avatarUrl,
          hasBarberProfile,
          suiAddress: user.sui_address ?? null,
          needsPlatformPassword: user.has_platform_password === false,
        },
        accessToken: token,
        refreshToken,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Verify email with token
 */
export const verifyEmail = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { token } = req.body;

    if (!token) {
      throw new ApiError(400, 'Verification token required');
    }

    // Verify JWT token
    const secret = process.env.JWT_SECRET;
    if (!secret) throw new Error('JWT_SECRET not configured');

    const decoded = jwt.verify(token, secret) as { userId: string };

    // Update user's email_verified status
    await pool.query(
      'UPDATE users SET email_verified = TRUE WHERE id = $1',
      [decoded.userId]
    );

    logger.info(`Email verified for user: ${decoded.userId}`);

    res.json({
      success: true,
      message: 'Email verified successfully',
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Request password reset
 */
export const requestPasswordReset = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { email } = req.body;

    const result = await pool.query('SELECT id FROM users WHERE email = $1', [email]);

    if (result.rows.length === 0) {
      // Don't reveal if email exists
      res.json({
        success: true,
        message: 'If email exists, reset instructions have been sent',
      });
      return;
    }

    // Generate reset token and send email
    const userId = result.rows[0].id;
    const resetToken = generatePasswordResetToken(userId);
    const frontendUrl = process.env.FRONTEND_URL || 'https://campuscut.com';
    const resetLink = `${frontendUrl}/web/reset-password?token=${resetToken}`;
    
    // Send password reset email (non-blocking)
    sendPasswordResetEmail(email, resetLink).catch((err) => {
      logger.error('Failed to send password reset email:', err.message);
    });

    res.json({
      success: true,
      message: 'If email exists, reset instructions have been sent',
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Reset password
 */
export const resetPassword = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { token, newPassword } = req.body;

    const secret = process.env.JWT_SECRET;
    if (!secret) throw new Error('JWT_SECRET not configured');

    const decoded = jwt.verify(token, secret) as { userId: string };
    const passwordHash = await bcrypt.hash(newPassword, 10);

    await pool.query(
      'UPDATE users SET password_hash = $1 WHERE id = $2',
      [passwordHash, decoded.userId]
    );

    logger.info(`Password reset for user: ${decoded.userId}`);

    res.json({
      success: true,
      message: 'Password reset successful',
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Refresh access token
 */
export const refreshToken = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      throw new ApiError(400, 'Refresh token required');
    }

    const secret = process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET;
    if (!secret) throw new Error('JWT secrets not configured');

    const decoded = jwt.verify(refreshToken, secret) as JwtPayload;

    const userResult = await pool.query(
      `SELECT email, role, "campusId" FROM users WHERE id = $1`,
      [decoded.userId]
    );
    if (userResult.rows.length === 0) {
      throw new ApiError(401, 'User no longer exists');
    }
    const u = userResult.rows[0];
    const accessRole = await resolveAccessTokenRole(decoded.userId, u.role);

    const newToken = generateAccessToken({
      userId: decoded.userId,
      email: u.email,
      role: accessRole,
      campusId: u.campusId,
    });

    res.json({
      success: true,
      data: { token: newToken, accessToken: newToken },
    });
  } catch (error) {
    next(new ApiError(401, 'Invalid refresh token'));
  }
};

/**
 * Get current user profile
 * Returns the authenticated user's data including role information
 */
export const getCurrentUser = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user?.userId;

    if (!userId) {
      throw new ApiError(401, 'Not authenticated');
    }

    const result = await pool.query(
      `SELECT 
        id, email, first_name, last_name, role, "campusId", 
        email_verified, "avatarUrl", "displayName", bio,
        "isBlocked", "isBanned", "createdAt", sui_address,
        has_platform_password
       FROM users WHERE id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'User not found');
    }

    const user = result.rows[0];

    // Check if user has an ACTIVE barber profile (demoted barbers have isActive = false)
    const barberCheck = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1 AND "isActive" = true',
      [userId]
    );
    const hasBarberProfile = barberCheck.rows.length > 0;

    // Map database role to frontend role
    let frontendRole: 'student' | 'barber' | 'campus_manager' | 'admin';
    switch (user.role) {
      case 'CONSUMER':
        frontendRole = 'student';
        break;
      case 'BARBER':
        frontendRole = 'barber';
        break;
      case 'CAMPUS_MANAGER':
        frontendRole = 'campus_manager';
        break;
      case 'ADMIN':
        frontendRole = 'admin';
        break;
      default:
        frontendRole = 'student';
    }

    if (hasBarberProfile && frontendRole === 'student') {
      frontendRole = 'barber';
    }

    // Admins have all privileges including campus manager at all campuses
    const isAdmin = frontendRole === 'admin';
    const isCampusManager = frontendRole === 'campus_manager' || isAdmin;
    
    const needsPw = user.has_platform_password === false;

    res.json({
      success: true,
      data: {
        id: user.id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        firstName: user.first_name,
        lastName: user.last_name,
        user_type: frontendRole,
        is_admin: isAdmin,
        is_campus_manager: isCampusManager,
        has_barber_profile: hasBarberProfile,
        is_verified: user.email_verified,
        profile_picture_url: user.avatarUrl,
        display_name: user.displayName,
        bio: user.bio,
        campus_id: user.campusId,
        created_at: user.createdAt,
        sui_address: user.sui_address ?? null,
        needs_platform_password: needsPw,
        needsPlatformPassword: needsPw,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * JWT token generation and verification is now handled by utils/jwt.utils.ts
 * See that file for comprehensive JWT documentation and helper functions.
 */

