import { Router } from 'express';
import {
  submitApplication,
  submitGuestApplication,
  getMyApplication,
  getAllApplications,
  updateApplicationStatus
} from '../controllers/barber-application.controller';
import { authenticate, requireCampusManager } from '../middleware/auth.middleware';

const router = Router();

/**
 * @route   POST /api/v1/barber-applications/guest
 * @desc    Submit a guest barber application (no authentication required)
 * @access  Public
 */
router.post('/guest', submitGuestApplication);

/**
 * @route   POST /api/v1/barber-applications
 * @desc    Submit a new barber application
 * @access  Private (authenticated users only)
 */
router.post('/', authenticate, submitApplication);

/**
 * @route   GET /api/v1/barber-applications/my-application
 * @desc    Get current user's application status
 * @access  Private (authenticated users only)
 */
router.get('/my-application', authenticate, getMyApplication);

/**
 * @route   GET /api/v1/barber-applications
 * @desc    Get all applications (admin/campus manager only)
 * @access  Private (admin or campus manager)
 */
router.get('/', authenticate, requireCampusManager, getAllApplications);

/**
 * @route   PUT /api/v1/barber-applications/:id/status
 * @desc    Update application status (admin/campus manager only)
 * @access  Private (admin or campus manager)
 */
router.put('/:id/status', authenticate, requireCampusManager, updateApplicationStatus);

export default router;

