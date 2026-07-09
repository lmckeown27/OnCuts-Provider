# CampusCuts PostgreSQL Commands Reference

Quick reference for accessing and managing all database tables.

---

## Connect to Database

```bash
sudo -u postgres psql -d campuscuts
```

---

## Role Hierarchy

CampusCuts uses a role-based permission system with the following hierarchy:

| Role | Description | Privileges | University Affiliation |
|------|-------------|------------|------------------------|
| **ADMIN** | Platform administrator | Highest privileges. Campus manager at ALL campuses. Manages platform via PostgreSQL commands. No admin UI pages (security measure). | **All Universities** (platform-wide) |
| **CAMPUS_MANAGER** | Campus-specific manager | Manages barber applications, campus metrics, incidents for their specific campus. Typically 2 per campus (1 dedicated + admin). | **One University** (their campus) |
| **BARBER** | Service provider | Can offer haircut services, manage bookings, set availability and pricing. | **One University** (their campus) |
| **CONSUMER** | Customer | Can browse barbers, book services, make payments. Also referred to as "student" in frontend. | **None** (not tied to any university) |

### University Affiliation Rules
- **CONSUMER**: Never tied to a specific university, even if they were once a barber (demoted barbers lose campus affiliation)
- **BARBER**: Tied to one specific university where they provide services
- **CAMPUS_MANAGER**: Tied to one specific university that they manage
- **ADMIN**: Has privileges at ALL universities (platform-wide access)

### Admin Privileges
- Admin users have **campus manager privileges at ALL campuses**
- Each campus typically has 2 campus managers: one dedicated campus manager + the admin
- Admin functions are managed via PostgreSQL commands (no UI pages for security)
- When admin logs in, they are redirected to the barber page with full platform access

### Current Admin
- **Email**: `liam.mckeown38415@gmail.com`
- **Role**: `ADMIN`

---

## USERS

## Number of Users
'''bash
sudo -u postgres psql -d campuscuts -c "SELECT COUNT(*) AS total_users FROM users;"
'''

### Number of Users (By Role)
'''bash
sudo -u postgres psql -d campuscuts -c "SELECT role, COUNT(*) FROM users GROUP BY role ORDER BY COUNT(*) DESC;"
'''

### View All Users (Table Format)
```bash
sudo -u postgres psql -d campuscuts -c "SELECT email, first_name, last_name, role, email_verified FROM users;"
```

### View All Users (Expanded/Vertical Format)
```bash
sudo -u postgres psql -d campuscuts -x -c "SELECT id, email, first_name, last_name, role, email_verified, \"createdAt\" FROM users;"
```

### View All Users (Formatted Table)
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    SUBSTRING(email, 1, 30) AS email,
    first_name,
    last_name,
    role,
    CASE WHEN email_verified THEN 'Yes' ELSE 'No' END AS verified
FROM users 
ORDER BY \"createdAt\" DESC;
"
```

### View Specific User by Email
```bash
# Replace EMAIL with actual email address
# Use -x for vertical format (easier to read)
sudo -u postgres psql -d campuscuts -x -c "SELECT * FROM users WHERE email = 'EMAIL';"

# Example:
sudo -u postgres psql -d campuscuts -x -c "SELECT * FROM users WHERE email = 'liam.mckeown38415@gmail.com';"
```

### View User with All Details
```bash
sudo -u postgres psql -d campuscuts -c "SELECT id, email, first_name, last_name, \"displayName\", role, email_verified, \"isVerified\", \"avatarUrl\", \"instagramHandle\", \"createdAt\" FROM users WHERE email = 'user@example.com';"
```

### Update User Role

**IMPORTANT:** Role changes require updating BOTH the `users` table AND the `barbers` table for full platform consistency.

```bash
# ============================================================================
# PROMOTE TO BARBER
# ============================================================================
# Step 1: Update user role
sudo -u postgres psql -d campuscuts -c "UPDATE users SET role = 'BARBER', \"updatedAt\" = CURRENT_TIMESTAMP WHERE email = 'user@example.com';"

# Step 2: Activate barber record (if exists) or create one
# Check if barber record exists first:
sudo -u postgres psql -d campuscuts -c "SELECT b.id, b.\"isActive\" FROM barbers b JOIN users u ON b.\"userId\" = u.id WHERE u.email = 'user@example.com';"

# If barber record exists, activate it:
sudo -u postgres psql -d campuscuts -c "UPDATE barbers SET \"isActive\" = true, \"updatedAt\" = CURRENT_TIMESTAMP WHERE \"userId\" = (SELECT id FROM users WHERE email = 'user@example.com');"

# ============================================================================
# PROMOTE TO CAMPUS_MANAGER
# ============================================================================
# Step 1: Update user role AND set their campusId
sudo -u postgres psql -d campuscuts -c "UPDATE users SET role = 'CAMPUS_MANAGER', \"campusId\" = 'CAMPUS_UUID_HERE', \"updatedAt\" = CURRENT_TIMESTAMP WHERE email = 'user@example.com';"

# Step 2: Set isCampusManager flag on barber record
sudo -u postgres psql -d campuscuts -c "UPDATE barbers SET \"isCampusManager\" = true, \"isActive\" = true, \"updatedAt\" = CURRENT_TIMESTAMP WHERE \"userId\" = (SELECT id FROM users WHERE email = 'user@example.com');"

# ============================================================================
# DEMOTE TO CONSUMER (from BARBER or CAMPUS_MANAGER)
# ============================================================================
# Step 1: Update user role
sudo -u postgres psql -d campuscuts -c "UPDATE users SET role = 'CONSUMER', \"updatedAt\" = CURRENT_TIMESTAMP WHERE email = 'user@example.com';"

# Step 2: Deactivate barber record and remove campus manager flag
sudo -u postgres psql -d campuscuts -c "UPDATE barbers SET \"isActive\" = false, \"isCampusManager\" = false, \"updatedAt\" = CURRENT_TIMESTAMP WHERE \"userId\" = (SELECT id FROM users WHERE email = 'user@example.com');"

# Step 3: Delete any CM-barber direct conversations (optional cleanup)
sudo -u postgres psql -d campuscuts -c "DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE booking_id IS NULL AND (user1_id = (SELECT id FROM users WHERE email = 'user@example.com') OR user2_id = (SELECT id FROM users WHERE email = 'user@example.com'))); DELETE FROM conversations WHERE booking_id IS NULL AND (user1_id = (SELECT id FROM users WHERE email = 'user@example.com') OR user2_id = (SELECT id FROM users WHERE email = 'user@example.com'));"

# ============================================================================
# PROMOTE TO ADMIN
# ============================================================================
# Admins have campus manager privileges at ALL campuses automatically
sudo -u postgres psql -d campuscuts -c "UPDATE users SET role = 'ADMIN', \"updatedAt\" = CURRENT_TIMESTAMP WHERE email = 'user@example.com';"

# ============================================================================
# REVOKE CAMPUS_MANAGER (keep as BARBER)
# ============================================================================
# Step 1: Change role to BARBER
sudo -u postgres psql -d campuscuts -c "UPDATE users SET role = 'BARBER', \"updatedAt\" = CURRENT_TIMESTAMP WHERE email = 'user@example.com';"

# Step 2: Remove isCampusManager flag but keep barber active
sudo -u postgres psql -d campuscuts -c "UPDATE barbers SET \"isCampusManager\" = false, \"updatedAt\" = CURRENT_TIMESTAMP WHERE \"userId\" = (SELECT id FROM users WHERE email = 'user@example.com');"

# ============================================================================
# QUICK REFERENCE: Get Campus IDs
# ============================================================================
sudo -u postgres psql -d campuscuts -c "SELECT id, name FROM campuses WHERE name ILIKE '%cal poly%' OR name ILIKE '%your campus%' LIMIT 10;"
```

### Update User Email Verification
```bash
# Verify email
sudo -u postgres psql -d campuscuts -c "UPDATE users SET email_verified = true WHERE email = 'user@example.com';"

# Unverify email
sudo -u postgres psql -d campuscuts -c "UPDATE users SET email_verified = false WHERE email = 'user@example.com';"
```

### Update User Profile
```bash
# Update display name
sudo -u postgres psql -d campuscuts -c "UPDATE users SET \"displayName\" = 'New Name' WHERE email = 'user@example.com';"

# Update avatar
sudo -u postgres psql -d campuscuts -c "UPDATE users SET \"avatarUrl\" = 'https://example.com/image.jpg' WHERE email = 'user@example.com';"

# Update Instagram
sudo -u postgres psql -d campuscuts -c "UPDATE users SET \"instagramHandle\" = '@username' WHERE email = 'user@example.com';"
```

### Block/Unblock User
```bash
# Block user
sudo -u postgres psql -d campuscuts -c "UPDATE users SET \"isBlocked\" = true WHERE email = 'user@example.com';"

# Unblock user
sudo -u postgres psql -d campuscuts -c "UPDATE users SET \"isBlocked\" = false WHERE email = 'user@example.com';"
```

### Delete User (Simple)
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM users WHERE email = 'user@example.com';"
```

### Delete User Completely (Handles All Foreign Keys)
Use this when simple delete fails due to foreign key constraints. Deletes all related data first.

