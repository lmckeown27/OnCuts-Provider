-- Migration: Set up campus managers for Cal Poly
-- This assigns specific users as campus managers for Cal Poly campus

-- First, ensure we have the Cal Poly campus (find it by name pattern)
-- Then update the specified users to be campus managers for that campus

-- Step 1: Get or identify Cal Poly campus
-- The campus should already exist from the university selection

-- Step 2: Update justincschroeter1@gmail.com as campus manager for Cal Poly
UPDATE users 
SET role = 'CAMPUS_MANAGER'
WHERE email = 'justincschroeter1@gmail.com';

-- Step 3: Update liam.mckeown38415@gmail.com as campus manager for Cal Poly  
UPDATE users 
SET role = 'CAMPUS_MANAGER'
WHERE email = 'liam.mckeown38415@gmail.com';

-- Step 4: Ensure barber profiles exist and are marked as campus managers
-- For justincschroeter1@gmail.com
UPDATE barbers 
SET "isCampusManager" = true,
    "campusId" = (
      SELECT id FROM campuses 
      WHERE LOWER(name) LIKE '%cal poly%' 
         OR LOWER(name) LIKE '%california polytechnic%'
      LIMIT 1
    )
WHERE "userId" = (SELECT id FROM users WHERE email = 'justincschroeter1@gmail.com')
  AND EXISTS (
    SELECT 1 FROM campuses 
    WHERE LOWER(name) LIKE '%cal poly%' 
       OR LOWER(name) LIKE '%california polytechnic%'
  );

-- For liam.mckeown38415@gmail.com
UPDATE barbers 
SET "isCampusManager" = true,
    "campusId" = (
      SELECT id FROM campuses 
      WHERE LOWER(name) LIKE '%cal poly%' 
         OR LOWER(name) LIKE '%california polytechnic%'
      LIMIT 1
    )
WHERE "userId" = (SELECT id FROM users WHERE email = 'liam.mckeown38415@gmail.com')
  AND EXISTS (
    SELECT 1 FROM campuses 
    WHERE LOWER(name) LIKE '%cal poly%' 
       OR LOWER(name) LIKE '%california polytechnic%'
  );

-- Add comments
COMMENT ON TABLE barbers IS 'Barber profiles - isCampusManager flag indicates campus management privileges';

