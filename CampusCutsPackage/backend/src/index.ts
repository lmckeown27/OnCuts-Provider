// Load environment variables FIRST, before any other imports
import dotenv from 'dotenv';
dotenv.config();

import { applyAppNetworkModeDefaults } from './config/app-network';
applyAppNetworkModeDefaults();

import express, { Application, Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import path from 'path';
import morgan from 'morgan';
import compression from 'compression';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { logger } from './utils/logger';
import { errorHandler } from './middleware/errorHandler';
import { connectRedis } from './config/redis';
import rateLimit from 'express-rate-limit';

// PostgreSQL Cache Layer (Hybrid Architecture)
import { pool, checkHealth as checkPostgresHealth, closePool, connectToPostgres } from './database/connection';

// Import routes
import authRoutes from './routes/auth.routes';
import barberRoutes from './routes/barber.routes';
import bookingRoutes from './routes/booking.routes';
import paymentRoutes from './routes/payment.routes';
import reviewRoutes from './routes/review.routes';
import campusRoutes from './routes/campus.routes';
import messageRoutes from './routes/message.routes';
import notificationRoutes from './routes/notification.routes';
import uploadRoutes from './routes/upload.routes';
import walletRoutes from './routes/wallet.routes';

// V2 Routes (Production custodial wallet system)
import bookingV2Routes from './routes/booking-v2.routes';
import zkloginRoutes from './routes/zklogin.routes';
import walletV2Routes from './routes/wallet-v2.routes';
import adminRoutes from './routes/admin.routes';

// Stripe Integration Routes
import webhookRoutes from './routes/webhook.routes';
import bookingPaymentRoutes from './routes/booking-payment.routes';
import barberConnectRoutes from './routes/barber-connect.routes';

// Live Transaction Feed Routes
import liveFeedRoutes from './routes/live-feed.routes';

// Gas Wallet Management Routes
import gasWalletRoutes from './routes/gas-wallet.routes';

// Dynamic Pricing Routes
import pricingRoutes from './routes/pricing.routes';

// User Management Routes
import userRoutes from './routes/user.routes';

// Admin Transaction Monitoring Routes
import adminTransactionsRoutes from './routes/admin-transactions.routes';

// Admin User Management Routes
import adminUsersRoutes from './routes/admin-users.routes';

// System Health Routes
import systemHealthRoutes from './routes/system-health.routes';

// Gas Wallet Monitoring Routes (Admin)
import gasMonitorRoutes from './routes/gas-wallet.routes';
import adminGasWalletRoutes from './routes/admin-gas-wallet.routes';

// Marketplace Engine Routes (Capitalistic)
import marketplaceRoutes from './routes/marketplace.routes';
import { marketplaceCronService } from './services/marketplace-cron.service';
import { bookingReminderCronService } from './services/booking-reminder-cron.service';
import { barberCheckInCronService } from './services/barber-checkin-cron.service';
import { paymentReminderCronService } from './services/payment-reminder-cron.service';
import { pendingBookingCronService } from './services/pending-booking-cron.service';

// Booking Request Routes (AirBnb-style)
import bookingRequestRoutes from './routes/booking-request.routes';

// Campus Location Routes (Crowd-sourced location system)
import locationRoutes from './routes/location.routes';
import locationAdminRoutes from './routes/admin/location-admin.routes';

// Campus Manager Routes (Public landing page + management)
import campusManagerRoutes from './routes/campus-manager.routes';

// Circle USDC Integration - DISABLED (Platform uses Stripe)
// import circleWebhookRoutes from './routes/circle-webhook.routes';

// Barber Applications
import barberApplicationRoutes from './routes/barber-application.routes';


// Simple Booking Routes (matches production schema)
import bookingSimpleRoutes from './routes/booking-simple.routes';
import publicStripeRoutes from './routes/public-stripe.routes';

// Google Calendar Integration
import googleCalendarRoutes from './routes/google-calendar.routes';

// Environment variables already loaded at top of file

const app: Application = express();
const PORT = process.env.PORT || 3000;

// Trust proxy - required when running behind Nginx reverse proxy
// This ensures rate limiting and IP detection work correctly
app.set('trust proxy', 1);

// Create HTTP server for Socket.IO
const httpServer = createServer(app);

// Allowed origins for CORS
const allowedOrigins = [
  'http://localhost:3000',
  'http://localhost:3001',
  'https://campuscut.com',
  'https://www.campuscut.com',
  'https://campuscuts.app',
  'https://www.campuscuts.app',
  'https://api.campuscuts.app',
];

// Socket.IO setup for real-time messaging
const io = new Server(httpServer, {
  path: '/socket.io/',
  cors: {
    origin: (origin, callback) => {
      if (!origin) return callback(null, true);
      if (allowedOrigins.indexOf(origin) !== -1) {
        callback(null, true);
      } else {
        console.warn('🚫 Socket.IO CORS: Blocked origin:', origin);
        callback(new Error('Not allowed by CORS'));
      }
    },
    methods: ['GET', 'POST'],
    credentials: true,
  },
  transports: ['polling', 'websocket'],
  pingTimeout: 60000,
  pingInterval: 25000,
});

// Socket.IO connection handling
io.on('connection', (socket) => {
  console.log('✅ Socket.IO: User connected:', socket.id);

  // Join user to their personal room for direct messages
  socket.on('join-personal', (userId: number) => {
    socket.join(`user-${userId}`);
    console.log(`📬 Socket.IO: User ${socket.id} joined personal room: user-${userId}`);
    socket.emit('joined-personal', { userId, socketId: socket.id });
  });

  // Join user to their campus room for campus-wide updates
  socket.on('join-campus', (campusId: number) => {
    socket.join(`campus-${campusId}`);
    console.log(`🏫 Socket.IO: User ${socket.id} joined campus room: campus-${campusId}`);
  });

  // Join admin to live transaction feed room (admin dashboard)
  socket.on('join-admin-live-feed', (userId: number) => {
    // TODO: Verify user is admin before allowing join
    socket.join('admin-live-feed');
    console.log(`👑 Socket.IO: Admin ${socket.id} joined live feed room`);
    socket.emit('joined-admin-live-feed', { userId, socketId: socket.id });
  });

  socket.on('disconnect', (reason) => {
    console.log('❌ Socket.IO: User disconnected:', socket.id, 'Reason:', reason);
  });

  socket.on('error', (error) => {
    console.error('🔴 Socket.IO: Socket error:', error);
  });
});

console.log('✅ Socket.IO server initialized');

// Make Socket.IO available to routes
app.set('io', io);

// Connect to Redis
connectRedis();

// Middleware
app.use(helmet());
app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true);
    if (allowedOrigins.indexOf(origin) !== -1 || process.env.NODE_ENV === 'development') {
      callback(null, true);
    } else {
      console.log('CORS blocked origin:', origin);
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use(compression());
app.use(morgan('combined', { stream: { write: (message) => logger.info(message.trim()) } }));

// IMPORTANT: Webhook routes MUST come BEFORE express.json()
// Stripe requires raw body to verify webhook signatures
app.use('/api/webhooks', express.raw({ type: 'application/json' }), webhookRoutes);

// Then apply JSON parsing for all other routes
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Rate limiting - Production-ready settings
// General API: 1000 requests per 15 minutes (generous for normal usage)
const generalLimiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000'), // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '1000'), // 1000 requests per window
  message: { error: 'Too many requests from this IP, please try again later.' },
  standardHeaders: true,
  legacyHeaders: false,
});

