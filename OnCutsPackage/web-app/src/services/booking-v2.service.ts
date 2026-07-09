/**
 * Booking Service V2 — /api/v2/bookings (Stripe Checkout + Sui settlement)
 */

import axios, { AxiosInstance } from 'axios';
import { getBackendOrigin, STORAGE_KEYS } from '../config/constants';

function bookingsV2Client(): AxiosInstance {
  const token = localStorage.getItem(STORAGE_KEYS.ACCESS_TOKEN);
  return axios.create({
    baseURL: `${getBackendOrigin()}/api/v2/bookings`,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      'Content-Type': 'application/json',
    },
  });
}

export interface BookingV2 {
  id: string;
  consumer_id: string;
  barber_id: string;
  service_id?: string;
  price_cents: number;
  tip_cents?: number;
  requested_slot: string;
  status: 'pending' | 'confirmed' | 'completed' | 'cancelled' | 'disputed';
  created_at: string;
  completed_at?: string;
  cancelled_at?: string;
  consumer_first_name?: string;
  consumer_last_name?: string;
  barber_first_name?: string;
  barber_last_name?: string;
  escrow_status?: 'held' | 'released' | 'refunded' | 'expired';
  escrow_amount?: number;
  escrow_expires_at?: string;
}

export interface CreateBookingPayment {
  checkoutUrl: string;
  sessionId: string;
  amountCents: number;
}

export interface CreateBookingResponse {
  booking: BookingV2;
  payment: CreateBookingPayment;
}

export interface CompleteBookingResponse {
  booking_id: string;
  status: string;
  net_to_barber_dollars: number;
  platform_fee_dollars: number;
  tip_dollars: number;
}

export interface CancelBookingResponse {
  booking_id: string;
  status: string;
  refund_amount_dollars: number;
}

class BookingV2Service {
  async createBooking(params: {
    barberId: string;
    serviceId?: string;
    priceCents: number;
    requestedSlot: string;
    locationDetails?: string;
    specialRequests?: string;
  }): Promise<CreateBookingResponse> {
    const res = await bookingsV2Client().post<{ success: boolean; data: CreateBookingResponse }>(
      '/',
      params
    );
    return res.data.data;
  }

  async getCheckoutSettlement(sessionId: string) {
    const res = await bookingsV2Client().get<{ success: boolean; data: unknown }>(
      `/checkout-session/${encodeURIComponent(sessionId)}/settlement`
    );
    return res.data.data;
  }

  async getBookings(status?: string): Promise<BookingV2[]> {
    const res = await bookingsV2Client().get<{ success: boolean; data: BookingV2[] }>('/', {
      params: status ? { status } : {},
    });
    return res.data.data;
  }

  async getBookingById(bookingId: string): Promise<BookingV2> {
    const res = await bookingsV2Client().get<{ success: boolean; data: BookingV2 }>(`/${bookingId}`);
    return res.data.data;
  }

  async completeBooking(bookingId: string, tipCents?: number): Promise<CompleteBookingResponse> {
    const res = await bookingsV2Client().post<{ success: boolean; data: CompleteBookingResponse }>(
      `/${bookingId}/complete`,
      { tipCents }
    );
    return res.data.data;
  }

  async cancelBooking(bookingId: string, reason: string): Promise<CancelBookingResponse> {
    const res = await bookingsV2Client().post<{ success: boolean; data: CancelBookingResponse }>(
      `/${bookingId}/cancel`,
      { reason }
    );
    return res.data.data;
  }
}

export default new BookingV2Service();
