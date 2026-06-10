import express, { Router } from 'express';
import { param, query } from 'express-validator';
import {
  getAllCampuses,
  getCampusById,
  getCampusBarbers,
  getCampusStats,
} from '../controllers/campus.controller';
import { validate } from '../middleware/validator';

const router: Router = express.Router();

/**
 * @route   GET /api/campus
 * @desc    Get all campuses
 * @access  Public
 */
router.get('/', getAllCampuses);

/**
 * @route   GET /api/campus/:id
 * @desc    Get campus by ID
 * @access  Public
 */
router.get('/:id', [param('id').isInt(), validate], getCampusById);

/**
 * @route   GET /api/campus/:id/barbers
 * @desc    Get all barbers for a campus
 * @access  Public
 */
router.get(
  '/:id/barbers',
  [
    param('id').isInt(),
    query('sortBy').optional().isIn(['rating', 'price', 'bookings']),
    validate,
  ],
  getCampusBarbers
);

/**
 * @route   GET /api/campus/:id/stats
 * @desc    Get campus statistics
 * @access  Public
 */
router.get('/:id/stats', [param('id').isInt(), validate], getCampusStats);

export default router;

