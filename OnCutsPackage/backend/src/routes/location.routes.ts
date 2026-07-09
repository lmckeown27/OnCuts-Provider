/**
 * Location Routes
 * 
 * API endpoints for managing service locations and barber location assignments
 * 
 * Flow:
 * 1. Campus Manager creates locations (auto-approved, universal by default)
 * 2. Barber can request new locations (pending approval)
 * 3. Campus Manager approves/rejects barber requests
 * 4. Campus Manager decides if location is universal or barber-specific
 * 
 * Tables:
 * - service_locations: All locations with status (pending/approved/rejected)
 * - barber_service_locations: Which barbers work at which locations
 */

import { Router, Response, NextFunction } from 'express';
import { pool } from '../database/connection';
import { authenticate, AuthRequest } from '../middleware/auth';
import { logger } from '../utils/logger';

const router = Router();

// ============================================================================
// SERVICE LOCATIONS (Campus Manager / Admin)
// ============================================================================

/**
 * GET /api/v1/locations/campus/:campusId
 * Get all locations for a campus (Campus Manager sees all, others see approved only)
 */
router.get('/campus/:campusId', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { campusId } = req.params;
    const { status } = req.query; // 'pending', 'approved', 'rejected', or 'all'
    
    // Check if user is campus manager or admin
    const authCheck = await pool.query(
      `SELECT u.role, b."isCampusManager", b."campusId"
       FROM users u
       LEFT JOIN barbers b ON u.id = b."userId"
       WHERE u.id = $1`,
      [userId]
    );
    
    const user = authCheck.rows[0];
    const isAdmin = user?.role === 'ADMIN';
    const isCampusManager = user?.isCampusManager && user?.campusId === campusId;
    const canSeeAll = isAdmin || isCampusManager;
    
    let whereClause = 'sl.campus_id = $1';
    if (status && status !== 'all' && canSeeAll) {
      whereClause += ` AND sl.status = '${status}'`;
    } else if (!canSeeAll) {
      whereClause += " AND sl.status = 'approved' AND sl.is_active = true";
    }
    
    const result = await pool.query(
      `SELECT 
        sl.id,
        sl.campus_id,
        sl.name,
        sl.description,
        sl.is_active,
        sl.status,
        sl.is_universal,
        sl.restricted_to_barber_id,
        sl.created_at,
        sl.updated_at,
        sl.reviewed_at,
        u.first_name || ' ' || u.last_name as created_by_name,
        u.email as created_by_email,
        rb.id as restricted_barber_id,
        ru.first_name || ' ' || ru.last_name as restricted_barber_name,
        reviewer.first_name || ' ' || reviewer.last_name as reviewed_by_name,
        (SELECT COUNT(*) FROM barber_service_locations bsl WHERE bsl.location_id = sl.id) as barber_count
      FROM service_locations sl
      LEFT JOIN users u ON sl.created_by = u.id
      LEFT JOIN barbers rb ON sl.restricted_to_barber_id = rb.id
      LEFT JOIN users ru ON rb."userId" = ru.id
      LEFT JOIN users reviewer ON sl.reviewed_by = reviewer.id
      WHERE ${whereClause}
      ORDER BY 
        CASE sl.status 
          WHEN 'pending' THEN 1 
          WHEN 'approved' THEN 2 
          ELSE 3 
        END,
        sl.name ASC`,
      [campusId]
    );
    
    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error: any) {
    logger.error('Error fetching campus locations:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/locations/campus/:campusId
 * Create a new location for a campus (Campus Manager / Admin only - auto-approved)
 */
router.post('/campus/:campusId', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { campusId } = req.params;
    const { name, description, isUniversal, restrictedToBarberId } = req.body;
    
    if (!name || !name.trim()) {
      return res.status(400).json({
        success: false,
        error: 'Location name is required',
      });
    }
    
    // Check if user is campus manager or admin
    const authCheck = await pool.query(
      `SELECT u.role, b."isCampusManager", b."campusId"
       FROM users u
       LEFT JOIN barbers b ON u.id = b."userId"
       WHERE u.id = $1`,
      [userId]
    );
    
    const user = authCheck.rows[0];
    const isAdmin = user?.role === 'ADMIN';
    const isCampusManager = user?.isCampusManager && user?.campusId === campusId;
    
    if (!isAdmin && !isCampusManager) {
      return res.status(403).json({
        success: false,
        error: 'Only campus managers and admins can create locations',
      });
    }
    
    // Check for duplicate name
    const duplicateCheck = await pool.query(
      `SELECT id FROM service_locations WHERE campus_id = $1 AND LOWER(name) = LOWER($2)`,
      [campusId, name.trim()]
    );
    
    if (duplicateCheck.rows.length > 0) {
      return res.status(400).json({
        success: false,
        error: 'A location with this name already exists for this campus',
      });
    }
    
    // Campus manager creates - auto approved
    const result = await pool.query(
      `INSERT INTO service_locations (campus_id, name, description, created_by, status, is_universal, restricted_to_barber_id, reviewed_by, reviewed_at)
       VALUES ($1, $2, $3, $4, 'approved', $5, $6, $4, CURRENT_TIMESTAMP)
       RETURNING *`,
      [campusId, name.trim(), description || null, userId, isUniversal !== false, restrictedToBarberId || null]
    );
    
    // If restricted to a specific barber, auto-assign them
    if (restrictedToBarberId) {
      await pool.query(
        `INSERT INTO barber_service_locations (barber_id, location_id, is_primary)
         VALUES ($1, $2, false)
         ON CONFLICT (barber_id, location_id) DO NOTHING`,
        [restrictedToBarberId, result.rows[0].id]
      );
    }
    
    logger.info(`Location created: ${name} for campus ${campusId} by campus manager ${userId}`);
    
    res.status(201).json({
      success: true,
      data: result.rows[0],
    });
  } catch (error: any) {
    logger.error('Error creating location:', error.message || error);
    next(error);
  }
});

