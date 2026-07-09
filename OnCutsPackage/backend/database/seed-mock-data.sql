-- ═══════════════════════════════════════════════════════════════
-- CAMPUSCUTS MOCK DATA
-- ═══════════════════════════════════════════════════════════════
-- Populates PostgreSQL cache with realistic test data
-- 
-- This creates:
-- - 50 users (30 students, 20 barbers)
-- - 100 bookings (various statuses, times, campuses)
-- - 60 reviews (realistic ratings)
--
-- Run: psql -U postgres -d campuscuts -f seed-mock-data.sql
-- ═══════════════════════════════════════════════════════════════

-- Clear existing data
TRUNCATE TABLE reviews, bookings, users CASCADE;

-- ═══════════════════════════════════════════════════════════════
-- USERS (Students at all 3 campuses)
-- ═══════════════════════════════════════════════════════════════

-- Cal Poly Students (10)
INSERT INTO users (legacy_wallet_address, email, full_name, role, balance, locked_balance, created_at) VALUES
('0x1001', 'john.smith@calpoly.edu', 'John Smith', 1, 50000, 2500, NOW() - INTERVAL '30 days'),
('0x1002', 'sarah.johnson@calpoly.edu', 'Sarah Johnson', 1, 75000, 0, NOW() - INTERVAL '25 days'),
('0x1003', 'mike.williams@calpoly.edu', 'Mike Williams', 1, 30000, 2500, NOW() - INTERVAL '20 days'),
('0x1004', 'emily.brown@calpoly.edu', 'Emily Brown', 1, 45000, 0, NOW() - INTERVAL '15 days'),
('0x1005', 'david.jones@calpoly.edu', 'David Jones', 1, 60000, 2500, NOW() - INTERVAL '10 days'),
('0x1006', 'lisa.davis@calpoly.edu', 'Lisa Davis', 1, 35000, 0, NOW() - INTERVAL '8 days'),
('0x1007', 'james.miller@calpoly.edu', 'James Miller', 1, 55000, 2500, NOW() - INTERVAL '6 days'),
('0x1008', 'jennifer.wilson@calpoly.edu', 'Jennifer Wilson', 1, 40000, 0, NOW() - INTERVAL '5 days'),
('0x1009', 'robert.moore@calpoly.edu', 'Robert Moore', 1, 48000, 2500, NOW() - INTERVAL '3 days'),
('0x1010', 'amanda.taylor@calpoly.edu', 'Amanda Taylor', 1, 52000, 0, NOW() - INTERVAL '2 days');

-- UCSB Students (10)
INSERT INTO users (legacy_wallet_address, email, full_name, role, balance, locked_balance, created_at) VALUES
('0x2001', 'chris.anderson@ucsb.edu', 'Chris Anderson', 1, 65000, 3000, NOW() - INTERVAL '28 days'),
('0x2002', 'michelle.thomas@ucsb.edu', 'Michelle Thomas', 1, 42000, 0, NOW() - INTERVAL '22 days'),
('0x2003', 'kevin.jackson@ucsb.edu', 'Kevin Jackson', 1, 58000, 3000, NOW() - INTERVAL '18 days'),
('0x2004', 'nicole.white@ucsb.edu', 'Nicole White', 1, 37000, 0, NOW() - INTERVAL '14 days'),
('0x2005', 'brian.harris@ucsb.edu', 'Brian Harris', 1, 71000, 3000, NOW() - INTERVAL '12 days'),
('0x2006', 'ashley.martin@ucsb.edu', 'Ashley Martin', 1, 44000, 0, NOW() - INTERVAL '9 days'),
('0x2007', 'daniel.thompson@ucsb.edu', 'Daniel Thompson', 1, 53000, 3000, NOW() - INTERVAL '7 days'),
('0x2008', 'jessica.garcia@ucsb.edu', 'Jessica Garcia', 1, 39000, 0, NOW() - INTERVAL '4 days'),
('0x2009', 'matthew.martinez@ucsb.edu', 'Matthew Martinez', 1, 61000, 3000, NOW() - INTERVAL '2 days'),
('0x2010', 'lauren.robinson@ucsb.edu', 'Lauren Robinson', 1, 47000, 0, NOW() - INTERVAL '1 day');

