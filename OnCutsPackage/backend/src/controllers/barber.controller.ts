import { Response, NextFunction } from 'express';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest } from '../middleware/auth';
import suiChainService from '../services/sui-chain.service';
import { uploadToS3 } from '../services/s3.service';
import { logger } from '../utils/logger';
import { getSocketIO } from '../index';
import { USER_PRIMARY_WALLET_SQL_U } from '../utils/user-wallet-address';

export const getAllBarbers = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { campusId, minRating, maxPrice, specialty, lat, lng, maxDistance, includeHidden } = req.query;
    
    // Parse user location for distance-based sorting
    const userLat = lat ? parseFloat(lat as string) : null;
    const userLng = lng ? parseFloat(lng as string) : null;
    const hasUserLocation = userLat !== null && userLng !== null && 
                            !isNaN(userLat) && !isNaN(userLng);
    
    // Maximum distance filter in km (default: 8km / ~5 miles - reasonable for university area)
    // This prevents students from accidentally booking barbers too far away
    const maxDistanceKm = maxDistance ? parseFloat(maxDistance as string) : 8;

    // Build dynamic query for barbers from PostgreSQL
    // Column names match Prisma schema: avgRating, totalReviews, totalBookings, isActive
    // If user location provided, calculate distance using Haversine formula
    let query = `
      SELECT 
        b.id,
        b."userId" as user_id,
        b.bio,
        b.specialties,
        b.pricing,
        b."avgRating" as average_rating,
        b."totalReviews" as total_reviews,
        b."totalBookings" as total_bookings,
        b."isActive" as is_active,
        b."createdAt" as created_at,
        b."weeklySchedule" as weekly_schedule,
        b.service_latitude,
        b.service_longitude,
        b.service_radius_km,
        u.email,
        u.first_name,
        u.last_name,
        u."displayName" as display_name,
        u."avatarUrl" as profile_picture_url,
        u."instagramHandle" as instagram_handle,
        u."campusId" as campus_id,
        u.latitude as user_latitude,
        u.longitude as user_longitude,
        u.stripe_account_id,
        u.stripe_payouts_enabled
    `;
    
    const params: any[] = [];
    let paramIndex = 1;

    // Add distance calculation if user location is provided
    if (hasUserLocation) {
      // Haversine formula for distance in km
      // Uses barber's service location if set, otherwise falls back to user's location
      query += `,
        (6371 * acos(
          LEAST(1.0, GREATEST(-1.0,
            cos(radians($${paramIndex})) * 
            cos(radians(COALESCE(b.service_latitude, u.latitude))) * 
            cos(radians(COALESCE(b.service_longitude, u.longitude)) - radians($${paramIndex + 1})) + 
            sin(radians($${paramIndex})) * 
            sin(radians(COALESCE(b.service_latitude, u.latitude)))
          ))
        )) as distance_km
      `;
      params.push(userLat, userLng);
      paramIndex += 2;
    }

    // Build WHERE clause - campus managers can request to include hidden barbers
    // When includeHidden=true (CM view), show ALL barbers including those without Stripe
    // When includeHidden=false (consumer view), only show active barbers with Stripe setup
    const shouldIncludeHidden = includeHidden === 'true';
    
    // Filter by user role = 'BARBER' or 'CAMPUS_MANAGER' to exclude demoted users
    // Campus managers are still barbers who can accept bookings
    // When includeHidden=true (CM view), show all barbers including those without Stripe or inactive
    // When includeHidden=false (consumer view), only show active barbers with Stripe setup
    query += `
      FROM barbers b
      JOIN users u ON b."userId" = u.id
      WHERE u.role IN ('BARBER', 'CAMPUS_MANAGER', 'ADMIN') ${shouldIncludeHidden ? '' : 'AND b."isActive" = true AND u.stripe_account_id IS NOT NULL AND u.stripe_payouts_enabled = true'}
    `;

    // Handle campusId - can be UUID or slug
    let resolvedCampusId = campusId as string | undefined;
    if (campusId) {
      // Check if it's a UUID (simple regex check)
      const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(campusId as string);
      
      if (!isUUID) {
        // It's a slug - look up the campus by name/slug
        const campusResult = await pool.query(
          `SELECT id FROM campuses 
           WHERE LOWER(REPLACE(name, ' ', '-')) LIKE LOWER($1) 
              OR LOWER(name) LIKE LOWER($2)
           LIMIT 1`,
          [`%${campusId}%`, `%${(campusId as string).replace(/-/g, ' ')}%`]
        );
        
        if (campusResult.rows.length > 0) {
          resolvedCampusId = campusResult.rows[0].id;
          logger.info(`Resolved campus slug "${campusId}" to UUID: ${resolvedCampusId}`);
        } else {
          logger.warn(`Campus slug "${campusId}" not found in database`);
          resolvedCampusId = undefined; // Don't filter by campus if not found
        }
      }
      
      if (resolvedCampusId) {
        query += ` AND b."campusId" = $${paramIndex}`;
        params.push(resolvedCampusId);
        paramIndex++;
      }
    }

    if (minRating) {
      query += ` AND b."avgRating" >= $${paramIndex}`;
      params.push(Number(minRating));
      paramIndex++;
    }

    if (specialty) {
      query += ` AND $${paramIndex} = ANY(b.specialties)`;
      params.push(String(specialty));
      paramIndex++;
    }

    // Sort by distance if user location provided, otherwise by rating
    if (hasUserLocation) {
      query += ` ORDER BY distance_km ASC NULLS LAST, b."avgRating" DESC NULLS LAST`;
    } else {
      query += ` ORDER BY b."avgRating" DESC NULLS LAST`;
    }

    const result = await pool.query(query, params);
    
    // Filter by max distance if user location is provided
    // BUT: If campusId is provided, show ALL barbers for that campus (they may be temporarily away)
    // Default 8km (~5 miles) is reasonable for university students when no campus is specified
    let filteredRows = result.rows;
    let showingClosestFallback = false;
    
    // Only apply distance filtering if NO campusId is specified (or if it wasn't resolved)
    // When a campus is selected, show all barbers assigned to that campus regardless of location
    if (hasUserLocation && !resolvedCampusId) {
      const nearbyRows = result.rows.filter(row => {
        // Include barbers without location data (they might be new)
        if (row.distance_km === null || row.distance_km === undefined) return true;
        return row.distance_km <= maxDistanceKm;
      });
      
      // If no barbers within radius, show all barbers sorted by distance (closest first)
      if (nearbyRows.length === 0 && result.rows.length > 0) {
        filteredRows = result.rows; // All barbers, already sorted by distance
        showingClosestFallback = true;
      } else {
        filteredRows = nearbyRows;
      }
    }
    // When campusId IS provided: show all barbers for that campus, sorted by distance
    
    // Get services/pricing for each barber
    const barbers = await Promise.all(filteredRows.map(async (barber) => {
      // Get fallback pricing from barber_services table
      const servicesResult = await pool.query(
        `SELECT id, name, description, "priceUsdCents" as price, "durationMinutes" as duration_minutes
         FROM barber_services 
         WHERE "barberId" = $1 AND "isActive" = true`,
        [barber.id]
      );
      
      // Get portfolio images
      const portfolioResult = await pool.query(
        `SELECT id, "imageUrl" as image_url, caption, "orderIndex" as order_index
         FROM portfolio_images 
         WHERE "barberId" = $1 
         ORDER BY "orderIndex"`,
        [barber.id]
      );
      
      // Get barber's assigned service locations
      const locationsResult = await pool.query(
        `SELECT 
          sl.id,
          sl.name,
          sl.description,
          bsl.is_primary
        FROM barber_service_locations bsl
        JOIN service_locations sl ON bsl.location_id = sl.id
        WHERE bsl.barber_id = $1 AND sl.status = 'approved' AND sl.is_active = true
        ORDER BY bsl.is_primary DESC, sl.name ASC`,
        [barber.id]
      );
      
      // Get review stats from bookings (average and count of submitted reviews only)
      const reviewStatsResult = await pool.query(
        `SELECT 
          AVG("reviewRating")::numeric(3,2) as average_rating,
          COUNT(*) as review_count
        FROM bookings 
        WHERE "barberId" = $1 AND "reviewRating" IS NOT NULL`,
        [barber.id]
      );
      const averageRating = parseFloat(reviewStatsResult.rows[0]?.average_rating || '0');
      const reviewCount = parseInt(reviewStatsResult.rows[0]?.review_count || '0', 10);
      
      // Use barber.pricing (from barbers table JSONB) if available, otherwise fall back to barber_services
      const customPricing = barber.pricing || [];
      const servicePricing = servicesResult.rows.map(s => ({
        ...s,
        price: s.price / 100 // Convert cents to dollars for frontend
      }));
      
      // Filter out services that have been deleted (is_active = false in services table)
      let filteredPricing = customPricing.length > 0 ? customPricing : servicePricing;
      const activeServicesResult = await pool.query(
        `SELECT LOWER(name) as name FROM services WHERE is_active = true`
      );
      const activeServiceNames = new Set(activeServicesResult.rows.map(s => s.name.toLowerCase()));
      
      if (filteredPricing.length > 0) {
        filteredPricing = filteredPricing.filter((p: any) => 
          activeServiceNames.has(p.name?.toLowerCase())
        );
      }
      
      // Also filter specialties to remove deleted services
      const filteredSpecialties = Array.isArray(barber.specialties) 
        ? barber.specialties.filter((s: string) => activeServiceNames.has(s?.toLowerCase()))
        : [];
      
      return {
        ...barber,
        name: barber.display_name || `${barber.first_name} ${barber.last_name}`,
        // Include distance if calculated (rounded to 1 decimal)
        distance_km: barber.distance_km !== null ? Math.round(barber.distance_km * 10) / 10 : null,
        // Convert km to miles for US users
        distance_miles: barber.distance_km !== null ? Math.round(barber.distance_km * 0.621371 * 10) / 10 : null,
        pricing: filteredPricing,
        specialties: filteredSpecialties,
        portfolio_images: portfolioResult.rows,
        service_locations: locationsResult.rows,
        average_rating: averageRating,
        review_count: reviewCount,
        // Stripe status - fully set up (visible to consumers) vs not
        has_stripe_setup: !!barber.stripe_account_id && barber.stripe_payouts_enabled === true,
      };
    }));

    // Apply maxPrice filter in-memory (since it requires pricing data)
    let filteredBarbers = barbers;
    if (maxPrice) {
      filteredBarbers = barbers.filter(b => {
        if (!b.pricing || b.pricing.length === 0) return true;
        const minPrice = Math.min(...b.pricing.map((p: any) => p.price));
        return minPrice <= Number(maxPrice);
      });
    }

    res.json({
      success: true,
      data: filteredBarbers,
      pagination: {
        page: 1,
        limit: filteredBarbers.length,
        total: filteredBarbers.length,
        total_pages: 1,
      },
      meta: {
        sorted_by: hasUserLocation ? 'distance' : 'rating',
        user_location_provided: hasUserLocation,
        max_distance_km: hasUserLocation && !showingClosestFallback ? maxDistanceKm : null,
        max_distance_miles: hasUserLocation && !showingClosestFallback ? Math.round(maxDistanceKm * 0.621371 * 10) / 10 : null,
        total_before_distance_filter: hasUserLocation ? result.rows.length : filteredBarbers.length,
        showing_closest_fallback: showingClosestFallback, // true if no barbers within radius, showing closest instead
      },
    });
  } catch (error) {
    logger.error('Error in getAllBarbers:', error);
    next(error);
  }
};

