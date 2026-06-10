import express, { Router } from 'express';
import { body, param, query } from 'express-validator';
import {
  getAllBarbers,
  getBarberById,
  getBarberByUserId,
  getMyBarberProfile,
  createBarberProfile,
  updateBarberProfile,
  deleteBarberProfile,
  removeBarber,
  getBarberPortfolio,
  addPortfolioImage,
  deletePortfolioImage,
  updateAvailability,
  getBarberAvailability,
  getBarberEarnings,
  getBarberAnalytics,
} from '../controllers/barber.controller';
import { authenticate, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validator';
import { upload } from '../middleware/upload';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';

const router: Router = express.Router();

/**
 * @route   GET /api/barbers
 * @desc    Get all barbers (with filters)
 * @access  Public
 */
router.get(
  '/',
  [
    query('campusId').optional().isString(), // Accept UUID or slug
    query('minRating').optional().isFloat({ min: 0, max: 5 }),
    query('maxPrice').optional().isInt(),
    query('specialty').optional().isString(),
    validate,
  ],
  getAllBarbers
);

/**
 * @route   GET /api/barbers/me
 * @desc    Get current user's barber profile
 * @access  Private (Barbers only)
 */
router.get('/me', authenticate, getMyBarberProfile);

/**
 * @route   GET /api/barbers/user/:userId
 * @desc    Get barber by user ID
 * @access  Public
 */
router.get('/user/:userId', getBarberByUserId);

/**
 * @route   GET /api/barbers/available-at-time
 * @desc    Get barbers available at a specific date/time (for rebooking after cancellation)
 * @access  Public
 */
router.get(
  '/available-at-time',
  async (req, res, next) => {
    try {
      const { campusId, date, time, serviceType, excludeBarberId } = req.query;
      
      if (!campusId || !date || !time) {
        return res.status(400).json({ 
          success: false, 
          error: 'campusId, date (YYYY-MM-DD), and time (HH:MM) are required' 
        });
      }
      
      logger.info(`[available-at-time] Searching for barbers at campus ${campusId} on ${date} at ${time}`);
      
      // Parse the requested time
      const [requestedHour, requestedMin] = (time as string).split(':').map(Number);
      const requestedTimeInMinutes = requestedHour * 60 + requestedMin;
      
      // Parse date to get day of week
      const [year, month, day] = (date as string).split('-').map(Number);
      const targetDate = new Date(year, month - 1, day, 12, 0, 0);
      const dayNames = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
      const dayName = dayNames[targetDate.getDay()];
      
      logger.info(`[available-at-time] Day: ${dayName}, Time: ${requestedTimeInMinutes} minutes`);
      
      // Get all active barbers at this campus
      const barbersResult = await pool.query(`
        SELECT 
          b.id,
          COALESCE(u."displayName", u.first_name || ' ' || u.last_name) as name,
          u."avatarUrl" as avatar,
          b."weeklySchedule" as weekly_schedule,
          b.pricing as services,
          (SELECT AVG(r.rating)::numeric(3,2) FROM reviews r WHERE r."barberId" = b.id) as average_rating,
          (SELECT COUNT(*) FROM reviews r WHERE r."barberId" = b.id) as total_reviews
        FROM barbers b
        JOIN users u ON b."userId" = u.id
        WHERE b."campusId" = $1
          AND b."isActive" = true
          ${excludeBarberId ? `AND b.id != $2` : ''}
      `, excludeBarberId ? [campusId, excludeBarberId] : [campusId]);
      
      logger.info(`[available-at-time] Found ${barbersResult.rows.length} barbers at campus`);
      
      const availableBarbers = [];
      
      for (const barber of barbersResult.rows) {
        // Check if barber offers the service (if serviceType provided)
        if (serviceType) {
          const serviceTypeUpper = (serviceType as string).toUpperCase().replace(/_/g, ' ').replace(/AND/g, '&');
          const offersService = (barber.services || []).some((s: any) => {
            const serviceName = (s.name || s.type || s.service_type || '').toUpperCase().replace(/_/g, ' ').replace(/AND/g, '&');
            return serviceName === serviceTypeUpper || 
                   serviceName.includes(serviceTypeUpper) || 
                   serviceTypeUpper.includes(serviceName);
          });
          
          if (!offersService) {
            logger.info(`[available-at-time] ${barber.name} does not offer ${serviceType}`);
            continue;
          }
        }
        
        // Check weekly schedule for this day
        const weeklySchedule = barber.weekly_schedule || {};
        const daySchedule = weeklySchedule[dayName];
        
        if (!daySchedule || !daySchedule.enabled) {
          logger.info(`[available-at-time] ${barber.name} not available on ${dayName}`);
          continue;
        }
        
        // Get intervals
        let intervals: { start: string; end: string }[] = [];
        if (daySchedule.intervals && Array.isArray(daySchedule.intervals)) {
          intervals = daySchedule.intervals;
        } else if (daySchedule.start && daySchedule.end) {
          intervals = [{ start: daySchedule.start, end: daySchedule.end }];
        }
        
        if (intervals.length === 0) {
          logger.info(`[available-at-time] ${barber.name} has no intervals on ${dayName}`);
          continue;
        }
        
        // Check if requested time falls within any interval
        let inSchedule = false;
        for (const interval of intervals) {
          const [startHour, startMin] = interval.start.split(':').map(Number);
          const [endHour, endMin] = interval.end.split(':').map(Number);
          const startMinutes = startHour * 60 + startMin;
          const endMinutes = endHour * 60 + endMin;
          
          if (requestedTimeInMinutes >= startMinutes && requestedTimeInMinutes < endMinutes) {
            inSchedule = true;
            break;
          }
        }
        
        if (!inSchedule) {
          logger.info(`[available-at-time] ${barber.name} - ${time} not within schedule intervals`);
          continue;
        }
        
        // Check for existing bookings or time blocks at this time
        const conflictsResult = await pool.query(`
          SELECT 1 FROM bookings 
          WHERE "barberId" = $1 
            AND DATE("requestedAt" AT TIME ZONE 'America/Los_Angeles') = $2
            AND EXTRACT(HOUR FROM "requestedAt" AT TIME ZONE 'America/Los_Angeles') * 60 + 
                EXTRACT(MINUTE FROM "requestedAt" AT TIME ZONE 'America/Los_Angeles') <= $3
            AND EXTRACT(HOUR FROM "requestedAt" AT TIME ZONE 'America/Los_Angeles') * 60 + 
                EXTRACT(MINUTE FROM "requestedAt" AT TIME ZONE 'America/Los_Angeles') + 60 > $3
            AND status IN ('ACCEPTED', 'PENDING', 'COMPLETED')
          UNION ALL
          SELECT 1 FROM barber_time_blocks
          WHERE barber_id = $1
            AND block_date = $2
            AND EXTRACT(HOUR FROM start_time) * 60 + EXTRACT(MINUTE FROM start_time) <= $3
            AND EXTRACT(HOUR FROM end_time) * 60 + EXTRACT(MINUTE FROM end_time) > $3
        `, [barber.id, date, requestedTimeInMinutes]);
        
        if (conflictsResult.rows.length > 0) {
          logger.info(`[available-at-time] ${barber.name} has conflict at ${time}`);
          continue;
        }
        
        logger.info(`[available-at-time] ${barber.name} IS AVAILABLE at ${time}`);
        availableBarbers.push({
          id: barber.id,
          name: barber.name,
          avatar: barber.avatar,
          average_rating: parseFloat(barber.average_rating) || null,
          total_reviews: parseInt(barber.total_reviews) || 0,
        });
      }
      
      logger.info(`[available-at-time] Total available: ${availableBarbers.length}`);
      
      res.json({
        success: true,
        data: {
          barbers: availableBarbers,
          date,
          time,
          campusId,
        }
      });
    } catch (error: any) {
      console.error('Error in available-at-time:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  }
);

/**
 * @route   GET /api/barbers/:id
 * @desc    Get barber by ID
 * @access  Public
 */
router.get('/:id', getBarberById); // Removed UUID validation for demo

/**
 * @route   POST /api/barbers
 * @desc    Create barber profile
 * @access  Private (Barbers only)
 */
router.post(
  '/',
  authenticate,
  requireRole('barber'),
  [
    body('bio').notEmpty().withMessage('Bio required'),
    body('pricing').isObject().withMessage('Pricing object required'),
    body('specialties').isArray().withMessage('Specialties array required'),
    body('yearsExperience').optional().isInt(),
    validate,
  ],
  createBarberProfile
);

/**
 * @route   PUT /api/barbers/:id
 * @desc    Update barber profile
 * @access  Private (Owner only)
 */
router.put(
  '/:id',
  authenticate,
  [param('id').isUUID(), validate],
  updateBarberProfile
);

/**
 * @route   DELETE /api/barbers/:id
 * @desc    Delete barber profile
 * @access  Private (Owner only)
 */
router.delete(
  '/:id',
  authenticate,
  requireRole('barber'),
  [param('id').isUUID(), validate],
  deleteBarberProfile
);

/**
 * @route   POST /api/barbers/:id/remove
 * @desc    Remove barber (demote to consumer) - Campus Manager only
 * @access  Private (Campus Manager or Admin)
 */
router.post(
  '/:id/remove',
  authenticate,
  [param('id').isUUID(), validate],
  removeBarber
);

/**
 * @route   GET /api/barbers/:id/portfolio
 * @desc    Get barber portfolio images
 * @access  Public
 */
router.get('/:id/portfolio', [param('id').isUUID(), validate], getBarberPortfolio);

/**
 * @route   POST /api/barbers/:id/portfolio
 * @desc    Add portfolio image
 * @access  Private (Owner only)
 */
router.post(
  '/:id/portfolio',
  authenticate,
  requireRole('barber'),
  upload.single('image'),
  [param('id').isUUID(), body('caption').optional().isString(), validate],
  addPortfolioImage
);

/**
 * @route   DELETE /api/barbers/:barberId/portfolio/:imageId
 * @desc    Delete portfolio image
 * @access  Private (Owner only)
 */
router.delete(
  '/:barberId/portfolio/:imageId',
  authenticate,
  requireRole('barber'),
  [param('barberId').isUUID(), param('imageId').isUUID(), validate],
  deletePortfolioImage
);

/**
 * @route   PUT /api/barbers/:id/availability
 * @desc    Update availability schedule
 * @access  Private (Owner only)
 */
router.put(
  '/:id/availability',
  authenticate,
  requireRole('barber'),
  [param('id').isUUID(), body('schedule').isArray(), validate],
  updateAvailability
);

/**
 * @route   GET /api/barbers/:id/availability
 * @desc    Get barber availability
 * @access  Public
 */
router.get(
  '/:id/availability',
  [param('id').isUUID(), query('date').optional().isISO8601(), validate],
  getBarberAvailability
);

/**
 * @route   GET /api/barbers/:id/earnings
 * @desc    Get barber earnings summary
 * @access  Private (Owner only)
 */
router.get(
  '/:id/earnings',
  authenticate,
  requireRole('barber'),
  [param('id').isUUID(), validate],
  getBarberEarnings
);

/**
 * @route   GET /api/barbers/:id/analytics
 * @desc    Get barber analytics dashboard
 * @access  Private (Owner only)
 */
router.get(
  '/:id/analytics',
  authenticate,
  requireRole('barber'),
  [param('id').isUUID(), validate],
  getBarberAnalytics
);

// =====================================================
// TIME BLOCKS - One-time date-specific availability blocks
// =====================================================

import {
  getTimeBlocks,
  createTimeBlock,
  deleteTimeBlock
} from '../controllers/barber.controller';

/**
 * @route   GET /api/barbers/:id/time-blocks
 * @desc    Get barber's time blocks (optionally filtered by date range)
 * @access  Private (Owner only)
 */
router.get(
  '/:id/time-blocks',
  authenticate,
  requireRole('barber'),
  [
    param('id').isUUID(),
    query('startDate').optional().isISO8601(),
    query('endDate').optional().isISO8601(),
    validate
  ],
  getTimeBlocks
);

/**
 * @route   POST /api/barbers/:id/time-blocks
 * @desc    Create a new time block for a specific date
 * @access  Private (Owner only)
 */
router.post(
  '/:id/time-blocks',
  authenticate,
  requireRole('barber'),
  [
    param('id').isUUID(),
    body('blockDate').isISO8601().withMessage('Valid date required (YYYY-MM-DD)'),
    body('startTime').matches(/^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/).withMessage('Valid start time required (HH:MM)'),
    body('endTime').matches(/^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/).withMessage('Valid end time required (HH:MM)'),
    body('reason').optional().isString().isLength({ max: 255 }),
    validate
  ],
  createTimeBlock
);

/**
 * @route   DELETE /api/barbers/:id/time-blocks/:blockId
 * @desc    Delete a time block
 * @access  Private (Owner only)
 */
router.delete(
  '/:id/time-blocks/:blockId',
  authenticate,
  requireRole('barber'),
  [
    param('id').isUUID(),
    param('blockId').isUUID(),
    validate
  ],
  deleteTimeBlock
);

export default router;

