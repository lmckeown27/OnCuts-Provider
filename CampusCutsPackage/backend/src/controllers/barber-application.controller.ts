import { Request, Response, NextFunction } from 'express';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest } from '../middleware/auth.middleware';
import { sendBarberApplicationNotification, sendGuestApplicationApprovedEmail } from '../services/email.service';

/**
 * Service base prices (in dollars) - used to generate initial pricing for new barbers
 * Synced with web-app/src/config/services.ts
 */
const SERVICE_BASE_PRICES: Record<string, number> = {
  'Buzz Cut': 23,
  'Line Up': 23,
  'Beard Trim': 23,
  'Haircut': 28,
  'Taper': 28,
  'Hot Shave': 28,
  'Kids Cut': 28,
  'Fade': 35,
  'Haircut & Fade': 35,
  'Mullet': 35,
  'Design/Art': 38,
  'Afro Textures': 38,
  "Women's Cut": 40,
  'Color Treatment': 45,
  'Perm': 45,
};

/**
 * Generate pricing array from specialties using base prices
 */
function generatePricingFromSpecialties(specialties: string[]): { name: string; price: number }[] {
  return specialties.map(specialty => ({
    name: specialty,
    price: SERVICE_BASE_PRICES[specialty] || 25, // Default to $25 if not found
  }));
}

interface BarberApplicationBody {
  campusId?: string | null;
  phoneNumber: string;
  yearsExperience: string;
  hasLicense: boolean;
  licenseNumber?: string;
  specialties: string[];
  hasOwnTools: boolean;
  availableHours: string;
  whyBeBarber: string;
  portfolioDescription?: string;
  socialMedia?: string;
  additionalNotes?: string;
}

/**
 * Submit a new barber application
 * POST /api/v1/barber-applications
 */