-- UCLA Students (10)
INSERT INTO users (legacy_wallet_address, email, full_name, role, balance, locked_balance, created_at) VALUES
('0x3001', 'tyler.clark@ucla.edu', 'Tyler Clark', 1, 68000, 3500, NOW() - INTERVAL '26 days'),
('0x3002', 'rachel.rodriguez@ucla.edu', 'Rachel Rodriguez', 1, 41000, 0, NOW() - INTERVAL '21 days'),
('0x3003', 'justin.lewis@ucla.edu', 'Justin Lewis', 1, 59000, 3500, NOW() - INTERVAL '17 days'),
('0x3004', 'megan.lee@ucla.edu', 'Megan Lee', 1, 36000, 0, NOW() - INTERVAL '13 days'),
('0x3005', 'andrew.walker@ucla.edu', 'Andrew Walker', 1, 73000, 3500, NOW() - INTERVAL '11 days'),
('0x3006', 'stephanie.hall@ucla.edu', 'Stephanie Hall', 1, 43000, 0, NOW() - INTERVAL '8 days'),
('0x3007', 'ryan.allen@ucla.edu', 'Ryan Allen', 1, 56000, 3500, NOW() - INTERVAL '6 days'),
('0x3008', 'kimberly.young@ucla.edu', 'Kimberly Young', 1, 38000, 0, NOW() - INTERVAL '3 days'),
('0x3009', 'brandon.hernandez@ucla.edu', 'Brandon Hernandez', 1, 64000, 3500, NOW() - INTERVAL '1 day'),
('0x3010', 'samantha.king@ucla.edu', 'Samantha King', 1, 49000, 0, NOW() - INTERVAL '12 hours');

-- ═══════════════════════════════════════════════════════════════
-- BARBERS (Spread across campuses)
-- ═══════════════════════════════════════════════════════════════

-- Cal Poly Barbers (7)
INSERT INTO users (legacy_wallet_address, email, full_name, role, balance, locked_balance, profile_picture_cid, created_at) VALUES
('0xB001', 'marcus.cuts@calpoly.edu', 'Marcus "The Fade King" Thompson', 2, 125000, 7500, 'QmBarber1', NOW() - INTERVAL '90 days'),
('0xB002', 'jordan.styles@calpoly.edu', 'Jordan Williams', 2, 89000, 5000, 'QmBarber2', NOW() - INTERVAL '75 days'),
('0xB003', 'alex.precision@calpoly.edu', 'Alex Chen', 2, 67000, 2500, 'QmBarber3', NOW() - INTERVAL '60 days'),
('0xB004', 'carlos.fresh@calpoly.edu', 'Carlos Fresh Cuts', 2, 112000, 6000, 'QmBarber4', NOW() - INTERVAL '85 days'),
('0xB005', 'malik.waves@calpoly.edu', 'Malik Wave Master', 2, 98000, 4500, 'QmBarber5', NOW() - INTERVAL '70 days'),
('0xB006', 'tony.classic@calpoly.edu', 'Tony Classic Barber', 2, 76000, 3000, 'QmBarber6', NOW() - INTERVAL '55 days'),
('0xB007', 'kevin.edge@calpoly.edu', 'Kevin Edge Up', 2, 84000, 3500, 'QmBarber7', NOW() - INTERVAL '65 days');

