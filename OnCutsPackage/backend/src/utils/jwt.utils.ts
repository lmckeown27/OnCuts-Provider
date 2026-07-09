import jwt from 'jsonwebtoken';
import { JwtPayload } from '../middleware/auth';

/**
 * JWT Utilities for Token Generation and Management
 * 
 * This file contains utility functions for creating and managing JWT tokens.
 * 
 * ## How JWT Works:
 * 1. User logs in with email/password
 * 2. Server verifies credentials against database
 * 3. Server generates JWT token signed with JWT_SECRET
 * 4. Client stores token (localStorage, cookie, etc.)
 * 5. Client sends token in Authorization header: "Bearer <token>"
 * 6. Server verifies token signature and extracts payload
 * 7. Server grants access if token is valid
 * 
 * ## Environment Variables Required:
 * - JWT_SECRET: Secret key for signing access tokens (must be strong, 32+ chars)
 * - JWT_EXPIRES_IN: Access token expiration time (e.g., "15m", "7d", "24h")
 * - JWT_REFRESH_SECRET: Secret for refresh tokens (optional, defaults to JWT_SECRET)
 * - JWT_REFRESH_EXPIRES_IN: Refresh token expiration (e.g., "30d", "90d")
 * 
 * ## Token Types:
 * - Access Token: Short-lived, used for API requests (15min - 7 days)
 * - Refresh Token: Long-lived, used to get new access tokens (30-90 days)
 * 
 * @module jwt.utils
 */

/**
 * Generate JWT Access Token
 * 
 * Creates a signed JWT token containing user information.
 * The token is signed with JWT_SECRET and expires after JWT_EXPIRES_IN.
 * 
 * @param payload - User information to encode in token (userId, email, role, campusId)
 * @returns Signed JWT token string
 * @throws Error if JWT_SECRET is not configured in environment
 * 
 * @example
 * const token = generateAccessToken({
 *   userId: '123e4567-e89b-12d3-a456-426614174000',
 *   email: 'student@university.edu',
 *   role: 'student',
 *   campusId: 1
 * });
 * // Returns: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
 */
export const generateAccessToken = (payload: JwtPayload): string => {
  const secret = process.env.JWT_SECRET;
  
  if (!secret) {
    throw new Error(
      'JWT_SECRET not configured. Please set JWT_SECRET in your .env file. ' +
      'Generate a strong secret with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"'
    );
  }

  // Default to 7 days if not specified
  const expiresIn: string = process.env.JWT_EXPIRES_IN || '7d';

  /**
   * JWT Signing Process:
   * 1. Takes the payload (user data)
   * 2. Creates a header with algorithm (HS256 by default)
   * 3. Encodes header and payload to Base64URL
   * 4. Creates signature: HMACSHA256(base64UrlEncode(header) + "." + base64UrlEncode(payload), secret)
   * 5. Combines: header.payload.signature
   * 
   * Result: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiIxMjMiLCJpYXQiOjE3MDk...signature"
   */
  return jwt.sign(payload, secret, {
    expiresIn: expiresIn,
    issuer: 'campuscuts-api', // Identifies token issuer
    audience: 'campuscuts-client', // Identifies intended recipient
  } as jwt.SignOptions);
};

/**
 * Generate JWT Refresh Token
 * 
 * Creates a long-lived token used to obtain new access tokens.
 * Should be stored securely (httpOnly cookie recommended).
 * 
 * @param payload - User information to encode in token
 * @returns Signed refresh token string
 * @throws Error if JWT_REFRESH_SECRET or JWT_SECRET is not configured
 * 
 * @example
 * const refreshToken = generateRefreshToken({
 *   userId: '123e4567-e89b-12d3-a456-426614174000',
 *   email: 'student@university.edu',
 *   role: 'student',
 *   campusId: 1
 * });
 */
export const generateRefreshToken = (payload: JwtPayload): string => {
  // Use dedicated refresh secret, fallback to main secret
  const secret = process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET;
  
  if (!secret) {
    throw new Error(
      'JWT secrets not configured. Please set JWT_SECRET and optionally JWT_REFRESH_SECRET in your .env file.'
    );
  }

  // Default to 30 days for refresh tokens
  const expiresIn: string = process.env.JWT_REFRESH_EXPIRES_IN || '30d';

  return jwt.sign(payload, secret, {
    expiresIn: expiresIn,
    issuer: 'campuscuts-api',
    audience: 'campuscuts-client',
  } as jwt.SignOptions);
};

/**
 * Verify JWT Token
 * 
 * Verifies the signature and expiration of a JWT token.
 * Returns decoded payload if valid, throws error if invalid.
 * 
 * @param token - JWT token string to verify
 * @param isRefreshToken - Set to true to verify refresh token
 * @returns Decoded JWT payload
 * @throws jwt.JsonWebTokenError if token is malformed
 * @throws jwt.TokenExpiredError if token has expired
 * @throws jwt.NotBeforeError if token is used before nbf claim
 * 
 * @example
 * try {
 *   const payload = verifyToken(token);
 *   console.log('User ID:', payload.userId);
 * } catch (error) {
 *   if (error instanceof jwt.TokenExpiredError) {
 *     console.log('Token expired, please login again');
 *   }
 * }
 */
