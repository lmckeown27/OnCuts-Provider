/**
 * Admin Routes
 * 
 * Admin-only operations for platform management
 */

import express from 'express';
import { authenticate, refreshAccessRoleFromDb } from '../middleware/auth';
import * as adminController from '../controllers/admin.controller';

const router = express.Router();

// All routes require authentication. Role checks in controllers use `req.user.role`,
// which we refresh from the database so promoted admins aren't blocked by stale JWTs.
router.use(authenticate, refreshAccessRoleFromDb);

// Platform Fees
router.get('/fees', adminController.getPlatformFees);
router.post('/fees/withdraw', adminController.withdrawPlatformFees);

// Reconciliation
router.post('/reconciliation/run', adminController.runReconciliation);
router.get('/reconciliation/reports', adminController.getReconciliationReports);

// Withdrawal Batches
router.get('/withdrawals/batches', adminController.getWithdrawalBatches);
router.post('/withdrawals/process-batch', adminController.processBatch);

// User Management
router.get('/users/:userId/balance', adminController.getUserBalance);
router.get('/users/:userId/bookings', adminController.getUserBookings);
router.post('/users/:userId/credit', adminController.issueCredit);

// Audit Logs
router.get('/audit-logs', adminController.getAuditLogs);

// Treasury Stats
router.get('/treasury', adminController.getTreasuryStats);

// Platform Stats (total users, bookings, etc.)
router.get('/stats', adminController.getPlatformStats);

// Services Management (for campus managers and admins)
router.get('/services', adminController.getServices);
router.post('/services', adminController.createService);
router.put('/services/:id', adminController.updateService);
router.delete('/services/:id', adminController.deleteService);

// Campus Management (admin only)
router.get('/campuses', adminController.getAllCampuses);
router.get('/campuses/aggregate/performance', adminController.getAggregatePerformance);
router.get('/campuses/aggregate/metrics', adminController.getAggregateMetrics);
router.get('/campuses/:campusId/performance', adminController.getCampusPerformance);
router.get('/campuses/:campusId/metrics', adminController.getCampusMetrics);
router.get('/campuses/:campusId/barbers', adminController.getCampusBarbers);
router.post('/campuses/:campusId/manager', adminController.assignCampusManager);

// Barber Management (admin only)
router.get('/barbers', adminController.getAllBarbers);
router.get('/barbers/:barberRecordId/bookings', adminController.getBarberBookings);
router.get('/bookings/:bookingId/messages', adminController.getBookingMessages);

// User Management (admin only)
router.get('/users', adminController.getAllUsers);

export default router;

