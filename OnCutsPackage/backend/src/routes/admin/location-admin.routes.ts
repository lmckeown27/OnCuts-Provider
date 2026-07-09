/**
 * Admin Location Routes
 * 
 * Admin-only endpoints for location management
 * 
 * Endpoints:
 * - GET /admin/locations/unverified - View unverified locations
 * - POST /admin/locations/:id/verify - Manually verify location
 * - POST /admin/locations/merge - Merge duplicate locations
 * - PUT /admin/locations/:id - Update location details
 * - DELETE /admin/locations/:id - Delete location
 * - GET /admin/locations/merge-log - View merge history
 */

import { Router, Request, Response, NextFunction } from 'express';
import { body, query, param, validationResult } from 'express-validator';
import { authenticate, requireAdmin } from '../../middleware/auth';
import { pool } from '../../database/connection';
import { CampusLocationService } from '../../services/campus-location.service';
import { ApiError } from '../../middleware/errorHandler';
import { logger } from '../../utils/logger';

const router = Router();
const locationService = new CampusLocationService(pool);

/**
 * Validation helper
 */
const validate = (req: Request, res: Response, next: NextFunction) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  next();
};

/**
 * GET /api/admin/locations/unverified
 * Get all unverified locations requiring review
 */
router.get(
  '/unverified',
  authenticate,
  requireAdmin,
  [
    query('universityId').optional().isUUID(),
    query('minUsageCount').optional().isInt({ min: 0 }).toInt(),
    query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
  ],
  validate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { universityId, minUsageCount = 2, limit = 50 } = req.query;

      let query = `
        SELECT cl.*,
          ARRAY_AGG(DISTINCT cla.alias) FILTER (WHERE cla.alias IS NOT NULL) as aliases,
          COUNT(DISTINCT b.id) as barber_count
        FROM campus_locations cl
        LEFT JOIN campus_location_aliases cla ON cla.campus_location_id = cl.id
        LEFT JOIN bookings b ON b.location_id = cl.id
        WHERE cl.is_verified = false
        AND cl.usage_count >= $1
      `;
      const params: any[] = [minUsageCount];
      let paramIndex = 2;

      if (universityId) {
        query += ` AND cl.university_id = $${paramIndex++}`;
        params.push(universityId);
      }

      query += `
        GROUP BY cl.id
        ORDER BY cl.usage_count DESC, cl.confidence DESC
        LIMIT $${paramIndex}
      `;
      params.push(limit);

      const result = await pool.query(query, params);

      res.json({
        success: true,
        data: {
          locations: result.rows,
          count: result.rows.length,
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * POST /api/admin/locations/:id/verify
 * Manually verify a location
 */
router.post(
  '/:id/verify',
  authenticate,
  requireAdmin,
  [param('id').isUUID().withMessage('Valid location ID required')],
  validate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const adminId = (req as any).user.userId;

      await pool.query(
        `UPDATE campus_locations
         SET is_verified = true, confidence = 1.0, updated_at = NOW()
         WHERE id = $1`,
        [id]
      );

      logger.info('Location manually verified by admin', { locationId: id, adminId });

      res.json({
        success: true,
        message: 'Location verified successfully',
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * POST /api/admin/locations/merge
 * Merge two duplicate locations
 */
router.post(
  '/merge',
  authenticate,
  requireAdmin,
  [
    body('sourceLocationId').isUUID().withMessage('Valid source location ID required'),
    body('targetLocationId').isUUID().withMessage('Valid target location ID required'),
    body('reason').optional().isString().trim(),
  ],
  validate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { sourceLocationId, targetLocationId, reason = 'Admin manual merge' } = req.body;
      const adminId = (req as any).user.userId;

      // Prevent self-merge
      if (sourceLocationId === targetLocationId) {
        throw new ApiError(400, 'Cannot merge a location with itself');
      }

      await locationService.mergeLocations(
        sourceLocationId,
        targetLocationId,
        reason,
        adminId
      );

      logger.info('Locations merged by admin', {
        sourceLocationId,
        targetLocationId,
        adminId,
      });

      res.json({
        success: true,
        message: 'Locations merged successfully',
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * PUT /api/admin/locations/:id
 * Update location details
 */
router.put(
  '/:id',
  authenticate,
  requireAdmin,
  [
    param('id').isUUID().withMessage('Valid location ID required'),
    body('name').optional().isString().trim().isLength({ min: 2, max: 200 }),
    body('category')
      .optional()
      .isIn(['ON_CAMPUS', 'OFF_CAMPUS', 'DORM', 'APARTMENT', 'COMMON_AREA', 'OTHER']),
    body('cohort')
      .optional()
      .isIn(['FIRST_YEAR', 'UPPER_CLASS', 'GRAD', 'MIXED', 'UNKNOWN']),
  ],
  validate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const { name, category, cohort } = req.body;

      const updates: string[] = [];
      const params: any[] = [];
      let paramIndex = 1;

      if (name) {
        updates.push(`name = $${paramIndex++}`);
        params.push(name);
      }

      if (category) {
        updates.push(`category = $${paramIndex++}`);
        params.push(category);
      }

      if (cohort) {
        updates.push(`cohort = $${paramIndex++}`);
        params.push(cohort);
      }

      if (updates.length === 0) {
        throw new ApiError(400, 'No updates provided');
      }

      updates.push(`updated_at = NOW()`);
      params.push(id);

      await pool.query(
        `UPDATE campus_locations SET ${updates.join(', ')} WHERE id = $${paramIndex}`,
        params
      );

      logger.info('Location updated by admin', { locationId: id, updates });

      res.json({
        success: true,
        message: 'Location updated successfully',
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * DELETE /api/admin/locations/:id
 * Delete a location
 */
router.delete(
  '/:id',
  authenticate,
  requireAdmin,
  [param('id').isUUID().withMessage('Valid location ID required')],
  validate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const adminId = (req as any).user.userId;

      // Check if location is in use
      const usageCheck = await pool.query(
        'SELECT COUNT(*) as count FROM bookings WHERE location_id = $1',
        [id]
      );

      const bookingCount = parseInt(usageCheck.rows[0].count);

      if (bookingCount > 0) {
        throw new ApiError(
          400,
          `Cannot delete location: ${bookingCount} booking(s) reference this location`
        );
      }

      await pool.query('DELETE FROM campus_locations WHERE id = $1', [id]);

      logger.warn('Location deleted by admin', { locationId: id, adminId });

      res.json({
        success: true,
        message: 'Location deleted successfully',
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * GET /api/admin/locations/merge-log
 * View merge history
 */
router.get(
  '/merge-log',
  authenticate,
  requireAdmin,
  [query('limit').optional().isInt({ min: 1, max: 100 }).toInt()],
  validate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { limit = 20 } = req.query;

      const result = await pool.query(
        `SELECT lml.*, u.full_name as merged_by_name
         FROM location_merge_log lml
         LEFT JOIN users u ON u.id = lml.merged_by_user_id
         ORDER BY lml.created_at DESC
         LIMIT $1`,
        [limit]
      );

      res.json({
        success: true,
        data: {
          logs: result.rows,
          count: result.rows.length,
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * GET /api/admin/locations/duplicates
 * Find potential duplicate locations
 */
router.get(
  '/duplicates',
  authenticate,
  requireAdmin,
  [
    query('universityId').optional().isUUID(),
    query('threshold').optional().isFloat({ min: 0.8, max: 0.99 }).toFloat(),
  ],
  validate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { universityId, threshold = 0.9 } = req.query;

      // This is a simplified duplicate detection
      // For production, would use fuzzy matching service
      let query = `
        SELECT 
          cl1.id as id1,
          cl1.name as name1,
          cl1.usage_count as usage1,
          cl2.id as id2,
          cl2.name as name2,
          cl2.usage_count as usage2,
          similarity(cl1.normalized_name, cl2.normalized_name) as similarity_score
        FROM campus_locations cl1
        JOIN campus_locations cl2 ON cl1.university_id = cl2.university_id
          AND cl1.id < cl2.id
          AND similarity(cl1.normalized_name, cl2.normalized_name) > $1
      `;
      const params: any[] = [threshold];

      if (universityId) {
        query += ` WHERE cl1.university_id = $2`;
        params.push(universityId);
      }

      query += ` ORDER BY similarity_score DESC LIMIT 50`;

      const result = await pool.query(query, params);

      res.json({
        success: true,
        data: {
          duplicates: result.rows,
          count: result.rows.length,
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

export default router;

