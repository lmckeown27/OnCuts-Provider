import { pool } from './connection';
import { logger } from '../utils/logger';
import fs from 'fs';
import path from 'path';

/**
 * Run database migrations
 */
async function migrate() {
  try {
    logger.info('🔄 Starting database migration...');

    const schemaPath = path.join(__dirname, 'schema.sql');
    const schema = fs.readFileSync(schemaPath, 'utf-8');

    await pool.query(schema);

    logger.info('✅ Database migration completed successfully');
    process.exit(0);
  } catch (error) {
    logger.error('❌ Database migration failed:', error);
    process.exit(1);
  }
}

migrate();

