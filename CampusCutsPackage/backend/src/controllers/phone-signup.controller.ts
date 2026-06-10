/**
 * Phone-first signup: SMS before password (Intera + web).
 */
import { Response, NextFunction } from 'express';
import bcrypt from 'bcrypt';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest } from '../middleware/auth';
import { logger } from '../utils/logger';
import { sendVerificationSms } from '../services/sms.service';
import { isAutoVerifyEnabled, sendWelcomeEmail } from '../services/email.service';
import { normalizePhoneToE164, syntheticEmailFromPhoneE164 } from '../utils/phone.utils';
import { upsertPhoneSignupOtp, verifyPhoneSignupOtp } from '../services/phone-signup.service';
import { generatePhoneSignupTicket, verifyPhoneSignupTicket } from '../utils/phone-signup-jwt';
import { generateAccessToken, generateRefreshToken } from '../utils/jwt.utils';
import { resolveAccessTokenRole } from '../utils/access-token-role';

async function resolveCampusId(requestedCampusId: unknown): Promise<string | null> {
  if (!requestedCampusId || typeof requestedCampusId !== 'string' || !requestedCampusId.trim()) {
    return null;
  }
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const isUuid = uuidRegex.test(requestedCampusId);
  let validCampus;
  if (isUuid) {
    validCampus = await pool.query(
      'SELECT id, name FROM campuses WHERE id = $1 AND is_active = TRUE',
      [requestedCampusId]
    );
  } else {
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
    return validCampus.rows[0].id;
  }
  return null;
}

/**
 * POST /auth/signup/send-phone-code — send SMS (no password yet).
 */
