export interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  campusId: number;
  role: 'student' | 'barber' | 'campus_manager' | 'admin';
  suiAddress?: string;
  /** Pre-Sui custodial hex id (DB: legacy_wallet_address) */
  legacyWalletAddress?: string;
  emailVerified: boolean;
  studentIdVerified: boolean;
  createdAt: Date;
  isActive: boolean;
}

export interface Service {
  id?: string;
  name: string;
  description?: string;
  price: number;
  duration_minutes: number;
}

export interface Barber {
  id: string;
  userId: string;
  bio: string;
  specialties: string[];
  profileImageUrl?: string;
  pricing: Service[] | Record<string, number>; // Support both formats
  averageResponseTime?: number;
  totalEarnings: number;
  totalBookings: number;
  averageRating: number;
  yearsExperience?: number;
  suiAddress?: string;
  legacyWalletAddress?: string;
  createdAt: Date;
}

export interface Booking {
  id: string;
  blockchainBookingId: number;
  barberId: string;
  clientId: string;
  locationDetails?: string;
  specialRequests?: string;
  reminderSent: boolean;
  notificationSent: boolean;
  createdAt: Date;
}

export interface Review {
  id: string;
  blockchainReviewId: number;
  bookingId: number;
  reviewText: string;
  images?: string[];
  helpfulCount: number;
  createdAt: Date;
}

export interface Payment {
  id: string;
  blockchainPaymentId: number;
  bookingId: number;
  stripePaymentIntentId: string;
  stripeTransferId?: string;
  barberId: string;
  clientId: string;
  amount: number;
  platformFee: number;
  barberPayout: number;
  tipAmount: number;
  status: 'pending' | 'succeeded' | 'refunded' | 'failed';
  createdAt: Date;
}

export interface Campus {
  id: number;
  name: string;
  domain: string;
  city: string;
  state: string;
  country: string;
  timezone: string;
  isActive: boolean;
}

export interface PortfolioImage {
  id: string;
  barberId: string;
  imageUrl: string;
  caption?: string;
  orderIndex: number;
  createdAt: Date;
}

export interface AvailabilitySlot {
  id: string;
  barberId: string;
  dayOfWeek: number; // 0-6 (Sunday-Saturday)
  startTime: string; // HH:MM format
  endTime: string;
  isActive: boolean;
}

export interface ChatMessage {
  id: string;
  bookingId: number;
  senderId: string;
  receiverId: string;
  message: string;
  isRead: boolean;
  timestamp: Date;
}

export interface Notification {
  id: string;
  userId: string;
  type: string;
  title: string;
  message: string;
  data?: any;
  isRead: boolean;
  createdAt: Date;
}

// Extend Express Request type to include authenticated user
declare global {
  namespace Express {
    interface Request {
      user?: {
        userId: string;
        email: string;
        role: 'student' | 'barber' | 'campus_manager' | 'admin';
        campusId: number;
      };
    }
  }
}