/**
 * Get current user's barber profile (for authenticated barbers)
 */
export const getMyBarberProfile = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      throw new ApiError(401, 'Unauthorized');
    }

    const barberResult = await pool.query(
      `SELECT 
        b.id,
        b."userId" as user_id,
        b.bio,
        b.specialties,
        b.pricing,
        b."avgRating" as average_rating,
        b."totalReviews" as total_reviews,
        b."totalBookings" as total_bookings,
        b."isActive" as is_active,
        b."createdAt" as created_at,
        b."weeklySchedule" as weekly_schedule,
        u.email,
        u.first_name,
        u.last_name,
        u."displayName" as display_name,
        u."avatarUrl" as profile_picture_url,
        u."instagramHandle" as instagram_handle,
        u."campusId" as campus_id
      FROM barbers b
      JOIN users u ON b."userId" = u.id
      WHERE b."userId" = $1`,
      [userId]
    );

    if (barberResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No barber profile found for this user',
      });
    }

    const barber = barberResult.rows[0];

    // Get services/pricing
    const servicesResult = await pool.query(
      `SELECT id, name, description, "priceUsdCents" as price, "durationMinutes" as duration_minutes
       FROM barber_services 
       WHERE "barberId" = $1 AND "isActive" = true`,
      [barber.id]
    );

    // Filter out services that have been deleted (is_active = false in services table)
    let servicePricing = servicesResult.rows.map(s => ({
      ...s,
      price: s.price / 100
    }));
    if (servicePricing.length > 0) {
      const activeServicesResult = await pool.query(
        `SELECT LOWER(name) as name FROM services WHERE is_active = true`
      );
      const activeServiceNames = new Set(activeServicesResult.rows.map(s => s.name.toLowerCase()));
      servicePricing = servicePricing.filter((p: any) => 
        activeServiceNames.has(p.name?.toLowerCase())
      );
    }

    res.json({
      success: true,
      data: {
        ...barber,
        name: barber.display_name || `${barber.first_name} ${barber.last_name}`,
        pricing: servicePricing,
      },
    });
  } catch (error) {
    logger.error('Error in getMyBarberProfile:', error);
    next(error);
  }
};

/**
 * Get barber by user ID
 * Auto-creates a barber record if the user is a barber but doesn't have one yet
 */
