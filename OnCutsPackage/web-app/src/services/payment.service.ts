import api from './api.service';
import { PaymentIntent, EarningsReport } from '../types';

interface CreatePaymentIntentData {
  booking_id: string;
  amount: number;
}

class PaymentService {
  async createPaymentIntent(data: CreatePaymentIntentData): Promise<PaymentIntent> {
    return await api.post<PaymentIntent>('/payments/create-intent', data);
  }

  async confirmPayment(paymentIntentId: string, bookingId: string): Promise<any> {
    return await api.post('/payments/confirm', {
      payment_intent_id: paymentIntentId,
      booking_id: bookingId,
    });
  }

  async requestRefund(bookingId: string, reason: string): Promise<any> {
    return await api.post('/payments/refund', {
      booking_id: bookingId,
      reason,
    });
  }

  async getBarberEarnings(barberId: string, period: 'daily' | 'weekly' | 'monthly' = 'monthly', startDate?: string, endDate?: string): Promise<EarningsReport> {
    return await api.get<EarningsReport>(`/payments/barber/${barberId}/earnings`, {
      period,
      start_date: startDate,
      end_date: endDate,
    });
  }

  async getPaymentHistory(userId: string, userType: 'student' | 'barber'): Promise<any[]> {
    const endpoint = userType === 'student'
      ? `/payments/student/${userId}/history`
      : `/payments/barber/${userId}/history`;
    
    return await api.get<any[]>(endpoint);
  }
}

export default new PaymentService();

