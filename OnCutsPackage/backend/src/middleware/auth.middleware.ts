import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { pool } from '../database/connection';
import { ApiError } from './errorHandler';
import { resolveAccessTokenRole } from '../utils/access-token-role';
import { verifyToken, extractTokenFromHeader } from '../utils/jwt.utils';

/**
 * JWT Authentication Middleware
 * 
 * This file contains Express middleware for JWT-based authentication.
 * 
 * ## How JWT Authentication Works:
 * 
 * 1. **Client sends request** with JWT token in Authorization header:
 *    ```
 *    Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
 *    ```
 * 
 * 2. **Middleware extracts token** from "Bearer <token>" format
 * 
 * 3. **Token verification** process:
 *    - Splits token into header.payload.signature
 *    - Verifies signature using JWT_SECRET
 *    - Checks expiration (exp claim)
 *    - Validates issuer and audience
 * 
 * 4. **If valid**: Decoded payload attached to req.user, request continues
 * 
 * 5. **If invalid**: Returns 401 Unauthorized error
 * 
 * ## Environment Variables:
 * - JWT_SECRET: Secret key for verifying tokens (required, 32+ chars recommended)
 * - NODE_ENV: Set to 'production' to disable development bypasses
 * 
 * ## Usage Examples:
 * 
 * ### Protect a route (authentication required):
 * ```typescript
 * router.get('/profile', authenticate, (req, res) => {
 *   res.json({ user: req.user }); // req.user populated by middleware
 * });
 * ```
 * 
 * ### Optional authentication:
 * ```typescript
 * router.get('/public', optionalAuthenticate, (req, res) => {
 *   if (req.user) {
 *     // User is logged in
 *   } else {
 *     // Anonymous access
 *   }
 * });
 * ```
 * 
 * ### Role-based access:
 * ```typescript
 * router.post('/admin/users', authenticate, requireRole('admin'), handler);
 * router.get('/barber/bookings', authenticate, requireRole('barber', 'admin'), handler);
 * ```
 * 
 * @module auth.middleware
 */

/**
 * Token Payload Interface
 * 
 * Defines the structure of decoded JWT tokens.
 * This data is available in req.user after authentication.
 */
export interface TokenPayload {
  userId: string;      // Unique user identifier (UUID)
  email: string;       // User's email address
  role: 'student' | 'barber' | 'campus_manager' | 'admin';  // User role for authorization
  campusId: number;    // Campus the user belongs to
  iat?: number;        // Issued at timestamp (added by jwt.sign)
  exp?: number;        // Expiration timestamp (added by jwt.sign)
}

// Alias for backward compatibility
export type JwtPayload = TokenPayload;

/**
 * Extended Express Request with User
 * 
 * Extends Express Request to include authenticated user data.
 * After authenticate() middleware runs, req.user will be populated.
 */
export type AuthRequest = Request & {
  user?: JwtPayload;
};

/**
 * Main Authentication Middleware
 * 
 * Verifies JWT token from Authorization header and attaches user to request.
 * Returns 401 Unauthorized if token is missing or invalid.
 * 
 * ## Token Verification Process:
 * 1. Extract token from "Authorization: Bearer <token>" header
 * 2. Verify token signature using JWT_SECRET
 * 3. Check token expiration
 * 4. Decode payload and attach to req.user
 * 5. Call next() to continue request processing
 * 
 * ## Error Responses:
 * - 401 "No token provided" - Missing Authorization header
 * - 401 "Invalid token" - Token signature verification failed
 * - 401 "Token expired" - Token exp claim is in the past
 * 
 * ## Development Mode:
 * In development (NODE_ENV=development), requests without tokens
 * are allowed through with a mock admin user. This allows testing
 * without authentication. **MUST BE REMOVED IN PRODUCTION!**
 * 
 * @param req - Express request object
 * @param res - Express response object
 * @param next - Express next function
 * 
 * @example
 * // In routes file:
 * import { authenticate } from '../middleware/auth.middleware';
 * 
 * router.get('/protected', authenticate, (req: AuthRequest, res) => {
 *   console.log('Authenticated user:', req.user?.email);
 *   res.json({ userId: req.user?.userId });
 * });
 */
