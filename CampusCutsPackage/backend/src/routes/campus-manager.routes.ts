/**
 * Campus Manager API Routes
 * 
 * Handles Campus Manager role management and dashboard data
 * All routes require authentication
 */

import { Router, Request, Response, NextFunction } from 'express';
import { campusManagerService } from '../services/campus-manager.service';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';

const router = Router();

/**
 * GET /api/campus-manager/with-managers
 * Get all active campuses with their campus managers (if any) - PUBLIC for landing page
 */
router.get('/with-managers', async (req: Request, res: Response, next: NextFunction) => {
  try {
    // Find campus managers by checking BOTH:
    // 1. barbers.isCampusManager = true on the campus
    // 2. users.role = 'CAMPUS_MANAGER' with matching users.campusId
    // Prioritize users with CAMPUS_MANAGER role
    const result = await pool.query(`
      SELECT 
        c.id as campus_id,
        c.name as campus_name,
        c.city,
        c.state,
        cm.barber_id,
        cm.user_id,
        cm.first_name,
        cm.last_name,
        cm.bio,
        cm.profile_image_url,
        cm.instagram_handle
      FROM campuses c
      LEFT JOIN LATERAL (
        SELECT 
          b.id as barber_id,
          u.id as user_id,
          u.first_name,
          u.last_name,
          b.bio,
          u."avatarUrl" as profile_image_url,
          u."instagramHandle" as instagram_handle
        FROM users u
        LEFT JOIN barbers b ON b."userId" = u.id
        WHERE 
          -- User with CAMPUS_MANAGER role for this campus
          (u."campusId" = c.id AND u.role = 'CAMPUS_MANAGER')
          OR
          -- Barber with isCampusManager flag on this campus
          (b."campusId" = c.id AND b."isCampusManager" = true AND b."isActive" = true)
        ORDER BY 
          CASE WHEN u.role = 'CAMPUS_MANAGER' THEN 0 ELSE 1 END
        LIMIT 1
      ) cm ON true
      WHERE c.is_active = true
      ORDER BY c.name
    `);

    const campusesWithManagers = result.rows.map(row => ({
      campusId: row.campus_id,
      campusName: row.campus_name,
      city: row.city,
      state: row.state,
      manager: row.barber_id ? {
        barberId: row.barber_id,
        userId: row.user_id,
        firstName: row.first_name,
        lastName: row.last_name,
        bio: row.bio,
        profileImageUrl: row.profile_image_url,
        instagramHandle: row.instagram_handle,
      } : null
    }));

    res.json({
      success: true,
      data: campusesWithManagers,
      count: campusesWithManagers.length,
    });
  } catch (error) {
    logger.error('Error fetching campuses with managers:', error);
    next(error);
  }
});

/**
 * GET /api/campus-manager/check/:barberId
 * Check if a barber is a Campus Manager
 */
router.get('/check/:barberId', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { barberId } = req.params;
    
    const isCampusManager = await campusManagerService.isCampusManager(barberId);
    
    res.json({
      success: true,
      data: { isCampusManager },
    });
  } catch (error) {
    logger.error('Error checking Campus Manager status:', error);
    next(error);
  }
});

/**
 * GET /api/campus-manager/campus/:campusId
 * Get Campus Manager for a specific campus
 */
router.get('/campus/:campusId', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { campusId } = req.params;
    
    const campusManager = await campusManagerService.getCampusManager(campusId);
    
    res.json({
      success: true,
      data: { campusManager },
    });
  } catch (error) {
    logger.error('Error fetching Campus Manager:', error);
    next(error);
  }
});

/**
 * POST /api/campus-manager/promote
 * Promote a barber to Campus Manager (Admin only)
 */
router.post('/promote', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { barberId, campusId } = req.body;
    
    if (!barberId || !campusId) {
      return res.status(400).json({
        success: false,
        error: 'barberId and campusId are required',
      });
    }
    
    const result = await campusManagerService.promoteToCampusManager(barberId, campusId);
    
    if (!result.success) {
      return res.status(400).json({
        success: false,
        error: result.error,
      });
    }
    
    res.json({
      success: true,
      message: 'Barber promoted to Campus Manager successfully',
    });
  } catch (error) {
    logger.error('Error promoting to Campus Manager:', error);
    next(error);
  }
});

/**
 * POST /api/campus-manager/revoke
 * Revoke Campus Manager role (Admin only)
 */
router.post('/revoke', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { barberId } = req.body;
    
    if (!barberId) {
      return res.status(400).json({
        success: false,
        error: 'barberId is required',
      });
    }
    
    const success = await campusManagerService.revokeCampusManager(barberId);
    
    res.json({
      success,
      message: success 
        ? 'Campus Manager role revoked successfully' 
        : 'Failed to revoke Campus Manager role',
    });
  } catch (error) {
    logger.error('Error revoking Campus Manager:', error);
    next(error);
  }
});

/**
 * GET /api/campus-manager/permissions
 * Get Campus Manager permissions list
 */
router.get('/permissions', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const permissions = campusManagerService.getCampusManagerPermissions();
    
    res.json({
      success: true,
      data: { permissions },
    });
  } catch (error) {
    logger.error('Error fetching permissions:', error);
    next(error);
  }
});

/**
 * POST /api/campus-manager/verify-permission
 * Verify a Campus Manager has permission for an action
 */
router.post('/verify-permission', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { barberId, campusId, action } = req.body;
    
    if (!barberId || !campusId || !action) {
      return res.status(400).json({
        success: false,
        error: 'barberId, campusId, and action are required',
      });
    }
    
    const hasPermission = await campusManagerService.verifyPermission(
      barberId,
      campusId,
      action
    );
    
    res.json({
      success: true,
      data: { hasPermission },
    });
  } catch (error) {
    logger.error('Error verifying permission:', error);
    next(error);
  }
});

export default router;

