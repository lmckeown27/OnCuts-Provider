import { pool } from './connection';
import { logger } from '../utils/logger';
import bcrypt from 'bcrypt';

/**
 * Seed database with sample data for development
 */
async function seed() {
  try {
    logger.info('🌱 Starting database seeding...');

    // Check if data already exists
    const userCount = await pool.query('SELECT COUNT(*) FROM users');
    if (parseInt(userCount.rows[0].count) > 0) {
      logger.info('⚠️  Database already contains data. Skipping seed.');
      process.exit(0);
    }

    // Create sample users
    const password = await bcrypt.hash('password123', 10);

    // Sample student
    const studentResult = await pool.query(
      `INSERT INTO users (email, password_hash, first_name, last_name, campus_id, role, legacy_wallet_address, email_verified)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id`,
      ['student@harvard.edu', password, 'John', 'Student', 1, 'student', '0x1234567890abcdef', true]
    );

    logger.info('✅ Sample student created');

    // Sample barber users
    const barber1Result = await pool.query(
      `INSERT INTO users (email, password_hash, first_name, last_name, campus_id, role, legacy_wallet_address, email_verified)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id`,
      ['barber1@harvard.edu', password, 'Mike', 'Barber', 1, 'barber', '0xabcdef1234567890', true]
    );

    const barber2Result = await pool.query(
      `INSERT INTO users (email, password_hash, first_name, last_name, campus_id, role, legacy_wallet_address, email_verified)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id`,
      ['barber2@harvard.edu', password, 'Alex', 'Styles', 1, 'barber', '0xfedcba0987654321', true]
    );

    // Create barber profiles
    await pool.query(
      `INSERT INTO barbers (user_id, bio, pricing, average_rating, total_bookings, years_experience)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        barber1Result.rows[0].id,
        'Professional barber specializing in fades and tapers. 5 years of experience.',
        JSON.stringify({ 'Haircut': 25, 'Fade': 30, 'Beard Trim': 15, 'Line Up': 10 }),
        4.8,
        150,
        5
      ]
    );

    await pool.query(
      `INSERT INTO barbers (user_id, bio, pricing, average_rating, total_bookings, years_experience)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        barber2Result.rows[0].id,
        'Expert in all hair types. Specializing in braids, locs, and natural hair care.',
        JSON.stringify({ 'Haircut': 30, 'Braids': 50, 'Locs': 60, 'Twist Out': 35 }),
        4.9,
        200,
        7
      ]
    );

    logger.info('✅ Sample barbers created');

    logger.info('🌱 Database seeding completed successfully');
    logger.info('\n📝 Test Credentials:');
    logger.info('   Student: student@harvard.edu / password123');
    logger.info('   Barber 1: barber1@harvard.edu / password123');
    logger.info('   Barber 2: barber2@harvard.edu / password123');

    process.exit(0);
  } catch (error) {
    logger.error('❌ Database seeding failed:', error);
    process.exit(1);
  }
}

seed();