export const sendPhoneSignupCode = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { phone, firstName, lastName, role, campusId: requestedCampusId } = req.body;

    if (!phone || !firstName || !lastName || !role) {
      throw new ApiError(400, 'phone, firstName, lastName, and role are required');
    }

    const phoneE164 = normalizePhoneToE164(String(phone));
    const syntheticEmail = syntheticEmailFromPhoneE164(phoneE164);

    const existingUser = await pool.query('SELECT id FROM users WHERE email = $1', [syntheticEmail]);
    if (existingUser.rows.length > 0) {
      throw new ApiError(400, 'An account with this phone number already exists');
    }

    const campusId = await resolveCampusId(requestedCampusId);

    const code = await upsertPhoneSignupOtp({
      phoneE164,
      firstName: String(firstName).trim(),
      lastName: String(lastName).trim(),
      role: String(role).trim(),
      campusId,
    });

    await sendVerificationSms(phoneE164, code);

    if (isAutoVerifyEnabled()) {
      return res.status(200).json({
        success: true,
        message: 'Code sent (AUTO-VERIFY MODE)',
        data: {
          phone: phoneE164,
          expiresIn: 600,
          verificationCode: code,
        },
      });
    }

    res.status(200).json({
      success: true,
      message: 'Verification code sent to your phone.',
      data: {
        phone: phoneE164,
        expiresIn: 600,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * POST /auth/signup/verify-phone-code — exchange SMS code for a short-lived signup token.
 */
export const verifyPhoneSignupCodeHandler = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const { phone, code } = req.body;
    if (!phone || !code) {
      throw new ApiError(400, 'phone and code are required');
    }

    const phoneE164 = normalizePhoneToE164(String(phone));
    const row = await verifyPhoneSignupOtp(phoneE164, String(code).trim());

    if (!row) {
      throw new ApiError(400, 'Invalid or expired verification code');
    }

    const syntheticEmail = syntheticEmailFromPhoneE164(phoneE164);
    const ticket = generatePhoneSignupTicket({
      phoneE164,
      syntheticEmail,
      firstName: row.firstName,
      lastName: row.lastName,
      role: row.role,
      campusId: row.campusId,
    });

    res.status(200).json({
      success: true,
      data: {
        phoneSignupToken: ticket,
        phone: phoneE164,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * POST /auth/signup/complete-phone — set password and create account (after SMS + token).
 */
export const completePhoneSignupWithPassword = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const { phoneSignupToken, password } = req.body;

    if (!phoneSignupToken || typeof phoneSignupToken !== 'string') {
      throw new ApiError(400, 'phoneSignupToken is required');
    }
    if (!password || String(password).length < 8) {
      throw new ApiError(400, 'Password must be at least 8 characters');
    }

    let t: ReturnType<typeof verifyPhoneSignupTicket>;
    try {
      t = verifyPhoneSignupTicket(String(phoneSignupToken));
    } catch {
      throw new ApiError(401, 'Invalid or expired signup session. Verify your phone again.');
    }

    const email = t.syntheticEmail;

    const existingUser = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
    if (existingUser.rows.length > 0) {
      throw new ApiError(400, 'User already exists. Please log in.');
    }

    const approvedGuestApp = await pool.query(
      `SELECT id, campus_id, specialties FROM guest_barber_applications 
       WHERE email = $1 AND status = 'approved' AND linked_user_id IS NULL
       ORDER BY created_at DESC LIMIT 1`,
      [email.toLowerCase()]
    );

    const hasApprovedApplication = approvedGuestApp.rows.length > 0;

    let dbRole: string;
    if (hasApprovedApplication) {
      dbRole = 'BARBER';
      logger.info(`User ${email} has an approved guest application - auto-promoting to BARBER`);
    } else {
      const roleMap: { [key: string]: string } = {
        student: 'CONSUMER',
        barber: 'BARBER',
        admin: 'ADMIN',
      };
      dbRole = roleMap[t.role.toLowerCase()] || 'CONSUMER';
    }

    const campusId = hasApprovedApplication
      ? approvedGuestApp.rows[0].campus_id
      : t.campusId;

    if (!campusId) {
      logger.info(
        `${dbRole === 'BARBER' ? 'Barber' : 'Consumer'} ${email} registering without campus affiliation`
      );
    }

    const passwordHash = await bcrypt.hash(String(password), 10);

    const result = await pool.query(
      `INSERT INTO users (id, email, password_hash, first_name, last_name, "campusId", role, email_verified, "updatedAt")
       VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6::"UserRole", TRUE, NOW())
       RETURNING id, email, first_name, last_name, "campusId", role, "createdAt"`,
      [email, passwordHash, t.firstName, t.lastName, campusId, dbRole]
    );

    const user = result.rows[0];

    if (hasApprovedApplication) {
      const guestApp = approvedGuestApp.rows[0];
      const specialties = guestApp.specialties || [];
      const SERVICE_BASE_PRICES: Record<string, number> = {
        'Buzz Cut': 23,
        'Line Up': 23,
        'Beard Trim': 23,
        Haircut: 28,
        Taper: 28,
        'Hot Shave': 28,
        'Kids Cut': 28,
        Fade: 35,
        'Haircut & Fade': 35,
        Mullet: 35,
        'Design/Art': 38,
        'Afro Textures': 38,
        "Women's Cut": 40,
        'Color Treatment': 45,
        Perm: 45,
      };
      const pricing = specialties.map((specialty: string) => ({
        name: specialty,
        price: SERVICE_BASE_PRICES[specialty] || 25,
      }));

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

      await pool.query(
        'UPDATE guest_barber_applications SET linked_user_id = $1 WHERE id = $2',
        [user.id, guestApp.id]
      );
    }

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

    sendWelcomeEmail(user.email, user.first_name).catch((err) => {
      logger.error('Failed to send welcome email:', err);
    });

    res.status(201).json({
      success: true,
      message: 'Account created successfully.',
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.first_name,
          lastName: user.last_name,
          role: user.role,
          campusId: user.campusId,
          emailVerified: true,
        },
        accessToken: token,
        refreshToken,
      },
    });
  } catch (error) {
    next(error);
  }
};