export const verifyToken = (token: string, isRefreshToken = false): JwtPayload => {
  const secret = isRefreshToken 
    ? (process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET)
    : process.env.JWT_SECRET;
  
  if (!secret) {
    throw new Error('JWT secrets not configured');
  }

  /**
   * JWT Verification Process:
   * 1. Splits token into header.payload.signature
   * 2. Decodes header and payload from Base64URL
   * 3. Recomputes signature using header, payload, and secret
   * 4. Compares computed signature with provided signature
   * 5. Checks expiration (exp claim)
   * 6. Checks not-before (nbf claim) if present
   * 7. Validates issuer and audience if specified
   * 
   * If all checks pass, returns decoded payload. Otherwise throws error.
   */
  return jwt.verify(token, secret, {
    issuer: 'campuscuts-api',
    audience: 'campuscuts-client',
  }) as JwtPayload;
};

/**
 * Decode JWT Token Without Verification
 * 
 * Extracts payload from JWT without verifying signature.
 * SECURITY WARNING: Only use for debugging or when signature verification
 * is not required. Never trust unverified tokens for authentication!
 * 
 * @param token - JWT token string to decode
 * @returns Decoded payload or null if invalid
 * 
 * @example
 * const payload = decodeToken(token);
 * console.log('Token contains:', payload);
 */
export const decodeToken = (token: string): JwtPayload | null => {
  try {
    return jwt.decode(token) as JwtPayload;
  } catch (error) {
    return null;
  }
};

/**
 * Generate Email Verification Token
 * 
 * Creates a short-lived token for email verification.
 * Contains only userId and purpose flag.
 * 
 * @param userId - User ID to verify
 * @returns JWT token for email verification
 * 
 * @example
 * const verifyToken = generateEmailVerificationToken('user-123');
 * // Send in verification email link
 * const link = `https://campuscuts.com/verify-email?token=${verifyToken}`;
 */
export const generateEmailVerificationToken = (userId: string): string => {
  const secret = process.env.JWT_SECRET;
  
  if (!secret) {
    throw new Error('JWT_SECRET not configured');
  }

  // Email verification tokens expire in 24 hours
  return jwt.sign(
    { 
      userId,
      purpose: 'email-verification'
    },
    secret,
    { expiresIn: '24h' }
  );
};

/**
 * Generate Password Reset Token
 * 
 * Creates a short-lived token for password reset.
 * Contains userId and purpose flag.
 * 
 * @param userId - User ID requesting reset
 * @returns JWT token for password reset
 * 
 * @example
 * const resetToken = generatePasswordResetToken('user-123');
 * // Send in password reset email
 * const link = `https://campuscuts.com/reset-password?token=${resetToken}`;
 */
export const generatePasswordResetToken = (userId: string): string => {
  const secret = process.env.JWT_SECRET;
  
  if (!secret) {
    throw new Error('JWT_SECRET not configured');
  }

  // Password reset tokens expire in 1 hour for security
  return jwt.sign(
    { 
      userId,
      purpose: 'password-reset'
    },
    secret,
    { expiresIn: '1h' }
  );
};

/**
 * Extract Token from Authorization Header
 * 
 * Parses "Bearer <token>" format and extracts the token.
 * 
 * @param authHeader - Authorization header value
 * @returns Extracted token or null
 * 
 * @example
 * const token = extractTokenFromHeader(req.headers.authorization);
 * if (token) {
 *   const payload = verifyToken(token);
 * }
 */
export const extractTokenFromHeader = (authHeader?: string): string | null => {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }
  
  // Extract token after "Bearer " (7 characters)
  return authHeader.substring(7);
};

/**
 * Check if Token is Expired
 * 
 * Checks expiration without verifying signature.
 * Useful for client-side token refresh logic.
 * 
 * @param token - JWT token to check
 * @returns true if token is expired, false otherwise
 * 
 * @example
 * if (isTokenExpired(token)) {
 *   // Request new token using refresh token
 *   const newToken = await refreshAccessToken();
 * }
 */
export const isTokenExpired = (token: string): boolean => {
  try {
    const decoded = jwt.decode(token) as any;
    
    if (!decoded || !decoded.exp) {
      return true;
    }
    
    // exp is in seconds, Date.now() is in milliseconds
    return decoded.exp * 1000 < Date.now();
  } catch (error) {
    return true;
  }
};

/**
 * Get Token Expiration Time
 * 
 * Returns the expiration timestamp of a token.
 * 
 * @param token - JWT token
 * @returns Expiration date or null if invalid
 * 
 * @example
 * const expiresAt = getTokenExpiration(token);
 * console.log('Token expires:', expiresAt?.toISOString());
 */
export const getTokenExpiration = (token: string): Date | null => {
  try {
    const decoded = jwt.decode(token) as any;
    
    if (!decoded || !decoded.exp) {
      return null;
    }
    
    return new Date(decoded.exp * 1000);
  } catch (error) {
    return null;
  }
};

/**
 * Generate Secure Random Secret
 * 
 * Helper function to generate a cryptographically secure secret.
 * Use this to generate JWT_SECRET and JWT_REFRESH_SECRET values.
 * 
 * @returns Hex-encoded random secret (64 characters)
 * 
 * @example
 * const secret = generateSecret();
 * console.log('Add to .env: JWT_SECRET=' + secret);
 */
export const generateSecret = (): string => {
  const crypto = require('crypto');
  return crypto.randomBytes(32).toString('hex');
};

