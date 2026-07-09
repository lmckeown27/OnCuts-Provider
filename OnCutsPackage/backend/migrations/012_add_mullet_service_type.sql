-- Add MULLET to ServiceType enum
-- Run this migration to enable Mullet as a barber service option

ALTER TYPE "ServiceType" ADD VALUE IF NOT EXISTS 'MULLET';

