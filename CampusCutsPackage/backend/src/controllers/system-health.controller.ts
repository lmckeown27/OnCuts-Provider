/**
 * System Health Controller
 * 
 * Provides system status information for admin monitoring
 * Monitors PostgreSQL database connectivity and performance
 */

import { Request, Response } from 'express';
import { isAnyStripeSecretKeyConfigured } from '../config/stripe';
import { resolveAppNetworkModeFromEnv } from '../config/app-network';
import { logger } from '../utils/logger';
import { checkHealth as checkPostgresHealth, pool } from '../database/connection';

interface ServiceStatus {
  name: string;
  status: 'operational' | 'degraded' | 'down';
  responseTime?: number;
  message?: string;
  lastChecked: string;
}

interface SystemMetrics {
  uptime: number;
  memoryUsage: {
    used: number;
    total: number;
    percentage: number;
  };
  activeConnections: number;
  totalRequests?: number;
}

/**
 * GET /api/system/health
 * Get comprehensive system health status
 */
export async function getSystemHealth(req: Request, res: Response) {
  try {
    const startTime = Date.now();
    
    // Check PostgreSQL connection
    const postgresHealth = await checkPostgresHealth();
    const postgresResponseTime = Date.now() - startTime;
    const isPostgresHealthy = typeof postgresHealth === 'object' && postgresHealth.healthy === true;

    // Get memory usage
    const memUsage = process.memoryUsage();
    const totalMemory = require('os').totalmem();
    
    // Build response
    res.json({
      status: isPostgresHealthy ? 'operational' : 'degraded',
      services: {
        database: {
          name: 'PostgreSQL',
          status: isPostgresHealthy ? 'operational' : 'down',
          responseTime: postgresResponseTime,
          message: isPostgresHealthy 
            ? 'Database connected and responding' 
            : 'Database connection failed',
          lastChecked: new Date().toISOString(),
          details: isPostgresHealthy ? {
            pool: {
              total: pool.totalCount,
              idle: pool.idleCount,
              waiting: pool.waitingCount,
            }
          } : null,
        },
        api: {
          name: 'API Server',
          status: 'operational',
          responseTime: 1,
          message: 'API server is running',
          lastChecked: new Date().toISOString(),
        },
        stripe: {
          name: 'Stripe Payments',
          status: isAnyStripeSecretKeyConfigured() ? 'operational' : 'not_configured',
          message: isAnyStripeSecretKeyConfigured()
            ? 'Payment processing available'
            : 'Stripe not configured',
          lastChecked: new Date().toISOString(),
          app_network_mode: resolveAppNetworkModeFromEnv(),
        },
        email: {
          name: 'Email Service',
          status: process.env.SMTP_HOST ? 'operational' : 'not_configured',
          message: process.env.SMTP_HOST 
            ? 'Email service configured' 
            : 'Email service not configured',
          lastChecked: new Date().toISOString(),
        },
      },
      metrics: {
        uptime: Math.floor(process.uptime()),
        memoryUsage: {
          used: Math.round(memUsage.heapUsed / 1024 / 1024),
          total: Math.round(memUsage.heapTotal / 1024 / 1024),
          percentage: Math.round((memUsage.heapUsed / memUsage.heapTotal) * 100),
        },
        activeConnections: pool.totalCount - pool.idleCount,
        nodeVersion: process.version,
        environment: process.env.NODE_ENV || 'development',
        app_network_mode: resolveAppNetworkModeFromEnv(),
        sui_rpc_configured: Boolean(process.env.SUI_RPC_URL?.trim()),
      },
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error('System health check error:', error);
    res.status(500).json({
      status: 'error',
      error: 'Failed to check system health',
      timestamp: new Date().toISOString(),
    });
  }
}

/**
 * GET /api/system/database-status
 * Detailed database status and metrics
 */
export async function getDatabaseStatus(req: Request, res: Response) {
  try {
    const startTime = Date.now();
    const postgresHealth = await checkPostgresHealth();
    const responseTime = Date.now() - startTime;
    const isPostgresHealthy = typeof postgresHealth === 'object' && postgresHealth.healthy === true;

    // Get table counts if connected
    let tableCounts = null;
    if (isPostgresHealthy) {
      try {
        const result = await pool.query(`
          SELECT 
            (SELECT COUNT(*) FROM users) as users,
            (SELECT COUNT(*) FROM bookings) as bookings,
            (SELECT COUNT(*) FROM campuses) as campuses,
            (SELECT COUNT(*) FROM reviews) as reviews
        `);
        tableCounts = result.rows[0];
      } catch (e) {
        // Table counts are optional
        logger.warn('Could not get table counts:', e);
      }
    }

    res.json({
      database: {
        type: 'PostgreSQL',
        status: isPostgresHealthy ? 'connected' : 'disconnected',
        healthy: isPostgresHealthy,
        responseTime: `${responseTime}ms`,
        connectionPool: isPostgresHealthy ? {
          total: pool.totalCount,
          active: pool.totalCount - pool.idleCount,
          idle: pool.idleCount,
          waiting: pool.waitingCount,
          maxConnections: 8,
        } : null,
        tableCounts: tableCounts,
        message: isPostgresHealthy 
          ? 'Database is healthy and accepting connections'
          : 'Unable to connect to database. Check DATABASE_URL configuration.',
      },
      performance: {
        status: responseTime < 50 ? 'excellent' : responseTime < 200 ? 'good' : 'slow',
        latency: `${responseTime}ms`,
        threshold: {
          excellent: '<50ms',
          good: '50-200ms',
          slow: '>200ms',
        },
      },
      configuration: {
        host: process.env.DATABASE_URL ? 'configured' : 'not configured',
        ssl: process.env.NODE_ENV === 'production',
        poolSize: 8,
      },
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error('Database status check error:', error);
    res.status(500).json({ 
      database: {
        status: 'error',
        healthy: false,
        message: 'Failed to check database status',
      },
      timestamp: new Date().toISOString(),
    });
  }
}

/**
 * GET /api/system/stats
 * Get platform statistics
 */
export async function getSystemStats(req: Request, res: Response) {
  try {
    const postgresHealth = await checkPostgresHealth();
    const isPostgresHealthy = typeof postgresHealth === 'object' && postgresHealth.healthy === true;

    if (!isPostgresHealthy) {
      return res.json({
        available: false,
        message: 'Statistics unavailable - database not connected',
        timestamp: new Date().toISOString(),
      });
    }

    // Get platform statistics
    const statsResult = await pool.query(`
      SELECT 
        (SELECT COUNT(*) FROM users WHERE role = 'student') as total_students,
        (SELECT COUNT(*) FROM users WHERE role = 'barber') as total_barbers,
        (SELECT COUNT(*) FROM bookings) as total_bookings,
        (SELECT COUNT(*) FROM bookings WHERE status = 'completed') as completed_bookings,
        (SELECT COUNT(*) FROM bookings WHERE status = 'pending') as pending_bookings,
        (SELECT COUNT(*) FROM campuses WHERE is_active = true) as active_campuses,
        (SELECT COUNT(*) FROM reviews) as total_reviews,
        (SELECT COALESCE(AVG(rating), 0) FROM reviews) as avg_rating
    `);

    const stats = statsResult.rows[0];

    res.json({
      available: true,
      stats: {
        users: {
          students: parseInt(stats.total_students) || 0,
          barbers: parseInt(stats.total_barbers) || 0,
          total: (parseInt(stats.total_students) || 0) + (parseInt(stats.total_barbers) || 0),
        },
        bookings: {
          total: parseInt(stats.total_bookings) || 0,
          completed: parseInt(stats.completed_bookings) || 0,
          pending: parseInt(stats.pending_bookings) || 0,
          completionRate: stats.total_bookings > 0 
            ? Math.round((stats.completed_bookings / stats.total_bookings) * 100) 
            : 0,
        },
        campuses: {
          active: parseInt(stats.active_campuses) || 0,
        },
        reviews: {
          total: parseInt(stats.total_reviews) || 0,
          averageRating: parseFloat(stats.avg_rating).toFixed(1) || '0.0',
        },
      },
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error('System stats error:', error);
    res.json({
      available: false,
      message: 'Failed to retrieve statistics',
      timestamp: new Date().toISOString(),
    });
  }
}
