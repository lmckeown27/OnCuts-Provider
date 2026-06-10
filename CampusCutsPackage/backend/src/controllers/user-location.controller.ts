/**
 * User Location Controller
 * 
 * Handles updating and retrieving user location data
 * for proximity-based barber matching.
 */

import { Response, NextFunction } from 'express';
import { AuthRequest } from '../middleware/auth';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { logger } from '../utils/logger';

interface UpdateLocationBody {
  latitude: number;
  longitude: number;
  permission: 'granted' | 'denied' | 'prompt' | 'unavailable';
}

/**
 * Update user's current location
 * PUT /api/users/location
 */
export const updateUserLocation = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      throw new ApiError(401, 'Unauthorized');
    }

    const { latitude, longitude, permission }: UpdateLocationBody = req.body;

    // Validate permission value
    const validPermissions = ['granted', 'denied', 'prompt', 'unavailable'];
    if (!validPermissions.includes(permission)) {
      throw new ApiError(400, `Invalid permission value. Must be one of: ${validPermissions.join(', ')}`);
    }

    // If permission is granted, latitude and longitude are required
    if (permission === 'granted') {
      if (typeof latitude !== 'number' || typeof longitude !== 'number') {
        throw new ApiError(400, 'Latitude and longitude are required when permission is granted');
      }

      // Validate coordinate ranges
      if (latitude < -90 || latitude > 90) {
        throw new ApiError(400, 'Latitude must be between -90 and 90');
      }
      if (longitude < -180 || longitude > 180) {
        throw new ApiError(400, 'Longitude must be between -180 and 180');
      }
    }

    // Update user location
    const result = await pool.query(
      `UPDATE users 
       SET latitude = $1,
           longitude = $2,
           location_permission = $3,
           location_updated_at = NOW(),
           "updatedAt" = NOW()
       WHERE id = $4
       RETURNING id, latitude, longitude, location_permission, location_updated_at`,
      [
        permission === 'granted' ? latitude : null,
        permission === 'granted' ? longitude : null,
        permission,
        userId
      ]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'User not found');
    }

    logger.info(`User ${userId} location updated: permission=${permission}, lat=${latitude}, lng=${longitude}`);

    res.json({
      success: true,
      message: 'Location updated successfully',
      data: {
        latitude: result.rows[0].latitude,
        longitude: result.rows[0].longitude,
        permission: result.rows[0].location_permission,
        updated_at: result.rows[0].location_updated_at,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Get user's current location status
 * GET /api/users/location
 */
export const getUserLocation = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      throw new ApiError(401, 'Unauthorized');
    }

    const result = await pool.query(
      `SELECT latitude, longitude, location_permission, location_updated_at
       FROM users WHERE id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'User not found');
    }

    const user = result.rows[0];

    res.json({
      success: true,
      data: {
        latitude: user.latitude,
        longitude: user.longitude,
        permission: user.location_permission || 'prompt',
        updated_at: user.location_updated_at,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Update barber's service location (where they provide services)
 * PUT /api/barbers/service-location
 */
export const updateBarberServiceLocation = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      throw new ApiError(401, 'Unauthorized');
    }

    const { latitude, longitude, service_radius_km } = req.body;

    // Validate coordinates if provided
    if (latitude !== undefined && longitude !== undefined) {
      if (typeof latitude !== 'number' || typeof longitude !== 'number') {
        throw new ApiError(400, 'Latitude and longitude must be numbers');
      }
      if (latitude < -90 || latitude > 90) {
        throw new ApiError(400, 'Latitude must be between -90 and 90');
      }
      if (longitude < -180 || longitude > 180) {
        throw new ApiError(400, 'Longitude must be between -180 and 180');
      }
    }

    // Validate service radius
    if (service_radius_km !== undefined) {
      if (typeof service_radius_km !== 'number' || service_radius_km < 0 || service_radius_km > 100) {
        throw new ApiError(400, 'Service radius must be a number between 0 and 100 km');
      }
    }

    // Check if user has a barber profile
    const barberCheck = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1',
      [userId]
    );

    if (barberCheck.rows.length === 0) {
      throw new ApiError(404, 'Barber profile not found');
    }

    const barberId = barberCheck.rows[0].id;

    // Update barber service location
    const result = await pool.query(
      `UPDATE barbers 
       SET service_latitude = COALESCE($1, service_latitude),
           service_longitude = COALESCE($2, service_longitude),
           service_radius_km = COALESCE($3, service_radius_km),
           "updatedAt" = NOW()
       WHERE id = $4
       RETURNING id, service_latitude, service_longitude, service_radius_km`,
      [latitude, longitude, service_radius_km, barberId]
    );

    logger.info(`Barber ${barberId} service location updated`);

    res.json({
      success: true,
      message: 'Service location updated successfully',
      data: {
        service_latitude: result.rows[0].service_latitude,
        service_longitude: result.rows[0].service_longitude,
        service_radius_km: result.rows[0].service_radius_km,
      },
    });
  } catch (error) {
    next(error);
  }
};

