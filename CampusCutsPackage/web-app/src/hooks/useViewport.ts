/**
 * useViewport Hook
 * 
 * Detects and tracks viewport size and orientation for responsive design.
 * 
 * Viewport Types:
 * - 'mobile-portrait': < 640px width, height > width
 * - 'mobile-landscape': < 640px width, width > height  
 * - 'tablet': 640px - 1023px
 * - 'desktop': 1024px - 1535px
 * - 'desktop-large': 1536px+
 * 
 * Usage:
 * const { viewport, isMobile, isTablet, isDesktop, width, height, isPortrait } = useViewport();
 */

import { useState, useEffect, useCallback } from 'react';

export type ViewportType = 
  | 'mobile-portrait' 
  | 'mobile-landscape' 
  | 'tablet' 
  | 'desktop' 
  | 'desktop-large';

export interface ViewportInfo {
  viewport: ViewportType;
  width: number;
  height: number;
  isPortrait: boolean;
  isLandscape: boolean;
  isMobile: boolean;
  isMobilePortrait: boolean;
  isMobileLandscape: boolean;
  isTablet: boolean;
  isDesktop: boolean;
  isDesktopLarge: boolean;
  // Breakpoint checks (matches Tailwind)
  isSm: boolean;  // 640px+
  isMd: boolean;  // 768px+
  isLg: boolean;  // 1024px+
  isXl: boolean;  // 1280px+
  is2xl: boolean; // 1536px+
}

// Breakpoint constants (matching Tailwind defaults)
const BREAKPOINTS = {
  sm: 640,
  md: 768,
  lg: 1024,
  xl: 1280,
  '2xl': 1536,
} as const;

function getViewportType(width: number, height: number): ViewportType {
  const isPortrait = height > width;
  
  if (width < BREAKPOINTS.sm) {
    return isPortrait ? 'mobile-portrait' : 'mobile-landscape';
  } else if (width < BREAKPOINTS.lg) {
    return 'tablet';
  } else if (width < BREAKPOINTS['2xl']) {
    return 'desktop';
  } else {
    return 'desktop-large';
  }
}

function getViewportInfo(width: number, height: number): ViewportInfo {
  const viewport = getViewportType(width, height);
  const isPortrait = height > width;
  
  return {
    viewport,
    width,
    height,
    isPortrait,
    isLandscape: !isPortrait,
    isMobile: viewport === 'mobile-portrait' || viewport === 'mobile-landscape',
    isMobilePortrait: viewport === 'mobile-portrait',
    isMobileLandscape: viewport === 'mobile-landscape',
    isTablet: viewport === 'tablet',
    isDesktop: viewport === 'desktop' || viewport === 'desktop-large',
    isDesktopLarge: viewport === 'desktop-large',
    // Tailwind breakpoint checks
    isSm: width >= BREAKPOINTS.sm,
    isMd: width >= BREAKPOINTS.md,
    isLg: width >= BREAKPOINTS.lg,
    isXl: width >= BREAKPOINTS.xl,
    is2xl: width >= BREAKPOINTS['2xl'],
  };
}

// Get initial values (SSR-safe)
function getInitialViewport(): ViewportInfo {
  if (typeof window === 'undefined') {
    // SSR fallback - assume desktop
    return getViewportInfo(1024, 768);
  }
  return getViewportInfo(window.innerWidth, window.innerHeight);
}

export function useViewport(): ViewportInfo {
  const [viewportInfo, setViewportInfo] = useState<ViewportInfo>(getInitialViewport);

  const updateViewport = useCallback(() => {
    const width = window.innerWidth;
    const height = window.innerHeight;
    setViewportInfo(getViewportInfo(width, height));
  }, []);

  useEffect(() => {
    // Update on mount (in case SSR values differ)
    updateViewport();

    // Debounced resize handler for performance
    let timeoutId: ReturnType<typeof setTimeout>;
    const handleResize = () => {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(updateViewport, 100);
    };

    // Listen for resize and orientation change
    window.addEventListener('resize', handleResize);
    window.addEventListener('orientationchange', updateViewport);

    return () => {
      clearTimeout(timeoutId);
      window.removeEventListener('resize', handleResize);
      window.removeEventListener('orientationchange', updateViewport);
    };
  }, [updateViewport]);

  return viewportInfo;
}

// Convenience hook for just checking if mobile
export function useIsMobile(): boolean {
  const { isMobile } = useViewport();
  return isMobile;
}

// Convenience hook for just getting viewport type
export function useViewportType(): ViewportType {
  const { viewport } = useViewport();
  return viewport;
}

export default useViewport;