export const submitApplication = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user?.userId;
    
    if (!userId) {
      throw new ApiError(401, 'Authentication required');
    }

    const {
      campusId: requestedCampusId,
      phoneNumber,
      yearsExperience,
      hasLicense,
      licenseNumber,
      specialties,
      hasOwnTools,
      availableHours,
      whyBeBarber,
      portfolioDescription,
      socialMedia,
      additionalNotes
    }: BarberApplicationBody = req.body;

    const rawCampusId =
      requestedCampusId != null && String(requestedCampusId).trim() !== '' ? String(requestedCampusId).trim() : '';
    let resolvedCampusId: string | null = null;
    if (rawCampusId) {
      const campusCheck = await pool.query('SELECT id, name FROM campuses WHERE id = $1', [rawCampusId]);
      if (campusCheck.rows.length === 0) {
        throw new ApiError(400, 'Invalid campus selected');
      }
      resolvedCampusId = campusCheck.rows[0].id;
    }

    // Validate required fields (campus optional — location-based clients omit it)
    if (!phoneNumber || !yearsExperience || !specialties || specialties.length === 0 || !availableHours || !whyBeBarber) {
      throw new ApiError(
        400,
        'Missing required fields: phoneNumber, yearsExperience, specialties, availableHours, and whyBeBarber are required'
      );
    }

    // Get user's role
    const userResult = await pool.query(
      'SELECT role FROM users WHERE id = $1',
      [userId]
    );

    if (userResult.rows.length === 0) {
      throw new ApiError(404, 'User not found');
    }

    const user = userResult.rows[0];
    user.campusId = resolvedCampusId;

    // Check if user is already a barber
    if (user.role === 'BARBER') {
      throw new ApiError(400, 'You are already a barber on this platform');
    }

    // Check for existing pending application
    const existingApplication = await pool.query(
      `SELECT id, status FROM barber_applications 
       WHERE user_id = $1 AND status IN ('pending', 'under_review', 'interview_scheduled')`,
      [userId]
    );

    if (existingApplication.rows.length > 0) {
      const existing = existingApplication.rows[0];
      throw new ApiError(400, `You already have a ${existing.status.replace('_', ' ')} application. Please wait for it to be processed.`);
    }

    // Insert the application
    const result = await pool.query(
      `INSERT INTO barber_applications (
        user_id, campus_id, phone_number, years_experience, has_license, license_number,
        specialties, has_own_tools, available_hours, why_be_barber,
        portfolio_description, social_media, additional_notes, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 'pending')
      RETURNING id, status, created_at`,
      [
        userId,
        resolvedCampusId,
        phoneNumber,
        yearsExperience,
        hasLicense || false,
        licenseNumber || null,
        specialties,
        hasOwnTools || false,
        availableHours,
        whyBeBarber,
        portfolioDescription || null,
        socialMedia || null,
        additionalNotes || null
      ]
    );

    const application = result.rows[0];

    logger.info(`New barber application submitted: ${application.id} by user ${userId}`);

    // Get applicant details and campus manager info for email notification
    try {
      const applicantInfo = await pool.query(
        `SELECT u.first_name, u.last_name, u.email, c.name as campus_name
         FROM users u
         LEFT JOIN campuses c ON u."campusId" = c.id
         WHERE u.id = $1`,
        [userId]
      );

      const applicant = applicantInfo.rows[0];

      // Find campus manager(s) for this campus
      // Check both: barbers with isCampusManager=true, OR users with role='CAMPUS_MANAGER' at this campus
      const campusManagers = await pool.query(
        `SELECT DISTINCT u.id, u.first_name, u.last_name, u.email
         FROM users u
         LEFT JOIN barbers b ON u.id = b."userId"
         WHERE 
           (b."campusId" = $1 AND b."isCampusManager" = true)
           OR (u."campusId" = $1 AND u.role = 'CAMPUS_MANAGER')`,
        [user.campusId]
      );

      let campusName = applicant.campus_name || 'Intera provider';
      if (user.campusId) {
        const campusInfo = await pool.query('SELECT name FROM campuses WHERE id = $1', [user.campusId]);
        if (campusInfo.rows[0]?.name) {
          campusName = campusInfo.rows[0].name;
        }
      }

      const applicationDetails = {
        applicantName: `${applicant.first_name} ${applicant.last_name}`.trim(),
        applicantEmail: applicant.email,
        applicantPhone: phoneNumber || undefined,
        campusName,
        yearsExperience,
        hasLicense: hasLicense || false,
        licenseNumber: licenseNumber || undefined,
        specialties,
        hasOwnTools: hasOwnTools || false,
        availableHours,
        whyBeBarber,
        portfolioDescription: portfolioDescription || undefined,
        socialMedia: socialMedia || undefined,
        additionalNotes: additionalNotes || undefined,
        applicationId: application.id,
        submittedAt: new Date(application.created_at).toLocaleDateString('en-US', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
          hour: 'numeric',
          minute: '2-digit'
        })
      };

      if (campusManagers.rows.length > 0) {
        // Send email to each campus manager
        for (const manager of campusManagers.rows) {
          const managerName = `${manager.first_name} ${manager.last_name}`.trim();
          
          await sendBarberApplicationNotification(
            manager.email,
            managerName,
            applicationDetails
          );
          
          logger.info(`Barber application notification sent to campus manager: ${manager.email}`);
        }
      } else {
        // No campus manager for this campus - send to all admins
        const admins = await pool.query(
          `SELECT id, first_name, last_name, email FROM users WHERE role = 'ADMIN'`
        );
        
        if (admins.rows.length > 0) {
          for (const admin of admins.rows) {
            const adminName = `${admin.first_name} ${admin.last_name}`.trim() || 'Admin';
            await sendBarberApplicationNotification(
              admin.email,
              adminName,
              applicationDetails
            );
            logger.info(`Barber application notification sent to admin: ${admin.email} (no campus manager for campus ${user.campusId})`);
          }
        } else {
          logger.warn(`No campus manager or admin found to notify for application ${application.id}`);
        }
      }
    } catch (emailError: any) {
      // Don't fail the application submission if email fails
      logger.error(`Failed to send barber application notification email:`, emailError.message);
    }

    res.status(201).json({
      success: true,
      message: 'Application submitted successfully! Our team will review it within 2-3 business days.',
      data: {
        applicationId: application.id,
        status: application.status,
        submittedAt: application.created_at
      }
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Get current user's application status
 * GET /api/v1/barber-applications/my-application
 */
export const getMyApplication = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const userId = req.user?.userId;
    
    if (!userId) {
      throw new ApiError(401, 'Authentication required');
    }

    const result = await pool.query(
      `SELECT id, status, years_experience, specialties, available_hours,
              created_at, reviewed_at, interview_scheduled_at
       FROM barber_applications 
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 1`,
      [userId]
    );

    if (result.rows.length === 0) {
      return res.json({
        success: true,
        data: null,
        message: 'No application found'
      });
    }

    res.json({
      success: true,
      data: result.rows[0]
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Get all applications (admin/campus manager only)
 * GET /api/v1/barber-applications
 * 
 * Returns both regular barber applications (from authenticated users)
 * and guest applications (from unauthenticated users via landing page)
 */
export const getAllApplications = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { status, campusId, page = 1, limit = 20 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    // Build filter conditions
    const params: any[] = [];
    let paramIndex = 1;
    let statusFilter = '';
    let campusFilter = '';

    if (status) {
      statusFilter = `status::text = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    if (campusId) {
      campusFilter = `campus_id = $${paramIndex}`;
      params.push(campusId);
      paramIndex++;
    }

    // Combined query using UNION ALL to get both regular and guest applications
    let query = `
      SELECT * FROM (
        -- Regular applications (authenticated users)
        SELECT 
          ba.id,
          ba.user_id,
          ba.status::text as status,
          ba.years_experience,
          ba.has_license,
          ba.license_number,
          ba.specialties,
          ba.has_own_tools,
          ba.available_hours,
          ba.why_be_barber,
          ba.phone_number,
          ba.social_media,
          ba.additional_notes,
          ba.created_at,
          ba.reviewed_at,
          ba.interview_scheduled_at,
          u.email,
          u.first_name,
          u.last_name,
          c.name as campus_name,
          ba.campus_id,
          'regular' as application_type
        FROM barber_applications ba
        JOIN users u ON ba.user_id = u.id
        LEFT JOIN campuses c ON ba.campus_id = c.id
        WHERE 1=1
        ${statusFilter ? `AND ba.${statusFilter}` : ''}
        ${campusFilter ? `AND ba.${campusFilter}` : ''}

        UNION ALL

        -- Guest applications (unauthenticated users from landing page)
        SELECT 
          gba.id,
          gba.linked_user_id as user_id,
          gba.status,
          gba.years_experience,
          gba.has_license,
          gba.license_number,
          gba.specialties,
          gba.has_own_tools,
          gba.available_hours,
          gba.why_be_barber,
          gba.phone_number,
          gba.social_media,
          gba.additional_notes,
          gba.created_at,
          NULL as reviewed_at,
          NULL as interview_scheduled_at,
          gba.email,
          gba.first_name,
          gba.last_name,
          c.name as campus_name,
          gba.campus_id,
          'guest' as application_type
        FROM guest_barber_applications gba
        LEFT JOIN campuses c ON gba.campus_id = c.id
        WHERE 1=1
        ${statusFilter ? `AND gba.${statusFilter}` : ''}
        ${campusFilter ? `AND gba.${campusFilter}` : ''}
      ) combined
      ORDER BY created_at DESC
      LIMIT $${paramIndex} OFFSET $${paramIndex + 1}
    `;
    params.push(Number(limit), offset);

    const result = await pool.query(query, params);

    // Get total count from both tables
    const countParams: any[] = [];
    let countIndex = 1;
    let countStatusFilter = '';
    let countCampusFilter = '';

    if (status) {
      countStatusFilter = `status::text = $${countIndex}`;
      countParams.push(status);
      countIndex++;
    }

    if (campusId) {
      countCampusFilter = `campus_id = $${countIndex}`;
      countParams.push(campusId);
    }

    const countQuery = `
      SELECT (
        (SELECT COUNT(*) FROM barber_applications ba WHERE 1=1 
          ${countStatusFilter ? `AND ba.${countStatusFilter}` : ''}
          ${countCampusFilter ? `AND ba.${countCampusFilter}` : ''})
        +
        (SELECT COUNT(*) FROM guest_barber_applications gba WHERE 1=1
          ${countStatusFilter ? `AND gba.${countStatusFilter}` : ''}
          ${countCampusFilter ? `AND gba.${countCampusFilter}` : ''})
      ) as total
    `;

    const countResult = await pool.query(countQuery, countParams);
    const total = parseInt(countResult.rows[0].total);

    res.json({
      success: true,
      data: {
        applications: result.rows,
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total,
          totalPages: Math.ceil(total / Number(limit))
        }
      }
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Update application status (admin/campus manager only)
 * PATCH /api/v1/barber-applications/:id/status
 * 
 * Handles both regular applications (barber_applications table)
 * and guest applications (guest_barber_applications table)
 */
export const updateApplicationStatus = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { status, reviewNotes, interviewScheduledAt } = req.body;
    const reviewerId = req.user?.userId;

    const validStatuses = ['pending', 'under_review', 'interview_scheduled', 'approved', 'rejected'];
    if (!validStatuses.includes(status)) {
      throw new ApiError(400, `Invalid status. Must be one of: ${validStatuses.join(', ')}`);
    }

    // First check regular barber_applications table
    let existing = await pool.query(
      'SELECT id, user_id, status, campus_id, specialties FROM barber_applications WHERE id = $1',
      [id]
    );
    let isGuestApplication = false;

    // If not found in regular table, check guest_barber_applications
    if (existing.rows.length === 0) {
      existing = await pool.query(
        'SELECT id, linked_user_id as user_id, email, status, campus_id, specialties FROM guest_barber_applications WHERE id = $1',
        [id]
      );
      if (existing.rows.length === 0) {
        throw new ApiError(404, 'Application not found');
      }
      isGuestApplication = true;
    }

    const applicationData = existing.rows[0];
    let updatedApplication;

    if (isGuestApplication) {
      // Update guest application
      const result = await pool.query(
        `UPDATE guest_barber_applications 
         SET status = $1, 
             updated_at = NOW()
         WHERE id = $2
         RETURNING *`,
        [status, id]
      );
      updatedApplication = result.rows[0];

      // For guest applications being approved:
      // - If user with this email already exists, promote them to barber
      // - If user doesn't exist yet, send them an email to create an account
      // The user will be auto-promoted when they sign up (handled in auth.controller.ts)
      if (status === 'approved') {
        const existingUser = await pool.query(
          'SELECT id FROM users WHERE email = $1',
          [applicationData.email.toLowerCase()]
        );

        if (existingUser.rows.length > 0) {
          // User exists - promote them to barber now
          const userId = existingUser.rows[0].id;
          await pool.query(
            `UPDATE users SET role = 'BARBER', "updatedAt" = NOW() WHERE id = $1`,
            [userId]
          );

          // Link the guest application to the user
          await pool.query(
            'UPDATE guest_barber_applications SET linked_user_id = $1 WHERE id = $2',
            [userId, id]
          );

          // Create barber profile
          const specialties = applicationData.specialties || [];
          const pricing = generatePricingFromSpecialties(specialties);

          await pool.query(
            `INSERT INTO barbers (
               id, "userId", "campusId", specialties, pricing, "isActive", "weeklySchedule",
               "currentMinPriceUsdCents", "currentMaxPriceUsdCents",
               "totalBookings", "completedBookings", "cancelledBookings", "totalReviews",
               "pricingMultiplier", "isCampusManager", "isOnboarded",
               "createdAt", "updatedAt"
             )
             VALUES (
               gen_random_uuid(), $1, $2, $3, $4, true, '{}',
               0, 0,
               0, 0, 0, 0,
               1.00, false, false,
               NOW(), NOW()
             )
             ON CONFLICT ("userId") DO UPDATE SET 
               specialties = EXCLUDED.specialties,
               pricing = EXCLUDED.pricing,
               "isActive" = true,
               "campusId" = EXCLUDED."campusId",
               "updatedAt" = NOW()`,
            [userId, applicationData.campus_id, specialties, JSON.stringify(pricing)]
          );

          logger.info(`Existing user ${applicationData.email} promoted to BARBER after guest application ${id} approved`);
        } else {
          // User doesn't exist yet - send them an email to create an account
          // They will be auto-promoted when they sign up with this email
          const campusInfo = await pool.query('SELECT name FROM campuses WHERE id = $1', [applicationData.campus_id]);
          const campusName = campusInfo.rows[0]?.name || 'your campus';

          try {
            await sendGuestApplicationApprovedEmail(
              applicationData.email,
              updatedApplication.first_name || 'Applicant',
              campusName
            );
            logger.info(`Approval email sent to guest applicant: ${applicationData.email}`);
          } catch (emailError: any) {
            logger.error(`Failed to send approval email to ${applicationData.email}:`, emailError.message);
          }

          logger.info(`Guest application ${id} approved. User ${applicationData.email} must create an account to become a barber.`);
        }
      }
    } else {
      // Update regular application
      const result = await pool.query(
        `UPDATE barber_applications 
         SET status = $1, 
             reviewed_by = $2, 
             reviewed_at = NOW(),
             review_notes = COALESCE($3, review_notes),
             interview_scheduled_at = $4,
             updated_at = NOW()
         WHERE id = $5
         RETURNING *`,
        [status, reviewerId, reviewNotes || null, interviewScheduledAt || null, id]
      );
      updatedApplication = result.rows[0];

      // If approved, update user role to BARBER
      if (status === 'approved') {
        await pool.query(
          `UPDATE users SET role = 'BARBER', "updatedAt" = NOW() WHERE id = $1`,
          [updatedApplication.user_id]
        );

        const specialties = applicationData.specialties || [];
        const pricing = generatePricingFromSpecialties(specialties);

        await pool.query(
          `INSERT INTO barbers (
             id, "userId", "campusId", specialties, pricing, "isActive", "weeklySchedule",
             "currentMinPriceUsdCents", "currentMaxPriceUsdCents",
             "totalBookings", "completedBookings", "cancelledBookings", "totalReviews",
             "pricingMultiplier", "isCampusManager", "isOnboarded",
             "createdAt", "updatedAt"
           )
           VALUES (
             gen_random_uuid(), $1, $2, $3, $4, true, '{}',
             0, 0,
             0, 0, 0, 0,
             1.00, false, false,
             NOW(), NOW()
           )
           ON CONFLICT ("userId") DO UPDATE SET 
             specialties = EXCLUDED.specialties,
             pricing = EXCLUDED.pricing,
             "isActive" = true,
             "campusId" = EXCLUDED."campusId",
             "updatedAt" = NOW()`,
          [updatedApplication.user_id, updatedApplication.campus_id, specialties, JSON.stringify(pricing)]
        );

        logger.info(`User ${updatedApplication.user_id} promoted to BARBER after application ${id} approved`);
      }
    }

    logger.info(`Barber application ${id} status updated to ${status} by ${reviewerId}`);

    res.json({
      success: true,
      message: `Application ${status === 'approved' ? 'approved! User has been promoted to barber.' : 'updated successfully.'}`,
      data: updatedApplication
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Guest Barber Application Body Interface
 */
interface GuestBarberApplicationBody extends BarberApplicationBody {
  firstName: string;
  lastName: string;
  email: string;
}

/**
 * Submit a guest barber application (no authentication required)
 * POST /api/v1/barber-applications/guest
 * 
 * This allows users to apply to become a barber before creating an account.
 * The application is stored with their email and can be linked when they sign up.
 */
export const submitGuestApplication = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const {
      email,
      firstName,
      lastName,
      phoneNumber,
      campusId,
      yearsExperience,
      hasLicense,
      licenseNumber,
      specialties,
      hasOwnTools,
      availableHours,
      whyBeBarber,
      portfolioDescription,
      socialMedia,
      additionalNotes
    }: GuestBarberApplicationBody = req.body;

    // Validate required fields
    if (!firstName || !firstName.trim()) {
      throw new ApiError(400, 'First name is required');
    }

    if (!lastName || !lastName.trim()) {
      throw new ApiError(400, 'Last name is required');
    }

    if (!email) {
      throw new ApiError(400, 'Email address is required');
    }

    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      throw new ApiError(400, 'Please enter a valid email address');
    }

    if (!phoneNumber || !phoneNumber.trim()) {
      throw new ApiError(400, 'Phone number is required');
    }

    if (!campusId || !yearsExperience || !specialties || specialties.length === 0 || !availableHours || !whyBeBarber) {
      throw new ApiError(400, 'Missing required fields: campusId, yearsExperience, specialties, availableHours, and whyBeBarber are required');
    }

    // Verify the campus exists
    const campusCheck = await pool.query('SELECT id, name FROM campuses WHERE id = $1', [campusId]);
    if (campusCheck.rows.length === 0) {
      throw new ApiError(400, 'Invalid campus selected');
    }

    const campusName = campusCheck.rows[0].name;

    // Check if email already has a user account
    const existingUser = await pool.query('SELECT id, role FROM users WHERE email = $1', [email.toLowerCase()]);
    
    if (existingUser.rows.length > 0) {
      const user = existingUser.rows[0];
      if (user.role === 'BARBER') {
        throw new ApiError(400, 'This email is already registered as a barber. Please sign in instead.');
      }
      // If user exists but isn't a barber, suggest they sign in to apply
      throw new ApiError(400, 'This email is already registered. Please sign in to complete your barber application.');
    }

    // Check for existing guest application with this email
    const existingGuestApp = await pool.query(
      `SELECT id, status FROM guest_barber_applications 
       WHERE email = $1 AND status IN ('pending', 'under_review')`,
      [email.toLowerCase()]
    );

    if (existingGuestApp.rows.length > 0) {
      throw new ApiError(400, 'You already have a pending application with this email. Please wait for it to be reviewed or sign up to check your status.');
    }

    // Ensure the guest_barber_applications table exists with phone_number column
    await pool.query(`
      CREATE TABLE IF NOT EXISTS guest_barber_applications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email VARCHAR(255) NOT NULL,
        first_name VARCHAR(100),
        last_name VARCHAR(100),
        phone_number VARCHAR(50),
        campus_id UUID NOT NULL REFERENCES campuses(id),
        years_experience VARCHAR(50) NOT NULL,
        has_license BOOLEAN DEFAULT FALSE,
        license_number VARCHAR(100),
        specialties TEXT[] NOT NULL,
        has_own_tools BOOLEAN DEFAULT TRUE,
        available_hours TEXT NOT NULL,
        why_be_barber TEXT NOT NULL,
        portfolio_description TEXT,
        social_media TEXT,
        additional_notes TEXT,
        status VARCHAR(50) DEFAULT 'pending',
        linked_user_id UUID REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    // Add phone_number column if it doesn't exist (for existing tables)
    await pool.query(`
      ALTER TABLE guest_barber_applications 
      ADD COLUMN IF NOT EXISTS phone_number VARCHAR(50)
    `);

    // Insert the guest application
    const result = await pool.query(
      `INSERT INTO guest_barber_applications (
        email, first_name, last_name, phone_number, campus_id, years_experience, has_license, license_number,
        specialties, has_own_tools, available_hours, why_be_barber,
        portfolio_description, social_media, additional_notes, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, 'pending')
      RETURNING id, status, created_at`,
      [
        email.toLowerCase(),
        firstName || null,
        lastName || null,
        phoneNumber || null,
        campusId,
        yearsExperience,
        hasLicense || false,
        licenseNumber || null,
        specialties,
        hasOwnTools !== false, // Default to true
        availableHours,
        whyBeBarber,
        portfolioDescription || null,
        socialMedia || null,
        additionalNotes || null
      ]
    );

    const application = result.rows[0];

    logger.info(`New guest barber application submitted: ${application.id} from ${email}`);

    // Send notification email to campus manager(s)
    try {
      // Check both: barbers with isCampusManager=true, OR users with role='CAMPUS_MANAGER' at this campus
      const campusManagers = await pool.query(
        `SELECT DISTINCT u.id, u.first_name, u.last_name, u.email
         FROM users u
         LEFT JOIN barbers b ON u.id = b."userId"
         WHERE 
           (b."campusId" = $1 AND b."isCampusManager" = true)
           OR (u."campusId" = $1 AND u.role = 'CAMPUS_MANAGER')`,
        [campusId]
      );

      const applicantName = firstName && lastName 
        ? `${firstName} ${lastName}`.trim() 
        : email.split('@')[0]; // Use email prefix as fallback name

      const applicationDetails = {
        applicantName,
        applicantEmail: email,
        applicantPhone: phoneNumber || undefined,
        campusName,
        yearsExperience,
        hasLicense: hasLicense || false,
        licenseNumber: licenseNumber || undefined,
        specialties,
        hasOwnTools: hasOwnTools !== false,
        availableHours,
        whyBeBarber,
        portfolioDescription: portfolioDescription || undefined,
        socialMedia: socialMedia || undefined,
        additionalNotes: additionalNotes || undefined,
        applicationId: application.id,
        submittedAt: new Date(application.created_at).toLocaleDateString('en-US', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
          hour: 'numeric',
          minute: '2-digit'
        })
      };

      if (campusManagers.rows.length > 0) {
        for (const manager of campusManagers.rows) {
          const managerName = `${manager.first_name} ${manager.last_name}`.trim();
          await sendBarberApplicationNotification(
            manager.email,
            managerName,
            applicationDetails
          );
          logger.info(`Guest barber application notification sent to campus manager: ${manager.email}`);
        }
      } else {
        // No campus manager - send to all admins
        const admins = await pool.query(
          `SELECT id, first_name, last_name, email FROM users WHERE role = 'ADMIN'`
        );
        
        if (admins.rows.length > 0) {
          for (const admin of admins.rows) {
            const adminName = `${admin.first_name} ${admin.last_name}`.trim() || 'Admin';
            await sendBarberApplicationNotification(
              admin.email,
              adminName,
              applicationDetails
            );
            logger.info(`Guest barber application notification sent to admin: ${admin.email} (no campus manager)`);
          }
        } else {
          logger.warn(`No campus manager or admin found to notify for guest application ${application.id}`);
        }
      }
    } catch (emailError: any) {
      logger.error(`Failed to send guest application notification email:`, emailError.message);
    }

    res.status(201).json({
      success: true,
      message: 'Application submitted successfully! We\'ll review your application and contact you at the email address provided.',
      data: {
        id: application.id,
        email,
        status: application.status,
        createdAt: application.created_at
      }
    });
  } catch (error) {
    next(error);
  }
};