export const getBarberByUserId = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { userId } = req.params;

    let barberResult = await pool.query(
      `SELECT 
        b.id,
        b."userId" as user_id,
        b.bio,
        b.specialties,
        b.pricing,
        b."avgRating" as average_rating,
        b."totalReviews" as total_reviews,
        b."totalBookings" as total_bookings,
        b."isActive" as is_active,
        b."createdAt" as created_at,
        b."weeklySchedule" as weekly_schedule,
        u.email,
        u.first_name,
        u.last_name,
        u."displayName" as display_name,
        u."avatarUrl" as profile_picture_url,
        u."instagramHandle" as instagram_handle,
        u."campusId" as campus_id,
        u.role as user_type,
        c.timezone as campus_timezone
      FROM barbers b
      JOIN users u ON b."userId" = u.id
      LEFT JOIN campuses c ON u."campusId" = c.id
      WHERE b."userId" = $1`,
      [userId]
    );

    // If no barber record exists, check if this is a barber user and auto-create one
    if (barberResult.rows.length === 0) {
      // Check if user exists and is a barber
      const userResult = await pool.query(
        `SELECT id, first_name, last_name, email, "displayName" as display_name, 
                "avatarUrl" as profile_picture_url, "instagramHandle" as instagram_handle, 
                "campusId" as campus_id, role as user_type
         FROM users WHERE id = $1`,
        [userId]
      );

      if (userResult.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'User not found',
        });
      }

      const user = userResult.rows[0];

      // Only auto-create if user is a barber or campus_manager
      // Role values are uppercase in the database
      const userRole = (user.user_type || '').toUpperCase();
      logger.info(`Auto-create role check: user_type=${user.user_type}, normalized=${userRole}, campus_id=${user.campus_id}`);
      
      if (userRole !== 'BARBER' && userRole !== 'CAMPUS_MANAGER') {
        logger.warn(`User ${userId} has role ${userRole}, not allowed to auto-create barber profile`);
        return res.status(404).json({
          success: false,
          message: 'User is not a barber',
        });
      }

      // Auto-create barber record with defaults
      // Using only columns that are guaranteed to exist in the barbers table
      logger.info(`Auto-creating barber record for user ${userId}`);
      
      const defaultSchedule = {
        sunday: { enabled: false, intervals: [] },
        monday: { enabled: true, intervals: [{ id: 'default-1', start: '09:00', end: '17:00' }] },
        tuesday: { enabled: true, intervals: [{ id: 'default-2', start: '09:00', end: '17:00' }] },
        wednesday: { enabled: true, intervals: [{ id: 'default-3', start: '09:00', end: '17:00' }] },
        thursday: { enabled: true, intervals: [{ id: 'default-4', start: '09:00', end: '17:00' }] },
        friday: { enabled: true, intervals: [{ id: 'default-5', start: '09:00', end: '17:00' }] },
        saturday: { enabled: false, intervals: [] },
      };
      
      // Use upsert pattern - explicitly generate UUID for id since table lacks default
      // Include ALL required NOT NULL columns from barbers table schema
      const isCampusManager = userRole === 'CAMPUS_MANAGER';
      
      const createResult = await pool.query(
        `INSERT INTO barbers (
           id, "userId", "campusId", specialties, "isActive", "weeklySchedule",
           "currentMinPriceUsdCents", "currentMaxPriceUsdCents",
           "totalBookings", "completedBookings", "cancelledBookings", "totalReviews",
           "pricingMultiplier", "isCampusManager", "isOnboarded",
           "createdAt", "updatedAt"
         )
         VALUES (
           gen_random_uuid(), $1, $2, ARRAY[]::text[], true, $3,
           0, 0,
           0, 0, 0, 0,
           1.00, $4, false,
           NOW(), NOW()
         )
         ON CONFLICT ("userId") DO UPDATE SET 
           "isActive" = true,
           "weeklySchedule" = COALESCE(barbers."weeklySchedule", EXCLUDED."weeklySchedule"),
           "updatedAt" = NOW()
         RETURNING id, "userId" as user_id, bio, specialties, 
                   "isActive" as is_active, "createdAt" as created_at, "weeklySchedule" as weekly_schedule`,
        [
          userId,
          user.campus_id,
          JSON.stringify(defaultSchedule),
          isCampusManager
        ]
      );

      const barber = createResult.rows[0];
      
      return res.json({
        success: true,
        data: {
          ...barber,
          bio: barber.bio || '',
          average_rating: 0,
          total_reviews: 0,
          total_bookings: 0,
          email: user.email,
          first_name: user.first_name,
          last_name: user.last_name,
          display_name: user.display_name,
          profile_picture_url: user.profile_picture_url,
          instagram_handle: user.instagram_handle,
          campus_id: user.campus_id,
          name: user.display_name || `${user.first_name} ${user.last_name}`,
        },
      });
    }

    const barber = barberResult.rows[0];

    res.json({
      success: true,
      data: {
        ...barber,
        name: barber.display_name || `${barber.first_name} ${barber.last_name}`,
      },
    });
  } catch (error) {
    logger.error('Error in getBarberByUserId:', error);
    next(error);
  }
};