export const authenticate = (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const authHeader = req.headers.authorization;

    // Step 1: Check for Authorization header
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new ApiError(401, 'No token provided');
    }

    // Step 2: Extract token from "Bearer <token>" format
    const token = extractTokenFromHeader(authHeader);
    
    if (!token) {
      throw new ApiError(401, 'Invalid authorization header format');
    }

    // Step 3: Verify JWT_SECRET is configured
    const secret = process.env.JWT_SECRET;
    if (!secret) {
      throw new Error(
        'JWT_SECRET not configured. Add JWT_SECRET to your .env file. ' +
        'Generate with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"'
      );
    }

    // Step 4: Verify token signature and decode payload
    /**
     * Token verification internally:
     * 1. Splits token: header.payload.signature
     * 2. Decodes header and payload from Base64URL
     * 3. Recomputes signature: HMACSHA256(header + payload, secret)
     * 4. Compares signatures (must match exactly)
     * 5. Checks exp claim (must be in future)
     * 6. Returns decoded payload if all checks pass
     */
    const decoded = jwt.verify(token, secret) as TokenPayload;

    // Step 5: Attach user data to request object
    (req as AuthRequest).user = decoded;

    // Step 6: Continue to next middleware/route handler
    next();

  } catch (error) {
    // ========================================
    // ERROR HANDLING
    // ========================================
    
    if (error instanceof jwt.JsonWebTokenError) {
      // Invalid token format or signature mismatch
      next(new ApiError(401, 'Invalid token'));
    } else if (error instanceof jwt.TokenExpiredError) {
      // Token exp claim is in the past
      next(new ApiError(401, 'Token expired'));
    } else if (error instanceof jwt.NotBeforeError) {
      // Token used before nbf (not before) claim
      next(new ApiError(401, 'Token not yet valid'));
    } else {
      // Other errors (database, configuration, etc.)
      next(error);
    }
  }
};

/**
 * Optional Authentication Middleware
 * 
 * Extracts user from token if present, but allows request to continue
 * without authentication. Useful for public routes that behave differently
 * for authenticated users.
 * 
 * ## Use Cases:
 * - Public content that shows personalization for logged-in users
 * - APIs that return different data based on authentication status
 * - Landing pages with login-specific features
 * 
 * @param req - Express request object
 * @param res - Express response object
 * @param next - Express next function
 * 
 * @example
 * router.get('/discover', optionalAuthenticate, (req: AuthRequest, res) => {
 *   if (req.user) {
 *     // Return personalized barber recommendations
 *     return res.json({ barbers: getPersonalizedBarbers(req.user.campusId) });
 *   } else {
 *     // Return general barber list
 *     return res.json({ barbers: getAllBarbers() });
 *   }
 * });
 */
export const optionalAuthenticate = (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const authHeader = req.headers.authorization;

    // No token provided - continue without authentication
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return next();
    }

    const token = extractTokenFromHeader(authHeader);
    
    if (!token) {
      return next();
    }

    const secret = process.env.JWT_SECRET;

    // If secret not configured, log warning and continue without auth
    if (!secret) {
      console.warn('JWT_SECRET not configured - continuing without authentication');
      return next();
    }

    try {
      // Try to verify and decode token
      const decoded = jwt.verify(token, secret) as TokenPayload;
      (req as AuthRequest).user = decoded;
    } catch (error) {
      // Invalid token - just log and continue without authentication
      console.warn('Invalid token provided in optionalAuthenticate, continuing without auth');
    }

    next();
  } catch (error) {
    // Any unexpected error - just continue without authentication
    next();
  }
};

