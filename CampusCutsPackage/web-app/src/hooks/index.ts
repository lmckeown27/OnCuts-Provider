/**
 * Hooks Index
 * 
 * Export all custom hooks for easy importing
 */

export { useViewport, useIsMobile, useViewportType } from './useViewport';
export type { ViewportType, ViewportInfo } from './useViewport';

export { useBodyScrollLock } from './useBodyScrollLock';

export { useGeolocation, calculateDistance, kmToMiles } from './useGeolocation';
export type { GeolocationState, UseGeolocationReturn } from './useGeolocation';

export { useDynamicViewportHeight } from './useDynamicViewportHeight';