// Auth endpoints: Stricter limits to prevent brute force
// Login/register: 30 per 15 min (allows for typos and multiple attempts)
// /me endpoint is excluded as it's called frequently on page loads
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 30, // 30 auth attempts per window (increased from 20)
  message: { error: 'Too many authentication attempts, please try again in 15 minutes.' },
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => {
    // Skip rate limiting for /me endpoint (called on every page load)
    // These are authenticated requests, not login attempts
    return req.path === '/me' && req.method === 'GET';
  },
});

// Apply rate limiters
app.use('/api/v1/auth', authLimiter);
app.use('/api', generalLimiter);

// Health check (PostgreSQL + Stripe - Off-chain architecture)
app.get('/health', async (req: Request, res: Response) => {
  try {
    // Check PostgreSQL database
    const pgHealth = await checkPostgresHealth();
    
    // Get basic stats from PostgreSQL
    let stats = null;
    try {
      const usersResult = await pool.query('SELECT COUNT(*) FROM users');
      const bookingsResult = await pool.query('SELECT COUNT(*) FROM bookings');
      stats = {
        total_users: parseInt(usersResult.rows[0].count),
        total_bookings: parseInt(bookingsResult.rows[0].count),
      };
    } catch {
      // Stats query failed, but system can still be healthy
    }
    
    const overallStatus = pgHealth.healthy ? 'healthy' : 'unhealthy';
    
    res.json({
      status: overallStatus,
      timestamp: new Date().toISOString(),
      architecture: 'off-chain',
      payment_provider: 'stripe',
      database: {
        status: pgHealth.healthy ? 'connected' : 'disconnected',
        provider: 'postgresql',
        pool: pgHealth.pool,
      },
      stats,
    });
  } catch (error: any) {
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message,
    });
  }
});