/**
 * Role-Based Authorization Middleware
 * 
 * Ensures authenticated user has one of the specified roles.
 * Must be used AFTER authenticate() middleware.
 * 
 * ## Authorization vs Authentication:
 * - **Authentication**: Verifying WHO you are (handled by authenticate)
 * - **Authorization**: Verifying WHAT you can do (handled by requireRole)
 * 
 * @param roles - List of allowed roles
 * @returns Express middleware function
 * 
 * @example
 * // Only admins can access
 * router.delete('/users/:id', authenticate, requireRole('admin'), deleteUser);
 * 
 * // Both barbers and admins can access
 * router.get('/bookings', authenticate, requireRole('barber', 'admin'), getBookings);
 * 
 * // All authenticated users (any role)
 * router.get('/profile', authenticate, getProfile);
 * 
 * ## Role Hierarchy:
 * - ADMIN: Has access to all roles (admin, campus_manager, barber, student)
 * - CAMPUS_MANAGER: Has access to campus_manager, barber, and student routes
 * - BARBER: Has access to barber and student routes
 * - STUDENT/CONSUMER: Has access to student routes only
 */
export const requireRole = (...roles: Array<'student' | 'barber' | 'campus_manager' | 'admin'>) => {
  return (req: Request, res: Response, next: NextFunction) => {
    const authReq = req as AuthRequest;

    // Check if user is authenticated
    if (!authReq.user) {
      return next(new ApiError(401, 'Not authenticated'));
    }

    // Get user's role (case-insensitive)
    const userRole = authReq.user.role?.toLowerCase();
    const allowedRoles = roles.map(r => r.toLowerCase());
    
    // Role hierarchy: higher roles include access to lower roles
    const roleHierarchy: Record<string, string[]> = {
      'admin': ['admin', 'campus_manager', 'barber', 'student', 'consumer'],
      'campus_manager': ['campus_manager', 'barber', 'student', 'consumer'],
      'barber': ['barber', 'student', 'consumer'],
      'student': ['student', 'consumer'],
      'consumer': ['student', 'consumer'],
    };
    
    // Get all roles the user has access to based on hierarchy
    const userAccessibleRoles = roleHierarchy[userRole] || [userRole];
    
    // Check if any of the required roles are in the user's accessible roles
    const hasAccess = allowedRoles.some(role => userAccessibleRoles.includes(role));
    
    if (!hasAccess) {
      return next(
        new ApiError(
          403, 
          `Access denied. Required role: ${roles.join(' or ')}. Your role: ${authReq.user.role}`
        )
      );
    }

    // User has required role - continue
    next();
  };
};

/**
 * Email Verification Requirement Middleware
 * 
 * Ensures user has verified their email address.
 * Must be used AFTER authenticate() middleware.
 * 
 * NOTE: Current implementation is a placeholder.
 * Actual implementation requires database query to check email_verified status.
 * 
 * @param req - Express request object
 * @param res - Express response object
 * @param next - Express next function
 * 
 * @example
 * router.post('/book-barber', authenticate, requireEmailVerification, createBooking);
 */
export const requireEmailVerification = (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  // TODO: Implement email verification check
  // This would query the database to check user's email_verified status
  // For now, just pass through
  
  // Example implementation:
  // const authReq = req as AuthRequest;
  // const user = await getUserFromDatabase(authReq.user?.userId);
  // if (!user.email_verified) {
  //   return next(new ApiError(403, 'Email verification required'));
  // }
  
  next();
};

/**
 * Admin-Only Middleware
 * 
 * Convenience middleware to require admin role.
 * Equivalent to requireRole('admin').
 * 
 * @param req - Express request object
 * @param res - Express response object
 * @param next - Express next function
 * 
 * @example
 * router.post('/admin/campus', authenticate, requireAdmin, createCampus);
 * router.get('/admin/users', authenticate, requireAdmin, getAllUsers);
 */