/**
 * PUT /api/v1/locations/:locationId
 * Update a location (Campus Manager / Admin only)
 */
router.put('/:locationId', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { locationId } = req.params;
    const { name, description, isActive, isUniversal, restrictedToBarberId } = req.body;
    
    // Get the location to check campus
    const locationCheck = await pool.query(
      `SELECT campus_id FROM service_locations WHERE id = $1`,
      [locationId]
    );
    
    if (locationCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Location not found',
      });
    }
    
    const campusId = locationCheck.rows[0].campus_id;
    
    // Check if user is campus manager or admin
    const authCheck = await pool.query(
      `SELECT u.role, b."isCampusManager", b."campusId"
       FROM users u
       LEFT JOIN barbers b ON u.id = b."userId"
       WHERE u.id = $1`,
      [userId]
    );
    
    const user = authCheck.rows[0];
    const isAdmin = user?.role === 'ADMIN';
    const isCampusManager = user?.isCampusManager && user?.campusId === campusId;
    
    if (!isAdmin && !isCampusManager) {
      return res.status(403).json({
        success: false,
        error: 'Only campus managers and admins can update locations',
      });
    }
    
    const result = await pool.query(
      `UPDATE service_locations
       SET name = COALESCE($1, name),
           description = COALESCE($2, description),
           is_active = COALESCE($3, is_active),
           is_universal = COALESCE($4, is_universal),
           restricted_to_barber_id = $5,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $6
       RETURNING *`,
      [name, description, isActive, isUniversal, restrictedToBarberId, locationId]
    );
    
    res.json({
      success: true,
      data: result.rows[0],
    });
  } catch (error: any) {
    logger.error('Error updating location:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/locations/:locationId/approve
 * Approve a pending location request (Campus Manager / Admin only)
 */
router.post('/:locationId/approve', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { locationId } = req.params;
    const { isUniversal, restrictedToBarberId } = req.body;
    
    // Get the location
    const locationCheck = await pool.query(
      `SELECT campus_id, created_by, status FROM service_locations WHERE id = $1`,
      [locationId]
    );
    
    if (locationCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Location not found',
      });
    }
    
    const location = locationCheck.rows[0];
    
    if (location.status !== 'pending') {
      return res.status(400).json({
        success: false,
        error: 'This location has already been reviewed',
      });
    }
    
    // Check if user is campus manager or admin
    const authCheck = await pool.query(
      `SELECT u.role, b."isCampusManager", b."campusId"
       FROM users u
       LEFT JOIN barbers b ON u.id = b."userId"
       WHERE u.id = $1`,
      [userId]
    );
    
    const user = authCheck.rows[0];
    const isAdmin = user?.role === 'ADMIN';
    const isCampusManager = user?.isCampusManager && user?.campusId === location.campus_id;
    
    if (!isAdmin && !isCampusManager) {
      return res.status(403).json({
        success: false,
        error: 'Only campus managers and admins can approve locations',
      });
    }
    
    // Get the barber who created it (for auto-assignment)
    const creatorBarber = await pool.query(
      `SELECT id FROM barbers WHERE "userId" = $1`,
      [location.created_by]
    );
    
    const creatorBarberId = creatorBarber.rows[0]?.id;
    
    // Approve the location
    const result = await pool.query(
      `UPDATE service_locations
       SET status = 'approved',
           is_universal = $1,
           restricted_to_barber_id = $2,
           reviewed_by = $3,
           reviewed_at = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $4
       RETURNING *`,
      [isUniversal !== false, restrictedToBarberId || null, userId, locationId]
    );
    
    // Auto-assign to the barber who requested it
    if (creatorBarberId) {
      await pool.query(
        `INSERT INTO barber_service_locations (barber_id, location_id, is_primary)
         VALUES ($1, $2, false)
         ON CONFLICT (barber_id, location_id) DO NOTHING`,
        [creatorBarberId, locationId]
      );
    }
    
    // If restricted to a specific barber (different from creator), assign them too
    if (restrictedToBarberId && restrictedToBarberId !== creatorBarberId) {
      await pool.query(
        `INSERT INTO barber_service_locations (barber_id, location_id, is_primary)
         VALUES ($1, $2, false)
         ON CONFLICT (barber_id, location_id) DO NOTHING`,
        [restrictedToBarberId, locationId]
      );
    }
    
    logger.info(`Location approved: ${locationId} by ${userId}`);
    
    res.json({
      success: true,
      data: result.rows[0],
      message: 'Location approved successfully',
    });
  } catch (error: any) {
    logger.error('Error approving location:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/locations/:locationId/reject
 * Reject a pending location request (Campus Manager / Admin only)
 */
router.post('/:locationId/reject', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { locationId } = req.params;
    
    // Get the location
    const locationCheck = await pool.query(
      `SELECT campus_id, status FROM service_locations WHERE id = $1`,
      [locationId]
    );
    
    if (locationCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Location not found',
      });
    }
    
    const location = locationCheck.rows[0];
    
    if (location.status !== 'pending') {
      return res.status(400).json({
        success: false,
        error: 'This location has already been reviewed',
      });
    }
    
    // Check if user is campus manager or admin
    const authCheck = await pool.query(
      `SELECT u.role, b."isCampusManager", b."campusId"
       FROM users u
       LEFT JOIN barbers b ON u.id = b."userId"
       WHERE u.id = $1`,
      [userId]
    );
    
    const user = authCheck.rows[0];
    const isAdmin = user?.role === 'ADMIN';
    const isCampusManager = user?.isCampusManager && user?.campusId === location.campus_id;
    
    if (!isAdmin && !isCampusManager) {
      return res.status(403).json({
        success: false,
        error: 'Only campus managers and admins can reject locations',
      });
    }
    
    // Reject the location
    const result = await pool.query(
      `UPDATE service_locations
       SET status = 'rejected',
           reviewed_by = $1,
           reviewed_at = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $2
       RETURNING *`,
      [userId, locationId]
    );
    
    logger.info(`Location rejected: ${locationId} by ${userId}`);
    
    res.json({
      success: true,
      data: result.rows[0],
      message: 'Location rejected',
    });
  } catch (error: any) {
    logger.error('Error rejecting location:', error.message || error);
    next(error);
  }
});

