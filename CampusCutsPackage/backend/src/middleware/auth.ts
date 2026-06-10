/**
 * Auth Middleware - Compatibility Export
 * 
 * This file maintains backward compatibility by re-exporting all authentication
 * middleware from auth.middleware.ts.
 * 
 * All existing imports from '../middleware/auth' will continue to work.
 * 
 * For new code, consider importing directly from '../middleware/auth.middleware'
 * for clearer naming.
 * 
 * @deprecated Use '../middleware/auth.middleware' for new code
 * @see auth.middleware.ts for full documentation
 */

export {
  // Middleware functions
  authenticate,
  optionalAuthenticate,
  requireRole,
  requireEmailVerification,
  requireAdmin,
  refreshAccessRoleFromDb,
  requireCampusAccess,
  getUserIdForRateLimit,
  
  // Types
  JwtPayload,
  AuthRequest,
} from './auth.middleware';
