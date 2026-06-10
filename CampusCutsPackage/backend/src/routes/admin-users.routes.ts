/**
 * Admin Users Routes
 * 
 * API routes for admin user management
 */

import express from 'express';
import {
  getUserById,
  updateUserStatus,
  toggleVerification,
  addAdminNote,
  resetPassword,
  deleteUser,
} from '../controllers/admin-users.controller';

const router = express.Router();

// Note: In production, add authentication middleware here
// router.use(authenticate);
// router.use(requireAdmin);

/**
 * GET /api/admin/users/:userId
 * Get user details, activity logs, and transactions
 */
router.get('/:userId', getUserById);

/**
 * PUT /api/admin/users/:userId/status
 * Update user status (active, blocked, banned, suspended)
 * Body: { status: 'active' | 'blocked' | 'banned' | 'suspended' }
 */
router.put('/:userId/status', updateUserStatus);

/**
 * PUT /api/admin/users/:userId/verification
 * Toggle user verification status
 */
router.put('/:userId/verification', toggleVerification);

/**
 * POST /api/admin/users/:userId/notes
 * Add admin note to user
 * Body: { note: string }
 */
router.post('/:userId/notes', addAdminNote);

/**
 * POST /api/admin/users/:userId/reset-password
 * Send password reset email to user
 */
router.post('/:userId/reset-password', resetPassword);

/**
 * DELETE /api/admin/users/:userId
 * Delete user account (dangerous operation)
 */
router.delete('/:userId', deleteUser);

export default router;