/**
 * DELETE /api/v1/locations/:locationId
 * Delete a location (Campus Manager / Admin only)
 */
router.delete('/:locationId', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { locationId } = req.params;
    
    // Get the location to check campus
    const locationCheck = await pool.query(
      `SELECT campus_id, name FROM service_locations WHERE id = $1`,
      [locationId]
    );
    
    if (locationCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Location not found',
      });
    }
    
    const campusId = locationCheck.rows[0].campus_id;
    const locationName = locationCheck.rows[0].name;
    
    // Check if user is campus manager or admin
    const authCheck = await pool.query(
      `SELECT u.role, b."isCampusManager", b."campusId"
       FROM users u
       LEFT JOIN barbers b ON u.id = b."userId"
       WHERE u.id = $1`,
      [userId]
    );
    
    const user = authCheck.rows[0];
    const isAdmin = user?.role === 'ADMIN';
    const isCampusManager = user?.isCampusManager && user?.campusId === campusId;
    
    if (!isAdmin && !isCampusManager) {
      return res.status(403).json({
        success: false,
        error: 'Only campus managers and admins can delete locations',
      });
    }
    
    // Delete associated barber_service_locations first
    await pool.query(`DELETE FROM barber_service_locations WHERE location_id = $1`, [locationId]);
    
    // Delete the location
    await pool.query(`DELETE FROM service_locations WHERE id = $1`, [locationId]);
    
    logger.info(`Location deleted: ${locationName} (${locationId}) by user ${userId}`);
    
    res.json({
      success: true,
      message: 'Location deleted successfully',
    });
  } catch (error: any) {
    logger.error('Error deleting location:', error.message || error);
    next(error);
  }
});

