-- Add TAPER to ServiceType enum
-- This value was missing from the original enum definition

ALTER TYPE "ServiceType" ADD VALUE IF NOT EXISTS 'TAPER';

