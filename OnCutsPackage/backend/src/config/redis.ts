/**
 * Redis Configuration and Utilities
 * Transferred from CampusKinect with CampusCuts adaptations
 * 
 * Used for:
 * - Session caching
 * - API response caching
 * - Rate limiting
 * - Real-time data synchronization
 */

import { createClient, RedisClientType } from 'redis';

let client: RedisClientType | null = null;

export const connectRedis = async (): Promise<void> => {
  try {
    client = createClient({
      url: process.env.REDIS_URL || 'redis://localhost:6379',
      socket: {
        connectTimeout: 10000,
      },
    });

    client.on('error', (err) => {
      console.error('❌ Redis Client Error:', err);
    });

    client.on('connect', () => {
      console.log('✅ Connected to Redis');
    });

    client.on('ready', () => {
      console.log('✅ Redis client ready');
    });

    client.on('end', () => {
      console.log('🔌 Redis client disconnected');
    });

    await client.connect();

    // Test the connection
    await client.ping();
    console.log('✅ Redis connection test successful');
  } catch (error) {
    console.error('❌ Redis connection failed:', error);
    // Don't exit process, Redis is optional for development
    if (process.env.NODE_ENV === 'production') {
      process.exit(1);
    }
  }
};

// Helper functions for Redis operations
export const redisGet = async (key: string): Promise<any> => {
  try {
    if (!client || !client.isReady) return null;
    const value = await client.get(key);
    return value ? JSON.parse(value) : null;
  } catch (error) {
    console.error('Redis GET error:', error);
    return null;
  }
};

export const redisSet = async (
  key: string,
  value: any,
  expireSeconds: number = 3600
): Promise<boolean> => {
  try {
    if (!client || !client.isReady) return false;
    await client.setEx(key, expireSeconds, JSON.stringify(value));
    return true;
  } catch (error) {
    console.error('Redis SET error:', error);
    return false;
  }
};

export const redisDel = async (key: string): Promise<boolean> => {
  try {
    if (!client || !client.isReady) return false;
    await client.del(key);
    return true;
  } catch (error) {
    console.error('Redis DEL error:', error);
    return false;
  }
};

export const redisExists = async (key: string): Promise<boolean> => {
  try {
    if (!client || !client.isReady) return false;
    const result = await client.exists(key);
    return result === 1;
  } catch (error) {
    console.error('Redis EXISTS error:', error);
    return false;
  }
};

export const redisIncr = async (key: string): Promise<number | null> => {
  try {
    if (!client || !client.isReady) return null;
    return await client.incr(key);
  } catch (error) {
    console.error('Redis INCR error:', error);
    return null;
  }
};

export const redisExpire = async (key: string, seconds: number): Promise<boolean> => {
  try {
    if (!client || !client.isReady) return false;
    return await client.expire(key, seconds);
  } catch (error) {
    console.error('Redis EXPIRE error:', error);
    return false;
  }
};

// Cache keys for different data types
export const CACHE_KEYS = {
  USER: 'user',
  BARBER: 'barber',
  BOOKING: 'booking',
  CAMPUS: 'campus',
  SESSION: 'session',
  SEARCH: 'search',
  REVIEW: 'review',
};

// Generate cache keys
export const generateCacheKey = (type: string, identifier: string | number): string => {
  const keyType = CACHE_KEYS[type.toUpperCase() as keyof typeof CACHE_KEYS] || type;
  return `${keyType}:${identifier}`;
};

// Cache TTL values (in seconds)
export const CACHE_TTL = {
  USER: 3600, // 1 hour
  BARBER: 1800, // 30 minutes
  BOOKING: 900, // 15 minutes
  CAMPUS: 86400, // 24 hours
  SESSION: 7200, // 2 hours
  SEARCH: 600, // 10 minutes
  REVIEW: 3600, // 1 hour
  SHORT: 300, // 5 minutes
  MEDIUM: 1800, // 30 minutes
  LONG: 86400, // 24 hours
};

export const getRedisClient = (): RedisClientType | null => client;