// ============================================================================
// BARBER LOCATIONS
// ============================================================================

/**
 * GET /api/v1/locations/barber/:barberId
 * Get locations assigned to a barber
 */
router.get('/barber/:barberId', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { barberId } = req.params;
    
    const result = await pool.query(
      `SELECT 
        bsl.id as assignment_id,
        bsl.is_primary,
        bsl.created_at as assigned_at,
        sl.id as location_id,
        sl.name,
        sl.description,
        sl.is_active,
        sl.status
      FROM barber_service_locations bsl
      JOIN service_locations sl ON bsl.location_id = sl.id
      WHERE bsl.barber_id = $1 AND sl.status = 'approved' AND sl.is_active = true
      ORDER BY bsl.is_primary DESC, sl.name ASC`,
      [barberId]
    );
    
    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error: any) {
    logger.error('Error fetching barber locations:', error.message || error);
    next(error);
  }
});

/**
 * GET /api/v1/locations/my-locations
 * Get locations for the logged-in barber
 */
router.get('/my-locations', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    
    // Get barber ID for this user
    const barberCheck = await pool.query(
      `SELECT id, "campusId" FROM barbers WHERE "userId" = $1`,
      [userId]
    );
    
    if (barberCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Barber profile not found',
      });
    }
    
    const barberId = barberCheck.rows[0].id;
    const campusId = barberCheck.rows[0].campusId;
    
    // Get assigned locations (approved only)
    const assignedResult = await pool.query(
      `SELECT 
        bsl.id as assignment_id,
        bsl.is_primary,
        sl.id as location_id,
        sl.name,
        sl.description,
        sl.status
      FROM barber_service_locations bsl
      JOIN service_locations sl ON bsl.location_id = sl.id
      WHERE bsl.barber_id = $1 AND sl.status = 'approved' AND sl.is_active = true
      ORDER BY bsl.is_primary DESC, sl.name ASC`,
      [barberId]
    );
    
    // Get pending location requests by this barber
    const pendingResult = await pool.query(
      `SELECT id, name, description, status, created_at
       FROM service_locations
       WHERE created_by = $1 AND status = 'pending'
       ORDER BY created_at DESC`,
      [userId]
    );
    
    // Get all available universal locations for this campus (that barber can add)
    const availableResult = await pool.query(
      `SELECT id, name, description
       FROM service_locations
       WHERE campus_id = $1 
         AND status = 'approved' 
         AND is_active = true
         AND (is_universal = true OR restricted_to_barber_id = $2)
       ORDER BY name ASC`,
      [campusId, barberId]
    );
    
    res.json({
      success: true,
      data: {
        assigned: assignedResult.rows,
        pending: pendingResult.rows,
        available: availableResult.rows,
      },
    });
  } catch (error: any) {
    logger.error('Error fetching my locations:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/locations/barber/request
 * Request a new location (Barber submits for campus manager approval)
 */
router.post('/barber/request', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { name, description } = req.body;
    
    if (!name || !name.trim()) {
      return res.status(400).json({
        success: false,
        error: 'Location name is required',
      });
    }
    
    // Get barber info
    const barberCheck = await pool.query(
      `SELECT b.id, b."campusId", b."isActive"
       FROM barbers b
       WHERE b."userId" = $1`,
      [userId]
    );
    
    if (barberCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Barber profile not found',
      });
    }
    
    const campusId = barberCheck.rows[0].campusId;
    
    if (!barberCheck.rows[0].isActive) {
      return res.status(403).json({
        success: false,
        error: 'Your barber account is not active',
      });
    }
    
    // Check for duplicate name (any status)
    const duplicateCheck = await pool.query(
      `SELECT id, status FROM service_locations WHERE campus_id = $1 AND LOWER(name) = LOWER($2)`,
      [campusId, name.trim()]
    );
    
    if (duplicateCheck.rows.length > 0) {
      const existing = duplicateCheck.rows[0];
      if (existing.status === 'pending') {
        return res.status(400).json({
          success: false,
          error: 'A request for this location is already pending review',
        });
      } else if (existing.status === 'approved') {
        return res.status(400).json({
          success: false,
          error: 'This location already exists. You can add it from the available locations list.',
        });
      } else {
        return res.status(400).json({
          success: false,
          error: 'This location was previously rejected. Please contact your campus manager.',
        });
      }
    }
    
    // Create pending location request
    const result = await pool.query(
      `INSERT INTO service_locations (campus_id, name, description, created_by, status, is_universal)
       VALUES ($1, $2, $3, $4, 'pending', true)
       RETURNING *`,
      [campusId, name.trim(), description || null, userId]
    );
    
    logger.info(`Location request submitted: ${name} for campus ${campusId} by barber ${userId}`);
    
    res.status(201).json({
      success: true,
      data: result.rows[0],
      message: 'Location request submitted for review',
    });
  } catch (error: any) {
    logger.error('Error requesting location:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/locations/barber/assign
 * Assign an approved location to a barber
 */
router.post('/barber/assign', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { locationId, isPrimary } = req.body;
    
    if (!locationId) {
      return res.status(400).json({
        success: false,
        error: 'Location ID is required',
      });
    }
    
    // Get barber ID for this user
    const barberCheck = await pool.query(
      `SELECT b.id, b."campusId" FROM barbers b WHERE b."userId" = $1`,
      [userId]
    );
    
    if (barberCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Barber profile not found',
      });
    }
    
    const barberId = barberCheck.rows[0].id;
    const barberCampusId = barberCheck.rows[0].campusId;
    
    // Verify the location is approved and available to this barber
    const locationCheck = await pool.query(
      `SELECT campus_id, status, is_universal, restricted_to_barber_id 
       FROM service_locations 
       WHERE id = $1 AND is_active = true`,
      [locationId]
    );
    
    if (locationCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Location not found or inactive',
      });
    }
    
    const location = locationCheck.rows[0];
    
    if (location.status !== 'approved') {
      return res.status(400).json({
        success: false,
        error: 'This location has not been approved yet',
      });
    }
    
    if (location.campus_id !== barberCampusId) {
      return res.status(400).json({
        success: false,
        error: 'This location is not available for your campus',
      });
    }
    
    // Check if barber can use this location
    if (!location.is_universal && location.restricted_to_barber_id !== barberId) {
      return res.status(403).json({
        success: false,
        error: 'This location is restricted to another barber',
      });
    }
    
    // If setting as primary, unset other primary locations
    if (isPrimary) {
      await pool.query(
        `UPDATE barber_service_locations SET is_primary = false WHERE barber_id = $1`,
        [barberId]
      );
    }
    
    // Insert or update the assignment
    const result = await pool.query(
      `INSERT INTO barber_service_locations (barber_id, location_id, is_primary)
       VALUES ($1, $2, $3)
       ON CONFLICT (barber_id, location_id) 
       DO UPDATE SET is_primary = $3
       RETURNING *`,
      [barberId, locationId, isPrimary || false]
    );
    
    res.json({
      success: true,
      data: result.rows[0],
    });
  } catch (error: any) {
    logger.error('Error assigning location:', error.message || error);
    next(error);
  }
});

