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

    const {
      latitude,
      longitude,
      label,
      source,
      web_only: webOnlyBody,
      service_radius_km: serviceRadiusKm,
    } = req.body ?? {};

    const hasCoords = latitude !== undefined || longitude !== undefined;
    if (hasCoords) {
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

    if (serviceRadiusKm !== undefined) {
      if (typeof serviceRadiusKm !== 'number' || serviceRadiusKm < 0 || serviceRadiusKm > 100) {
        throw new ApiError(400, 'Service radius must be a number between 0 and 100 km');
      }
    }

    if (webOnlyBody !== undefined && typeof webOnlyBody !== 'boolean') {
      throw new ApiError(400, 'web_only must be a boolean');
    }

    const normalizedSource =
      typeof source === 'string' ? source.trim().toLowerCase() : undefined;
    if (
      normalizedSource !== undefined &&
      !['device', 'manual', 'campus_default'].includes(normalizedSource)
    ) {
      throw new ApiError(400, 'source must be device, manual, or campus_default');
    }

    const barberCheck = await pool.query(
      `SELECT id,
              service_location_web_only,
              service_latitude,
              service_longitude,
              service_location_label,
              service_location_source,
              service_radius_km
       FROM barbers
       WHERE "userId" = $1`,
      [userId]
    );

    if (barberCheck.rows.length === 0) {
      throw new ApiError(404, 'Barber profile not found');
    }

    const barber = barberCheck.rows[0];
    const barberId = barber.id as string;
    let webOnly = barber.service_location_web_only === true;

    if (typeof webOnlyBody === 'boolean') {
      await pool.query(
        `UPDATE barbers
         SET service_location_web_only = $1,
             "updatedAt" = NOW()
         WHERE id = $2`,
        [webOnlyBody, barberId]
      );
      webOnly = webOnlyBody;
    }

    const isDeviceUpdate = normalizedSource === 'device' && hasCoords;
    if (isDeviceUpdate && webOnly) {
      res.json({
        success: true,
        message: 'Device location ignored while manual location is locked',
        data: {
          service_latitude: barber.service_latitude != null ? Number(barber.service_latitude) : null,
          service_longitude: barber.service_longitude != null ? Number(barber.service_longitude) : null,
          service_location_label: barber.service_location_label ?? null,
          service_location_source: barber.service_location_source ?? null,
          service_location_web_only: true,
          service_radius_km: barber.service_radius_km != null ? Number(barber.service_radius_km) : null,
          ignored_device_update: true,
        },
      });
      return;
    }

    if (!hasCoords && webOnlyBody === undefined && serviceRadiusKm === undefined) {
      throw new ApiError(400, 'Provide coordinates, web_only, and/or service_radius_km');
    }

    if (hasCoords || serviceRadiusKm !== undefined) {
      const nextLabel =
        typeof label === 'string' && label.trim()
          ? label.trim()
          : undefined;
      const nextSource = normalizedSource ?? (hasCoords ? 'manual' : undefined);

      const result = await pool.query(
        `UPDATE barbers
         SET service_latitude = COALESCE($1, service_latitude),
             service_longitude = COALESCE($2, service_longitude),
             service_radius_km = COALESCE($3, service_radius_km),
             service_location_label = COALESCE($4, service_location_label),
             service_location_source = COALESCE($5, service_location_source),
             "updatedAt" = NOW()
         WHERE id = $6
         RETURNING id,
                   service_latitude,
                   service_longitude,
                   service_radius_km,
                   service_location_label,
                   service_location_source,
                   service_location_web_only`,
        [
          hasCoords ? latitude : null,
          hasCoords ? longitude : null,
          serviceRadiusKm ?? null,
          nextLabel ?? null,
          nextSource ?? null,
          barberId,
        ]
      );

      const row = result.rows[0];
      logger.info(`Barber ${barberId} service location updated`, {
        source: nextSource,
        webOnly: row.service_location_web_only === true,
      });

      res.json({
        success: true,
        message: 'Service location updated successfully',
        data: serializeServiceLocationRow(row),
      });
      return;
    }

    const refreshed = await pool.query(
      `SELECT service_latitude,
              service_longitude,
              service_radius_km,
              service_location_label,
              service_location_source,
              service_location_web_only
       FROM barbers
       WHERE id = $1`,
      [barberId]
    );

    res.json({
      success: true,
      message: 'Service location preference updated',
      data: serializeServiceLocationRow(refreshed.rows[0]),
    });
  } catch (error) {
    next(error);
  }
};

/**
 * GET /api/v1/barbers/service-location — current public discovery pin for the signed-in operator.
 */
export const getBarberServiceLocation = async (
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
      `SELECT service_latitude,
              service_longitude,
              service_radius_km,
              service_location_label,
              service_location_source,
              service_location_web_only
       FROM barbers
       WHERE "userId" = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'Barber profile not found');
    }

    res.json({
      success: true,
      data: serializeServiceLocationRow(result.rows[0]),
    });
  } catch (error) {
    next(error);
  }
};

function serializeServiceLocationRow(row: Record<string, unknown>) {
  return {
    service_latitude: row.service_latitude != null ? Number(row.service_latitude) : null,
    service_longitude: row.service_longitude != null ? Number(row.service_longitude) : null,
    service_radius_km: row.service_radius_km != null ? Number(row.service_radius_km) : null,
    service_location_label: (row.service_location_label as string | null) ?? null,
    service_location_source: (row.service_location_source as string | null) ?? null,
    service_location_web_only: row.service_location_web_only === true,
    ignored_device_update: false,
  };
}

