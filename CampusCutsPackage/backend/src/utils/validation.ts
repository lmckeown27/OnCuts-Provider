/**
 * Comprehensive Validation Utilities
 */

import Joi from 'joi';

// Email validation with .edu domain support
export const emailSchema = Joi.string()
  .email()
  .lowercase()
  .trim()
  .max(255)
  .required();

export const eduEmailSchema = Joi.string()
  .email()
  .lowercase()
  .trim()
  .pattern(/\.edu$/)
  .message('Must be a valid .edu email address')
  .required();

// Password validation
export const passwordSchema = Joi.string()
  .min(8)
  .max(128)
  .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
  .message('Password must contain at least one uppercase letter, one lowercase letter, and one number')
  .required();

// User schemas
export const userRegistrationSchema = Joi.object({
  email: eduEmailSchema,
  password: passwordSchema,
  first_name: Joi.string().trim().min(1).max(50).required(),
  last_name: Joi.string().trim().min(1).max(50).required(),
  user_type: Joi.string().valid('student', 'barber').required(),
  campus_id: Joi.string().uuid().optional(),
});

export const userLoginSchema = Joi.object({
  email: emailSchema,
  password: Joi.string().required(),
});

// Barber schemas
export const barberProfileSchema = Joi.object({
  bio: Joi.string().min(10).max(500).required(),
  specialties: Joi.array().items(Joi.string().max(50)).min(1).max(10).required(),
  years_of_experience: Joi.number().integer().min(0).max(50).required(),
  base_price: Joi.number().min(0).max(1000).required(),
  sui_address: Joi.string().pattern(/^0x[a-fA-F0-9]{64}$/).optional(),
  legacy_wallet_address: Joi.string().pattern(/^0x[a-fA-F0-9]{64}$/).optional(),
});

// Booking schemas
export const createBookingSchema = Joi.object({
  barber_id: Joi.string().uuid().required(),
  service_name: Joi.string().min(1).max(100).required(),
  service_price: Joi.number().min(0).max(1000).required(),
  scheduled_at: Joi.date().iso().greater('now').required(),
  duration_minutes: Joi.number().integer().min(15).max(480).required(),
  location: Joi.string().min(1).max(200).required(),
  notes: Joi.string().max(500).optional(),
});

export const updateBookingSchema = Joi.object({
  status: Joi.string().valid('pending', 'confirmed', 'completed', 'cancelled', 'no_show').required(),
  cancellation_reason: Joi.string().max(200).when('status', {
    is: 'cancelled',
    then: Joi.required(),
    otherwise: Joi.optional(),
  }),
});

// Review schemas
export const createReviewSchema = Joi.object({
  booking_id: Joi.string().uuid().required(),
  rating: Joi.number().integer().min(1).max(5).required(),
  comment: Joi.string().min(10).max(500).required(),
  service_quality: Joi.number().integer().min(1).max(5).optional(),
  professionalism: Joi.number().integer().min(1).max(5).optional(),
  cleanliness: Joi.number().integer().min(1).max(5).optional(),
  value_for_money: Joi.number().integer().min(1).max(5).optional(),
});

// Payment schemas
export const createPaymentSchema = Joi.object({
  booking_id: Joi.string().uuid().required(),
  amount: Joi.number().min(0).max(100000).required(),
  payment_method: Joi.string().valid('card', 'apple_pay', 'google_pay').required(),
  stripe_payment_intent_id: Joi.string().required(),
});

// Campus schemas
export const createCampusSchema = Joi.object({
  name: Joi.string().min(1).max(200).required(),
  domain: Joi.string().pattern(/\.edu$/).required(),
  city: Joi.string().min(1).max(100).required(),
  state: Joi.string().length(2).uppercase().required(),
  country: Joi.string().length(3).uppercase().default('USA'),
  timezone: Joi.string().required(),
});

// Message schemas
export const sendMessageSchema = Joi.object({
  recipient_id: Joi.string().uuid().required(),
  message_type: Joi.string().valid('text', 'image', 'system').default('text'),
  content: Joi.string().min(1).max(2000).when('message_type', {
    is: 'text',
    then: Joi.required(),
    otherwise: Joi.optional(),
  }),
  media_url: Joi.string().uri().when('message_type', {
    is: 'image',
    then: Joi.required(),
    otherwise: Joi.optional(),
  }),
});

// Availability schemas
export const availabilityTemplateSchema = Joi.object({
  day_of_week: Joi.number().integer().min(0).max(6).required(),
  start_time: Joi.string().pattern(/^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/).required(),
  end_time: Joi.string().pattern(/^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/).required(),
  is_available: Joi.boolean().default(true),
});

// Pagination schemas
export const paginationSchema = Joi.object({
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(100).default(20),
  sort_by: Joi.string().optional(),
  sort_order: Joi.string().valid('asc', 'desc').default('desc'),
});

// Query filter schemas
export const barberFilterSchema = Joi.object({
  campus_id: Joi.string().uuid().optional(),
  min_rating: Joi.number().min(0).max(5).optional(),
  max_price: Joi.number().min(0).optional(),
  specialties: Joi.array().items(Joi.string()).optional(),
  available_on: Joi.date().iso().optional(),
}).concat(paginationSchema);

export const bookingFilterSchema = Joi.object({
  status: Joi.string().valid('pending', 'confirmed', 'completed', 'cancelled', 'no_show').optional(),
  start_date: Joi.date().iso().optional(),
  end_date: Joi.date().iso().optional(),
}).concat(paginationSchema);

// Sanitization helpers
export const sanitizeString = (input: string): string => {
  return input
    .trim()
    .replace(/<[^>]*>/g, '') // Remove HTML tags
    .replace(/[^\w\s.,!?@#$%&*()-]/g, ''); // Remove special chars except common punctuation
};

export const sanitizeObject = (obj: any): any => {
  const sanitized: any = {};
  for (const key in obj) {
    if (typeof obj[key] === 'string') {
      sanitized[key] = sanitizeString(obj[key]);
    } else if (typeof obj[key] === 'object' && obj[key] !== null) {
      sanitized[key] = sanitizeObject(obj[key]);
    } else {
      sanitized[key] = obj[key];
    }
  }
  return sanitized;
};

/** 32-byte hex chain id (Sui / legacy custodial) */
export const isValidMoveHexWallet = (address: string): boolean => {
  return /^0x[a-fA-F0-9]{64}$/.test(address);
};

// UUID validation
export const isValidUUID = (uuid: string): boolean => {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(uuid);
};

// Date validation helpers
export const isValidFutureDate = (date: Date): boolean => {
  return date.getTime() > Date.now();
};

export const isValidDateRange = (startDate: Date, endDate: Date): boolean => {
  return startDate.getTime() < endDate.getTime();
};

// Export all schemas as a single object
export const schemas = {
  // User
  userRegistration: userRegistrationSchema,
  userLogin: userLoginSchema,
  
  // Barber
  barberProfile: barberProfileSchema,
  
  // Booking
  createBooking: createBookingSchema,
  updateBooking: updateBookingSchema,
  bookingFilter: bookingFilterSchema,
  
  // Review
  createReview: createReviewSchema,
  
  // Payment
  createPayment: createPaymentSchema,
  
  // Campus
  createCampus: createCampusSchema,
  
  // Message
  sendMessage: sendMessageSchema,
  
  // Availability
  availabilityTemplate: availabilityTemplateSchema,
  
  // Filters
  barberFilter: barberFilterSchema,
  
  // Pagination
  pagination: paginationSchema,
};