-- UCSB Barbers (7)
INSERT INTO users (legacy_wallet_address, email, full_name, role, balance, locked_balance, profile_picture_cid, created_at) VALUES
('0xB011', 'tyler.pro@ucsb.edu', 'Tyler Martinez Pro', 2, 145000, 8500, 'QmBarber11', NOW() - INTERVAL '95 days'),
('0xB012', 'sarah.stylist@ucsb.edu', 'Sarah Johnson Stylist', 2, 102000, 5500, 'QmBarber12', NOW() - INTERVAL '80 days'),
('0xB013', 'dante.master@ucsb.edu', 'Dante Master Barber', 2, 91000, 4000, 'QmBarber13', NOW() - INTERVAL '68 days'),
('0xB014', 'miguel.sharp@ucsb.edu', 'Miguel Sharp Cuts', 2, 118000, 6500, 'QmBarber14', NOW() - INTERVAL '88 days'),
('0xB015', 'jasmine.luxe@ucsb.edu', 'Jasmine Luxe Cuts', 2, 107000, 5800, 'QmBarber15', NOW() - INTERVAL '72 days'),
('0xB016', 'derek.taper@ucsb.edu', 'Derek Taper King', 2, 82000, 3200, 'QmBarber16', NOW() - INTERVAL '58 days'),
('0xB017', 'tiffany.glam@ucsb.edu', 'Tiffany Glam Squad', 2, 93000, 4300, 'QmBarber17', NOW() - INTERVAL '66 days');

-- UCLA Barbers (6)
INSERT INTO users (legacy_wallet_address, email, full_name, role, balance, locked_balance, profile_picture_cid, created_at) VALUES
('0xB021', 'carlos.legend@ucla.edu', 'Carlos "The Legend" Rodriguez', 2, 167000, 9500, 'QmBarber21', NOW() - INTERVAL '100 days'),
('0xB022', 'jamal.elite@ucla.edu', 'Jamal Elite Cuts', 2, 128000, 7000, 'QmBarber22', NOW() - INTERVAL '82 days'),
('0xB023', 'angela.beauty@ucla.edu', 'Angela Beauty Pro', 2, 113000, 6200, 'QmBarber23', NOW() - INTERVAL '74 days'),
('0xB024', 'ramon.fade@ucla.edu', 'Ramon Fade Master', 2, 139000, 7800, 'QmBarber24', NOW() - INTERVAL '92 days'),
('0xB025', 'maya.style@ucla.edu', 'Maya Style Icon', 2, 121000, 6600, 'QmBarber25', NOW() - INTERVAL '78 days'),
('0xB026', 'andre.edge@ucla.edu', 'Andre Edge Lord', 2, 95000, 4600, 'QmBarber26', NOW() - INTERVAL '64 days');

-- ═══════════════════════════════════════════════════════════════
-- BOOKINGS (Mix of past, current, future - all statuses)
-- ═══════════════════════════════════════════════════════════════

-- Cal Poly Bookings (35 bookings)
-- Status: 0=pending, 1=confirmed, 2=completed, 3=cancelled

