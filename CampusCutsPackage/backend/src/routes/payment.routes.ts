/**
 * Payment Routes
 * 
 * API routes for payment processing
 */

import express from 'express';
import {
  createPaymentIntent,
  getPaymentStatus,
  cancelPayment,
  createRefund,
  getPaymentMethods,
  createBarberConnectAccount,
  getBarberAccountStatus,
  createBarberPayout,
  getBarberBalance,
  getBarberPayoutHistory,
  getBarberDashboardLink,
} from '../controllers/payment.controller';

const router = express.Router();

// Note: Auth temporarily disabled for demo
// In production: add authenticate middleware

/**
 * Student Payment Routes
 */

// POST /api/payments/create-intent
router.post('/create-intent', createPaymentIntent);

// GET /api/payments/:paymentIntentId/status
router.get('/:paymentIntentId/status', getPaymentStatus);

// POST /api/payments/:paymentIntentId/cancel
router.post('/:paymentIntentId/cancel', cancelPayment);

// POST /api/payments/:paymentIntentId/refund
router.post('/:paymentIntentId/refund', createRefund);

// GET /api/payments/customer/:customerId/payment-methods
router.get('/customer/:customerId/payment-methods', getPaymentMethods);

/**
 * Barber Payment Routes (Stripe Connect)
 */

// POST /api/payments/barber/connect
router.post('/barber/connect', createBarberConnectAccount);

// GET /api/payments/barber/:accountId/status
router.get('/barber/:accountId/status', getBarberAccountStatus);

// POST /api/payments/barber/:accountId/payout
router.post('/barber/:accountId/payout', createBarberPayout);

// GET /api/payments/barber/:accountId/balance
router.get('/barber/:accountId/balance', getBarberBalance);

// GET /api/payments/barber/:accountId/payouts
router.get('/barber/:accountId/payouts', getBarberPayoutHistory);

// GET /api/payments/barber/:accountId/dashboard-link
router.get('/barber/:accountId/dashboard-link', getBarberDashboardLink);

export default router;
