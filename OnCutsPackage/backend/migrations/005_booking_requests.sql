-- Booking Request System (AirBnb-style)
-- Migration: 005
-- Description: Adds booking request workflow, customer profiles, and pre/post booking messaging

-- ============================================================
-- BOOKING STATUS UPDATES
-- ============================================================

-- Add new booking statuses for request workflow
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name='bookings' AND column_name='status') THEN
    ALTER TABLE bookings ADD COLUMN status TEXT DEFAULT 'pending';
  END IF;
END $$;

-- Possible statuses: pending, accepted, rejected, completed, cancelled, disputed

-- Add requested_at and responded_at timestamps
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name='bookings' AND column_name='requested_at') THEN
    ALTER TABLE bookings 
      ADD COLUMN requested_at TIMESTAMP DEFAULT NOW(),
      ADD COLUMN responded_at TIMESTAMP,
      ADD COLUMN rejection_reason TEXT;
  END IF;
END $$;

-- ============================================================
-- CUSTOMER PROFILES (for barber view)
-- ============================================================

CREATE TABLE IF NOT EXISTS customer_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT,
  bio TEXT,
  profile_image_url TEXT,
  verified BOOLEAN DEFAULT false,
  
  -- Stats for barbers to see
  total_bookings INT DEFAULT 0,
  completed_bookings INT DEFAULT 0,
  cancelled_bookings INT DEFAULT 0,
  no_show_count INT DEFAULT 0,
  
  -- Ratings (from barbers)
  avg_rating NUMERIC(3, 2) DEFAULT 0,
  total_reviews INT DEFAULT 0,
  
  -- Behavior flags
  is_reliable BOOLEAN DEFAULT true,
  response_rate NUMERIC(5, 2) DEFAULT 100,
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- CUSTOMER REVIEWS (from barbers about customers)
-- ============================================================

CREATE TABLE IF NOT EXISTS customer_reviews (
  review_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID REFERENCES users(id) ON DELETE CASCADE,
  barber_id UUID REFERENCES barbers(barber_id) ON DELETE CASCADE,
  booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
  
  rating INT CHECK (rating >= 1 AND rating <= 5),
  showed_up BOOLEAN,
  was_on_time BOOLEAN,
  was_respectful BOOLEAN,
  comment TEXT,
  
  created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- BOOKING MESSAGES (pre and post booking)
-- ============================================================

CREATE TABLE IF NOT EXISTS booking_messages (
  message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
  sender_type TEXT CHECK (sender_type IN ('barber', 'customer')),
  
  message TEXT NOT NULL,
  message_type TEXT DEFAULT 'text', -- 'text', 'image', 'system'
  
  read BOOLEAN DEFAULT false,
  read_at TIMESTAMP,
  
  created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- BOOKING REQUEST NOTIFICATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS booking_request_notifications (
  notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
  
  type TEXT CHECK (type IN ('new_request', 'accepted', 'rejected', 'new_message', 'reminder')),
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  
  read BOOLEAN DEFAULT false,
  read_at TIMESTAMP,
  
  created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_barber_pending ON bookings(barber_id, status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_bookings_customer ON bookings(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_reviews_customer ON customer_reviews(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_reviews_barber ON customer_reviews(barber_id);
CREATE INDEX IF NOT EXISTS idx_booking_messages_booking ON booking_messages(booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_messages_unread ON booking_messages(booking_id, read) WHERE read = false;
CREATE INDEX IF NOT EXISTS idx_booking_notifications_user_unread ON booking_request_notifications(user_id, read) WHERE read = false;

-- ============================================================
-- UPDATE EXISTING BOOKINGS
-- ============================================================

-- Set status for existing bookings
UPDATE bookings 
SET status = CASE
  WHEN completed = true THEN 'completed'
  ELSE 'accepted'
END
WHERE status IS NULL;

-- ============================================================
-- TRIGGERS
-- ============================================================

-- Auto-create customer profile when user signs up as customer
CREATE OR REPLACE FUNCTION create_customer_profile()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role = 0 OR NEW.role IS NULL THEN -- role 0 = customer
    INSERT INTO customer_profiles (user_id, display_name)
    VALUES (NEW.id, NEW.name)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_customer_profile ON users;
CREATE TRIGGER trigger_create_customer_profile
  AFTER INSERT ON users
  FOR EACH ROW
  EXECUTE FUNCTION create_customer_profile();

-- Update customer stats after booking completion
CREATE OR REPLACE FUNCTION update_customer_stats()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    UPDATE customer_profiles
    SET 
      completed_bookings = completed_bookings + 1,
      total_bookings = total_bookings + 1,
      updated_at = NOW()
    WHERE user_id = NEW.customer_id;
  END IF;
  
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    UPDATE customer_profiles
    SET 
      cancelled_bookings = cancelled_bookings + 1,
      updated_at = NOW()
    WHERE user_id = NEW.customer_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_customer_stats ON bookings;
CREATE TRIGGER trigger_update_customer_stats
  AFTER UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION update_customer_stats();

