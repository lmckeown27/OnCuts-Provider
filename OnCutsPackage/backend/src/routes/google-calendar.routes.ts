/**
 * Google Calendar OAuth Routes
 * Handles the OAuth flow for connecting barber's Google Calendar
 */

import express, { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { pool } from '../database/connection';
import { logger } from '../utils/logger';
import * as googleCalendarService from '../services/google-calendar.service';

const router: Router = express.Router();

const FRONTEND_URL = process.env.FRONTEND_URL || 'https://campuscut.com';

/**
 * @route   GET /api/v1/auth/google-calendar/connect
 * @desc    Initiate Google Calendar OAuth flow
 * @access  Private (Barbers only)
 */
router.get('/connect', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).user.userId;
    
    // Verify user is a barber
    const barberCheck = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1',
      [userId]
    );
    
    if (barberCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Only barbers can connect Google Calendar' });
    }
    
    // Generate auth URL with user ID in state
    const authUrl = googleCalendarService.generateAuthUrl(userId);
    
    logger.info('Google Calendar auth URL generated', { userId });
    
    // Prevent caching - authUrl should be fresh each time
    res.set('Cache-Control', 'no-store, no-cache, must-revalidate');
    res.set('Pragma', 'no-cache');
    res.set('Expires', '0');
    
    res.json({ authUrl });
  } catch (error) {
    logger.error('Failed to generate Google Calendar auth URL:', error);
    res.status(500).json({ error: 'Failed to initiate Google Calendar connection' });
  }
});

/**
 * @route   GET /api/v1/auth/google-calendar/callback
 * @desc    Handle Google OAuth callback
 * @access  Public (redirected from Google)
 */
router.get('/callback', async (req: Request, res: Response) => {
  try {
    const { code, state, error: oauthError } = req.query;
    
    // Handle OAuth errors
    if (oauthError) {
      logger.warn('Google OAuth error:', { error: oauthError });
      return res.redirect(`${FRONTEND_URL}/web/barber?googleCalendar=error&message=${encodeURIComponent(String(oauthError))}`);
    }
    
    if (!code || !state) {
      return res.redirect(`${FRONTEND_URL}/web/barber?googleCalendar=error&message=missing_params`);
    }
    
    const barberUserId = String(state);
    
    // Exchange code for tokens and save
    const result = await googleCalendarService.handleOAuthCallback(String(code), barberUserId);
    
    if (result.success) {
      logger.info('Google Calendar connected via callback', { barberUserId });
      return res.redirect(`${FRONTEND_URL}/web/barber?googleCalendar=success`);
    } else {
      return res.redirect(`${FRONTEND_URL}/web/barber?googleCalendar=error&message=${encodeURIComponent(result.error || 'unknown')}`);
    }
  } catch (error) {
    logger.error('Google Calendar callback error:', error);
    res.redirect(`${FRONTEND_URL}/web/barber?googleCalendar=error&message=callback_failed`);
  }
});

/**
 * @route   GET /api/v1/auth/google-calendar/status
 * @desc    Check if Google Calendar is connected
 * @access  Private (Barbers only)
 */
router.get('/status', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).user.userId;
    
    const result = await pool.query(
      `SELECT b.google_calendar_connected, b.google_calendar_connected_at, b.google_calendar_sync_enabled
       FROM barbers b
       WHERE b."userId" = $1`,
      [userId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Barber profile not found' });
    }
    
    const { google_calendar_connected, google_calendar_connected_at, google_calendar_sync_enabled } = result.rows[0];
    
    res.json({
      connected: google_calendar_connected || false,
      connectedAt: google_calendar_connected_at,
      syncEnabled: google_calendar_sync_enabled ?? true,
    });
  } catch (error) {
    logger.error('Failed to get Google Calendar status:', error);
    res.status(500).json({ error: 'Failed to get calendar status' });
  }
});

/**
 * @route   DELETE /api/v1/auth/google-calendar/disconnect
 * @desc    Disconnect Google Calendar
 * @access  Private (Barbers only)
 */
router.delete('/disconnect', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).user.userId;
    
    // Get barber ID
    const barberResult = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1',
      [userId]
    );
    
    if (barberResult.rows.length === 0) {
      return res.status(404).json({ error: 'Barber profile not found' });
    }
    
    await googleCalendarService.disconnectCalendar(barberResult.rows[0].id);
    
    res.json({ success: true, message: 'Google Calendar disconnected' });
  } catch (error) {
    logger.error('Failed to disconnect Google Calendar:', error);
    res.status(500).json({ error: 'Failed to disconnect calendar' });
  }
});

/**
 * @route   PUT /api/v1/auth/google-calendar/sync-settings
 * @desc    Update sync settings (enable/disable auto-sync)
 * @access  Private (Barbers only)
 */
router.put('/sync-settings', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).user.userId;
    const { syncEnabled } = req.body;
    
    await pool.query(
      `UPDATE barbers 
       SET google_calendar_sync_enabled = $1, "updatedAt" = NOW()
       WHERE "userId" = $2`,
      [syncEnabled, userId]
    );
    
    res.json({ success: true, syncEnabled });
  } catch (error) {
    logger.error('Failed to update sync settings:', error);
    res.status(500).json({ error: 'Failed to update settings' });
  }
});

/**
 * @route   GET /api/v1/auth/google-calendar/busy-times
 * @desc    Get busy times from Google Calendar for date range
 * @access  Private (Barbers only)
 */
router.get('/busy-times', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).user.userId;
    const { startDate, endDate } = req.query;
    
    if (!startDate || !endDate) {
      return res.status(400).json({ error: 'startDate and endDate are required' });
    }
    
    // Get barber ID
    const barberResult = await pool.query(
      'SELECT id, google_calendar_connected FROM barbers WHERE "userId" = $1',
      [userId]
    );
    
    if (barberResult.rows.length === 0) {
      return res.status(404).json({ error: 'Barber profile not found' });
    }
    
    if (!barberResult.rows[0].google_calendar_connected) {
      return res.status(400).json({ error: 'Google Calendar not connected' });
    }
    
    const busyTimes = await googleCalendarService.getBusyTimes(
      barberResult.rows[0].id,
      new Date(String(startDate)),
      new Date(String(endDate))
    );
    
    res.json({ busyTimes });
  } catch (error) {
    logger.error('Failed to get busy times:', error);
    res.status(500).json({ error: 'Failed to get busy times' });
  }
});

export default router;