/**
 * DELETE /api/v1/locations/barber/unassign/:locationId
 * Remove a location from a barber
 */
router.delete('/barber/unassign/:locationId', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { locationId } = req.params;
    
    // Get barber ID for this user
    const barberCheck = await pool.query(
      `SELECT id FROM barbers WHERE "userId" = $1`,
      [userId]
    );
    
    if (barberCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Barber profile not found',
      });
    }
    
    const barberId = barberCheck.rows[0].id;
    
    await pool.query(
      `DELETE FROM barber_service_locations WHERE barber_id = $1 AND location_id = $2`,
      [barberId, locationId]
    );
    
    res.json({
      success: true,
      message: 'Location removed from your profile',
    });
  } catch (error: any) {
    logger.error('Error unassigning location:', error.message || error);
    next(error);
  }
});

/**
 * GET /api/v1/locations/for-booking/:barberId
 * Get available locations for booking with a specific barber
 * (Used by consumers when scheduling a service)
 */
router.get('/for-booking/:barberId', async (req, res, next) => {
  try {
    const { barberId } = req.params;
    
    const result = await pool.query(
      `SELECT 
        sl.id,
        sl.name,
        sl.description,
        bsl.is_primary
      FROM barber_service_locations bsl
      JOIN service_locations sl ON bsl.location_id = sl.id
      WHERE bsl.barber_id = $1 AND sl.status = 'approved' AND sl.is_active = true
      ORDER BY bsl.is_primary DESC, sl.name ASC`,
      [barberId]
    );
    
    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error: any) {
    logger.error('Error fetching locations for booking:', error.message || error);
    next(error);
  }
});

