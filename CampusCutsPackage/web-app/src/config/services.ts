/**
 * Centralized Service/Specialty Definitions
 * 
 * This file is the single source of truth for all service types
 * used across the CampusCuts platform.
 * 
 * IMPORTANT: Any changes here will affect:
 * - Barber profile editor (what barbers can specialize in)
 * - Consumer filters (what consumers can search for)
 * - Booking flow (what services can be booked)
 * - Barber cards (displayed specialties)
 */

export interface ServiceType {
  id: string;
  name: string;
  description?: string;
  icon?: string;
  basePrice?: number; // Base price in dollars for pricing algorithm
}

/**
 * Master list of all service types
 * These are the standardized services across the platform
 * 
 * Price Tiers (aligned with CampusCut model):
 * - Budget ($23): Basic quick services
 * - Standard ($28): Standard haircuts
 * - Premium ($35-45): Specialized services
 */
export const SERVICE_TYPES: ServiceType[] = [
  { id: 'buzz-cut', name: 'Buzz Cut', description: 'Clipper cut all over', basePrice: 23 },
  { id: 'lineup', name: 'Line Up', description: 'Edge up / line up', basePrice: 23 },
  { id: 'beard-trim', name: 'Beard Trim', description: 'Beard shaping and trim', basePrice: 23 },
  { id: 'haircut', name: 'Haircut', description: 'Standard haircut', basePrice: 28 },
  { id: 'taper', name: 'Taper', description: 'Taper cut', basePrice: 28 },
  { id: 'hot-shave', name: 'Hot Shave', description: 'Traditional hot towel shave', basePrice: 28 },
  { id: 'kids-cut', name: 'Kids Cut', description: 'Haircuts for children', basePrice: 28 },
  { id: 'fade', name: 'Fade', description: 'Fade haircut', basePrice: 35 },
  { id: 'haircut-fade', name: 'Haircut & Fade', description: 'Full haircut with fade', basePrice: 35 },
  { id: 'mullet', name: 'Mullet', description: 'Business in the front, party in the back', basePrice: 35 },
  { id: 'design', name: 'Design/Art', description: 'Hair designs and artwork', basePrice: 38 },
  { id: 'afro', name: 'Afro Textures', description: 'Afro and textured hair styling', basePrice: 38 },
  { id: 'womens-cut', name: "Women's Cut", description: 'Haircuts for women', basePrice: 40 },
  { id: 'color', name: 'Color Treatment', description: 'Hair coloring services', basePrice: 45 },
  { id: 'perm', name: 'Perm', description: 'Permanent wave treatment', basePrice: 45 },
];

/**
 * Get just the service names for display
 */
export const SERVICE_NAMES = SERVICE_TYPES.map(s => s.name);

/**
 * For backwards compatibility with existing code that uses string arrays
 */
export const SPECIALTY_OPTIONS = SERVICE_NAMES;

/**
 * Find a service by ID or name
 */
export const findService = (idOrName: string): ServiceType | undefined => {
  const lower = idOrName.toLowerCase();
  return SERVICE_TYPES.find(
    s => s.id === lower || s.name.toLowerCase() === lower
  );
};

/**
 * Normalize specialty names for consistent storage
 * This helps when barbers have old data with different naming
 */
export const normalizeSpecialty = (specialty: string): string => {
  const found = findService(specialty);
  return found ? found.name : specialty;
};

export default SERVICE_TYPES;

