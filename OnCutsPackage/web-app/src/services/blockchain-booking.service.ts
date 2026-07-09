/**
 * Blockchain-First Booking Service
 * 
 * Legacy smart-contract booking client (unused in Stripe-first flows).
 * Funds are locked on-chain until service completion.
 * 
 * Key Features:
 * - Optimistic UI updates (instant feedback)
 * - Automatic retry on failure
 * - Real-time status updates via blockchain events
 */

import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001';

export interface CreateBookingData {
  barberAddress: string;
  serviceName: string;
  amount: number; // in USD
  scheduledTime: number; // Unix timestamp
  location?: string;
  notes?: string;
}

export interface Booking {
  id: string;
  student: string; // student blockchain address
  barber: string; // barber blockchain address
  serviceName: string;
  amount: string; // in scaled USDC
  status: number; // 0=pending, 1=completed, 2=cancelled, 3=no_show_student, 4=no_show_barber
  scheduledTime: string;
  createdAt: string;
  completedAt?: string;
  cancelledAt?: string;
  reviewId?: string;
}

export interface BookingResponse {
  success: boolean;
  message?: string;
  txHash?: string;
  bookingDetails?: any;
}

class BlockchainBookingService {
  /**
   * Create a new booking (locks funds in smart contract escrow)
   * Returns optimistically - blockchain confirmation happens in background
   */
  async createBooking(data: CreateBookingData): Promise<BookingResponse> {
    try {
      const response = await axios.post<BookingResponse>(
        `${API_BASE_URL}/api/bookings-blockchain`,
        data,
        {
          headers: { 'Content-Type': 'application/json' },
          timeout: 30000, // Blockchain tx timeout
        }
      );

      return response.data;
    } catch (error: any) {
      console.error('Create booking error:', error);
      return {
        success: false,
        message: error.response?.data?.message || 'Failed to create booking. Please try again.',
      };
    }
  }

  /**
   * Get user's bookings (from blockchain events)
   */
  async getUserBookings(): Promise<{ success: boolean; bookings?: Booking[]; message?: string }> {
    try {
      const response = await axios.get(`${API_BASE_URL}/api/bookings-blockchain`, {
        timeout: 15000,
      });

      return {
        success: true,
        bookings: response.data.bookings || [],
      };
    } catch (error: any) {
      console.error('Get bookings error:', error);
      return {
        success: false,
        message: error.response?.data?.message || 'Failed to fetch bookings.',
      };
    }
  }

  /**
   * Complete booking (releases funds to barber)
   */
  async completeBooking(bookingId: string): Promise<BookingResponse> {
    try {
      const response = await axios.post<BookingResponse>(
        `${API_BASE_URL}/api/bookings-blockchain/${bookingId}/complete`,
        { bookingId },
        { timeout: 30000 }
      );

      return response.data;
    } catch (error: any) {
      console.error('Complete booking error:', error);
      return {
        success: false,
        message: error.response?.data?.message || 'Failed to complete booking.',
      };
    }
  }

  /**
   * Cancel booking (refunds student automatically)
   */
  async cancelBooking(bookingId: string, reason: string): Promise<BookingResponse> {
    try {
      const response = await axios.post<BookingResponse>(
        `${API_BASE_URL}/api/bookings-blockchain/${bookingId}/cancel`,
        { bookingId, reason },
        { timeout: 30000 }
      );

      return response.data;
    } catch (error: any) {
      console.error('Cancel booking error:', error);
      return {
        success: false,
        message: error.response?.data?.message || 'Failed to cancel booking.',
      };
    }
  }

  /**
   * Get booking status display text
   */
  getStatusText(status: number): string {
    const statusMap: Record<number, string> = {
      0: 'Pending',
      1: 'Completed',
      2: 'Cancelled',
      3: 'No Show (Student)',
      4: 'No Show (Barber)',
    };
    return statusMap[status] || 'Unknown';
  }

  /**
   * Get booking status color for UI
   */
  getStatusColor(status: number): string {
    const colorMap: Record<number, string> = {
      0: 'yellow', // pending
      1: 'green', // completed
      2: 'gray', // cancelled
      3: 'red', // no show student
      4: 'red', // no show barber
    };
    return colorMap[status] || 'gray';
  }
}

// Singleton instance
export const blockchainBookingService = new BlockchainBookingService();
export default blockchainBookingService;

