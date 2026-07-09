export interface User {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  username?: string;
  user_type: 'student' | 'barber' | 'campus_manager' | 'admin';
  /** Native zkLogin Sui address when linked */
  sui_address?: string | null;
  campus_id?: string;
  is_verified: boolean;
  is_admin?: boolean;
  is_campus_manager?: boolean;
  has_barber_profile?: boolean;
  profile_picture_url?: string;
  bio?: string;
  created_at: string;
  // Location tracking
  latitude?: number;
  longitude?: number;
  location_updated_at?: string;
  location_permission?: 'granted' | 'denied' | 'prompt' | 'unavailable';
}

export interface Campus {
  id: string;
  name: string;
  slug?: string;
  shortName?: string; // Common abbreviation (e.g., "UCLA", "MIT") - derived from slug
  domain: string;
  city: string;
  state: string;
  country?: string;
  timezone?: string;
  is_active?: boolean;
  latitude?: number;
  longitude?: number;
}

// Time interval for availability (Calendly-style)
export interface TimeInterval {
  id: string;
  start: string; // "09:00" (24-hour format)
  end: string; // "17:00" (24-hour format)
}

// Day schedule with multiple intervals (Calendly-style)
export interface DaySchedule {
  enabled: boolean;
  intervals: TimeInterval[]; // Multiple time ranges per day
  // Legacy single interval support for backwards compatibility
  start?: string;
  end?: string;
}

export interface WeeklySchedule {
  monday: DaySchedule;
  tuesday: DaySchedule;
  wednesday: DaySchedule;
  thursday: DaySchedule;
  friday: DaySchedule;
  saturday: DaySchedule;
  sunday: DaySchedule;
}

// Helper to migrate old format to new format
export const migrateDaySchedule = (day: DaySchedule): DaySchedule => {
  // If already has intervals, return as-is
  if (day.intervals && day.intervals.length > 0) {
    return day;
  }
  // Migrate legacy single interval format
  if (day.start && day.end && day.enabled) {
    return {
      enabled: true,
      intervals: [{
        id: crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substring(7),
        start: day.start,
        end: day.end
      }]
    };
  }
  // Disabled day
  return {
    enabled: false,
    intervals: []
  };
};

export interface ServiceLocation {
  id: string;
  name: string;
  description?: string;
  is_primary?: boolean;
}

export interface Review {
  id: string;
  rating: number;
  review_text?: string;
  created_at: string;
  first_name?: string;
  last_name?: string;
  profile_picture_url?: string;
  service_name?: string;
}

export interface Barber {
  id: string;
  user_id: string;
  user?: User;
  name?: string; // Computed: display_name or first_name + last_name
  display_name?: string;
  first_name?: string;
  last_name?: string;
  bio: string;
  instagram_handle?: string;
  specialties: string[];
  years_experience: number;
  years_of_experience?: number; // Alias for backwards compatibility
  pricing: Service[];
  total_bookings: number;
  total_reviews?: number;
  is_active: boolean;
  profile_photo_url?: string;
  profile_picture_url?: string; // Alias from users table join
  portfolio?: PortfolioImage[];
  portfolio_images?: PortfolioImage[]; // Alias for backwards compatibility
  availability?: AvailabilityTemplate[];
  weekly_schedule?: WeeklySchedule; // Recurring weekly availability
  sui_address?: string;
  campus_id?: string;
  // Location fields
  service_latitude?: number;
  service_longitude?: number;
  service_radius_km?: number;
  user_latitude?: number; // Barber's user location (fallback)
  user_longitude?: number;
  distance_km?: number; // Calculated distance from user (when location provided)
  distance_miles?: number; // Distance in miles
  service_locations?: ServiceLocation[]; // Barber's available service locations
  average_rating?: number; // Average rating from submitted reviews
  review_count?: number; // Total number of submitted reviews
  reviews?: Review[]; // Recent reviews
}

export interface PortfolioImage {
  id: string;
  barber_id: string;
  url: string;
  image_url?: string; // Alias for backwards compatibility
  thumbnail_url?: string;
  order_index?: number;
  created_at?: string;
}

export interface Service {
  id?: string;
  name: string;
  description?: string;
  price: number;
  duration_minutes?: number; // Optional for custom barber pricing
}

export interface AvailabilityTemplate {
  id: string;
  barber_id: string;
  day_of_week: number; // 0 = Sunday, 6 = Saturday
  start_time: string; // "09:00"
  end_time: string; // "17:00"
  is_active: boolean;
}

export interface Booking {
  id: string;
  student_id: string;
  barber_id: string;
  service_id?: string;
  service_name: string;
  service_price: number;
  scheduled_time: string;
  duration_minutes: number;
  location: string;
  status: 'pending' | 'confirmed' | 'completed' | 'cancelled';
  special_requests?: string;
  student?: User;
  barber?: Barber;
  created_at: string;
  updated_at: string;
}

export interface Review {
  id: string;
  booking_id: string;
  barber_id: string;
  student_id: string;
  rating: number; // 1-5
  review_text?: string;
  student?: User;
  created_at: string;
}

export interface Conversation {
  id: string;
  user1_id: string;
  user2_id: string;
  booking_id?: string;
  last_message?: Message;
  last_message_at?: string;
  unread_count?: number;
  other_user?: User;
  is_active: boolean;
  created_at: string;
}

export interface Message {
  id: string;
  conversation_id: string;
  sender_id: string;
  content: string;
  message_type: 'text' | 'image' | 'system';
  media_url?: string;
  is_read: boolean;
  sender?: User;
  created_at: string;
}

export interface PaymentIntent {
  client_secret: string;
  amount: number;
  booking_id: string;
}

export interface EarningsReport {
  total_earnings: number;
  total_tips: number;
  total_bookings: number;
  period: {
    start: string;
    end: string;
  };
  daily_breakdown?: Array<{
    date: string;
    earnings: number;
    tips: number;
    bookings: number;
  }>;
}

export interface NotificationPreferences {
  messages: boolean;
  bookings: boolean;
  reviews: boolean;
  system: boolean;
  marketing: boolean;
  quietHours: {
    enabled: boolean;
    start: string;
    end: string;
  };
}

export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  message?: string;
  error?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    total_pages: number;
  };
}

// Blockchain / Wallet Types
export interface Balance {
  available: number;
  locked: number;
  total: number;
  availableUsd?: number;
  lockedUsd?: number;
  totalUsd?: number;
}