// ============================================================================
// ADMIN / CAMPUS MANAGER LOCATION ASSIGNMENT
// ============================================================================

/**
 * POST /api/v1/locations/admin/assign
 * Campus Manager assigns a location to a specific barber
 */
router.post('/admin/assign', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { barberId, locationId } = req.body;
    
    if (!barberId || !locationId) {
      return res.status(400).json({
        success: false,
        error: 'Barber ID and Location ID are required',
      });
    }
    
    // Get location and verify campus
    const locationCheck = await pool.query(
      `SELECT campus_id, status FROM service_locations WHERE id = $1`,
      [locationId]
    );
    
    if (locationCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Location not found',
      });
    }
    
    const campusId = locationCheck.rows[0].campus_id;
    
    // Check if user is campus manager or admin
    const authCheck = await pool.query(
      `SELECT u.role, b."isCampusManager", b."campusId"
       FROM users u
       LEFT JOIN barbers b ON u.id = b."userId"
       WHERE u.id = $1`,
      [userId]
    );
    
    const user = authCheck.rows[0];
    const isAdmin = user?.role === 'ADMIN';
    const isCampusManager = user?.isCampusManager && user?.campusId === campusId;
    
    if (!isAdmin && !isCampusManager) {
      return res.status(403).json({
        success: false,
        error: 'Only campus managers and admins can assign locations to barbers',
      });
    }
    
    // Verify barber belongs to this campus
    const barberCheck = await pool.query(
      `SELECT "campusId" FROM barbers WHERE id = $1`,
      [barberId]
    );
    
    if (barberCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Barber not found',
      });
    }
    
    if (barberCheck.rows[0].campusId !== campusId) {
      return res.status(400).json({
        success: false,
        error: 'Barber does not belong to this campus',
      });
    }
    
    // Assign location to barber
    const result = await pool.query(
      `INSERT INTO barber_service_locations (barber_id, location_id, is_primary)
       VALUES ($1, $2, false)
       ON CONFLICT (barber_id, location_id) DO NOTHING
       RETURNING *`,
      [barberId, locationId]
    );
    
    logger.info(`Location ${locationId} assigned to barber ${barberId} by campus manager ${userId}`);
    
    res.json({
      success: true,
      data: result.rows[0],
      message: 'Location assigned to barber',
    });
  } catch (error: any) {
    logger.error('Error assigning location to barber:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/locations/admin/revoke
 * Campus Manager revokes a location from a specific barber
 */
router.post('/admin/revoke', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { barberId, locationId } = req.body;
    
    if (!barberId || !locationId) {
      return res.status(400).json({
        success: false,
        error: 'Barber ID and Location ID are required',
      });
    }
    
    // Get location and verify campus
    const locationCheck = await pool.query(
      `SELECT campus_id FROM service_locations WHERE id = $1`,
      [locationId]
    );
    
    if (locationCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Location not found',
      });
    }
    
    const campusId = locationCheck.rows[0].campus_id;
    
    // Check if user is campus manager or admin
    const authCheck = await pool.query(
      `SELECT u.role, b."isCampusManager", b."campusId"
       FROM users u
       LEFT JOIN barbers b ON u.id = b."userId"
       WHERE u.id = $1`,
      [userId]
    );
    
    const user = authCheck.rows[0];
    const isAdmin = user?.role === 'ADMIN';
    const isCampusManager = user?.isCampusManager && user?.campusId === campusId;
    
    if (!isAdmin && !isCampusManager) {
      return res.status(403).json({
        success: false,
        error: 'Only campus managers and admins can revoke locations from barbers',
      });
    }
    
    // Remove assignment
    await pool.query(
      `DELETE FROM barber_service_locations WHERE barber_id = $1 AND location_id = $2`,
      [barberId, locationId]
    );
    
    logger.info(`Location ${locationId} revoked from barber ${barberId} by campus manager ${userId}`);
    
    res.json({
      success: true,
      message: 'Location revoked from barber',
    });
  } catch (error: any) {
    logger.error('Error revoking location from barber:', error.message || error);
    next(error);
  }
});

