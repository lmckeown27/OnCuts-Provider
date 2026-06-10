/**
 * Platform Detection Utility
 * 
 * Determines whether the user is on the web or app version
 * based on the current URL path.
 */

import { useLocation } from 'react-router-dom';

export type Platform = 'web' | 'app';

/**
 * Hook to get the current platform from the URL
 * Returns 'web' for /web/* routes and 'app' for /app/* routes
 * Defaults to 'web' if no platform prefix is found
 */
export function usePlatform(): Platform {
  const location = useLocation();
  
  if (location.pathname.startsWith('/app')) {
    return 'app';
  }
  
  return 'web';
}

/**
 * Get platform from pathname string
 * Useful for navigation without hooks
 */
export function getPlatformFromPath(pathname: string): Platform {
  if (pathname.startsWith('/app')) {
    return 'app';
  }
  
  return 'web';
}

/**
 * Prefix a route with the current platform
 * Example: `/barber/appointment/123` becomes `/web/barber/appointment/123`
 */
export function platformRoute(route: string, platform: Platform = 'web'): string {
  // Remove leading slash if present
  const cleanRoute = route.startsWith('/') ? route.slice(1) : route;
  
  // Return route with platform prefix
  return `/${platform}/${cleanRoute}`;
}