export const requireAdmin = (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  const authReq = req as AuthRequest;

  if (!authReq.user) {
    return next(new ApiError(401, 'Not authenticated'));
  }

  if (authReq.user.role?.toLowerCase() !== 'admin') {
    return next(new ApiError(403, 'Admin access required'));
  }

  next();
};

/**
 * Re-resolve `req.user.role` from the database after JWT authentication.
 *
 * JWT roles are fixed at sign-in / refresh time. Admin and campus-manager users who were
 * promoted after their last login (or mobile clients reusing an older access token) can
 * pass `GET /auth/me` while `/admin/*` still rejects them with "Admin access required".
 */
export const refreshAccessRoleFromDb = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const authReq = req as AuthRequest;
    const userId = authReq.user?.userId;
    if (!userId) {
      return next(new ApiError(401, 'Not authenticated'));
    }

    const result = await pool.query(
      'SELECT role FROM users WHERE id = $1',
      [userId]
    );
    if (result.rows.length === 0) {
      return next(new ApiError(401, 'User not found'));
    }

    authReq.user!.role = await resolveAccessTokenRole(userId, result.rows[0].role);
    next();
  } catch (error) {
    next(error);
  }
};

/**
 * Campus Manager Middleware
 * 
 * Convenience middleware to require campus_manager or admin role.
 * Campus managers have all barber + consumer functionality plus management capabilities.
 * 
 * @param req - Express request object
 * @param res - Express response object
 * @param next - Express next function
 * 
 * @example
 * router.post('/barber-applications/:id/review', authenticate, requireCampusManager, reviewApplication);
 */
export const requireCampusManager = (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  const authReq = req as AuthRequest;

  if (!authReq.user) {
    return next(new ApiError(401, 'Not authenticated'));
  }

  const userRole = authReq.user.role?.toLowerCase();
  if (userRole !== 'campus_manager' && userRole !== 'admin') {
    return next(new ApiError(403, 'Campus Manager access required'));
  }

  next();
};

/**
 * Campus Access Middleware
 * 
 * Ensures user can only access resources from their own campus.
 * Useful for multi-tenant isolation.
 * 
 * @param campusIdParam - Name of route parameter containing campus ID
 * @returns Express middleware function
 * 
 * @example
 * router.get('/campus/:campusId/barbers', authenticate, requireCampusAccess('campusId'), getBarbers);
 * // User with campusId=1 can only access /campus/1/barbers
 */
export const requireCampusAccess = (campusIdParam: string = 'campusId') => {
  return (req: Request, res: Response, next: NextFunction) => {
    const authReq = req as AuthRequest;

    if (!authReq.user) {
      return next(new ApiError(401, 'Not authenticated'));
    }

    // Admins can access all campuses
    if (authReq.user.role === 'admin') {
      return next();
    }

    // Get campus ID from route parameter
    const requestedCampusId = parseInt(req.params[campusIdParam]);

    // Check if user's campus matches requested campus
    if (authReq.user.campusId !== requestedCampusId) {
      return next(new ApiError(403, 'Access denied. You can only access resources from your campus.'));
    }

    next();
  };
};

/**
 * Rate Limiting by User Middleware
 * 
 * Helper to extract user ID for rate limiting purposes.
 * Use with express-rate-limit library.
 * 
 * @param req - Express request object
 * @returns User ID for rate limit key, or IP address as fallback
 * 
 * @example
 * import rateLimit from 'express-rate-limit';
 * 
 * const apiLimiter = rateLimit({
 *   windowMs: 15 * 60 * 1000, // 15 minutes
 *   max: 100, // 100 requests per window
 *   keyGenerator: getUserIdForRateLimit,
 * });
 * 
 * router.post('/api/bookings', authenticate, apiLimiter, createBooking);
 */
export const getUserIdForRateLimit = (req: Request): string => {
  const authReq = req as AuthRequest;
  return authReq.user?.userId || req.ip || 'anonymous';
};
