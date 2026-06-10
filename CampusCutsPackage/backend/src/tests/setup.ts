/**
 * Test Setup
 * 
 * Global test configuration and mocks
 */

// Mock environment variables
process.env.NODE_ENV = 'test';
process.env.SUI_RPC_URL = process.env.SUI_RPC_URL || 'https://fullnode.testnet.sui.io';
process.env.REDIS_URL = 'redis://localhost:6379';
process.env.ENCRYPTION_KEY = 'test-encryption-key-32-bytes-long!!';
process.env.JWT_SECRET = 'test-jwt-secret';

// Mock logger to reduce noise in tests
jest.mock('../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
    debug: jest.fn(),
  },
}));

// Mock Redis
jest.mock('../config/redis', () => ({
  redisGet: jest.fn().mockResolvedValue(null),
  redisSet: jest.fn().mockResolvedValue('OK'),
  redisDel: jest.fn().mockResolvedValue(1),
  generateCacheKey: (prefix: string, ...args: any[]) => `${prefix}:${args.join(':')}`,
  CACHE_TTL: {
    SHORT: 300,
    MEDIUM: 3600,
    LONG: 86400,
  },
}));

// Global test timeout
jest.setTimeout(10000);

// Clean up after all tests
afterAll(async () => {
  // Close any open connections
  await new Promise(resolve => setTimeout(resolve, 100));
});