```bash
# Replace 'user@example.com' with the actual email
sudo -u postgres psql -d campuscuts -c "
DO \$\$
DECLARE
    target_id UUID;
    target_email TEXT := 'user@example.com';
BEGIN
    -- Get user ID
    SELECT id INTO target_id FROM users WHERE email = target_email;
    
    IF target_id IS NULL THEN
        RAISE NOTICE 'User not found: %', target_email;
        RETURN;
    END IF;
    
    RAISE NOTICE 'Deleting user: % (%)', target_email, target_id;
    
    -- Delete payments linked to user's bookings (as consumer)
    DELETE FROM payments WHERE booking_id IN (
        SELECT id FROM bookings WHERE \"consumerId\" = target_id
    );
    RAISE NOTICE 'Deleted payments for consumer bookings';
    
    -- Delete payments linked to user's bookings (as barber via barbers table)
    DELETE FROM payments WHERE booking_id IN (
        SELECT b.id FROM bookings b
        JOIN barbers bar ON b.\"barberId\" = bar.id
        WHERE bar.\"userId\" = target_id
    );
    RAISE NOTICE 'Deleted payments for barber bookings';
    
    -- Delete bookings (as consumer)
    DELETE FROM bookings WHERE \"consumerId\" = target_id;
    RAISE NOTICE 'Deleted consumer bookings';
    
    -- Delete bookings (as barber)
    DELETE FROM bookings WHERE \"barberId\" IN (
        SELECT id FROM barbers WHERE \"userId\" = target_id
    );
    RAISE NOTICE 'Deleted barber bookings';
    
    -- Delete messages
    DELETE FROM messages WHERE sender_id = target_id;
    RAISE NOTICE 'Deleted messages';
    
    -- Delete conversations (as participant)
    DELETE FROM conversations WHERE user1_id = target_id OR user2_id = target_id;
    RAISE NOTICE 'Deleted conversations';
    
    -- Delete notifications
    DELETE FROM notifications WHERE user_id = target_id;
    RAISE NOTICE 'Deleted notifications';
    
    -- Delete barber applications
    DELETE FROM barber_applications WHERE user_id = target_id;
    RAISE NOTICE 'Deleted barber applications';
    
    -- Delete barber service location assignments
    DELETE FROM barber_service_locations WHERE barber_id IN (
        SELECT id FROM barbers WHERE \"userId\" = target_id
    );
    RAISE NOTICE 'Deleted barber service locations';
    
    -- Delete barber location assignments (old table)
    DELETE FROM barber_locations WHERE barber_id IN (
        SELECT id FROM barbers WHERE \"userId\" = target_id
    );
    RAISE NOTICE 'Deleted barber locations';
    
    -- Delete barber profile
    DELETE FROM barbers WHERE \"userId\" = target_id;
    RAISE NOTICE 'Deleted barber profile';
    
    -- Delete the user
    DELETE FROM users WHERE id = target_id;
    RAISE NOTICE 'User deleted successfully: %', target_email;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error: %', SQLERRM;
    RAISE;
END \$\$;
"
```

### Delete User (One-Liner Quick Version)
Simpler version that ignores tables that may not exist:

```bash
# Replace EMAIL with the actual email address
EMAIL='user@example.com' && sudo -u postgres psql -d campuscuts -c "
BEGIN;
DELETE FROM payments WHERE booking_id IN (SELECT id FROM bookings WHERE \"consumerId\" = (SELECT id FROM users WHERE email = '$EMAIL'));
DELETE FROM bookings WHERE \"consumerId\" = (SELECT id FROM users WHERE email = '$EMAIL');
DELETE FROM messages WHERE sender_id = (SELECT id FROM users WHERE email = '$EMAIL');
DELETE FROM conversations WHERE user1_id = (SELECT id FROM users WHERE email = '$EMAIL') OR user2_id = (SELECT id FROM users WHERE email = '$EMAIL');
DELETE FROM notifications WHERE user_id = (SELECT id FROM users WHERE email = '$EMAIL');
DELETE FROM barber_applications WHERE user_id = (SELECT id FROM users WHERE email = '$EMAIL');
DELETE FROM barbers WHERE \"userId\" = (SELECT id FROM users WHERE email = '$EMAIL');
DELETE FROM users WHERE email = '$EMAIL';
COMMIT;
"
```

### Delete Account Completely (For Testing)
Use this to fully delete an account so you can test account creation again.
This deletes the user AND all related records in other tables.

```bash
# Step 1: Find the user ID
sudo -u postgres psql -d campuscuts -c "SELECT id, email, first_name, role FROM users WHERE email = 'test@example.com';"

# Step 2: Delete all related records (replace USER_ID with actual UUID)
# Delete in order to avoid foreign key constraints

# Delete notifications
sudo -u postgres psql -d campuscuts -c "DELETE FROM notifications WHERE \"userId\" = 'USER_ID';"

# Delete bookings (as consumer or barber)
sudo -u postgres psql -d campuscuts -c "DELETE FROM bookings WHERE \"consumerId\" = 'USER_ID' OR \"barberId\" = 'USER_ID';"

# Delete messages
sudo -u postgres psql -d campuscuts -c "DELETE FROM messages WHERE \"senderId\" = 'USER_ID' OR \"receiverId\" = 'USER_ID';"

# Delete conversations
sudo -u postgres psql -d campuscuts -c "DELETE FROM conversations WHERE \"consumerId\" = 'USER_ID' OR \"barberId\" = 'USER_ID';"

# Delete barber application (if any)
sudo -u postgres psql -d campuscuts -c "DELETE FROM barber_applications WHERE \"userId\" = 'USER_ID';"

# Delete barber profile (if any)
sudo -u postgres psql -d campuscuts -c "DELETE FROM barbers WHERE \"userId\" = 'USER_ID';"

# Delete the user
sudo -u postgres psql -d campuscuts -c "DELETE FROM users WHERE id = 'USER_ID';"
```

### Delete Account by Email (One Command)
Deletes everything in the correct order using the email address directly.
Replace `test@example.com` with the actual email.

```bash
sudo -u postgres psql -d campuscuts -c "
DO \$\$
DECLARE
    target_user_id UUID;
BEGIN
    -- Get user ID
    SELECT id INTO target_user_id FROM users WHERE email = 'test@example.com';
    
    IF target_user_id IS NULL THEN
        RAISE NOTICE 'User not found';
        RETURN;
    END IF;
    
    RAISE NOTICE 'Deleting user: %', target_user_id;
    
    -- Delete related records (using correct column names)
    DELETE FROM notifications WHERE user_id = target_user_id;
    DELETE FROM bookings WHERE \"consumerId\" = target_user_id OR \"barberId\" = target_user_id;
    DELETE FROM messages WHERE sender_id = target_user_id;
    DELETE FROM barber_applications WHERE user_id = target_user_id;
    DELETE FROM barbers WHERE \"userId\" = target_user_id;
    DELETE FROM users WHERE id = target_user_id;
    
    RAISE NOTICE 'User deleted successfully';
END \$\$;
"
```

### Quick Delete Test Account
```bash
# Replace EMAIL with the test email address
EMAIL='test@example.com' && sudo -u postgres psql -d campuscuts -c "
DO \$\$
DECLARE uid UUID;
BEGIN
    SELECT id INTO uid FROM users WHERE email = '$EMAIL';
    IF uid IS NOT NULL THEN
        DELETE FROM notifications WHERE user_id = uid;
        DELETE FROM bookings WHERE \"consumerId\" = uid OR \"barberId\" = uid;
        DELETE FROM messages WHERE sender_id = uid;
        DELETE FROM barber_applications WHERE user_id = uid;
        DELETE FROM barbers WHERE \"userId\" = uid;
        DELETE FROM users WHERE id = uid;
        RAISE NOTICE 'Deleted: %', uid;
    ELSE
        RAISE NOTICE 'User not found: $EMAIL';
    END IF;
END \$\$;
"
```

### Count Users by Role
```bash
sudo -u postgres psql -d campuscuts -c "SELECT role, COUNT(*) FROM users GROUP BY role;"
```

### Find User ID by Email
```bash
sudo -u postgres psql -d campuscuts -c "SELECT id FROM users WHERE email = 'user@example.com';"
```

---

## CONSUMERS

> **Note:** Consumers are not tied to any university. The `campusId` stored is just where they signed up, not an operational restriction.

### View All Consumers
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
  u.first_name || ' ' || u.last_name AS name,
  u.email,
  u.email_verified AS verified,
  u.\"createdAt\"::date AS joined
FROM users u
WHERE u.role = 'CONSUMER'
ORDER BY u.\"createdAt\" DESC;
"
```

### View All Consumers (Detailed)
```bash
sudo -u postgres psql -d campuscuts -x -c "
SELECT 
  u.id,
  u.first_name,
  u.last_name,
  u.email,
  u.\"displayName\",
  u.\"avatarUrl\",
  u.email_verified,
  u.\"createdAt\",
  c.name AS signup_campus
FROM users u
LEFT JOIN campuses c ON u.\"campusId\" = c.id
WHERE u.role = 'CONSUMER'
ORDER BY u.\"createdAt\" DESC
LIMIT 20;
"
```

### View Consumers by Signup Campus
```bash
# Replace 'Cal Poly SLO' with campus name
sudo -u postgres psql -d campuscuts -c "
SELECT 
  u.first_name || ' ' || u.last_name AS name,
  u.email,
  u.email_verified AS verified,
  u.\"createdAt\"::date AS joined
FROM users u
JOIN campuses c ON u.\"campusId\" = c.id
WHERE u.role = 'CONSUMER'
  AND c.name ILIKE '%Cal Poly SLO%'
ORDER BY u.\"createdAt\" DESC;
"
```

### View Demoted Barbers (Now Consumers)
```bash
# Shows consumers who were previously barbers (have barber record with isActive=false)
sudo -u postgres psql -d campuscuts -c "
SELECT 
  u.first_name || ' ' || u.last_name AS name,
  u.email,
  u.role,
  b.\"avgRating\" AS prev_rating,
  b.\"totalBookings\" AS prev_bookings,
  c.name AS prev_campus
FROM users u
JOIN barbers b ON u.id = b.\"userId\"
JOIN campuses c ON u.\"campusId\" = c.id
WHERE u.role = 'CONSUMER'
  AND b.\"isActive\" = false
ORDER BY u.\"createdAt\" DESC;
"
```

### Count Consumers
```bash
sudo -u postgres psql -d campuscuts -c "SELECT COUNT(*) AS total_consumers FROM users WHERE role = 'CONSUMER';"
```

### Count Consumers by Signup Campus
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
  c.name AS campus,
  COUNT(*) AS consumer_count
FROM users u
JOIN campuses c ON u.\"campusId\" = c.id
WHERE u.role = 'CONSUMER'
GROUP BY c.name
ORDER BY consumer_count DESC;
"
```

