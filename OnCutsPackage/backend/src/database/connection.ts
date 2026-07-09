/**
 * PostgreSQL Connection Pool (Cache Layer)
 * 
 * PostgreSQL is the primary application store (bookings, users, payments).
 * Settlement uses Stripe + optional Sui relayer; chain state may be mirrored here.
 * 
 * Adapted from CampusKinect database architecture
 */

import { Pool, PoolConfig } from 'pg';
import { logger } from '../utils/logger';

// Pool configuration optimized for cache layer
const poolConfig: PoolConfig = {
  connectionString: process.env.DATABASE_URL,
  
  // SSL configuration (required for production, optional for dev)
  ssl: process.env.NODE_ENV === 'production' 
    ? { rejectUnauthorized: false }  // Heroku/Railway/Render requirement
    : false,
  
  // Connection pool sizing (adapted from CampusKinect)
  max: 8,                          // Maximum connections (conservative for cache layer)
  min: 1,                          // Minimum idle connections
  idleTimeoutMillis: 30000,        // 30s - release idle connections
  connectionTimeoutMillis: 10000,  // 10s - timeout for new connections
  
  // Query timeouts (cache queries should be fast!)
  statement_timeout: 5000,         // 5s - cache queries must be fast
  query_timeout: 5000,             // 5s - overall query timeout
};

// Create connection pool
export const pool = new Pool(poolConfig);

// Connection lifecycle events
pool.on('connect', (client) => {
  logger.info('PostgreSQL cache connection established');
  
  // Set application name for monitoring
  client.query(`SET application_name = 'campuscuts-api'`).catch(() => {});
});

pool.on('error', (err: any, client) => {
  logger.error('PostgreSQL cache connection error:', {
    message: err.message,
    code: err.code || 'UNKNOWN',
    detail: err.detail || 'No details available',
  });
  
  // Don't exit process - allow graceful degradation
  // Queries will fall back to blockchain if cache unavailable
});

pool.on('acquire', () => {
  if (process.env.LOG_LEVEL === 'debug') {
    logger.debug('PostgreSQL connection acquired from pool', {
      total: pool.totalCount,
      idle: pool.idleCount,
      waiting: pool.waitingCount,
    });
  }
});

pool.on('release', () => {
  if (process.env.LOG_LEVEL === 'debug') {
    logger.debug('PostgreSQL connection released to pool');
  }
});

/**
 * Query wrapper with error handling and logging
 * Adapted from CampusKinect query patterns
 */
export const query = async (text: string, params?: any[]) => {
  const start = Date.now();
  
  try {
    const result = await pool.query(text, params);
    const duration = Date.now() - start;
    
    // Log slow queries (>100ms)
    if (duration > 100) {
      logger.warn('Slow query detected', {
        duration: `${duration}ms`,
        query: text.substring(0, 100) + (text.length > 100 ? '...' : ''),
        rowCount: result.rowCount,
      });
    }
    
    return result;
  } catch (error: any) {
    const duration = Date.now() - start;
    
    logger.error('PostgreSQL query error', {
      duration: `${duration}ms`,
      query: text.substring(0, 100) + (text.length > 100 ? '...' : ''),
      error: error.message,
      code: error.code,
      detail: error.detail,
    });
    
    throw error;
  }
};

/**
 * Initialize database connection (test connectivity)
 */
export const connectToPostgres = async () => {
  try {
    const result = await pool.query('SELECT NOW() as time');
    logger.info('PostgreSQL cache connected successfully', {
      timestamp: result.rows[0].time,
      pool: {
        max: poolConfig.max,
        min: poolConfig.min,
      },
    });
    return true;
  } catch (error: any) {
    logger.error('Failed to connect to PostgreSQL cache:', {
      error: error.message,
      code: error.code,
      hint: 'Check DATABASE_URL in .env file',
    });
    throw error;
  }
};

/**
 * Test database connection and return health status
 */
export const checkHealth = async () => {
  try {
    const result = await pool.query('SELECT 1 as health, NOW() as timestamp');
    
    return {
      healthy: true,
      connected: result.rows[0].health === 1,
      timestamp: result.rows[0].timestamp,
      pool: {
        total: pool.totalCount,
        idle: pool.idleCount,
        waiting: pool.waitingCount,
      },
    };
  } catch (error: any) {
    logger.error('PostgreSQL health check failed:', {
      error: error.message,
      code: error.code || 'UNKNOWN',
    });
    
    return {
      healthy: false,
      connected: false,
      error: error.message,
      pool: {
        total: pool.totalCount,
        idle: pool.idleCount,
        waiting: pool.waitingCount,
      },
    };
  }
};

/**
 * Get pool statistics for monitoring
 */
export const getPoolStats = () => {
  return {
    total: pool.totalCount,
    idle: pool.idleCount,
    waiting: pool.waitingCount,
  };
};

/**
 * Graceful shutdown
 */
export const closePool = async () => {
  try {
    await pool.end();
    logger.info('PostgreSQL connection pool closed gracefully');
  } catch (error: any) {
    logger.error('Error closing PostgreSQL pool:', error);
    throw error;
  }
};

// Handle process termination
process.on('SIGTERM', async () => {
  logger.info('SIGTERM received, closing PostgreSQL pool...');
  await closePool();
});

process.on('SIGINT', async () => {
  logger.info('SIGINT received, closing PostgreSQL pool...');
  await closePool();
  process.exit(0);
});

// Export pool as default for backward compatibility
export default pool;
