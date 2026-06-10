import express, { Router } from 'express';
import { body, check, query } from 'express-validator';
import {
  register,
  login,
  checkEmailExists,
  googleIdTokenLogin,
  appleIdTokenLogin,
  verifyEmail,
  verifyEmailRegistration,
  resendVerificationCode,
  requestPasswordReset,
  resetPassword,
  refreshToken,
  getCurrentUser,
} from '../controllers/auth.controller';
import {
  sendPhoneSignupCode,
  verifyPhoneSignupCodeHandler,
  completePhoneSignupWithPassword,
} from '../controllers/phone-signup.controller';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validator';

const router: Router = express.Router();

/** JSON clients often send boolean `true`; some validators only accept the string `"true"`. */
function acceptedTermsOk(value: unknown): boolean {
  return value === true || value === 'true' || value === 1 || value === '1';
}

function rawAcceptedTerms(body: Record<string, unknown>): unknown {
  return body.accepted_terms ?? body.acceptedTerms;
}

/** Optional: omit or accept only affirmative values (reject explicit false). */
const optionalAcceptedTerms = check()
  .custom((_v, { req }) => {
    const raw = rawAcceptedTerms(req.body as Record<string, unknown>);
    if (raw === undefined || raw === null) return true;
    return acceptedTermsOk(raw);
  })
  .withMessage('You must accept the Terms of Service');

const xorEmailOrPhone = check()
  .custom((_v, { req }) => {
    const b = req.body as Record<string, unknown>;
    const e = b.email != null && String(b.email).trim() !== '';
    const p = b.phone != null && String(b.phone).trim() !== '';
    if (!e && !p) throw new Error('Email or phone is required');
    if (e && p) throw new Error('Provide only email or phone');
    return true;
  });

/**
 * @route   POST /api/auth/register
 * @desc    Register new user (creates pending registration, sends email verification)
 * @access  Public
 */
router.post(
  '/register',
  [
    body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
    body('firstName').notEmpty().withMessage('First name required'),
    body('lastName').notEmpty().withMessage('Last name required'),
    body('role').isIn(['student', 'barber']).withMessage('Role must be student or barber'),
    body('email').optional({ checkFalsy: true }).isEmail().withMessage('Valid email required'),
    body('phone').optional({ checkFalsy: true }).isString(),
    xorEmailOrPhone,
    optionalAcceptedTerms,
    validate,
  ],
  register
);

/**
 * @route   POST /api/auth/verify-email
 * @desc    Verify email with 6-digit code (completes registration)
 * @access  Public
 */
router.post(
  '/verify-email',
  [
    body('code').isLength({ min: 6, max: 6 }).withMessage('Verification code must be 6 digits'),
    body('email').optional({ checkFalsy: true }).isEmail().withMessage('Valid email required'),
    body('phone').optional({ checkFalsy: true }).isString(),
    xorEmailOrPhone,
    validate,
  ],
  verifyEmailRegistration
);

/**
 * @route   POST /api/auth/resend-verification
 * @desc    Resend email verification code
 * @access  Public
 */
router.post(
  '/resend-verification',
  [
    body('email').optional({ checkFalsy: true }).isEmail().withMessage('Valid email required'),
    body('phone').optional({ checkFalsy: true }).isString(),
    xorEmailOrPhone,
    validate,
  ],
  resendVerificationCode
);

/**
 * Phone-first signup (SMS before password) — Intera / web.
 */
router.post(
  '/signup/send-phone-code',
  [
    body('phone').notEmpty().withMessage('phone required'),
    body('firstName').notEmpty().withMessage('First name required'),
    body('lastName').notEmpty().withMessage('Last name required'),
    body('role').isIn(['student', 'barber']).withMessage('Role must be student or barber'),
    validate,
  ],
  sendPhoneSignupCode
);

router.post(
  '/signup/verify-phone-code',
  [
    body('phone').notEmpty().withMessage('phone required'),
    body('code').isLength({ min: 6, max: 6 }).withMessage('Code must be 6 digits'),
    validate,
  ],
  verifyPhoneSignupCodeHandler
);

router.post(
  '/signup/complete-phone',
  [
    body('phoneSignupToken').notEmpty().withMessage('phoneSignupToken required'),
    body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
    validate,
  ],
  completePhoneSignupWithPassword
);

/**
 * @route   POST /api/auth/login
 * @desc    Login user
 * @access  Public
 */
router.post(
  '/login',
  [
    body('email').isEmail().withMessage('Valid email required'),
    body('password').notEmpty().withMessage('Password required'),
    validate,
  ],
  login
);

/**
 * @route   GET /api/auth/check-email
 * @desc    Returns whether an account exists for the given email (public handshake)
 * @access  Public
 */
router.get(
  '/check-email',
  [query('email').isEmail().withMessage('Valid email required'), validate],
  checkEmailExists
);

/**
 * @route   POST /api/auth/google
 * @desc    Exchange Google ID token for CampusCuts JWTs (Intera / mobile)
 * @access  Public
 */
router.post('/google', googleIdTokenLogin);

/**
 * @route   POST /api/auth/apple
 * @desc    Exchange Apple Sign in with Apple `identityToken` for CampusCuts JWTs (Intera / mobile)
 * @access  Public
 */
router.post('/apple', appleIdTokenLogin);

/**
 * @route   POST /api/auth/verify-email-token
 * @desc    Verify email with JWT token (legacy, for existing users)
 * @access  Public
 */
router.post('/verify-email-token', verifyEmail);

/**
 * @route   POST /api/auth/request-password-reset
 * @desc    Request password reset email
 * @access  Public
 */
router.post(
  '/request-password-reset',
  [body('email').isEmail().withMessage('Valid email required'), validate],
  requestPasswordReset
);

/**
 * @route   POST /api/auth/reset-password
 * @desc    Reset password with token
 * @access  Public
 */
router.post(
  '/reset-password',
  [
    body('token').notEmpty().withMessage('Reset token required'),
    body('newPassword').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
    validate,
  ],
  resetPassword
);

/**
 * @route   POST /api/auth/refresh-token
 * @desc    Refresh access token
 * @access  Public
 */
router.post('/refresh-token', refreshToken);

/**
 * @route   GET /api/auth/me
 * @desc    Get current authenticated user profile
 * @access  Private
 */
router.get('/me', authenticate, getCurrentUser);

export default router;