---

## BARBERS

### View Barber Info Requirements (NOT NULL columns)
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT column_name, data_type, is_nullable, column_default 
FROM information_schema.columns 
WHERE table_name = 'barbers' AND is_nullable = 'NO'
ORDER BY ordinal_position;
"
```

### View All Active Barbers (System-Wide)
```bash
# Shows all active barbers. Consumers are not tied to any campus.
# ADMIN = All Campuses, CAMPUS_MANAGER/BARBER = their specific campus
sudo -u postgres psql -d campuscuts -c "
SELECT 
  u.first_name || ' ' || u.last_name AS name,
  u.email,
  u.role,
  CASE 
    WHEN u.role = 'ADMIN' THEN 'All Campuses'
    WHEN u.role = 'CONSUMER' THEN 'N/A'
    ELSE c.name 
  END AS campus_scope,
  COALESCE(b.\"avgRating\"::text, '-') AS rating,
  CASE WHEN b.\"isCampusManager\" = true OR u.role IN ('CAMPUS_MANAGER', 'ADMIN') THEN 'Yes' ELSE 'No' END AS campus_mgr
FROM barbers b 
JOIN users u ON b.\"userId\" = u.id 
JOIN campuses c ON u.\"campusId\" = c.id
WHERE b.\"isActive\" = true 
  AND u.role IN ('BARBER', 'CAMPUS_MANAGER', 'ADMIN')
ORDER BY u.role = 'ADMIN' DESC, u.role = 'CAMPUS_MANAGER' DESC, c.name, u.first_name;
"
```

### View All Campus Managers (System-Wide)
```bash
# Shows all campus managers and admins (who have CM privileges at all campuses)
sudo -u postgres psql -d campuscuts -c "
SELECT 
  u.first_name || ' ' || u.last_name AS name,
  u.email,
  u.role,
  CASE 
    WHEN u.role = 'ADMIN' THEN 'All Campuses'
    ELSE c.name 
  END AS scope,
  COALESCE(b.\"avgRating\"::text, '-') AS rating
FROM users u
LEFT JOIN barbers b ON u.id = b.\"userId\"
LEFT JOIN campuses c ON u.\"campusId\" = c.id
WHERE u.role IN ('CAMPUS_MANAGER', 'ADMIN')
   OR b.\"isCampusManager\" = true
ORDER BY u.role = 'ADMIN' DESC, c.name, u.first_name;
"
```

### Count Campus Managers by Campus
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
  c.name AS campus,
  COUNT(*) AS manager_count
FROM users u
JOIN campuses c ON u.\"campusId\" = c.id
WHERE u.role = 'CAMPUS_MANAGER'
GROUP BY c.name
ORDER BY manager_count DESC, c.name;
"
```

### View Barbers at a Specific University (by Campus Name)
```bash
# Replace 'University of Florida' with the campus name
# Note: ADMINs appear for ALL campuses since they have platform-wide privileges
sudo -u postgres psql -d campuscuts -c "
SELECT 
  u.first_name || ' ' || u.last_name AS name,
  u.email,
  u.role,
  CASE 
    WHEN u.role = 'ADMIN' THEN 'All Campuses'
    WHEN u.role = 'CONSUMER' THEN 'N/A'
    ELSE c.name 
  END AS campus_scope,
  COALESCE(b.\"avgRating\"::text, '-') AS rating,
  CASE WHEN b.\"isActive\" THEN 'Yes' ELSE 'No' END AS active,
  CASE WHEN b.\"isCampusManager\" = true OR u.role IN ('CAMPUS_MANAGER', 'ADMIN') THEN 'Yes' ELSE 'No' END AS campus_mgr
FROM barbers b 
JOIN users u ON b.\"userId\" = u.id 
JOIN campuses c ON u.\"campusId\" = c.id
WHERE c.name ILIKE '%University of Florida%' OR u.role = 'ADMIN'
ORDER BY u.role = 'ADMIN' DESC, (b.\"isCampusManager\" = true OR u.role = 'CAMPUS_MANAGER') DESC, u.first_name;
"
```

### View Barbers at a Specific University (by Campus ID)
```bash
# Replace the UUID with the actual campus ID
# Note: ADMINs appear for ALL campuses since they have platform-wide privileges
sudo -u postgres psql -d campuscuts -c "
SELECT 
  u.first_name || ' ' || u.last_name AS name,
  u.email,
  u.role,
  CASE 
    WHEN u.role = 'ADMIN' THEN 'All Campuses'
    WHEN u.role = 'CONSUMER' THEN 'N/A'
    ELSE 'This Campus' 
  END AS campus_scope,
  COALESCE(b.\"avgRating\"::text, '-') AS rating,
  CASE WHEN b.\"isActive\" THEN 'Yes' ELSE 'No' END AS active,
  CASE WHEN b.\"isCampusManager\" = true OR u.role IN ('CAMPUS_MANAGER', 'ADMIN') THEN 'Yes' ELSE 'No' END AS campus_mgr
FROM barbers b 
JOIN users u ON b.\"userId\" = u.id 
WHERE u.\"campusId\" = '9de371b8-6ce6-492e-a716-93cb03ae2f82' OR u.role = 'ADMIN'
ORDER BY u.role = 'ADMIN' DESC, (b.\"isCampusManager\" = true OR u.role = 'CAMPUS_MANAGER') DESC, u.first_name;
"
```

### View All Active Barbers at a University (Excludes Inactive/Demoted)
```bash
# Replace 'University of Florida' with the campus name
# Note: ADMINs appear for ALL campuses, Consumers show N/A
sudo -u postgres psql -d campuscuts -c "
SELECT 
  u.first_name || ' ' || u.last_name AS name,
  u.email,
  u.role,
  CASE 
    WHEN u.role = 'ADMIN' THEN 'All Campuses'
    ELSE c.name 
  END AS campus_scope,
  COALESCE(b.\"avgRating\"::text, '-') AS rating,
  CASE WHEN b.\"isCampusManager\" = true OR u.role IN ('CAMPUS_MANAGER', 'ADMIN') THEN 'Yes' ELSE 'No' END AS campus_mgr
FROM barbers b 
JOIN users u ON b.\"userId\" = u.id 
JOIN campuses c ON u.\"campusId\" = c.id
WHERE (c.name ILIKE '%Cal Poly SLO%' OR u.role = 'ADMIN')
  AND b.\"isActive\" = true
  AND u.role IN ('BARBER', 'CAMPUS_MANAGER', 'ADMIN')
ORDER BY u.role = 'ADMIN' DESC, (b.\"isCampusManager\" = true OR u.role = 'CAMPUS_MANAGER') DESC, b.\"avgRating\" DESC NULLS LAST;
"
```

### View Campus Manager for a University
```bash
# Replace 'University of Florida' with the campus name
# Note: ADMINs appear for ALL campuses (platform-wide privileges)
sudo -u postgres psql -d campuscuts -c "
SELECT 
  u.first_name || ' ' || u.last_name AS name,
  u.email,
  u.role,
  CASE WHEN u.role = 'ADMIN' THEN 'All Campuses' ELSE c.name END as scope
FROM barbers b 
JOIN users u ON b.\"userId\" = u.id 
JOIN campuses c ON u.\"campusId\" = c.id
WHERE (c.name ILIKE '%University of Florida%' AND (b.\"isCampusManager\" = true OR u.role = 'CAMPUS_MANAGER'))
   OR u.role = 'ADMIN'
ORDER BY u.role = 'ADMIN' DESC, u.first_name;
"
```

### View Specific Barber by Email
```bash
sudo -u postgres psql -d campuscuts -c "SELECT b.*, u.role, u.first_name, u.last_name FROM barbers b JOIN users u ON b.\"userId\" = u.id WHERE u.email = 'barber@example.com';"
```

### View Barber Schedule
```bash
sudo -u postgres psql -d campuscuts -c "SELECT u.email, b.\"weeklySchedule\" FROM barbers b JOIN users u ON b.\"userId\" = u.id WHERE u.email = 'barber@example.com';"
```

### View Barber Specialties
```bash
sudo -u postgres psql -d campuscuts -c "SELECT u.email, b.specialties FROM barbers b JOIN users u ON b.\"userId\" = u.id WHERE u.email = 'barber@example.com';"
```

### Update Barber Bio
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE barbers SET bio = 'New bio text here' FROM users WHERE barbers.\"userId\" = users.id AND users.email = 'barber@example.com';"
```

### Activate/Deactivate Barber
```bash
# Deactivate
sudo -u postgres psql -d campuscuts -c "UPDATE barbers SET \"isActive\" = false FROM users WHERE barbers.\"userId\" = users.id AND users.email = 'barber@example.com';"

# Activate
sudo -u postgres psql -d campuscuts -c "UPDATE barbers SET \"isActive\" = true FROM users WHERE barbers.\"userId\" = users.id AND users.email = 'barber@example.com';"
```

### Delete Barber Profile
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM barbers USING users WHERE barbers.\"userId\" = users.id AND users.email = 'barber@example.com';"
```

### Describe Barbers Table
```bash
sudo -u postgres psql -d campuscuts -c "\d barbers"
```

---

## BARBER APPLICATIONS

### View All Applications (Table Format)
```bash
sudo -u postgres psql -d campuscuts -c "SELECT ba.id, u.email, u.first_name, ba.status, ba.years_experience, ba.created_at FROM barber_applications ba JOIN users u ON ba.user_id = u.id ORDER BY ba.created_at DESC;"
```

### View All Applications (Expanded/Readable Format)
```bash
sudo -u postgres psql -d campuscuts -x -c "
SELECT 
    ba.id,
    u.first_name || ' ' || u.last_name as full_name,
    u.email,
    c.name as campus,
    ba.status,
    array_to_string(ba.specialties, ', ') as specialties,
    ba.years_experience,
    ba.has_license,
    ba.has_own_tools,
    ba.available_hours,
    ba.why_be_barber,
    ba.social_media,
    ba.created_at::date as applied_date
FROM barber_applications ba
JOIN users u ON ba.user_id = u.id
LEFT JOIN campuses c ON ba.campus_id = c.id
ORDER BY ba.created_at DESC;
"
```

### View Pending Applications
```bash
sudo -u postgres psql -d campuscuts -c "SELECT ba.*, u.email FROM barber_applications ba JOIN users u ON ba.user_id = u.id WHERE ba.status = 'pending';"
```

### View Pending Applications (Expanded)
```bash
sudo -u postgres psql -d campuscuts -x -c "
SELECT 
    ba.id,
    u.first_name || ' ' || u.last_name as full_name,
    u.email,
    c.name as campus,
    array_to_string(ba.specialties, ', ') as specialties,
    ba.years_experience,
    ba.has_license,
    ba.has_own_tools,
    ba.available_hours,
    ba.why_be_barber,
    ba.social_media,
    ba.created_at
FROM barber_applications ba
JOIN users u ON ba.user_id = u.id
LEFT JOIN campuses c ON ba.campus_id = c.id
WHERE ba.status = 'pending'
ORDER BY ba.created_at DESC;
"
```

### Approve Application
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE barber_applications SET status = 'approved', reviewed_at = NOW() WHERE id = 'UUID_HERE';"
```

### Reject Application
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE barber_applications SET status = 'rejected', reviewed_at = NOW(), review_notes = 'Reason here' WHERE id = 'UUID_HERE';"
```

### Delete Application
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM barber_applications WHERE id = 'UUID_HERE';"
```

### Count Applications by Status
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT status, COUNT(*) FROM barber_applications GROUP BY status
UNION ALL
SELECT status || ' (guest)', COUNT(*) FROM guest_barber_applications GROUP BY status;
"
```

### Describe Barber Applications Table
```bash
sudo -u postgres psql -d campuscuts -c "\d barber_applications"
```

---

## GUEST BARBER APPLICATIONS

Guest applications are from unauthenticated users who want to become barbers. They must create an account after approval.

### View All Guest Applications (Expanded)
```bash
sudo -u postgres psql -d campuscuts -x -c "
SELECT 
    gba.id,
    gba.full_name,
    gba.email,
    gba.phone,
    c.name as campus,
    gba.status,
    array_to_string(gba.specialties, ', ') as specialties,
    gba.years_experience,
    gba.linked_user_id,
    gba.created_at::date as applied_date
FROM guest_barber_applications gba
LEFT JOIN campuses c ON gba.campus_id = c.id
ORDER BY gba.created_at DESC;
"
```

### View Pending Guest Applications
```bash
sudo -u postgres psql -d campuscuts -x -c "
SELECT 
    gba.id,
    gba.full_name,
    gba.email,
    gba.phone,
    c.name as campus,
    array_to_string(gba.specialties, ', ') as specialties,
    gba.years_experience,
    gba.created_at
FROM guest_barber_applications gba
LEFT JOIN campuses c ON gba.campus_id = c.id
WHERE gba.status = 'pending'
ORDER BY gba.created_at DESC;
"
```

### Approve Guest Application
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE guest_barber_applications SET status = 'approved', reviewed_at = NOW() WHERE id = 'UUID_HERE';"
```

### Reject Guest Application
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE guest_barber_applications SET status = 'rejected', reviewed_at = NOW(), review_notes = 'Reason here' WHERE id = 'UUID_HERE';"
```

### Delete Guest Application
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM guest_barber_applications WHERE id = 'UUID_HERE';"
```

### Describe Guest Barber Applications Table
```bash
sudo -u postgres psql -d campuscuts -c "\d guest_barber_applications"
```

---

## CAMPUSES

### View All Campuses
```bash
sudo -u postgres psql -d campuscuts -c "SELECT id, name, city, state, \"isActive\" FROM campuses ORDER BY name;"
```

### View Campuses (Formatted)
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    name,
    city,
    state,
    slug,
    \"basePriceUsdCents\" / 100.0 as base_price,
    \"platformFeePercent\" as fee_pct,
    \"isActive\"
FROM campuses 
ORDER BY state, city;
"
```

### View Campus Count
```bash
sudo -u postgres psql -d campuscuts -c "SELECT COUNT(*) as total_campuses FROM campuses;"
```

### Find Campus by Name
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM campuses WHERE name ILIKE '%poly%';"
```

### Find Campuses by State
```bash
sudo -u postgres psql -d campuscuts -c "SELECT name, city FROM campuses WHERE state = 'CA' ORDER BY name;"
```

### Add New Campus
```bash
sudo -u postgres psql -d campuscuts -c "
INSERT INTO campuses (id, slug, name, city, state, timezone, \"updatedAt\")
VALUES (gen_random_uuid(), 'new-university', 'New University Name', 'City', 'ST', 'America/New_York', CURRENT_TIMESTAMP);
"
```

### Update Campus
```bash
# Activate/Deactivate campus
sudo -u postgres psql -d campuscuts -c "UPDATE campuses SET \"isActive\" = false WHERE slug = 'campus-slug';"

# Update pricing
sudo -u postgres psql -d campuscuts -c "UPDATE campuses SET \"basePriceUsdCents\" = 2500, \"averagePriceUsdCents\" = 4000 WHERE slug = 'campus-slug';"
```

### Delete Invalid Campuses
```bash
# Delete non-university entries (like GMAIL, ICLOUD)
sudo -u postgres psql -d campuscuts -c "DELETE FROM campuses WHERE name IN ('GMAIL', 'ICLOUD');"
```

### View Campus Timezones
```bash
# View timezones for all active campuses
sudo -u postgres psql -d campuscuts -c "
SELECT name, city, state, timezone 
FROM campuses 
WHERE \"isActive\" = true 
ORDER BY timezone, state, name;
"
```

### Update Campus Timezone
```bash
# Update timezone for a specific campus (e.g., fix a campus set to wrong timezone)
sudo -u postgres psql -d campuscuts -c "
UPDATE campuses 
SET timezone = 'America/Los_Angeles' 
WHERE slug = 'cal-poly';
"

# Common US timezones:
# - America/Los_Angeles (Pacific: CA, WA, OR, NV)
# - America/Denver (Mountain: CO, UT, AZ*, MT, NM, WY)
# - America/Chicago (Central: TX, IL, MN, WI, OK, NE, KS, IA, MO, AR, LA, MS, TN, AL)
# - America/New_York (Eastern: NY, MA, PA, FL, GA, NC, SC, VA, MD, NJ, CT, OH, MI, IN, KY, WV)
# - Pacific/Honolulu (Hawaii)
# - America/Phoenix (Arizona - no DST)
# * Arizona uses America/Phoenix (no daylight saving)
```

### Seed All Universities
```bash
# Run the seed script (after git pull)
# Option 1: Pipe the file (recommended - avoids permission issues)
cat ~/CampusCuts/backend/src/database/seed_campuses.sql | sudo -u postgres psql -d campuscuts

# Option 2: Copy to tmp first
cp ~/CampusCuts/backend/src/database/seed_campuses.sql /tmp/
sudo -u postgres psql -d campuscuts -f /tmp/seed_campuses.sql

# Option 3: Fix permissions then run directly
chmod 644 ~/CampusCuts/backend/src/database/seed_campuses.sql
sudo -u postgres psql -d campuscuts -f ~/CampusCuts/backend/src/database/seed_campuses.sql
```

### Describe Campuses Table
```bash
sudo -u postgres psql -d campuscuts -c "\d campuses"
```

### View All Campus Coordinates
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT name, city, state, latitude, longitude 
FROM campuses 
WHERE latitude IS NOT NULL 
ORDER BY state, name;
"
```

### View Campus Coordinates by State
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT name, city, latitude, longitude 
FROM campuses 
WHERE state = 'CA' AND latitude IS NOT NULL 
ORDER BY name;
"
```

### Find Campuses Near Coordinates
```bash
# Find campuses within ~50km of coordinates (approximate)
sudo -u postgres psql -d campuscuts -c "
SELECT 
    name, 
    city, 
    state,
    latitude, 
    longitude,
    ROUND((
        6371 * acos(
            cos(radians(35.3050)) * cos(radians(latitude)) * 
            cos(radians(longitude) - radians(-120.6625)) + 
            sin(radians(35.3050)) * sin(radians(latitude))
        )
    )::numeric, 2) as distance_km
FROM campuses 
WHERE latitude IS NOT NULL
ORDER BY distance_km 
LIMIT 10;
"
```

### Update Campus Coordinates
```bash
sudo -u postgres psql -d campuscuts -c "
UPDATE campuses 
SET latitude = 35.3050, longitude = -120.6625 
WHERE slug = 'cal-poly';
"
```

### Add Coordinates Columns (if not exists)
```bash
sudo -u postgres psql -d campuscuts -c "
ALTER TABLE campuses ADD COLUMN IF NOT EXISTS latitude DECIMAL(10, 6);
ALTER TABLE campuses ADD COLUMN IF NOT EXISTS longitude DECIMAL(10, 6);
CREATE INDEX IF NOT EXISTS idx_campuses_coordinates ON campuses(latitude, longitude);
"
```

---

## LOCATIONS

### View All Locations
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    l.id,
    l.name,
    l.type,
    c.name as campus_name,
    l.\"isVerified\"
FROM locations l
JOIN campuses c ON l.\"campusId\" = c.id
ORDER BY c.name, l.name;
"
```

### View Locations for Campus
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT l.* FROM locations l
JOIN campuses c ON l.\"campusId\" = c.id
WHERE c.slug = 'cal-poly';
"
```

### Create Default Location for Campus
```bash
sudo -u postgres psql -d campuscuts -c "
INSERT INTO locations (id, \"campusId\", name, \"normalizedName\", type, cohort, \"usageCount\", confidence, \"isVerified\", \"updatedAt\")
SELECT 
    gen_random_uuid(),
    id,
    'Campus Default',
    'campus-default',
    'DORM'::\"LocationType\",
    'UNKNOWN'::\"LocationCohort\",
    1,
    0.50,
    false,
    CURRENT_TIMESTAMP
FROM campuses
WHERE slug = 'cal-poly';
"
```

### Describe Locations Table
```bash
sudo -u postgres psql -d campuscuts -c "\d locations"
```

---

## CAMPUS LOCATIONS (New System)

The new campus locations system allows campus managers to define predefined locations where barbers can offer services.

### Create Campus Locations Tables (Run Once)
```bash
sudo -u postgres psql -d campuscuts -c "
-- Campus locations table: stores locations available at each campus
CREATE TABLE IF NOT EXISTS campus_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campus_id UUID NOT NULL REFERENCES campuses(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  address TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(campus_id, name)
);

-- Barber locations: junction table linking barbers to their available locations
CREATE TABLE IF NOT EXISTS barber_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barber_id UUID NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
  location_id UUID NOT NULL REFERENCES campus_locations(id) ON DELETE CASCADE,
  is_primary BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(barber_id, location_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_campus_locations_campus ON campus_locations(campus_id);
CREATE INDEX IF NOT EXISTS idx_campus_locations_active ON campus_locations(campus_id, is_active);
CREATE INDEX IF NOT EXISTS idx_barber_locations_barber ON barber_locations(barber_id);
CREATE INDEX IF NOT EXISTS idx_barber_locations_location ON barber_locations(location_id);
"
```

### View All Campus Locations
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    cl.id,
    cl.name,
    cl.description,
    c.name as campus_name,
    cl.is_active,
    cl.created_at
FROM campus_locations cl
JOIN campuses c ON cl.campus_id = c.id
ORDER BY c.name, cl.name;
"
```

### View Locations for a Specific Campus
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT cl.id, cl.name, cl.description, cl.is_active
FROM campus_locations cl
JOIN campuses c ON cl.campus_id = c.id
WHERE c.slug = 'cal-poly'
ORDER BY cl.name;
"
```

### Add a Location to a Campus
```bash
sudo -u postgres psql -d campuscuts -c "
INSERT INTO campus_locations (campus_id, name, description, address)
SELECT id, 'Dexter Lawn', 'Popular outdoor meetup area', 'Near Kennedy Library'
FROM campuses WHERE slug = 'cal-poly';
"
```

### View Barber Location Assignments
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.first_name || ' ' || u.last_name as barber_name,
    cl.name as location_name,
    bl.is_primary,
    bl.created_at as assigned_at
FROM barber_locations bl
JOIN barbers b ON bl.barber_id = b.id
JOIN users u ON b.\"userId\" = u.id
JOIN campus_locations cl ON bl.location_id = cl.id
ORDER BY barber_name, cl.name;
"
```

### Assign Location to a Barber
```bash
sudo -u postgres psql -d campuscuts -c "
INSERT INTO barber_locations (barber_id, location_id, is_primary)
SELECT b.id, cl.id, true
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
JOIN campus_locations cl ON cl.campus_id = b.\"campusId\"
WHERE u.email = 'barber@example.com'
AND cl.name = 'Dexter Lawn';
"
```

### Remove Location from a Barber
```bash
sudo -u postgres psql -d campuscuts -c "
DELETE FROM barber_locations bl
USING barbers b, users u, campus_locations cl
WHERE bl.barber_id = b.id
AND b.\"userId\" = u.id
AND bl.location_id = cl.id
AND u.email = 'barber@example.com'
AND cl.name = 'Dexter Lawn';
"
```

### Delete a Campus Location
```bash
sudo -u postgres psql -d campuscuts -c "
DELETE FROM campus_locations
WHERE name = 'Dexter Lawn'
AND campus_id = (SELECT id FROM campuses WHERE slug = 'cal-poly');
"
```

### Describe Campus Locations Tables
```bash
sudo -u postgres psql -d campuscuts -c "\d campus_locations"
sudo -u postgres psql -d campuscuts -c "\d barber_locations"
```

---

## AVAILABILITY

### View All Availability Slots
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    a.id,
    u.email as barber_email,
    a.\"startTime\",
    a.\"endTime\",
    a.status,
    a.\"priceUsdCents\" / 100.0 as price
FROM availability a
JOIN barbers b ON a.\"barberId\" = b.id
JOIN users u ON b.\"userId\" = u.id
ORDER BY a.\"startTime\" DESC
LIMIT 20;
"
```

### View Open Slots
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM availability WHERE status = 'OPEN' ORDER BY \"startTime\";"
```

### View Booked Slots
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM availability WHERE status = 'BOOKED' ORDER BY \"startTime\" DESC;"
```

### Describe Availability Table
```bash
sudo -u postgres psql -d campuscuts -c "\d availability"
```

---

## BOOKINGS

### View All Bookings
```bash
sudo -u postgres psql -d campuscuts -c "SELECT id, \"barberId\", \"consumerId\", \"serviceType\", status, \"requestedAt\" FROM bookings ORDER BY \"requestedAt\" DESC LIMIT 20;"
```

### View All Bookings (Expanded)
```bash
sudo -u postgres psql -d campuscuts -x -c "SELECT * FROM bookings ORDER BY \"requestedAt\" DESC LIMIT 10;"
```

### View Bookings by Status
```bash
# Status values: PENDING, ACCEPTED, REJECTED, COMPLETED, CANCELLED
sudo -u postgres psql -d campuscuts -c "SELECT * FROM bookings WHERE status = 'PENDING';"
sudo -u postgres psql -d campuscuts -c "SELECT * FROM bookings WHERE status = 'ACCEPTED';"
sudo -u postgres psql -d campuscuts -c "SELECT * FROM bookings WHERE status = 'REJECTED';"
sudo -u postgres psql -d campuscuts -c "SELECT * FROM bookings WHERE status = 'COMPLETED';"
sudo -u postgres psql -d campuscuts -c "SELECT * FROM bookings WHERE status = 'CANCELLED';"
```

### Booking Lifecycle Stages

#### Stage 1: PENDING (Consumer requested, waiting for barber response)
```bash
# View all pending booking requests
sudo -u postgres psql -d campuscuts -c "
SELECT 
    bar_u.first_name || ' ' || bar_u.last_name AS barber,
    c.first_name || ' ' || c.last_name AS consumer,
    b.\"serviceType\" AS service,
    '\$' || (b.\"priceUsdCents\" / 100.0)::numeric(10,2) AS price,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'Mon DD, YYYY') AS date,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'HH12:MI AM') AS time
FROM bookings b
JOIN users c ON b.\"consumerId\" = c.id
LEFT JOIN users bar_u ON b.\"barberId\" = bar_u.id
WHERE b.status = 'PENDING'
ORDER BY b."requestedAt" DESC;
"
```

#### Stage 2: ACCEPTED (Barber accepted the booking)
```bash
# View all accepted bookings awaiting service
sudo -u postgres psql -d campuscuts -c "
SELECT 
    bar_u.first_name || ' ' || bar_u.last_name AS barber,
    c.first_name || ' ' || c.last_name AS consumer,
    b.\"serviceType\" AS service,
    '\$' || (b.\"priceUsdCents\" / 100.0)::numeric(10,2) AS price,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'Mon DD, YYYY') AS date,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'HH12:MI AM') AS time
FROM bookings b
JOIN users c ON b.\"consumerId\" = c.id
LEFT JOIN users bar_u ON b.\"barberId\" = bar_u.id
WHERE b.status = 'ACCEPTED'
ORDER BY b."requestedAt" DESC;
"
```

#### Stage 3: REJECTED (Barber declined the booking)
```bash
# View all rejected bookings
sudo -u postgres psql -d campuscuts -c "
SELECT 
    bar_u.first_name || ' ' || bar_u.last_name AS barber,
    c.first_name || ' ' || c.last_name AS consumer,
    b.\"serviceType\" AS service,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'Mon DD, YYYY') AS date,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'HH12:MI AM') AS time,
    TO_CHAR(b.\"updatedAt\" AT TIME ZONE 'America/Los_Angeles', 'Mon DD HH12:MI AM') AS rejected_at
FROM bookings b
JOIN users c ON b.\"consumerId\" = c.id
LEFT JOIN users bar_u ON b.\"barberId\" = bar_u.id
WHERE b.status = 'REJECTED'
ORDER BY b.\"updatedAt\" DESC;
"
```

#### Stage 4: COMPLETED (Service finished)
```bash
# View all completed bookings
sudo -u postgres psql -d campuscuts -c "
SELECT 
    bar_u.first_name || ' ' || bar_u.last_name AS barber,
    c.first_name || ' ' || c.last_name AS consumer,
    b.\"serviceType\" AS service,
    '\$' || (b.\"priceUsdCents\" / 100.0)::numeric(10,2) AS price,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'Mon DD, YYYY') AS date,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'HH12:MI AM') AS time
FROM bookings b
JOIN users c ON b.\"consumerId\" = c.id
LEFT JOIN users bar_u ON b.\"barberId\" = bar_u.id
WHERE b.status = 'COMPLETED'
ORDER BY b.\"completedAt\" DESC;
"
```

#### Stage 5: CANCELLED (Booking was cancelled)
```bash
# View all cancelled bookings
sudo -u postgres psql -d campuscuts -c "
SELECT 
    bar_u.first_name || ' ' || bar_u.last_name AS barber,
    c.first_name || ' ' || c.last_name AS consumer,
    b.\"serviceType\" AS service,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'Mon DD, YYYY') AS date,
    TO_CHAR(b."requestedAt" AT TIME ZONE 'America/Los_Angeles', 'HH12:MI AM') AS time,
    TO_CHAR(b.\"cancelledAt\" AT TIME ZONE 'America/Los_Angeles', 'Mon DD HH12:MI AM') AS cancelled_at
FROM bookings b
JOIN users c ON b.\"consumerId\" = c.id
LEFT JOIN users bar_u ON b.\"barberId\" = bar_u.id
WHERE b.status = 'CANCELLED'
ORDER BY b.\"cancelledAt\" DESC;
"
```

### View Booking with Linked Conversation
```bash
# See booking and its linked conversation status
sudo -u postgres psql -d campuscuts -c "
SELECT 
    b.id as booking_id,
    b.status as booking_status,
    b.\"serviceType\",
    c.id as conversation_id,
    c.booking_status as conv_status,
    c.service_name,
    c.scheduled_time
FROM bookings b
LEFT JOIN conversations c ON c.booking_id = b.id
WHERE b.id = 'BOOKING_UUID_HERE';
"
```

### Booking Status Summary
```bash
# Count bookings by status
sudo -u postgres psql -d campuscuts -c "
SELECT 
    status,
    COUNT(*) as count,
    SUM(\"priceUsdCents\") / 100.0 as total_value_usd
FROM bookings
GROUP BY status
ORDER BY count DESC;
"
```

### View Barber's Booking Pipeline
```bash
# See all booking stages for a specific barber
sudo -u postgres psql -d campuscuts -c "
SELECT 
    b.status,
    COUNT(*) as count,
    b.\"serviceType\"
FROM bookings b
JOIN users u ON b.\"barberId\" = u.id
WHERE u.email = 'barber@example.com'
GROUP BY b.status, b.\"serviceType\"
ORDER BY 
    CASE b.status 
        WHEN 'PENDING' THEN 1 
        WHEN 'ACCEPTED' THEN 2 
        WHEN 'COMPLETED' THEN 3 
        WHEN 'REJECTED' THEN 4 
        WHEN 'CANCELLED' THEN 5 
    END;
"
```

### View Bookings with User Details
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    b.id,
    b.\"serviceType\",
    b.status,
    b.\"priceUsdCents\" / 100.0 as price_usd,
    u.email as consumer,
    b.\"requestedAt\"
FROM bookings b
JOIN users u ON b.\"consumerId\" = u.id
ORDER BY b.\"requestedAt\" DESC
LIMIT 20;
"
```

### Update Booking Status
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE bookings SET status = 'ACCEPTED', \"acceptedAt\" = NOW() WHERE id = 'UUID_HERE';"
sudo -u postgres psql -d campuscuts -c "UPDATE bookings SET status = 'COMPLETED', \"completedAt\" = NOW() WHERE id = 'UUID_HERE';"
sudo -u postgres psql -d campuscuts -c "UPDATE bookings SET status = 'CANCELLED', \"cancelledAt\" = NOW() WHERE id = 'UUID_HERE';"
```

### Delete Booking
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM bookings WHERE id = 'UUID_HERE';"
```

### View BookingStatus Enum Values
```bash
sudo -u postgres psql -d campuscuts -c "SELECT unnest(enum_range(NULL::\"BookingStatus\"));"
```

### Describe Bookings Table
```bash
sudo -u postgres psql -d campuscuts -c "\d bookings"
```

---

## CONVERSATIONS

### View All Conversations
```bash
sudo -u postgres psql -d campuscuts -c "SELECT id, user1_id, user2_id, service_name, booking_status, created_at, last_message_at FROM conversations ORDER BY last_message_at DESC;"
```

### View Conversations for a User
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM conversations WHERE user1_id = 'UUID_HERE' OR user2_id = 'UUID_HERE';"
```

### Delete Conversation
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM conversations WHERE id = 123;"
```

### Describe Conversations Table
```bash
sudo -u postgres psql -d campuscuts -c "\d conversations"
```

---

## MESSAGES

### View Recent Messages
```bash
sudo -u postgres psql -d campuscuts -c "SELECT id, conversation_id, content, message_type, is_read, created_at FROM messages ORDER BY created_at DESC LIMIT 50;"
```

### View Messages in a Conversation
```bash
sudo -u postgres psql -d campuscuts -c "SELECT m.id, u.email as sender, m.content, m.is_read, m.created_at FROM messages m JOIN users u ON m.sender_id = u.id WHERE m.conversation_id = 123 ORDER BY m.created_at;"
```

### Mark Messages as Read
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE messages SET is_read = true WHERE conversation_id = 123;"
```

### Delete Message
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM messages WHERE id = 123;"
```

### Describe Messages Table
```bash
sudo -u postgres psql -d campuscuts -c "\d messages"
```

---

## USER LOCATIONS

### View All Users with Location Data
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    email,
    first_name,
    last_name,
    role,
    latitude,
    longitude,
    location_permission,
    location_updated_at
FROM users 
WHERE latitude IS NOT NULL 
ORDER BY location_updated_at DESC;
"
```

### View Users Grouped by Approximate Location (Summary)
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    ROUND(latitude::numeric, 2) as lat_zone,
    ROUND(longitude::numeric, 2) as lng_zone,
    COUNT(*) as user_count,
    COUNT(*) FILTER (WHERE role = 'BARBER') as barber_count,
    COUNT(*) FILTER (WHERE role = 'CONSUMER') as consumer_count
FROM users
WHERE latitude IS NOT NULL
GROUP BY lat_zone, lng_zone
ORDER BY user_count DESC;
"
```

### View Users with Names/Emails Grouped by Location
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    email,
    first_name,
    last_name,
    role,
    ROUND(latitude::numeric, 4) as latitude,
    ROUND(longitude::numeric, 4) as longitude,
    ROUND(latitude::numeric, 2) as location_zone
FROM users
WHERE latitude IS NOT NULL
ORDER BY ROUND(latitude::numeric, 2), ROUND(longitude::numeric, 2), email;
"
```

### View All Users in a Specific Location Zone
```bash
# Replace lat_zone and lng_zone with values from the summary query above
sudo -u postgres psql -d campuscuts -c "
SELECT 
    email,
    first_name,
    last_name,
    role,
    latitude,
    longitude
FROM users
WHERE ROUND(latitude::numeric, 2) = 35.31 
  AND ROUND(longitude::numeric, 2) = -120.66;
"
```

### View Users Who Granted Location Permission
```bash
sudo -u postgres psql -d campuscuts -c "SELECT email, first_name, last_name, role, location_permission FROM users WHERE location_permission = 'granted';"
```

### View Users Who Denied Location Permission
```bash
sudo -u postgres psql -d campuscuts -c "SELECT email, first_name, last_name, role, location_permission FROM users WHERE location_permission = 'denied';"
```

### Update User Location (Manual)
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE users SET latitude = 37.2395, longitude = -121.9251, location_updated_at = NOW(), location_permission = 'granted' WHERE email = 'user@example.com';"
```

### Clear User Location
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE users SET latitude = NULL, longitude = NULL, location_updated_at = NULL, location_permission = 'prompt' WHERE email = 'user@example.com';"
```

### View Barbers with Service Location Set
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.email,
    u.first_name,
    u.last_name,
    b.service_latitude,
    b.service_longitude,
    b.service_radius_km
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
WHERE b.service_latitude IS NOT NULL;
"
```

### Update Barber Service Location
```bash
sudo -u postgres psql -d campuscuts -c "
UPDATE barbers 
SET service_latitude = 37.2395, service_longitude = -121.9251, service_radius_km = 10.0
FROM users 
WHERE barbers.\"userId\" = users.id AND users.email = 'barber@example.com';
"
```

### Find Users Within X km of a Location
```bash
# Find users within 8km of coordinates (37.2395, -121.9251)
sudo -u postgres psql -d campuscuts -c "
SELECT 
    email,
    first_name,
    last_name,
    role,
    (6371 * acos(
        cos(radians(37.2395)) * 
        cos(radians(latitude)) * 
        cos(radians(longitude) - radians(-121.9251)) + 
        sin(radians(37.2395)) * 
        sin(radians(latitude))
    )) as distance_km
FROM users
WHERE latitude IS NOT NULL
HAVING distance_km <= 8
ORDER BY distance_km;
"
```

### Describe Users Table (Location Columns)
```bash
sudo -u postgres psql -d campuscuts -c "\d users" | grep -E "latitude|longitude|location"
```

---

## NOTIFICATIONS

### View User Notifications
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM notifications WHERE user_id = 'UUID_HERE' ORDER BY created_at DESC;"
```

### Mark Notifications as Read
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE notifications SET is_read = true WHERE user_id = 'UUID_HERE';"
```

### Delete Old Notifications
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM notifications WHERE created_at < NOW() - INTERVAL '30 days';"
```

### Describe Notifications Table
```bash
sudo -u postgres psql -d campuscuts -c "\d notifications"
```

---

## STRIPE CONNECT (Barber Payouts)

> **Note:** Stripe Connect account IDs are stored in the `users` table (`stripe_account_id` column). Barbers must complete Stripe Connect onboarding to receive payouts.

### View All Barbers with Stripe Connect Status
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.email,
    u.first_name,
    u.last_name,
    b.\"isActive\",
    CASE 
        WHEN u.stripe_account_id IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS stripe_connected,
    u.stripe_account_id
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
ORDER BY u.stripe_account_id IS NULL, u.first_name;
"
```

### View Barbers WITHOUT Stripe Connect
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT u.email, u.first_name, u.last_name, b.\"isActive\"
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
WHERE u.stripe_account_id IS NULL;
"
```

### View Barbers WITH Stripe Connect
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT u.email, u.first_name, u.last_name, b.\"isActive\", u.stripe_account_id
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
WHERE u.stripe_account_id IS NOT NULL;
"
```

### Check Specific Barber's Stripe Status
```bash
sudo -u postgres psql -d campuscuts -c "SELECT stripe_account_id FROM users WHERE email = 'barber@example.com';"
```

---

## BARBER AVAILABILITY (Weekly Schedule)

> **Note:** The `weeklySchedule` column is stored as JSONB in the `barbers` table. Each day has `enabled`, `start`, `end`, and optionally `intervals` for multi-slot schedules.

### View All Barbers' Availability Settings
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.first_name,
    u.last_name,
    u.email,
    b.\"weeklySchedule\"
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
ORDER BY u.first_name;
"
```

### View Barbers' Availability (Pretty Printed)
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.first_name || ' ' || u.last_name AS barber_name,
    jsonb_pretty(b.\"weeklySchedule\") AS schedule
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
ORDER BY u.first_name;
"
```

### View Specific Barber's Availability by Email
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT jsonb_pretty(b.\"weeklySchedule\") AS schedule
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
WHERE u.email = 'barber@example.com';
"
```

### View Barbers WITH Availability Configured (At Least One Day Enabled)
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.first_name,
    u.last_name,
    u.email
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
WHERE b.\"weeklySchedule\" IS NOT NULL
  AND (
    (b.\"weeklySchedule\"->>'monday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'tuesday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'wednesday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'thursday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'friday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'saturday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'sunday')::jsonb->>'enabled' = 'true'
  );
"
```

### View Barbers WITHOUT Availability (No Days Enabled or NULL Schedule)
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.first_name,
    u.last_name,
    u.email
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
WHERE b.\"weeklySchedule\" IS NULL
   OR NOT (
    (b.\"weeklySchedule\"->>'monday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'tuesday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'wednesday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'thursday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'friday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'saturday')::jsonb->>'enabled' = 'true' OR
    (b.\"weeklySchedule\"->>'sunday')::jsonb->>'enabled' = 'true'
  );
"
```

### View Monday Availability for All Barbers
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.first_name || ' ' || u.last_name AS barber_name,
    b.\"weeklySchedule\"->'monday'->>'enabled' AS monday_enabled,
    b.\"weeklySchedule\"->'monday'->>'start' AS monday_start,
    b.\"weeklySchedule\"->'monday'->>'end' AS monday_end
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
ORDER BY u.first_name;
"
```

---

## PAYMENTS (Stripe Off-Chain)

> **Note:** CampusCuts uses Stripe for all payments. Blockchain payment columns are deprecated.

### View All Payment Transactions (Stripe)
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    pt.id,
    pt.stripe_payment_intent_id,
    pt.stripe_transfer_id,
    u_c.email AS consumer_email,
    u_b.email AS barber_email,
    pt.amount,
    pt.platform_fee,
    pt.barber_payout,
    pt.tip_amount,
    pt.status,
    pt.created_at
FROM payment_transactions pt
LEFT JOIN users u_c ON pt.client_id = u_c.id
LEFT JOIN barbers b ON pt.barber_id = b.id
LEFT JOIN users u_b ON b.\"userId\" = u_b.id
ORDER BY pt.created_at DESC 
LIMIT 20;
"
```

### View Transactions by Status
```bash
# Succeeded transactions
sudo -u postgres psql -d campuscuts -c "SELECT * FROM payment_transactions WHERE status = 'succeeded' ORDER BY created_at DESC;"

# Pending transactions
sudo -u postgres psql -d campuscuts -c "SELECT * FROM payment_transactions WHERE status = 'pending' ORDER BY created_at DESC;"

# Failed transactions
sudo -u postgres psql -d campuscuts -c "SELECT * FROM payment_transactions WHERE status = 'failed' ORDER BY created_at DESC;"
```

### View Payment Summary
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    status,
    COUNT(*) as count,
    SUM(amount) as total_amount,
    SUM(platform_fee) as total_fees,
    SUM(barber_payout) as total_payouts
FROM payment_transactions 
GROUP BY status;
"
```

### View Barber Earnings
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.email AS barber_email,
    u.first_name,
    u.last_name,
    SUM(pt.barber_payout) AS total_earned,
    SUM(pt.tip_amount) AS total_tips,
    COUNT(*) AS transaction_count
FROM payment_transactions pt
JOIN barbers b ON pt.barber_id = b.id
JOIN users u ON b.\"userId\" = u.id
WHERE pt.status = 'succeeded'
GROUP BY u.email, u.first_name, u.last_name
ORDER BY total_earned DESC;
"
```

### Describe Payment Transactions Table
```bash
sudo -u postgres psql -d campuscuts -c "\d payment_transactions"
```

---

## ESCROWS (Stripe PaymentIntent Holds)

### View All Escrows
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM escrows ORDER BY created_at DESC LIMIT 20;"
```

### View Active (Held) Escrows
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM escrows WHERE status = 'held' ORDER BY created_at DESC;"
```

### View Escrow by Booking
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM escrows WHERE booking_id = 'BOOKING_ID_HERE';"
```

### Describe Escrows Table
```bash
sudo -u postgres psql -d campuscuts -c "\d escrows"
```

---

## LEDGER ENTRIES

### View User Ledger
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM ledger_entries WHERE user_id = 'UUID_HERE' ORDER BY created_at DESC;"
```

### View Recent Ledger Entries
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM ledger_entries ORDER BY created_at DESC LIMIT 50;"
```

### Describe Ledger Entries Table
```bash
sudo -u postgres psql -d campuscuts -c "\d ledger_entries"
```

---

## WITHDRAWAL REQUESTS

### View All Withdrawals
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM withdrawal_requests ORDER BY requested_at DESC;"
```

### View Pending Withdrawals
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM withdrawal_requests WHERE status = 'pending';"
```

### Update Withdrawal Status
```bash
sudo -u postgres psql -d campuscuts -c "UPDATE withdrawal_requests SET status = 'completed', completed_at = NOW() WHERE id = 'UUID_HERE';"
```

### Describe Withdrawal Requests Table
```bash
sudo -u postgres psql -d campuscuts -c "\d withdrawal_requests"
```

---

## ANALYTICS EVENTS

### View Recent Events
```bash
sudo -u postgres psql -d campuscuts -c "SELECT event_type, COUNT(*) FROM analytics_events WHERE timestamp > NOW() - INTERVAL '7 days' GROUP BY event_type ORDER BY COUNT(*) DESC;"
```

### View User Activity
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM analytics_events WHERE user_id = 'UUID_HERE' ORDER BY timestamp DESC LIMIT 50;"
```

### Describe Analytics Events Table
```bash
sudo -u postgres psql -d campuscuts -c "\d analytics_events"
```

---

## REFERRALS

### View All Referrals
```bash
sudo -u postgres psql -d campuscuts -c "SELECT * FROM referrals;"
```

### Describe Referrals Table
```bash
sudo -u postgres psql -d campuscuts -c "\d referrals"
```

---

## STRIPE EVENTS (Webhook Logs)

### View Recent Stripe Events
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    event_id,
    event_type,
    payment_intent_id,
    amount_usd,
    status,
    student_email,
    barber_email,
    timestamp
FROM stripe_events 
ORDER BY timestamp DESC 
LIMIT 20;
"
```

### View Stripe Events by Type
```bash
# Payment succeeded events
sudo -u postgres psql -d campuscuts -c "SELECT * FROM stripe_events WHERE event_type = 'payment_intent.succeeded' ORDER BY timestamp DESC LIMIT 10;"

# Payment failed events
sudo -u postgres psql -d campuscuts -c "SELECT * FROM stripe_events WHERE event_type = 'payment_intent.payment_failed' ORDER BY timestamp DESC LIMIT 10;"

# Payout events
sudo -u postgres psql -d campuscuts -c "SELECT * FROM stripe_events WHERE event_type LIKE 'payout.%' ORDER BY timestamp DESC LIMIT 10;"
```

### View Stripe Event Summary
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    event_type,
    COUNT(*) as count,
    SUM(amount_usd) as total_amount
FROM stripe_events 
WHERE timestamp > NOW() - INTERVAL '30 days'
GROUP BY event_type
ORDER BY count DESC;
"
```

### Describe Stripe Events Table
```bash
sudo -u postgres psql -d campuscuts -c "\d stripe_events"
```

---

## UTILITY COMMANDS

### List All Tables
```bash
sudo -u postgres psql -d campuscuts -c "\dt"
```

### Describe Any Table
```bash
sudo -u postgres psql -d campuscuts -c "\d TABLE_NAME"
```

### Count Rows in All Key Tables
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 'users' as table_name, COUNT(*) FROM users
UNION ALL SELECT 'barbers', COUNT(*) FROM barbers
UNION ALL SELECT 'barber_applications', COUNT(*) FROM barber_applications
UNION ALL SELECT 'bookings', COUNT(*) FROM bookings
UNION ALL SELECT 'conversations', COUNT(*) FROM conversations
UNION ALL SELECT 'messages', COUNT(*) FROM messages
UNION ALL SELECT 'campuses', COUNT(*) FROM campuses;
"
```

### Check Database Size
```bash
sudo -u postgres psql -d campuscuts -c "SELECT pg_size_pretty(pg_database_size('campuscuts'));"
```

### Check Table Sizes
```bash
sudo -u postgres psql -d campuscuts -c "SELECT relname as table, pg_size_pretty(pg_total_relation_size(relid)) as size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC;"
```

### View UserRole Enum Values
```bash
sudo -u postgres psql -d campuscuts -c "SELECT unnest(enum_range(NULL::\"UserRole\"));"
```

---

## BACKUP & RESTORE

### Full Backup
```bash
sudo -u postgres pg_dump campuscuts > ~/campuscuts_backup_$(date +%Y%m%d_%H%M%S).sql
```

### Backup Specific Table
```bash
sudo -u postgres pg_dump -t users campuscuts > ~/users_backup.sql
sudo -u postgres pg_dump -t barbers campuscuts > ~/barbers_backup.sql
```

### Restore from Backup
```bash
sudo -u postgres psql -d campuscuts < ~/campuscuts_backup.sql
```

---

## DANGEROUS COMMANDS (USE WITH CAUTION)

### Delete All Data from Table (Keep Structure)
```bash
sudo -u postgres psql -d campuscuts -c "TRUNCATE TABLE messages CASCADE;"
sudo -u postgres psql -d campuscuts -c "TRUNCATE TABLE conversations CASCADE;"
```

### Drop Table Completely
```bash
sudo -u postgres psql -d campuscuts -c "DROP TABLE IF EXISTS table_name CASCADE;"
```

### Reset Auto-Increment Sequence
```bash
sudo -u postgres psql -d campuscuts -c "ALTER SEQUENCE conversations_id_seq RESTART WITH 1;"
sudo -u postgres psql -d campuscuts -c "ALTER SEQUENCE messages_id_seq RESTART WITH 1;"
```

---

## SERVICE TYPES (ENUM)

### View All ServiceType Enum Values
```bash
sudo -u postgres psql -d campuscuts -c "SELECT unnest(enum_range(NULL::\"ServiceType\"));"
```

### Add New ServiceType to Enum
```bash
# Example: Add TAPER to ServiceType enum
sudo -u postgres psql -d campuscuts -c "ALTER TYPE \"ServiceType\" ADD VALUE IF NOT EXISTS 'TAPER';"
```

---

## BARBER DISCOVERY & VISIBILITY

### Check Why a Barber Isn't Showing to Consumers
```bash
# Check barber record status (isActive, isOnboarded, campusId)
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.email,
    u.first_name,
    u.last_name,
    u.role,
    u.\"campusId\" as user_campus_id,
    b.id as barber_id,
    b.\"isActive\",
    b.\"isOnboarded\",
    b.\"campusId\" as barber_campus_id
FROM users u
LEFT JOIN barbers b ON u.id = b.\"userId\"
WHERE u.email = 'barber@example.com';
"
```

### View All Active Barbers with Campus Info
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.email,
    u.first_name,
    u.last_name,
    b.\"isActive\",
    b.\"campusId\",
    c.name as campus_name
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
LEFT JOIN campuses c ON b.\"campusId\" = c.id
WHERE b.\"isActive\" = true;
"
```

### View Barbers by Campus
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.email,
    u.first_name,
    u.last_name,
    b.\"isActive\",
    b.\"isOnboarded\"
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
WHERE b.\"campusId\" = 'CAMPUS_UUID_HERE';
"
```

### Activate a Barber Profile
```bash
sudo -u postgres psql -d campuscuts -c "
UPDATE barbers SET \"isActive\" = true 
WHERE \"userId\" = (SELECT id FROM users WHERE email = 'barber@example.com');
"
```

---

## BARBER & USER LOCATIONS

### View All Barbers with Location Data
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.email,
    u.first_name,
    u.latitude,
    u.longitude,
    b.service_latitude,
    b.service_longitude,
    u.location_updated_at
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
WHERE b.\"isActive\" = true;
"
```

### Check Location Auto-Update Status for Barbers
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    email, 
    first_name,
    last_name,
    latitude, 
    longitude, 
    location_permission,
    location_updated_at 
FROM users 
WHERE role IN ('BARBER', 'CAMPUS_MANAGER')
ORDER BY location_updated_at DESC NULLS LAST;
"
```

### Manually Update Barber's Location (When GPS Not Working)
```bash
# Set to specific coordinates (e.g., Cal Poly SLO)
sudo -u postgres psql -d campuscuts -c "
UPDATE users 
SET latitude = 35.30500000, 
    longitude = -120.66250000,
    location_updated_at = NOW(),
    location_permission = 'granted'
WHERE email = 'barber@example.com';
"
```

### Find Barbers Within Distance of Coordinates
```bash
# Find barbers within 8km of Cal Poly SLO (35.3050, -120.6625)
sudo -u postgres psql -d campuscuts -c "
SELECT 
    u.email,
    u.first_name,
    u.last_name,
    u.latitude,
    u.longitude,
    ROUND((
        6371 * acos(
            LEAST(1.0, GREATEST(-1.0,
                cos(radians(35.3050)) * 
                cos(radians(u.latitude)) * 
                cos(radians(u.longitude) - radians(-120.6625)) + 
                sin(radians(35.3050)) * 
                sin(radians(u.latitude))
            ))
        )
    )::numeric, 2) as distance_km
FROM barbers b
JOIN users u ON b.\"userId\" = u.id
WHERE b.\"isActive\" = true
  AND u.latitude IS NOT NULL
ORDER BY distance_km;
"
```

---

## PENDING REGISTRATIONS

The `pending_registrations` table stores user registration data while awaiting email verification.
This table is auto-created by the verification service on startup.

### View Pending Registrations
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT email, first_name, last_name, role, expires_at, created_at
FROM pending_registrations
ORDER BY created_at DESC;
"
```

### Delete Expired Pending Registrations
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM pending_registrations WHERE expires_at < NOW();"
```

### Clear All Pending Registrations (Testing Only)
```bash
sudo -u postgres psql -d campuscuts -c "DELETE FROM pending_registrations;"
```

### Create Table Manually (if not auto-created)
```bash
sudo -u postgres psql -d campuscuts -c "
CREATE TABLE IF NOT EXISTS pending_registrations (
  email VARCHAR(255) PRIMARY KEY,
  password_hash TEXT NOT NULL,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  campus_id UUID,
  role VARCHAR(50) NOT NULL,
  verification_code VARCHAR(6) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"
```

---

## SERVICE LOCATIONS (Barber-defined and Campus Manager curated)

This system allows barbers to request new service locations, which campus managers approve/reject.
Campus managers can also create locations directly. Locations can be **universal** (all barbers) or **barber-specific**.

### Create Service Locations Tables (Run this once)
```bash
sudo -u postgres psql -d campuscuts -c "
-- New table for service locations with approval workflow
CREATE TABLE IF NOT EXISTS service_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campus_id UUID NOT NULL REFERENCES campuses(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  status VARCHAR(20) DEFAULT 'approved',  -- 'pending', 'approved', 'rejected'
  is_universal BOOLEAN DEFAULT true,       -- true = all barbers, false = specific barber
  restricted_to_barber_id UUID REFERENCES barbers(id) ON DELETE SET NULL,
  created_by UUID REFERENCES users(id),    -- who requested/created it
  reviewed_by UUID REFERENCES users(id),   -- campus manager who approved/rejected
  reviewed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(campus_id, name)
);

-- Barber assignments to service locations (which barbers use which locations)
CREATE TABLE IF NOT EXISTS barber_service_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barber_id UUID NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
  location_id UUID NOT NULL REFERENCES service_locations(id) ON DELETE CASCADE,
  is_primary BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(barber_id, location_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_service_locations_campus ON service_locations(campus_id);
CREATE INDEX IF NOT EXISTS idx_service_locations_status ON service_locations(campus_id, status);
CREATE INDEX IF NOT EXISTS idx_service_locations_active ON service_locations(campus_id, is_active);
CREATE INDEX IF NOT EXISTS idx_barber_service_locations_barber ON barber_service_locations(barber_id);
CREATE INDEX IF NOT EXISTS idx_barber_service_locations_location ON barber_service_locations(location_id);
"
```

### Add Approval Workflow Columns (Migration for existing tables)
If the `service_locations` table already exists without the approval columns:
```bash
sudo -u postgres psql -d campuscuts -c "
ALTER TABLE service_locations ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'approved';
ALTER TABLE service_locations ADD COLUMN IF NOT EXISTS is_universal BOOLEAN DEFAULT true;
ALTER TABLE service_locations ADD COLUMN IF NOT EXISTS restricted_to_barber_id UUID REFERENCES barbers(id) ON DELETE SET NULL;
ALTER TABLE service_locations ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES users(id);
ALTER TABLE service_locations ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMP WITH TIME ZONE;
CREATE INDEX IF NOT EXISTS idx_service_locations_status ON service_locations(campus_id, status);
"
```

### View All Service Locations
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    sl.id,
    sl.name,
    sl.description,
    sl.status,
    CASE WHEN sl.is_universal THEN 'All Barbers' ELSE 'Specific' END as availability,
    c.name as campus_name,
    sl.is_active,
    u.first_name || ' ' || u.last_name as created_by
FROM service_locations sl
JOIN campuses c ON sl.campus_id = c.id
LEFT JOIN users u ON sl.created_by = u.id
ORDER BY c.name, sl.status, sl.name;
"
```

### View Pending Location Requests
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    sl.id,
    sl.name,
    sl.description,
    c.name as campus_name,
    u.first_name || ' ' || u.last_name as requested_by,
    u.email as requester_email,
    sl.created_at
FROM service_locations sl
JOIN campuses c ON sl.campus_id = c.id
LEFT JOIN users u ON sl.created_by = u.id
WHERE sl.status = 'pending'
ORDER BY sl.created_at DESC;
"
```

### View Barber Location Assignments
```bash
sudo -u postgres psql -d campuscuts -c "
SELECT 
    bsl.id as assignment_id,
    u.first_name || ' ' || u.last_name as barber_name,
    sl.name as location_name,
    bsl.is_primary,
    sl.is_universal
FROM barber_service_locations bsl
JOIN barbers b ON bsl.barber_id = b.id
JOIN users u ON b.\"userId\" = u.id
JOIN service_locations sl ON bsl.location_id = sl.id
WHERE sl.status = 'approved'
ORDER BY barber_name, bsl.is_primary DESC, location_name;
"
```

### Approve a Pending Location Request (Example)
```bash
# Replace LOCATION_ID and REVIEWER_USER_ID with actual UUIDs
sudo -u postgres psql -d campuscuts -c "
UPDATE service_locations 
SET status = 'approved', 
    is_universal = true, 
    reviewed_by = 'REVIEWER_USER_ID', 
    reviewed_at = NOW() 
WHERE id = 'LOCATION_ID';
"
```

---

## PENDING MIGRATIONS

### Add paymentRequestedAt column to bookings (Required for payment flow)
```bash
sudo -u postgres psql -d campuscuts -c 'ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "paymentRequestedAt" TIMESTAMPTZ;'
```

### Add TAPER to ServiceType enum (Required for Taper service bookings)
```bash
sudo -u postgres psql -d campuscuts -c "ALTER TYPE \"ServiceType\" ADD VALUE IF NOT EXISTS 'TAPER';"
```

---