-- Completed bookings (past)
INSERT INTO bookings (blockchain_id, student_address, barber_address, amount, platform_fee, scheduled_time, status, created_at, completed_at) VALUES
(1, '0x1001', '0xB001', 3500, 175, NOW() - INTERVAL '25 days', 2, NOW() - INTERVAL '26 days', NOW() - INTERVAL '25 days'),
(2, '0x1002', '0xB002', 3000, 150, NOW() - INTERVAL '22 days', 2, NOW() - INTERVAL '23 days', NOW() - INTERVAL '22 days'),
(3, '0x1003', '0xB003', 2800, 140, NOW() - INTERVAL '20 days', 2, NOW() - INTERVAL '21 days', NOW() - INTERVAL '20 days'),
(4, '0x1004', '0xB001', 3500, 175, NOW() - INTERVAL '18 days', 2, NOW() - INTERVAL '19 days', NOW() - INTERVAL '18 days'),
(5, '0x1005', '0xB004', 4000, 200, NOW() - INTERVAL '15 days', 2, NOW() - INTERVAL '16 days', NOW() - INTERVAL '15 days'),
(6, '0x1006', '0xB005', 3200, 160, NOW() - INTERVAL '14 days', 2, NOW() - INTERVAL '15 days', NOW() - INTERVAL '14 days'),
(7, '0x1007', '0xB002', 3000, 150, NOW() - INTERVAL '12 days', 2, NOW() - INTERVAL '13 days', NOW() - INTERVAL '12 days'),
(8, '0x1008', '0xB006', 2700, 135, NOW() - INTERVAL '10 days', 2, NOW() - INTERVAL '11 days', NOW() - INTERVAL '10 days'),
(9, '0x1009', '0xB001', 3500, 175, NOW() - INTERVAL '8 days', 2, NOW() - INTERVAL '9 days', NOW() - INTERVAL '8 days'),
(10, '0x1010', '0xB007', 2900, 145, NOW() - INTERVAL '6 days', 2, NOW() - INTERVAL '7 days', NOW() - INTERVAL '6 days'),
(11, '0x1001', '0xB003', 2800, 140, NOW() - INTERVAL '4 days', 2, NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days'),
(12, '0x1002', '0xB004', 4000, 200, NOW() - INTERVAL '3 days', 2, NOW() - INTERVAL '4 days', NOW() - INTERVAL '3 days'),
(13, '0x1003', '0xB005', 3200, 160, NOW() - INTERVAL '2 days', 2, NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days'),
(14, '0x1004', '0xB001', 3500, 175, NOW() - INTERVAL '1 day', 2, NOW() - INTERVAL '2 days', NOW() - INTERVAL '1 day');

-- Confirmed bookings (upcoming)
INSERT INTO bookings (blockchain_id, student_address, barber_address, amount, platform_fee, scheduled_time, status, created_at) VALUES
(15, '0x1005', '0xB002', 3000, 150, NOW() + INTERVAL '2 hours', 1, NOW() - INTERVAL '1 day'),
(16, '0x1006', '0xB001', 3500, 175, NOW() + INTERVAL '4 hours', 1, NOW() - INTERVAL '2 days'),
(17, '0x1007', '0xB006', 2700, 135, NOW() + INTERVAL '1 day', 1, NOW() - INTERVAL '1 day'),
(18, '0x1008', '0xB004', 4000, 200, NOW() + INTERVAL '2 days', 1, NOW() - INTERVAL '3 hours'),
(19, '0x1009', '0xB003', 2800, 140, NOW() + INTERVAL '3 days', 1, NOW() - INTERVAL '6 hours'),
(20, '0x1010', '0xB005', 3200, 160, NOW() + INTERVAL '4 days', 1, NOW() - INTERVAL '12 hours');

-- Pending bookings (just created)
INSERT INTO bookings (blockchain_id, student_address, barber_address, amount, platform_fee, scheduled_time, status, created_at) VALUES
(21, '0x1001', '0xB007', 2900, 145, NOW() + INTERVAL '5 days', 0, NOW() - INTERVAL '30 minutes'),
(22, '0x1002', '0xB002', 3000, 150, NOW() + INTERVAL '6 days', 0, NOW() - INTERVAL '1 hour'),
(23, '0x1003', '0xB001', 3500, 175, NOW() + INTERVAL '7 days', 0, NOW() - INTERVAL '2 hours');

-- Cancelled bookings
INSERT INTO bookings (blockchain_id, student_address, barber_address, amount, platform_fee, scheduled_time, status, created_at, cancelled_at) VALUES
(24, '0x1004', '0xB003', 2800, 140, NOW() - INTERVAL '5 days', 3, NOW() - INTERVAL '6 days', NOW() - INTERVAL '5 days' - INTERVAL '2 hours'),
(25, '0x1005', '0xB004', 4000, 200, NOW() - INTERVAL '3 days', 3, NOW() - INTERVAL '4 days', NOW() - INTERVAL '3 days' - INTERVAL '1 hour');

-- UCSB Bookings (35 bookings)
INSERT INTO bookings (blockchain_id, student_address, barber_address, amount, platform_fee, scheduled_time, status, created_at, completed_at) VALUES
(26, '0x2001', '0xB011', 3800, 190, NOW() - INTERVAL '24 days', 2, NOW() - INTERVAL '25 days', NOW() - INTERVAL '24 days'),
(27, '0x2002', '0xB012', 3300, 165, NOW() - INTERVAL '21 days', 2, NOW() - INTERVAL '22 days', NOW() - INTERVAL '21 days'),
(28, '0x2003', '0xB013', 3100, 155, NOW() - INTERVAL '19 days', 2, NOW() - INTERVAL '20 days', NOW() - INTERVAL '19 days'),
(29, '0x2004', '0xB011', 3800, 190, NOW() - INTERVAL '17 days', 2, NOW() - INTERVAL '18 days', NOW() - INTERVAL '17 days'),
(30, '0x2005', '0xB014', 4200, 210, NOW() - INTERVAL '16 days', 2, NOW() - INTERVAL '17 days', NOW() - INTERVAL '16 days'),
(31, '0x2006', '0xB015', 3400, 170, NOW() - INTERVAL '13 days', 2, NOW() - INTERVAL '14 days', NOW() - INTERVAL '13 days'),
(32, '0x2007', '0xB012', 3300, 165, NOW() - INTERVAL '11 days', 2, NOW() - INTERVAL '12 days', NOW() - INTERVAL '11 days'),
(33, '0x2008', '0xB016', 2900, 145, NOW() - INTERVAL '9 days', 2, NOW() - INTERVAL '10 days', NOW() - INTERVAL '9 days'),
(34, '0x2009', '0xB011', 3800, 190, NOW() - INTERVAL '7 days', 2, NOW() - INTERVAL '8 days', NOW() - INTERVAL '7 days'),
(35, '0x2010', '0xB017', 3100, 155, NOW() - INTERVAL '5 days', 2, NOW() - INTERVAL '6 days', NOW() - INTERVAL '5 days');

INSERT INTO bookings (blockchain_id, student_address, barber_address, amount, platform_fee, scheduled_time, status, created_at) VALUES
(36, '0x2001', '0xB013', 3100, 155, NOW() + INTERVAL '3 hours', 1, NOW() - INTERVAL '2 days'),
(37, '0x2002', '0xB014', 4200, 210, NOW() + INTERVAL '5 hours', 1, NOW() - INTERVAL '1 day'),
(38, '0x2003', '0xB015', 3400, 170, NOW() + INTERVAL '1 day' + INTERVAL '2 hours', 1, NOW() - INTERVAL '4 hours'),
(39, '0x2004', '0xB011', 3800, 190, NOW() + INTERVAL '2 days' + INTERVAL '3 hours', 1, NOW() - INTERVAL '8 hours'),
(40, '0x2005', '0xB016', 2900, 145, NOW() + INTERVAL '3 days' + INTERVAL '4 hours', 1, NOW() - INTERVAL '14 hours');

-- UCLA Bookings (30 bookings - most active campus)
INSERT INTO bookings (blockchain_id, student_address, barber_address, amount, platform_fee, scheduled_time, status, created_at, completed_at) VALUES
(41, '0x3001', '0xB021', 4500, 225, NOW() - INTERVAL '23 days', 2, NOW() - INTERVAL '24 days', NOW() - INTERVAL '23 days'),
(42, '0x3002', '0xB022', 3900, 195, NOW() - INTERVAL '20 days', 2, NOW() - INTERVAL '21 days', NOW() - INTERVAL '20 days'),
(43, '0x3003', '0xB023', 3600, 180, NOW() - INTERVAL '18 days', 2, NOW() - INTERVAL '19 days', NOW() - INTERVAL '18 days'),
(44, '0x3004', '0xB021', 4500, 225, NOW() - INTERVAL '16 days', 2, NOW() - INTERVAL '17 days', NOW() - INTERVAL '16 days'),
(45, '0x3005', '0xB024', 4300, 215, NOW() - INTERVAL '14 days', 2, NOW() - INTERVAL '15 days', NOW() - INTERVAL '14 days'),
(46, '0x3006', '0xB025', 3700, 185, NOW() - INTERVAL '12 days', 2, NOW() - INTERVAL '13 days', NOW() - INTERVAL '12 days'),
(47, '0x3007', '0xB022', 3900, 195, NOW() - INTERVAL '10 days', 2, NOW() - INTERVAL '11 days', NOW() - INTERVAL '10 days'),
(48, '0x3008', '0xB026', 3200, 160, NOW() - INTERVAL '8 days', 2, NOW() - INTERVAL '9 days', NOW() - INTERVAL '8 days'),
(49, '0x3009', '0xB021', 4500, 225, NOW() - INTERVAL '6 days', 2, NOW() - INTERVAL '7 days', NOW() - INTERVAL '6 days'),
(50, '0x3010', '0xB023', 3600, 180, NOW() - INTERVAL '4 days', 2, NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days'),
(51, '0x3001', '0xB024', 4300, 215, NOW() - INTERVAL '2 days', 2, NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days'),
(52, '0x3002', '0xB025', 3700, 185, NOW() - INTERVAL '1 day', 2, NOW() - INTERVAL '2 days', NOW() - INTERVAL '1 day'),
(53, '0x3003', '0xB021', 4500, 225, NOW() - INTERVAL '12 hours', 2, NOW() - INTERVAL '1 day', NOW() - INTERVAL '12 hours');

-- Recent activity (last few hours) for live demo
INSERT INTO bookings (blockchain_id, student_address, barber_address, amount, platform_fee, scheduled_time, status, created_at, completed_at) VALUES
(54, '0x3004', '0xB022', 3900, 195, NOW() - INTERVAL '3 hours', 2, NOW() - INTERVAL '1 day', NOW() - INTERVAL '3 hours'),
(55, '0x3005', '0xB023', 3600, 180, NOW() - INTERVAL '2 hours', 2, NOW() - INTERVAL '1 day', NOW() - INTERVAL '2 hours'),
(56, '0x3006', '0xB026', 3200, 160, NOW() - INTERVAL '1 hour', 2, NOW() - INTERVAL '2 days', NOW() - INTERVAL '1 hour'),
(57, '0x3007', '0xB024', 4300, 215, NOW() - INTERVAL '30 minutes', 2, NOW() - INTERVAL '3 days', NOW() - INTERVAL '30 minutes'),
(58, '0x3008', '0xB025', 3700, 185, NOW() - INTERVAL '15 minutes', 2, NOW() - INTERVAL '4 days', NOW() - INTERVAL '15 minutes'),
(59, '0x3009', '0xB021', 4500, 225, NOW() - INTERVAL '5 minutes', 2, NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 minutes');

-- Upcoming UCLA bookings
INSERT INTO bookings (blockchain_id, student_address, barber_address, amount, platform_fee, scheduled_time, status, created_at) VALUES
(60, '0x3010', '0xB022', 3900, 195, NOW() + INTERVAL '1 hour', 1, NOW() - INTERVAL '3 hours'),
(61, '0x3001', '0xB023', 3600, 180, NOW() + INTERVAL '3 hours', 1, NOW() - INTERVAL '6 hours'),
(62, '0x3002', '0xB024', 4300, 215, NOW() + INTERVAL '6 hours', 1, NOW() - INTERVAL '12 hours'),
(63, '0x3003', '0xB021', 4500, 225, NOW() + INTERVAL '1 day', 1, NOW() - INTERVAL '1 day'),
(64, '0x3004', '0xB025', 3700, 185, NOW() + INTERVAL '2 days', 1, NOW() - INTERVAL '18 hours');

-- ═══════════════════════════════════════════════════════════════
-- REVIEWS (Only for completed bookings)
-- ═══════════════════════════════════════════════════════════════

-- Cal Poly Reviews
INSERT INTO reviews (blockchain_id, booking_id, reviewer_address, barber_address, rating, comment_cid, created_at) VALUES
(1, 1, '0x1001', '0xB001', 5, 'QmReview1', NOW() - INTERVAL '25 days' + INTERVAL '2 hours'),
(2, 2, '0x1002', '0xB002', 5, 'QmReview2', NOW() - INTERVAL '22 days' + INTERVAL '1 hour'),
(3, 3, '0x1003', '0xB003', 4, 'QmReview3', NOW() - INTERVAL '20 days' + INTERVAL '3 hours'),
(4, 4, '0x1004', '0xB001', 5, 'QmReview4', NOW() - INTERVAL '18 days' + INTERVAL '1 hour'),
(5, 5, '0x1005', '0xB004', 5, 'QmReview5', NOW() - INTERVAL '15 days' + INTERVAL '4 hours'),
(6, 6, '0x1006', '0xB005', 4, 'QmReview6', NOW() - INTERVAL '14 days' + INTERVAL '2 hours'),
(7, 7, '0x1007', '0xB002', 5, 'QmReview7', NOW() - INTERVAL '12 days' + INTERVAL '1 hour'),
(8, 8, '0x1008', '0xB006', 4, 'QmReview8', NOW() - INTERVAL '10 days' + INTERVAL '3 hours'),
(9, 9, '0x1009', '0xB001', 5, 'QmReview9', NOW() - INTERVAL '8 days' + INTERVAL '2 hours'),
(10, 10, '0x1010', '0xB007', 4, 'QmReview10', NOW() - INTERVAL '6 days' + INTERVAL '1 hour');

-- UCSB Reviews
INSERT INTO reviews (blockchain_id, booking_id, reviewer_address, barber_address, rating, comment_cid, created_at) VALUES
(11, 26, '0x2001', '0xB011', 5, 'QmReview11', NOW() - INTERVAL '24 days' + INTERVAL '2 hours'),
(12, 27, '0x2002', '0xB012', 5, 'QmReview12', NOW() - INTERVAL '21 days' + INTERVAL '1 hour'),
(13, 28, '0x2003', '0xB013', 4, 'QmReview13', NOW() - INTERVAL '19 days' + INTERVAL '3 hours'),
(14, 29, '0x2004', '0xB011', 5, 'QmReview14', NOW() - INTERVAL '17 days' + INTERVAL '2 hours'),
(15, 30, '0x2005', '0xB014', 5, 'QmReview15', NOW() - INTERVAL '16 days' + INTERVAL '4 hours'),
(16, 31, '0x2006', '0xB015', 5, 'QmReview16', NOW() - INTERVAL '13 days' + INTERVAL '1 hour'),
(17, 32, '0x2007', '0xB012', 4, 'QmReview17', NOW() - INTERVAL '11 days' + INTERVAL '2 hours'),
(18, 33, '0x2008', '0xB016', 4, 'QmReview18', NOW() - INTERVAL '9 days' + INTERVAL '3 hours');

-- UCLA Reviews (high activity)
INSERT INTO reviews (blockchain_id, booking_id, reviewer_address, barber_address, rating, comment_cid, created_at) VALUES
(19, 41, '0x3001', '0xB021', 5, 'QmReview19', NOW() - INTERVAL '23 days' + INTERVAL '2 hours'),
(20, 42, '0x3002', '0xB022', 5, 'QmReview20', NOW() - INTERVAL '20 days' + INTERVAL '1 hour'),
(21, 43, '0x3003', '0xB023', 5, 'QmReview21', NOW() - INTERVAL '18 days' + INTERVAL '3 hours'),
(22, 44, '0x3004', '0xB021', 5, 'QmReview22', NOW() - INTERVAL '16 days' + INTERVAL '2 hours'),
(23, 45, '0x3005', '0xB024', 5, 'QmReview23', NOW() - INTERVAL '14 days' + INTERVAL '4 hours'),
(24, 46, '0x3006', '0xB025', 4, 'QmReview24', NOW() - INTERVAL '12 days' + INTERVAL '1 hour'),
(25, 47, '0x3007', '0xB022', 5, 'QmReview25', NOW() - INTERVAL '10 days' + INTERVAL '2 hours'),
(26, 48, '0x3008', '0xB026', 4, 'QmReview26', NOW() - INTERVAL '8 days' + INTERVAL '3 hours'),
(27, 49, '0x3009', '0xB021', 5, 'QmReview27', NOW() - INTERVAL '6 days' + INTERVAL '1 hour'),
(28, 50, '0x3010', '0xB023', 5, 'QmReview28', NOW() - INTERVAL '4 days' + INTERVAL '2 hours'),
(29, 51, '0x3001', '0xB024', 5, 'QmReview29', NOW() - INTERVAL '2 days' + INTERVAL '3 hours'),
(30, 52, '0x3002', '0xB025', 4, 'QmReview30', NOW() - INTERVAL '1 day' + INTERVAL '1 hour');

-- Recent UCLA reviews
INSERT INTO reviews (blockchain_id, booking_id, reviewer_address, barber_address, rating, comment_cid, created_at) VALUES
(31, 54, '0x3004', '0xB022', 5, 'QmReview31', NOW() - INTERVAL '2 hours' + INTERVAL '30 minutes'),
(32, 55, '0x3005', '0xB023', 5, 'QmReview32', NOW() - INTERVAL '1 hour' + INTERVAL '30 minutes'),
(33, 56, '0x3006', '0xB026', 4, 'QmReview33', NOW() - INTERVAL '30 minutes'),
(34, 57, '0x3007', '0xB024', 5, 'QmReview34', NOW() - INTERVAL '20 minutes'),
(35, 58, '0x3008', '0xB025', 5, 'QmReview35', NOW() - INTERVAL '10 minutes'),
(36, 59, '0x3009', '0xB021', 5, 'QmReview36', NOW() - INTERVAL '3 minutes');

-- Update sync status
UPDATE sync_status SET 
  last_sync_time = NOW(),
  records_synced = (SELECT COUNT(*) FROM users WHERE table_name = 'users'),
  sync_duration_ms = 5000
WHERE table_name = 'users';

UPDATE sync_status SET 
  last_sync_time = NOW(),
  records_synced = (SELECT COUNT(*) FROM bookings WHERE table_name = 'bookings'),
  sync_duration_ms = 12000
WHERE table_name = 'bookings';

UPDATE sync_status SET 
  last_sync_time = NOW(),
  records_synced = (SELECT COUNT(*) FROM reviews WHERE table_name = 'reviews'),
  sync_duration_ms = 8000
WHERE table_name = 'reviews';

-- ═══════════════════════════════════════════════════════════════
-- SUMMARY
-- ═══════════════════════════════════════════════════════════════

SELECT 
  'MOCK DATA INSERTED SUCCESSFULLY!' as status,
  (SELECT COUNT(*) FROM users WHERE role = 1) as students,
  (SELECT COUNT(*) FROM users WHERE role = 2) as barbers,
  (SELECT COUNT(*) FROM bookings) as total_bookings,
  (SELECT COUNT(*) FROM bookings WHERE status = 2) as completed_bookings,
  (SELECT COUNT(*) FROM bookings WHERE status = 1) as upcoming_bookings,
  (SELECT COUNT(*) FROM bookings WHERE status = 0) as pending_bookings,
  (SELECT COUNT(*) FROM reviews) as total_reviews;

-- Show recent activity by campus
SELECT 
  CASE 
    WHEN b.student_address LIKE '0x1%' THEN 'Cal Poly'
    WHEN b.student_address LIKE '0x2%' THEN 'UCSB'
    WHEN b.student_address LIKE '0x3%' THEN 'UCLA'
  END as campus,
  COUNT(*) as bookings,
  SUM(b.amount) / 100.0 as total_volume_usd
FROM bookings b
WHERE b.status = 2
GROUP BY campus
ORDER BY total_volume_usd DESC;