export const getBarberById = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;

    // Get barber from PostgreSQL
    // Column names match Prisma schema
    const barberResult = await pool.query(
      `SELECT 
        b.id,
        b."userId" as user_id,
        b.bio,
        b.specialties,
        b.pricing,
        b."avgRating" as average_rating,
        b."totalReviews" as total_reviews,
        b."totalBookings" as total_bookings,
        b."isActive" as is_active,
        b."createdAt" as created_at,
        b."weeklySchedule" as weekly_schedule,
        u."instagramHandle" as instagram_handle,
        u.email,
        u.first_name,
        u.last_name,
        u."displayName" as display_name,
        u."avatarUrl" as profile_picture_url,
        u."campusId" as campus_id
      FROM barbers b
      JOIN users u ON b."userId" = u.id
      WHERE b.id = $1`,
      [id]
    );

    if (barberResult.rows.length === 0) {
      throw new ApiError(404, 'Barber not found');
    }

    const barber = barberResult.rows[0];

    // Get services/pricing
    const servicesResult = await pool.query(
      `SELECT id, name, description, "priceUsdCents" as price, "durationMinutes" as duration_minutes
       FROM barber_services 
       WHERE "barberId" = $1 AND "isActive" = true`,
      [id]
    );

    // Get portfolio images
    const portfolioResult = await pool.query(
      `SELECT id, "imageUrl" as image_url, caption, "orderIndex" as order_index
       FROM portfolio_images 
       WHERE "barberId" = $1 
       ORDER BY "orderIndex"`,
      [id]
    );

    // Get reviews from bookings table (reviews are stored as reviewRating and reviewComment on bookings)
    const reviewsResult = await pool.query(
      `SELECT 
        b.id,
        b."reviewRating" as rating,
        b."reviewComment" as review_text,
        b."reviewedAt" as created_at,
        u.first_name,
        u.last_name,
        u."avatarUrl" as profile_picture_url,
        COALESCE(c.service_name, b."serviceType"::text) as service_name
      FROM bookings b
      JOIN users u ON b."consumerId" = u.id
      LEFT JOIN conversations c ON b.id = c.booking_id
      WHERE b."barberId" = $1 AND b."reviewRating" IS NOT NULL
      ORDER BY b."reviewedAt" DESC
      LIMIT 10`,
      [id]
    );

    // Get review stats from bookings (average and count of submitted reviews only)
    const reviewStatsResult = await pool.query(
      `SELECT 
        AVG("reviewRating")::numeric(3,2) as average_rating,
        COUNT(*) as review_count
      FROM bookings 
      WHERE "barberId" = $1 AND "reviewRating" IS NOT NULL`,
      [id]
    );
    const averageRating = parseFloat(reviewStatsResult.rows[0]?.average_rating || '0');
    const reviewCount = parseInt(reviewStatsResult.rows[0]?.review_count || '0', 10);

    // Get barber's assigned service locations
    const locationsResult = await pool.query(
      `SELECT 
        sl.id,
        sl.name,
        sl.description,
        bsl.is_primary
      FROM barber_service_locations bsl
      JOIN service_locations sl ON bsl.location_id = sl.id
      WHERE bsl.barber_id = $1 AND sl.status = 'approved' AND sl.is_active = true
      ORDER BY bsl.is_primary DESC, sl.name ASC`,
      [id]
    );

    // Use barber.pricing (from barbers table JSONB) if available, otherwise fall back to barber_services table
    const customPricing = barber.pricing || [];
    const servicePricing = servicesResult.rows.map(s => ({
      ...s,
      price: s.price / 100 // Convert cents to dollars
    }));

    // Filter out services that have been deleted (is_active = false in services table)
    let filteredPricing = customPricing.length > 0 ? customPricing : servicePricing;
    const activeServicesResult = await pool.query(
      `SELECT LOWER(name) as name FROM services WHERE is_active = true`
    );
    const activeServiceNames = new Set(activeServicesResult.rows.map(s => s.name.toLowerCase()));
    
    if (filteredPricing.length > 0) {
      filteredPricing = filteredPricing.filter((p: any) => 
        activeServiceNames.has(p.name?.toLowerCase())
      );
    }
    
    // Also filter specialties to remove deleted services
    const filteredSpecialties = Array.isArray(barber.specialties) 
      ? barber.specialties.filter((s: string) => activeServiceNames.has(s?.toLowerCase()))
      : [];

    res.json({
      success: true,
      data: {
        ...barber,
        name: barber.display_name || `${barber.first_name} ${barber.last_name}`,
        pricing: filteredPricing,
        specialties: filteredSpecialties,
        portfolio_images: portfolioResult.rows,
        reviews: reviewsResult.rows,
        service_locations: locationsResult.rows,
        average_rating: averageRating,
        review_count: reviewCount,
      },
    });
  } catch (error) {
    logger.error('Error in getBarberById:', error);
    next(error);
  }
};