/**
 * POST /api/v1/locations/admin/assign-all
 * Campus Manager assigns a location to ALL barbers on a campus
 */
router.post('/admin/assign-all', authenticate, async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user!.userId;
    const { locationId, campusId } = req.body;
    
    if (!locationId || !campusId) {
      return res.status(400).json({
        success: false,
        error: 'Location ID and Campus ID are required',
      });
    }
    
    // Get location and verify campus
    const locationCheck = await pool.query(
      `SELECT campus_id, status FROM service_locations WHERE id = $1`,
      [locationId]
    );
    
    if (locationCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Location not found',
      });
    }
    
    if (locationCheck.rows[0].campus_id !== campusId) {
      return res.status(400).json({
        success: false,
        error: 'Location does not belong to this campus',
      });
    }
    
    // Check if user is campus manager or admin
    const authCheck = await pool.query(
      `SELECT u.role, b."isCampusManager", b."campusId"
       FROM users u
       LEFT JOIN barbers b ON u.id = b."userId"
       WHERE u.id = $1`,
      [userId]
    );
    
    const user = authCheck.rows[0];
    const isAdmin = user?.role === 'ADMIN';
    const isCampusManager = user?.isCampusManager && user?.campusId === campusId;
    
    if (!isAdmin && !isCampusManager) {
      return res.status(403).json({
        success: false,
        error: 'Only campus managers and admins can assign locations to all barbers',
      });
    }
    
    // Get all active barbers for this campus
    const barbersResult = await pool.query(
      `SELECT id FROM barbers WHERE "campusId" = $1 AND "isActive" = true`,
      [campusId]
    );
    
    // Assign location to all barbers
    let assignedCount = 0;
    for (const barber of barbersResult.rows) {
      const result = await pool.query(
        `INSERT INTO barber_service_locations (barber_id, location_id, is_primary)
         VALUES ($1, $2, false)
         ON CONFLICT (barber_id, location_id) DO NOTHING
         RETURNING *`,
        [barber.id, locationId]
      );
      if (result.rows.length > 0) assignedCount++;
    }
    
    logger.info(`Location ${locationId} assigned to ${assignedCount} barbers on campus ${campusId} by ${userId}`);
    
    res.json({
      success: true,
      message: `Location assigned to ${assignedCount} barbers`,
      assignedCount,
    });
  } catch (error: any) {
    logger.error('Error assigning location to all barbers:', error.message || error);
    next(error);
  }
});

export default router;
