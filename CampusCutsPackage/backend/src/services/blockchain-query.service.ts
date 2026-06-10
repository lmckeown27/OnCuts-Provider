/**
 * Blockchain query facade — Postgres + Sui via Bridge; on-chain reads are stubbed until indexer wired.
 */

import { logger } from '../utils/logger';
import { redisDel } from '../config/redis';

interface UserAccount {
  address: string;
  email_hash: string;
  campus_domain: string;
  role: number;
  balance_available: string;
  balance_locked: string;
  profile_photo_cid: string;
  bio: string;
  username: string;
  created_at: string;
  last_active: string;
  is_active: boolean;
  is_verified: boolean;
  years_of_experience?: number;
  specialties?: string[];
  portfolio_cids?: string[];
  total_bookings: string;
  total_spent: string;
  total_earned: string;
}

interface Booking {
  id: string;
  student_addr: string;
  barber_addr: string;
  service_name: string;
  service_description: string;
  amount_total: string;
  amount_to_barber: string;
  platform_fee: string;
  scheduled_time: string;
  created_at: string;
  completed_at: string;
  status: number;
  escrow_released: boolean;
  location_description: string;
  student_notes: string;
  barber_notes: string;
}

interface Review {
  id: string;
  booking_id: string;
  student_addr: string;
  barber_addr: string;
  rating: number;
  review_text_cid: string;
  student_performance_score: string;
  review_weight: string;
  weighted_rating: string;
  created_at: string;
  is_verified: boolean;
}

interface BarberRating {
  barber_addr: string;
  total_reviews: string;
  average_rating: string;
  weighted_average_rating: string;
  rating_5_count: string;
  rating_4_count: string;
  rating_3_count: string;
  rating_2_count: string;
  rating_1_count: string;
  last_updated: string;
}

class BlockchainQueryService {
  constructor() {
    logger.info('BlockchainQueryService: Sui (on-chain reads stubbed until indexer is wired)');
  }

  async getUserAccount(_address: string): Promise<UserAccount | null> {
    return null;
  }

  async getUserBalance(
    _address: string
  ): Promise<{ available: string; locked: string } | null> {
    return { available: '0', locked: '0' };
  }

  async isBarber(_address: string): Promise<boolean> {
    return false;
  }

  async getBarbersByCampus(_campusDomain: string): Promise<UserAccount[]> {
    return [];
  }

  async getBooking(_bookingId: string): Promise<Booking | null> {
    return null;
  }

  async getUserBookings(_userAddress: string): Promise<Booking[]> {
    return [];
  }

  async getUserBookingCount(_userAddress: string): Promise<number> {
    return 0;
  }

  async getBarberRating(_barberAddress: string): Promise<BarberRating | null> {
    return null;
  }

  async getBarberReviews(_barberAddress: string, _limit = 20): Promise<Review[]> {
    return [];
  }

  async getPlatformStats(): Promise<{
    totalUsers: number;
    totalStudents: number;
    totalBarbers: number;
    totalBookings: number;
    totalReviews: number;
    totalVolume: string;
  }> {
    return {
      totalUsers: 0,
      totalStudents: 0,
      totalBarbers: 0,
      totalBookings: 0,
      totalReviews: 0,
      totalVolume: '0',
    };
  }

  async invalidateUserCache(address: string): Promise<void> {
    try {
      await redisDel(`user:${address}`);
      await redisDel(`bookings:${address}`);
    } catch (e) {
      logger.error('invalidateUserCache', e);
    }
  }

  async invalidateBookingCache(bookingId: string): Promise<void> {
    try {
      await redisDel(`booking:${bookingId}`);
    } catch (e) {
      logger.error('invalidateBookingCache', e);
    }
  }

  async clearAllCaches(): Promise<void> {
    logger.info('clearAllCaches: noop stub');
  }
}

export default new BlockchainQueryService();