export const createBarberProfile = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { bio, pricing, specialties, yearsExperience } = req.body;
    const userId = req.user!.userId;

    // Check if barber profile already exists
    const existing = await pool.query('SELECT id FROM barbers WHERE "userId" = $1', [userId]);
    
    if (existing.rows.length > 0) {
      throw new ApiError(400, 'Barber profile already exists');
    }

    // Get user details
    const userResult = await pool.query(
      `SELECT ${USER_PRIMARY_WALLET_SQL_U} AS primary_wallet, u.campus_id FROM users u WHERE u.id = $1`,
      [userId]
    );

    const user = userResult.rows[0];

    // Create barber profile in database
    const result = await pool.query(
      `INSERT INTO barbers (user_id, bio, pricing, years_experience)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [userId, bio, JSON.stringify(pricing), yearsExperience]
    );

    const barber = result.rows[0];

    const bioHash = Buffer.from(bio).toString('base64');
    const pricingHash = Buffer.from(JSON.stringify(pricing)).toString('base64');

    await suiChainService.registerBarber({
      barberAddress: user.primary_wallet,
      campusId: user.campus_id,
      specialties,
      bioHash,
      pricingHash,
    });

    logger.info(`Barber profile created: ${barber.id}`);

    res.status(201).json({
      success: true,
      data: barber,
      message: 'Barber profile created successfully',
    });
  } catch (error) {
    next(error);
  }
};

export const updateBarberProfile = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { bio, instagram_handle, display_name, specialties, yearsExperience, weekly_schedule, is_active, pricing } = req.body;
    const userId = req.user!.userId;

    // Verify ownership
    const ownership = await pool.query('SELECT id FROM barbers WHERE id = $1 AND "userId" = $2', [id, userId]);
    
    if (ownership.rows.length === 0) {
      throw new ApiError(403, 'Not authorized to update this profile');
    }

    // Build dynamic update query for barbers table
    const barberUpdateFields: string[] = [];
    const barberValues: any[] = [];
    let paramIndex = 1;

    if (bio !== undefined) {
      barberUpdateFields.push(`bio = $${paramIndex}`);
      barberValues.push(bio);
      paramIndex++;
    }
    if (specialties !== undefined) {
      barberUpdateFields.push(`specialties = $${paramIndex}`);
      barberValues.push(specialties);
      paramIndex++;
    }
    if (yearsExperience !== undefined) {
      barberUpdateFields.push(`"yearsExperience" = $${paramIndex}`);
      barberValues.push(yearsExperience);
      paramIndex++;
    }
    if (weekly_schedule !== undefined) {
      barberUpdateFields.push(`"weeklySchedule" = $${paramIndex}`);
      barberValues.push(JSON.stringify(weekly_schedule));
      paramIndex++;
    }
    if (is_active !== undefined) {
      barberUpdateFields.push(`"isActive" = $${paramIndex}`);
      barberValues.push(is_active);
      paramIndex++;
    }
    if (pricing !== undefined) {
      // Pricing is an array of {name: string, price: number} objects
      barberUpdateFields.push(`pricing = $${paramIndex}`);
      barberValues.push(JSON.stringify(pricing));
      paramIndex++;
    }

    // Update barbers table if there are fields to update
    if (barberUpdateFields.length > 0) {
      barberUpdateFields.push(`"updatedAt" = NOW()`);
      barberValues.push(id);

      await pool.query(
        `UPDATE barbers 
         SET ${barberUpdateFields.join(', ')}
         WHERE id = $${paramIndex}`,
        barberValues
      );
      
      // Emit WebSocket event if weekly_schedule was updated
      if (weekly_schedule !== undefined) {
        try {
          const io = getSocketIO();
          if (io) {
            io.to(`user-${userId}`).emit('availability-update', {
              barberId: id
            });
            logger.info(`Emitted availability-update to user-${userId} from updateBarberProfile`);
          }
        } catch (wsError: any) {
          logger.error(`Error emitting availability-update: ${wsError.message}`);
        }
      }
    }

    // Update user profile fields (display_name, instagram_handle) on users table
    const userUpdateFields: string[] = [];
    const userValues: any[] = [];
    let userParamIndex = 1;

    if (display_name !== undefined) {
      userUpdateFields.push(`"displayName" = $${userParamIndex}`);
      userValues.push(display_name);
      userParamIndex++;
    }
    if (instagram_handle !== undefined) {
      userUpdateFields.push(`"instagramHandle" = $${userParamIndex}`);
      userValues.push(instagram_handle);
      userParamIndex++;
    }

    if (userUpdateFields.length > 0) {
      userUpdateFields.push(`"updatedAt" = NOW()`);
      userValues.push(userId);

      await pool.query(
        `UPDATE users SET ${userUpdateFields.join(', ')} WHERE id = $${userParamIndex}`,
        userValues
      );
    }

    // Fetch updated barber profile
    const result = await pool.query(
      `SELECT 
        b.id,
        b."userId" as user_id,
        b.bio,
        b.specialties,
        b."avgRating" as average_rating,
        b."totalReviews" as total_reviews,
        b."totalBookings" as total_bookings,
        b."isActive" as is_active,
        u.first_name,
        u.last_name,
        u."displayName" as display_name,
        u."avatarUrl" as profile_picture_url,
        u."instagramHandle" as instagram_handle
      FROM barbers b
      JOIN users u ON b."userId" = u.id
      WHERE b.id = $1`,
      [id]
    );

    const barber = result.rows[0];

    res.json({
      success: true,
      data: {
        ...barber,
        name: barber.display_name || `${barber.first_name} ${barber.last_name}`.trim(),
      },
      message: 'Profile updated successfully',
    });
  } catch (error) {
    next(error);
  }
};

export const deleteBarberProfile = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const userId = req.user!.userId;

    const ownership = await pool.query('SELECT id FROM barbers WHERE id = $1 AND user_id = $2', [id, userId]);
    
    if (ownership.rows.length === 0) {
      throw new ApiError(403, 'Not authorized');
    }

    await pool.query('DELETE FROM barbers WHERE id = $1', [id]);

    res.json({
      success: true,
      message: 'Barber profile deleted successfully',
    });
  } catch (error) {
    next(error);
  }
};

export const getBarberPortfolio = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;

    const result = await pool.query(
      'SELECT * FROM portfolio_images WHERE barber_id = $1 ORDER BY order_index',
      [id]
    );

    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    next(error);
  }
};

export const addPortfolioImage = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { caption } = req.body;
    const userId = req.user!.userId;

    if (!req.file) {
      throw new ApiError(400, 'Image file required');
    }

    // Verify ownership
    const ownership = await pool.query('SELECT id FROM barbers WHERE id = $1 AND user_id = $2', [id, userId]);
    
    if (ownership.rows.length === 0) {
      throw new ApiError(403, 'Not authorized');
    }

    // Upload to S3
    const file = req.file as Express.Multer.File;
    const s3Result = await uploadToS3(file.buffer, `portfolio/${id}/${Date.now()}.webp`);

    if (!s3Result.success || !s3Result.url) {
      throw new ApiError(500, 'Failed to upload image');
    }

    // Get max order index
    const maxOrder = await pool.query(
      'SELECT COALESCE(MAX(order_index), -1) as max_order FROM portfolio_images WHERE barber_id = $1',
      [id]
    );

    const nextOrder = maxOrder.rows[0].max_order + 1;

    // Save to database
    const result = await pool.query(
      `INSERT INTO portfolio_images (barber_id, image_url, caption, order_index)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [id, s3Result.url, caption, nextOrder]
    );

    res.status(201).json({
      success: true,
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

export const deletePortfolioImage = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { barberId, imageId } = req.params;
    const userId = req.user!.userId;

    const ownership = await pool.query('SELECT id FROM barbers WHERE id = $1 AND user_id = $2', [barberId, userId]);
    
    if (ownership.rows.length === 0) {
      throw new ApiError(403, 'Not authorized');
    }

    await pool.query('DELETE FROM portfolio_images WHERE id = $1 AND barber_id = $2', [imageId, barberId]);

    res.json({
      success: true,
      message: 'Portfolio image deleted',
    });
  } catch (error) {
    next(error);
  }
};

export const updateAvailability = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { schedule } = req.body;
    const userId = req.user!.userId;

    const ownership = await pool.query('SELECT id FROM barbers WHERE id = $1 AND user_id = $2', [id, userId]);
    
    if (ownership.rows.length === 0) {
      throw new ApiError(403, 'Not authorized');
    }

    // Delete existing availability
    await pool.query('DELETE FROM availability_templates WHERE barber_id = $1', [id]);

    // Insert new schedule
    for (const slot of schedule) {
      await pool.query(
        `INSERT INTO availability_templates (barber_id, day_of_week, start_time, end_time)
         VALUES ($1, $2, $3, $4)`,
        [id, slot.dayOfWeek, slot.startTime, slot.endTime]
      );
    }

    // Emit WebSocket event for real-time updates
    try {
      const io = getSocketIO();
      if (io) {
        io.to(`user-${userId}`).emit('availability-update', {
          barberId: id
        });
        logger.info(`Emitted availability-update to user-${userId}`);
      }
    } catch (wsError: any) {
      logger.error(`Error emitting availability-update: ${wsError.message}`);
    }

    res.json({
      success: true,
      message: 'Availability updated successfully',
    });
  } catch (error) {
    next(error);
  }
};

// Types for availability
interface TimeInterval {
  id: string;
  start: string;
  end: string;
}

interface DayAvailability {
  enabled: boolean;
  intervals: TimeInterval[];
  // Legacy format support
  start?: string;
  end?: string;
}

interface WeeklySchedule {
  sunday?: DayAvailability;
  monday?: DayAvailability;
  tuesday?: DayAvailability;
  wednesday?: DayAvailability;
  thursday?: DayAvailability;
  friday?: DayAvailability;
  saturday?: DayAvailability;
}

// Helper to convert time string to minutes
const timeToMinutes = (time: string): number => {
  const [hours, minutes] = time.split(':').map(Number);
  return hours * 60 + minutes;
};

// Helper to convert minutes to time string
const minutesToTime = (minutes: number): string => {
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return `${hours.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}`;
};

// Generate available time slots in 15-minute increments
// currentTimeMinutes: if > 0, exclude slots before this time (for same-day bookings)
const generateTimeSlotsWithCurrentTime = (
  intervals: TimeInterval[],
  bookedSlots: { start: string; end: string }[],
  slotDuration: number = 15, // minutes
  currentTimeMinutes: number = 0 // Current time in minutes (0 = don't filter past times)
): { time: string; available: boolean }[] => {
  const slots: { time: string; available: boolean }[] = [];
  
  for (const interval of intervals) {
    const startMins = timeToMinutes(interval.start);
    const endMins = timeToMinutes(interval.end);
    
    for (let mins = startMins; mins < endMins; mins += slotDuration) {
      // Skip past times entirely - don't include them in the list
      if (currentTimeMinutes > 0 && mins < currentTimeMinutes) {
        continue;
      }
      
      const time = minutesToTime(mins);
      
      // Check if this slot overlaps with any booked slots
      let isBooked = false;
      for (const booked of bookedSlots) {
        const bookedStart = timeToMinutes(booked.start);
        const bookedEnd = timeToMinutes(booked.end);
        
        // Check for overlap
        if (mins < bookedEnd && (mins + slotDuration) > bookedStart) {
          isBooked = true;
          break;
        }
      }
      
      slots.push({ time, available: !isBooked });
    }
  }
  
  return slots;
};

