import api from './api.service';
import type { Review, PaginatedResponse } from '../types';

interface CreateReviewData {
  booking_id: string;
  rating: number;
  review_text?: string;
}

class ReviewService {
  async createReview(data: CreateReviewData): Promise<Review> {
    return await api.post<Review>('/reviews', data);
  }

  async getReviewByBookingId(bookingId: string): Promise<Review | null> {
    try {
      return await api.get<Review>(`/reviews/booking/${bookingId}`);
    } catch (error) {
      return null;
    }
  }

  async getBarberReviews(barberId: string, page = 1, limit = 20): Promise<PaginatedResponse<Review>> {
    return await api.get<PaginatedResponse<Review>>(`/reviews/barber/${barberId}`, { page, limit });
  }

  async deleteReview(reviewId: string): Promise<void> {
    await api.delete(`/reviews/${reviewId}`);
  }
}

export default new ReviewService();

