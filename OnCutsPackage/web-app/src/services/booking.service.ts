import api from './api.service';
import type { Booking, PaginatedResponse } from '../types';

interface CreateBookingData {
  barber_id: string;
  service_id?: string;
  service_name: string;
  service_price: number;
  scheduled_time: string;
  duration_minutes: number;
  location: string;
  special_requests?: string;
}

class BookingService {
  async createBooking(data: CreateBookingData): Promise<Booking> {
    return await api.post<Booking>('/bookings', data);
  }

  async getBookingById(id: string): Promise<Booking> {
    return await api.get<Booking>(`/bookings/${id}`);
  }

  async getStudentBookings(studentId: string, status?: string): Promise<PaginatedResponse<Booking>> {
    return await api.get<PaginatedResponse<Booking>>(`/bookings/student/${studentId}`, { status });
  }

  async getBarberBookings(barberId: string, status?: string, date?: string): Promise<PaginatedResponse<Booking>> {
    return await api.get<PaginatedResponse<Booking>>(`/bookings/barber/${barberId}`, { status, date });
  }

  async updateBooking(id: string, data: Partial<Booking>): Promise<Booking> {
    return await api.put<Booking>(`/bookings/${id}`, data);
  }

  async confirmBooking(id: string): Promise<Booking> {
    return await api.put<Booking>(`/bookings/${id}`, { status: 'confirmed' });
  }

  async completeBooking(id: string): Promise<Booking> {
    return await api.put<Booking>(`/bookings/${id}`, { status: 'completed' });
  }

  async cancelBooking(id: string, reason?: string): Promise<Booking> {
    return await api.put<Booking>(`/bookings/${id}`, { status: 'cancelled', cancellation_reason: reason });
  }

  async getUpcomingBookings(userId: string, userType: 'student' | 'barber'): Promise<Booking[]> {
    const endpoint = userType === 'student' 
      ? `/bookings/student/${userId}` 
      : `/bookings/barber/${userId}`;
    
    const response = await api.get<PaginatedResponse<Booking>>(endpoint, { 
      status: 'confirmed',
      upcoming: true 
    });
    return response.data;
  }
}

export default new BookingService();