export const getBarberAvailability = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { date } = req.query; // Optional: specific date to check (YYYY-MM-DD)

    // Get barber's weekly schedule and campus timezone
    const barberResult = await pool.query(
      `SELECT b."weeklySchedule" as weekly_schedule, 
              COALESCE(c.timezone, 'America/Los_Angeles') as campus_timezone
       FROM barbers b
       LEFT JOIN users u ON b."userId" = u.id
       LEFT JOIN campuses c ON u."campusId" = c.id
       WHERE b.id = $1`,
      [id]
    );

    if (barberResult.rows.length === 0) {
      throw new ApiError(404, 'Barber not found');
    }

    const weeklySchedule: WeeklySchedule = barberResult.rows[0].weekly_schedule || {};
    const campusTimezone: string = barberResult.rows[0].campus_timezone;
    
    // If a specific date is provided, return available slots for that date
    if (date && typeof date === 'string') {
      // Parse date string (YYYY-MM-DD) manually to avoid timezone issues
      // We want to get the day of week for the date as the USER sees it, not UTC
      const [year, month, day] = date.split('-').map(Number);
      // Create date at noon to avoid DST edge cases
      const targetDate = new Date(year, month - 1, day, 12, 0, 0);
      const dayNames = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const;
      const dayName = dayNames[targetDate.getDay()];
      
      console.log(`[Availability] Date: ${date}, Parsed day: ${dayName}, weeklySchedule keys:`, Object.keys(weeklySchedule));
      
      const daySchedule = weeklySchedule[dayName];
      
      console.log(`[Availability] Day schedule for ${dayName}:`, JSON.stringify(daySchedule));
      
      if (!daySchedule || !daySchedule.enabled) {
        console.log(`[Availability] Day ${dayName} is not available - enabled: ${daySchedule?.enabled}`);
        // Prevent caching
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        res.setHeader('Pragma', 'no-cache');
        res.setHeader('Expires', '0');
        return res.json({
          success: true,
          data: {
            date,
            dayOfWeek: dayName,
            available: false,
            intervals: [],
            slots: []
          }
        });
      }

      // Get intervals (support both new and legacy format)
      let intervals: TimeInterval[] = [];
      if (daySchedule.intervals && Array.isArray(daySchedule.intervals)) {
        intervals = daySchedule.intervals;
      } else if (daySchedule.start && daySchedule.end) {
        // Legacy format - single interval
        intervals = [{ id: 'legacy', start: daySchedule.start, end: daySchedule.end }];
      }
      
      console.log(`[Availability] Found ${intervals.length} intervals for ${dayName}`);

      // If no intervals defined, day is effectively unavailable
      if (intervals.length === 0) {
        console.log(`[Availability] No intervals for ${dayName}, returning unavailable`);
        // Prevent caching
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        res.setHeader('Pragma', 'no-cache');
        res.setHeader('Expires', '0');
        return res.json({
          success: true,
          data: {
            date,
            dayOfWeek: dayName,
            available: false,
            intervals: [],
            slots: []
          }
        });
      }

      // Get booked slots for this date
      // Convert UTC stored times to Pacific time for proper comparison
      // Each appointment blocks 1 hour (60 minutes) from start time
      const bookingsResult = await pool.query(
        `SELECT 
          TO_CHAR("requestedAt" AT TIME ZONE 'America/Los_Angeles', 'HH24:MI') as start_time,
          TO_CHAR("requestedAt" AT TIME ZONE 'America/Los_Angeles' + INTERVAL '60 minutes', 'HH24:MI') as end_time
        FROM bookings 
        WHERE "barberId" = $1 
          AND DATE("requestedAt" AT TIME ZONE 'America/Los_Angeles') = $2
          AND status IN ('ACCEPTED', 'PENDING', 'COMPLETED')
        ORDER BY "requestedAt"`,
        [id, date]
      );

      // Get time blocks for this specific date (one-time blocks that don't affect weekly schedule)
      const timeBlocksResult = await pool.query(
        `SELECT 
          TO_CHAR(start_time, 'HH24:MI') as start_time,
          TO_CHAR(end_time, 'HH24:MI') as end_time
        FROM barber_time_blocks 
        WHERE barber_id = $1 
          AND block_date = $2
        ORDER BY start_time`,
        [id, date]
      );

      // Get Google Calendar busy times if connected
      let googleCalendarSlots: Array<{ start: string; end: string }> = [];
      try {
        const googleCalendarService = require('../services/google-calendar.service');
        const isConnected = await googleCalendarService.isCalendarConnected(id);
        
        console.log(`[Availability] Google Calendar connected for barber ${id}:`, isConnected);
        
        if (isConnected) {
          // Create start and end of day in campus timezone
          // The date parameter is YYYY-MM-DD in campus local time
          // We construct ISO strings with the timezone and let Date parse them
          // For simplicity, we'll query a full day in UTC that covers the campus day
          const [year, month, day] = date.split('-').map(Number);
          
          // Create dates at start and end of day, accounting for potential timezone offset
          // Query a wider range to ensure we capture all events for the campus day
          const dayStartUTC = new Date(Date.UTC(year, month - 1, day, 0, 0, 0));
          const dayEndUTC = new Date(Date.UTC(year, month - 1, day + 1, 12, 0, 0)); // Go into next day to catch late events
          
          console.log(`[Availability] Querying Google Calendar for ${date} (timezone: ${campusTimezone}), UTC range: ${dayStartUTC.toISOString()} to ${dayEndUTC.toISOString()}`);
          
          const busyTimes = await googleCalendarService.getBusyTimes(id, dayStartUTC, dayEndUTC);
          
          console.log(`[Availability] Google Calendar returned ${busyTimes.length} busy times:`, busyTimes);
          
          // Convert busy times to HH:MM format in campus timezone
          googleCalendarSlots = busyTimes.map((bt: { start: Date; end: Date }) => {
            const startTime = new Date(bt.start);
            const endTime = new Date(bt.end);
            
            // Convert to campus timezone for display
            const startLocal = startTime.toLocaleString('en-US', { timeZone: campusTimezone, hour: '2-digit', minute: '2-digit', hour12: false });
            const endLocal = endTime.toLocaleString('en-US', { timeZone: campusTimezone, hour: '2-digit', minute: '2-digit', hour12: false });
            
            console.log(`[Availability] Busy time in ${campusTimezone}: ${startLocal} - ${endLocal}`);
            
            return {
              start: startLocal,
              end: endLocal
            };
          });
          
          console.log(`[Availability] Converted Google Calendar slots:`, googleCalendarSlots);
        }
      } catch (error) {
        // Google Calendar integration is optional - silently continue
        console.log('[Availability] Google Calendar check failed, continuing without:', error);
      }

      // Combine booked slots with time blocks and Google Calendar busy times
      const bookedSlots = [
        ...bookingsResult.rows.map(row => ({
          start: row.start_time,
          end: row.end_time
        })),
        ...timeBlocksResult.rows.map(row => ({
          start: row.start_time,
          end: row.end_time
        })),
        ...googleCalendarSlots
      ];

      console.log(`[Availability] Found ${bookingsResult.rows.length} booked, ${timeBlocksResult.rows.length} time blocks, ${googleCalendarSlots.length} Google Calendar for ${date}:`, bookedSlots);

      // Check if the selected date is today (to filter out past times)
      // Use the campus timezone for accurate local time
      const campusTime = new Date().toLocaleString('en-US', { timeZone: campusTimezone });
      const campusNow = new Date(campusTime);
      const todayStr = `${campusNow.getFullYear()}-${String(campusNow.getMonth() + 1).padStart(2, '0')}-${String(campusNow.getDate()).padStart(2, '0')}`;
      const isToday = date === todayStr;
      
      // Get current time in campus timezone for filtering past slots
      const currentHour = campusNow.getHours();
      const currentMinute = campusNow.getMinutes();
      const currentTimeMinutes = isToday ? (currentHour * 60 + currentMinute + 15) : 0; // 15 min buffer

      // Generate available time slots (filter past times if booking for today)
      const slots = generateTimeSlotsWithCurrentTime(intervals, bookedSlots, 15, currentTimeMinutes);
      
      console.log(`[Availability] Generated ${slots.length} slots, ${slots.filter(s => s.available).length} available`);

      // Prevent caching of availability data
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');

      return res.json({
        success: true,
        data: {
          date,
          dayOfWeek: dayName,
          available: true,
          intervals,
          bookedSlots,
          slots
        }
      });
    }

    // Return the full weekly schedule
    // Also get legacy availability_templates for backwards compatibility
    const templatesResult = await pool.query(
      'SELECT * FROM availability_templates WHERE barber_id = $1 AND is_active = TRUE ORDER BY day_of_week, start_time',
      [id]
    );

    // Prevent caching of weekly availability data to ensure fresh data on login
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');

    res.json({
      success: true,
      data: {
        weeklySchedule,
        legacyTemplates: templatesResult.rows
      }
    });
  } catch (error) {
    next(error);
  }
};