// API Routes (V1 - versioned routes)
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/barbers', barberRoutes);
app.use('/api/v1/barber', barberConnectRoutes);  // Stripe Connect for barbers
app.use('/api/v1/bookings', bookingPaymentRoutes);  // Enhanced with Stripe payments
app.use('/api/v1/bookings-simple', bookingSimpleRoutes);  // Simple booking creation
app.use('/api/v1/payments', paymentRoutes);
app.use('/api/v1/reviews', reviewRoutes);
app.use('/api/v1/campus', campusRoutes);
app.use('/api/v1/messages', messageRoutes);
app.use('/api/v1/notifications', notificationRoutes);
app.use('/api/v1/upload', uploadRoutes);
app.use('/api/v1/wallet', walletRoutes);
app.use('/api/v1/stripe', publicStripeRoutes);
app.use('/api/stripe', publicStripeRoutes);

// Google Calendar OAuth Routes
app.use('/api/v1/auth/google-calendar', googleCalendarRoutes);
app.use('/api/auth/google-calendar', googleCalendarRoutes);  // Legacy route

// Legacy routes (backward compatibility - no /v1 prefix)
app.use('/api/auth', authRoutes);
app.use('/api/barbers', barberRoutes);
app.use('/api/barber', barberConnectRoutes);
app.use('/api/bookings', bookingPaymentRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/reviews', reviewRoutes);
app.use('/api/campus', campusRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/wallet', walletRoutes);

// Sui zkLogin (salt + link address)
app.use('/api/zklogin', zkloginRoutes);

// V2 Routes (Production custodial wallet system)
app.use('/api/v2/bookings', bookingV2Routes);
app.use('/api/v2/wallet', walletV2Routes);
app.use('/api/admin', adminRoutes);
app.use('/api/v1/admin', adminRoutes);  // Also mount at v1 for frontend compatibility
app.use('/api/admin/live-feed', liveFeedRoutes);  // Live transaction monitoring
app.use('/api/admin/transactions', adminTransactionsRoutes);  // Transaction history
app.use('/api/admin/users', adminUsersRoutes);  // User management (block, ban, etc.)
app.use('/api/gas', gasWalletRoutes);  // Gas wallet management

// Dynamic Pricing Routes
app.use('/api/pricing', pricingRoutes);  // Dynamic pricing engine

// User Management Routes
app.use('/api/v1/users', userRoutes);  // User profile management (versioned)
app.use('/api/users', userRoutes);  // User profile management (legacy)

// Campus Location Management (Crowd-sourced)
app.use('/api/v1/locations', locationRoutes);  // Location management (versioned)
app.use('/api/locations', locationRoutes);  // Location submission, search, retrieval (legacy)
app.use('/api/admin/locations', locationAdminRoutes);  // Admin location management

// System health monitoring
app.use('/api/system', systemHealthRoutes);  // System health and database status

// Gas wallet monitoring (Admin)
app.use('/api/gas', gasMonitorRoutes);  // Gas wallet balance and usage monitoring
app.use('/api/admin/gas-wallet', adminGasWalletRoutes);  // Admin gas wallet management (USDC system)

// Marketplace Engine (Capitalistic)
app.use('/api/marketplace', marketplaceRoutes);  // BQS, dynamic pricing, rankings, surge

// Booking Requests (AirBnb-style)
app.use('/api/v1/booking-requests', bookingRequestRoutes);  // Accept/reject, messaging, profiles
app.use('/api/booking-requests', bookingRequestRoutes);  // Legacy route

// Circle USDC Integration - DISABLED (Platform uses Stripe)
// app.use('/api/circle', circleWebhookRoutes);  // Circle webhook handler for USDC transfers

// Barber Applications (Consumer -> Barber flow)
app.use('/api/v1/barber-applications', barberApplicationRoutes);  // Submit and track barber applications
app.use('/api/v1/campus-manager', campusManagerRoutes);  // Campus manager info (public) + management
app.use('/api/barber-applications', barberApplicationRoutes);  // Legacy route

logger.info('✅ V2 routes enabled:');
logger.info('   - /api/v2/bookings (Stripe Checkout + Bridge / Sui)');
logger.info('   - /api/v2/wallet (production wallet)');
logger.info('   - /api/admin (platform management)');
logger.info('   - /api/admin/live-feed (real-time monitoring)');
logger.info('   - /api/admin/transactions (transaction history)');
logger.info('   - /api/gas (gas wallet & top-up management)');
logger.info('   - /api/pricing (dynamic pricing engine)');

// Blockchain routes are disabled - platform uses Stripe for off-chain payments
logger.info('💳 Payment system: Stripe (off-chain only)');
logger.info('   - GET /api/v1/stripe/client-config (+ /api/stripe/client-config, /api/v1/bookings-simple/stripe/client-config)');
logger.info('   - Blockchain routes disabled');
logger.info('   - All payments processed via Stripe');
logger.info('   - No cryptocurrency or smart contract escrow');


// 404 handler
// Static files for uploads (MUST be before 404 handler)
// Use absolute path to ensure it works in production when running from dist/
const uploadsDir = process.env.UPLOAD_PATH || path.join(__dirname, '..', 'uploads');

// Debug: Log the resolved path
logger.info(`📁 Static uploads directory: ${uploadsDir}`);
logger.info(`📁 __dirname is: ${__dirname}`);

// Check if directory exists
const fsSync = require('fs');
if (fsSync.existsSync(uploadsDir)) {
  const files = fsSync.readdirSync(uploadsDir);
  logger.info(`📁 Uploads directory exists with ${files.length} files`);
} else {
  logger.warn(`⚠️ Uploads directory does NOT exist: ${uploadsDir}`);
  // Create it
  fsSync.mkdirSync(uploadsDir, { recursive: true });
  logger.info(`📁 Created uploads directory: ${uploadsDir}`);
}

app.use('/uploads', express.static(uploadsDir));
app.use('/api/uploads', express.static(uploadsDir));  // For Nginx API proxy

// 404 handler (must be after all routes and static files)
app.use((req: Request, res: Response) => {
  res.status(404).json({
    error: 'Not Found',
    message: `Route ${req.method} ${req.path} not found`,
  });
});

// Error handler (must be last)
app.use(errorHandler);

// Start server
httpServer.listen(PORT, async () => {
  logger.info(`🚀 CampusCuts API server running on port ${PORT}`);
  logger.info(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
  logger.info(`💳 Payment Provider: Stripe (off-chain)`);
  logger.info(`💬 Socket.IO ready for real-time messaging`);

  // Initialize PostgreSQL cache connection
  try {
    await connectToPostgres();
    logger.info(`✅ PostgreSQL cache layer ready`);
    try {
      const { initVerificationSchema } = await import('./services/verification.service');
      await initVerificationSchema();
      logger.info(`✅ Verification schema ready (pending_registrations)`);
      const { initPhoneSignupSchema } = await import('./services/phone-signup.service');
      await initPhoneSignupSchema();
      logger.info(`✅ Phone signup schema ready (phone_signup_pending)`);
    } catch (verifyErr: unknown) {
      logger.warn('Verification schema init failed (registration codes may fail until DB is reachable)', {
        error: verifyErr instanceof Error ? verifyErr.message : String(verifyErr),
      });
    }
  } catch (error: any) {
    logger.error(`❌ PostgreSQL cache unavailable (app will use blockchain fallback)`, {
      error: error.message,
    });
  }

  // NOTE: Legacy chain monitor removed — Stripe + optional Sui relayer when enabled.
  // NOTE: Legacy gas-wallet cron disabled — use Sui sponsored txs (GAS_SPONSOR_SECRET) when on-chain is enabled.

  // Start marketplace cron jobs (BQS, pricing, rankings, surge)
  await marketplaceCronService.startAllJobs();

  // Start booking reminder cron job (sends reminders 1 hour before appointments)
  bookingReminderCronService.start();

  // Start barber check-in cron job (sends check-ins 1 hour after appointments if not updated)
  barberCheckInCronService.start();

  // Start payment reminder cron job (sends reminders when awaiting payment for 1+ hours)
  paymentReminderCronService.start();

  // Start pending booking cron job (warns 3h before, auto-cancels 2h before if not accepted)
  pendingBookingCronService.start();

  // DIY Sui relayer: sequential payouts (BullMQ concurrency 1) after Stripe checkout
  if (process.env.SUI_DIY_RELAYER_ENABLED === 'true') {
    try {
      const { startPayoutWorker } = await import('./queues/process-payout.queue');
      startPayoutWorker();
    } catch (e) {
      logger.error('Failed to start process-payout worker', e);
    }
  }

  // NOTE: Blockchain sync disabled - platform uses Stripe for payments
  // To re-enable blockchain features, uncomment below:
  // const blockchainSyncCronService = (await import('./services/blockchain-sync-cron.service')).default;
  // blockchainSyncCronService.start();
  // logger.info(`Blockchain sync cron job started (hourly sync)`);

  // Start pricing cron jobs (daily recompute, hourly metrics, weekly market update)
  // TEMPORARILY DISABLED: Requires PostgreSQL database to be properly configured
  // Uncomment when PostgreSQL is set up with correct DATABASE_URL
  // const pricingCronService = (await import('./services/pricing/pricing-cron.service')).default;
  // pricingCronService.start();
  logger.info(`⏸️  Pricing cron jobs disabled (enable when PostgreSQL is configured)`);
});

// Graceful shutdown (Hybrid Architecture - close PostgreSQL pool + servers)
process.on('SIGTERM', async () => {
  logger.info('SIGTERM signal received: closing servers and database connections');
  
  try {
    // Close HTTP server
    await new Promise((resolve) => {
      httpServer.close(() => {
        logger.info('HTTP server closed');
        resolve(true);
      });
    });
    
    // Close Socket.IO
    await new Promise((resolve) => {
      io.close(() => {
        logger.info('Socket.IO server closed');
        resolve(true);
      });
    });
    
    // Close PostgreSQL pool
    await closePool();
    logger.info('PostgreSQL pool closed');

    if (process.env.SUI_DIY_RELAYER_ENABLED === 'true') {
      try {
        const { closePayoutInfrastructure } = await import('./queues/process-payout.queue');
        await closePayoutInfrastructure();
        logger.info('process-payout queue closed');
      } catch (e) {
        logger.warn('process-payout shutdown', e);
      }
    }

    logger.info('✅ All services shut down gracefully (hybrid architecture)');
    process.exit(0);
  } catch (error) {
    logger.error('Error during shutdown:', error);
    process.exit(1);
  }
});

process.on('SIGINT', async () => {
  logger.info('SIGINT signal received: closing servers and database connections');
  
  try {
    if (process.env.SUI_DIY_RELAYER_ENABLED === 'true') {
      try {
        const { closePayoutInfrastructure } = await import('./queues/process-payout.queue');
        await closePayoutInfrastructure();
      } catch {
        /* ignore */
      }
    }
    await closePool();
    logger.info('PostgreSQL pool closed');
    process.exit(0);
  } catch (error) {
    logger.error('Error during shutdown:', error);
    process.exit(1);
  }
});

// Export Socket.IO instance for use in services
export { io };

// Getter function for io to avoid circular dependency issues
export function getSocketIO() {
  return io;
}

export default app;