export const getBarberEarnings = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const userId = req.user!.userId;

    const ownership = await pool.query('SELECT "userId" as user_id FROM barbers WHERE id = $1', [id]);
    
    if (ownership.rows.length === 0) {
      throw new ApiError(404, 'Barber not found');
    }

    if (ownership.rows[0].user_id !== userId) {
      throw new ApiError(403, 'Not authorized');
    }

    // Get detailed earnings from payment transactions
    const earnings = await pool.query(
      `SELECT 
        SUM(barber_payout) as total_earned,
        SUM(CASE WHEN status = 'succeeded' THEN barber_payout ELSE 0 END) as paid_out,
        SUM(CASE WHEN status = 'pending' THEN barber_payout ELSE 0 END) as pending,
        COUNT(*) as total_transactions
      FROM payment_transactions
      WHERE barber_id = $1`,
      [id]
    );

    res.json({
      success: true,
      data: earnings.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

export const getBarberAnalytics = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const userId = req.user!.userId;

    const ownership = await pool.query('SELECT "userId" as user_id FROM barbers WHERE id = $1', [id]);
    
    if (ownership.rows.length === 0) {
      throw new ApiError(404, 'Barber not found');
    }

    if (ownership.rows[0].user_id !== userId) {
      throw new ApiError(403, 'Not authorized');
    }

    // Aggregate analytics data
    const analytics = await pool.query(
      `SELECT 
        COUNT(DISTINCT bm.client_id) as unique_clients,
        COUNT(*) as total_bookings,
        AVG(pt.amount) as avg_booking_value,
        SUM(pt.barber_payout) as lifetime_earnings
      FROM booking_metadata bm
      LEFT JOIN payment_transactions pt ON bm.blockchain_booking_id = pt.booking_id
      WHERE bm.barber_id = $1`,
      [id]
    );

    res.json({
      success: true,
      data: analytics.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Remove barber (demote to consumer) - Campus Manager only
 * This doesn't delete the user, just changes their role from 'barber' to 'consumer'
 */
export const removeBarber = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params; // barber ID
    const userId = req.user!.userId;
    const userRole = req.user!.role;

    // Get the barber's details including their campus
    const barberResult = await pool.query(
      `SELECT b.id, b."userId", u."campusId", u.email, u.first_name, u.last_name
       FROM barbers b
       JOIN users u ON b."userId" = u.id
       WHERE b.id = $1`,
      [id]
    );

    if (barberResult.rows.length === 0) {
      throw new ApiError(404, 'Barber not found');
    }

    const barber = barberResult.rows[0];
    const barberCampusId = barber.campusId;
    const barberUserId = barber.userId;

    // Check if requester is admin (from database) or campus manager for this barber's campus
    const adminCheck = await pool.query(
      `SELECT role FROM users WHERE id = $1`,
      [userId]
    );
    const isAdmin = adminCheck.rows[0]?.role === 'ADMIN';

    if (!isAdmin) {
      // Check if user is a campus manager for this barber's campus
      const campusManagerCheck = await pool.query(
        `SELECT b.id FROM barbers b
         WHERE b."userId" = $1 
           AND b."campusId" = $2 
           AND b."isCampusManager" = true`,
        [userId, barberCampusId]
      );

      if (campusManagerCheck.rows.length === 0) {
        throw new ApiError(403, 'Not authorized to remove barbers from this campus');
      }
    }

    // Begin transaction
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Update user role from 'BARBER' to 'CONSUMER' (database uses uppercase enum values)
      await client.query(
        `UPDATE users SET role = 'CONSUMER', "updatedAt" = CURRENT_TIMESTAMP WHERE id = $1`,
        [barberUserId]
      );

      // Deactivate the barber profile (keep it for records, but mark inactive)
      await client.query(
        `UPDATE barbers SET "isActive" = false, "updatedAt" = CURRENT_TIMESTAMP WHERE id = $1`,
        [id]
      );

      // Delete CM-barber direct conversations (conversations without a booking_id)
      // First delete messages, then the conversations
      await client.query(
        `DELETE FROM messages 
         WHERE conversation_id IN (
           SELECT id FROM conversations 
           WHERE booking_id IS NULL 
             AND (user1_id = $1 OR user2_id = $1)
         )`,
        [barberUserId]
      );
      
      await client.query(
        `DELETE FROM conversations 
         WHERE booking_id IS NULL 
           AND (user1_id = $1 OR user2_id = $1)`,
        [barberUserId]
      );

      await client.query('COMMIT');

      logger.info(`Barber ${id} (user ${barberUserId}) demoted to consumer by ${userId}`);

      res.json({
        success: true,
        message: `Barber ${barber.first_name} ${barber.last_name} has been removed and demoted to consumer`,
      });
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  } catch (error) {
    next(error);
  }
};

// =====================================================
// TIME BLOCKS - One-time date-specific availability blocks
// =====================================================

/**
 * Get barber's time blocks (optionally filtered by date range)
 */
export const getTimeBlocks = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { startDate, endDate } = req.query;
    const userId = req.user!.userId;

    // Verify the user owns this barber profile
    const barberResult = await pool.query(
      'SELECT "userId" FROM barbers WHERE id = $1',
      [id]
    );

    if (barberResult.rows.length === 0) {
      throw new ApiError(404, 'Barber not found');
    }

    if (barberResult.rows[0].userId !== userId) {
      throw new ApiError(403, 'Not authorized to view this barber\'s time blocks');
    }

    // Build query with optional date filters
    // Use TO_CHAR to ensure consistent date/time string formats
    let query = `
      SELECT id, 
        TO_CHAR(block_date, 'YYYY-MM-DD') as block_date, 
        TO_CHAR(start_time, 'HH24:MI') as start_time, 
        TO_CHAR(end_time, 'HH24:MI') as end_time, 
        reason, 
        created_at
      FROM barber_time_blocks
      WHERE barber_id = $1
    `;
    const params: any[] = [id];

    // Filter to only future blocks by default, or use provided date range
    if (startDate) {
      params.push(startDate);
      query += ` AND block_date >= $${params.length}`;
    } else {
      // Default: only show today and future blocks
      query += ` AND block_date >= CURRENT_DATE`;
    }

    if (endDate) {
      params.push(endDate);
      query += ` AND block_date <= $${params.length}`;
    }

    query += ` ORDER BY block_date, start_time`;

    const result = await pool.query(query, params);

    res.json({
      success: true,
      data: result.rows.map(row => ({
        id: row.id,
        blockDate: row.block_date,
        startTime: row.start_time,
        endTime: row.end_time,
        reason: row.reason,
        createdAt: row.created_at
      }))
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Create a new time block for a specific date
 */
export const createTimeBlock = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { blockDate, startTime, endTime, reason } = req.body;
    const userId = req.user!.userId;

    // Verify the user owns this barber profile
    const barberResult = await pool.query(
      'SELECT "userId" FROM barbers WHERE id = $1',
      [id]
    );

    if (barberResult.rows.length === 0) {
      throw new ApiError(404, 'Barber not found');
    }

    if (barberResult.rows[0].userId !== userId) {
      throw new ApiError(403, 'Not authorized to create time blocks for this barber');
    }

    // Validate that blockDate is not in the past
    // Compare date strings directly to avoid timezone issues
    // blockDate is in YYYY-MM-DD format from frontend
    const todayUTC = new Date().toISOString().split('T')[0]; // YYYY-MM-DD in UTC
    
    // Allow today and future dates (blockDate >= todayUTC would be too strict for timezone differences)
    // Instead, allow dates from yesterday UTC onwards to account for timezone differences
    const yesterdayDate = new Date();
    yesterdayDate.setDate(yesterdayDate.getDate() - 1);
    const yesterdayUTC = yesterdayDate.toISOString().split('T')[0];
    
    if (blockDate < yesterdayUTC) {
      throw new ApiError(400, 'Cannot create time blocks for past dates');
    }

    // Validate end time is after start time
    if (startTime >= endTime) {
      throw new ApiError(400, 'End time must be after start time');
    }

    // Check for overlapping blocks on the same date
    const overlapResult = await pool.query(
      `SELECT id FROM barber_time_blocks
       WHERE barber_id = $1 
         AND block_date = $2
         AND (
           (start_time < $4 AND end_time > $3) -- Overlaps
         )`,
      [id, blockDate, startTime, endTime]
    );

    if (overlapResult.rows.length > 0) {
      throw new ApiError(400, 'This time block overlaps with an existing block');
    }

    // Insert the new time block
    const insertResult = await pool.query(
      `INSERT INTO barber_time_blocks (barber_id, block_date, start_time, end_time, reason)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, 
         TO_CHAR(block_date, 'YYYY-MM-DD') as block_date, 
         TO_CHAR(start_time, 'HH24:MI') as start_time, 
         TO_CHAR(end_time, 'HH24:MI') as end_time, 
         reason, 
         created_at`,
      [id, blockDate, startTime, endTime, reason || null]
    );

    const newBlock = insertResult.rows[0];

    logger.info(`Barber ${id} created time block on ${blockDate} from ${startTime} to ${endTime}`);

    // Emit WebSocket event for real-time updates
    try {
      const io = getSocketIO();
      if (io) {
        io.to(`user-${userId}`).emit('time-block-update', {
          barberId: id,
          action: 'created',
          timeBlock: {
            id: newBlock.id,
            blockDate: newBlock.block_date,
            startTime: newBlock.start_time,
            endTime: newBlock.end_time
          }
        });
        logger.info(`Emitted time-block-update (created) to user-${userId}`);
      }
    } catch (wsError: any) {
      logger.error(`Error emitting time-block-update: ${wsError.message}`);
    }

    res.status(201).json({
      success: true,
      data: {
        id: newBlock.id,
        blockDate: newBlock.block_date,
        startTime: newBlock.start_time,
        endTime: newBlock.end_time,
        reason: newBlock.reason,
        createdAt: newBlock.created_at
      }
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Delete a time block
 */
export const deleteTimeBlock = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id, blockId } = req.params;
    const userId = req.user!.userId;

    // Verify the user owns this barber profile
    const barberResult = await pool.query(
      'SELECT "userId" FROM barbers WHERE id = $1',
      [id]
    );

    if (barberResult.rows.length === 0) {
      throw new ApiError(404, 'Barber not found');
    }

    if (barberResult.rows[0].userId !== userId) {
      throw new ApiError(403, 'Not authorized to delete time blocks for this barber');
    }

    // Delete the time block
    const deleteResult = await pool.query(
      'DELETE FROM barber_time_blocks WHERE id = $1 AND barber_id = $2 RETURNING id',
      [blockId, id]
    );

    if (deleteResult.rows.length === 0) {
      throw new ApiError(404, 'Time block not found');
    }

    logger.info(`Barber ${id} deleted time block ${blockId}`);

    // Emit WebSocket event for real-time updates
    try {
      const io = getSocketIO();
      if (io) {
        io.to(`user-${userId}`).emit('time-block-update', {
          barberId: id,
          action: 'deleted',
          blockId: blockId
        });
        logger.info(`Emitted time-block-update (deleted) to user-${userId}`);
      }
    } catch (wsError: any) {
      logger.error(`Error emitting time-block-update: ${wsError.message}`);
    }

    res.json({
      success: true,
      message: 'Time block deleted successfully'
    });
  } catch (error) {
    next(error);
  }
};

